"""
04_extract_measurements.py
==========================
The one heavy stage. Streams the big ICU/hosp event tables and reduces them to
ONE row per ICU stay of first-24h physiology, providing the inputs for SOFA scoring
(script 05) and for the statistical report's feature matrix.

Window
------
Per stay we look at the first 24h of the ICU admission:
    chart / output / input :  [intime,        intime + 24h]
    labs (keyed on hadm_id):  [intime - 6h,   intime + 24h]   # catch admission labs

This "day-1" window is a deliberate, well-precedented operationalisation. From
script 03 we saw suspicion of infection lands a median of +1.1h from ICU
admission (IQR -1.5h..+3.1h), so the first 24h covers the Sepsis-3 suspicion
window for the large majority of stays, while giving every stay, septic or not,
an identical, non-circular feature window. chartevents is ICU-only, so no usable
data exists before intime anyway.

Big tables are never loaded whole: `utils.stream_windowed_agg` accumulates
per-(stay, itemid) min/max/mean in chunks. inputevents/outputevents are smaller
and read with a column-filtered chunk loop.

Output
------
processed_data/04_stay_measurements.parquet   (one row per stay)
    demographics carried from cohort + first-24h aggregates:
    hr_*, resp_rate_*, temp_max_c, spo2_min, map_min, gcs_min,
    pao2_min, fio2_max, pf_ratio_min, lactate_max, creatinine_max,
    bilirubin_max, platelets_min, wbc_max, wbc_min, urine_24h_ml,
    plus vasopressor flags/rates (norepi_epi_max_rate, dopamine_max_rate, ...).
"""
from __future__ import annotations

import argparse

import pandas as pd

import config as C
import utils as U
from logging_utils import setup_logging, step, log_separator

CHART_WINDOW_H = 24.0
LAB_LOOKBACK_H = 6.0
LAB_WINDOW_H = 24.0

# chartevents itemids we pull (verified present in section 5 of the report).
CHART_ITEMIDS = {
    "hr":        [220045],
    "resp_rate": [220210, 224690],
    "temp_c":    [223762],
    "temp_f":    [223761],
    "spo2":      [220277],
    "map":       [220052, 220181],
    "gcs_eye":   [220739],
    "gcs_verb":  [223900],
    "gcs_mot":   [223901],
    "fio2":      [223835],
}
LAB_ITEMIDS = {
    "lactate":    [50813],
    "creatinine": [50912],
    "bilirubin":  [50885],
    "platelets":  [51265],
    "wbc":        [51301, 51300],
    "pao2":       [50821],
}
VASOPRESSOR_ITEMIDS = {
    "norepinephrine": 221906,
    "epinephrine":    221289,
    "dopamine":       221662,
    "dobutamine":     221653,
    "vasopressin":    222315,
    "phenylephrine":  221749,
}


# --------------------------------------------------------------------------- #
# Helpers to fold the long [stay_id, itemid, vmin/vmax/vmean/vcount] result
# into named per-stay Series.
# --------------------------------------------------------------------------- #
def _extract_itemid_rows(long: pd.DataFrame, itemids, stat_col: str) -> pd.DataFrame:
    """Filter long-format aggregates to specific itemids and return the requested statistic."""
    filtered = long[long["itemid"].isin(itemids)]
    return filtered[["stay_id", stat_col, "vcount"]].copy()


def combine_min(long, itemids) -> pd.Series:
    """Per-stay minimum across all matching itemids."""
    rows = _extract_itemid_rows(long, itemids, "vmin")
    return rows.groupby("stay_id")["vmin"].min()


def combine_max(long, itemids) -> pd.Series:
    """Per-stay maximum across all matching itemids."""
    rows = _extract_itemid_rows(long, itemids, "vmax")
    return rows.groupby("stay_id")["vmax"].max()


def combine_mean(long, itemids) -> pd.Series:
    """Per-stay count-weighted mean across all matching itemids."""
    rows = _extract_itemid_rows(long, itemids, "vmean")
    rows["weighted_sum"] = rows["vmean"] * rows["vcount"]
    grouped = rows.groupby("stay_id").agg(
        weighted_sum=("weighted_sum", "sum"), total_count=("vcount", "sum"))
    return grouped["weighted_sum"] / grouped["total_count"]


def load_vasopressors(stays: pd.DataFrame) -> pd.DataFrame:
    """First-24h vasopressor presence + max weight-based rate per stay."""
    stay_windows = stays.set_index("stay_id")[["intime", "chart_end"]]
    keep_ids = set(VASOPRESSOR_ITEMIDS.values())
    cols = ["stay_id", "itemid", "starttime", "rate", "rateuom"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["inputevents"], usecols=cols,
                             parse_dates=["starttime"],
                             chunksize=1_000_000, low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep_ids)]
        sub = sub[sub["stay_id"].isin(stay_windows.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.DataFrame(index=stays["stay_id"])
    infusions = pd.concat(rows, ignore_index=True).join(stay_windows, on="stay_id")
    infusions = infusions[(infusions["starttime"] >= infusions["intime"])
                          & (infusions["starttime"] <= infusions["chart_end"])]
    infusions["rate"] = pd.to_numeric(infusions["rate"], errors="coerce")

    weight_based = infusions[infusions["rateuom"] == "mcg/kg/min"]
    stay_ids = stays["stay_id"].astype("int64")
    result = pd.DataFrame(index=stay_ids)
    result.index.name = "stay_id"

    def present(name) -> pd.Series:
        counts = infusions[infusions["itemid"] == VASOPRESSOR_ITEMIDS[name]].groupby("stay_id").size()
        return counts.reindex(stay_ids).fillna(0) > 0

    def max_rate(names) -> pd.Series:
        ids = [VASOPRESSOR_ITEMIDS[n] for n in names]
        rates = weight_based[weight_based["itemid"].isin(ids)].groupby("stay_id")["rate"].max()
        return rates.reindex(stay_ids)

    result["norepi_epi_any"] = present("norepinephrine") | present("epinephrine")
    result["dopamine_any"] = present("dopamine")
    result["dobutamine_any"] = present("dobutamine")
    result["other_vaso_any"] = present("phenylephrine") | present("vasopressin")
    result["norepi_epi_max_rate"] = max_rate(["norepinephrine", "epinephrine"])
    result["dopamine_max_rate"] = max_rate(["dopamine"])
    for col in ["norepi_epi_any", "dopamine_any", "dobutamine_any", "other_vaso_any"]:
        result[col] = result[col].astype(bool)
    result["vaso_any"] = result[["norepi_epi_any", "dopamine_any",
                                 "dobutamine_any", "other_vaso_any"]].any(axis=1)
    return result


def load_urine(stays: pd.DataFrame) -> pd.Series:
    """First-24h total urine output (mL) per stay."""
    stay_windows = stays.set_index("stay_id")[["intime", "chart_end"]]
    keep_ids = set(C.URINE_OUTPUT_ITEMIDS)
    cols = ["stay_id", "itemid", "charttime", "value"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["outputevents"], usecols=cols,
                             parse_dates=["charttime"],
                             chunksize=1_000_000, low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep_ids)]
        sub = sub[sub["stay_id"].isin(stay_windows.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.Series(dtype="float64", name="urine_24h_ml")
    urine_events = pd.concat(rows, ignore_index=True).join(stay_windows, on="stay_id")
    urine_events = urine_events[
        (urine_events["charttime"] >= urine_events["intime"])
        & (urine_events["charttime"] <= urine_events["chart_end"])]
    urine_events["value"] = pd.to_numeric(urine_events["value"], errors="coerce").clip(lower=0)
    return urine_events.groupby("stay_id")["value"].sum().rename("urine_24h_ml")


def main() -> None:
    ap = argparse.ArgumentParser(description="Extract first-24h measurements per ICU stay.")
    ap.parse_args()

    log = setup_logging("04_extract_measurements")

    with step(log, "loading cohort"):
        cohort = U.load("02_cohort", C.OUTPUT_DIR)
        cohort["intime"] = pd.to_datetime(cohort["intime"])
        cohort["hadm_id"] = pd.to_numeric(cohort["hadm_id"], errors="coerce")
        stays = cohort[["stay_id", "subject_id", "hadm_id", "intime"]].copy()
        stays["chart_end"] = stays["intime"] + pd.Timedelta(hours=CHART_WINDOW_H)
    log.info("cohort: %s stays", f"{len(stays):,}")

    chart_windows = stays.assign(
        win_start=stays["intime"],
        win_end=stays["chart_end"],
    )[["stay_id", "win_start", "win_end"]]
    chart_windows["stay_id"] = chart_windows["stay_id"].astype("int64")

    lab_windows = (
        stays.dropna(subset=["hadm_id"])
        .assign(
            win_start=stays["intime"] - pd.Timedelta(hours=LAB_LOOKBACK_H),
            win_end=stays["intime"] + pd.Timedelta(hours=LAB_WINDOW_H),
        )[["hadm_id", "stay_id", "win_start", "win_end"]]
        .drop_duplicates("hadm_id")
    )

    chart_ids = [i for ids in CHART_ITEMIDS.values() for i in ids]
    with step(log, "streaming chartevents"):
        chart_long = U.stream_windowed_agg(
            C.FILES["chartevents"], chart_ids,
            chart_windows.assign(stay_id=chart_windows["stay_id"]),
            key_col="stay_id", time_col="charttime",
        )

    lab_ids = [i for ids in LAB_ITEMIDS.values() for i in ids]
    with step(log, "streaming labevents"):
        lab_long = U.stream_windowed_agg(
            C.FILES["labevents"], lab_ids, lab_windows,
            key_col="hadm_id", time_col="charttime",
        )

    with step(log, "assembling per-stay features"):
        feat = pd.DataFrame(index=stays["stay_id"].astype("int64"))
        feat.index.name = "stay_id"

        feat["hr_mean"] = combine_mean(chart_long, CHART_ITEMIDS["hr"])
        feat["hr_max"] = combine_max(chart_long, CHART_ITEMIDS["hr"])
        feat["resp_rate_mean"] = combine_mean(chart_long, CHART_ITEMIDS["resp_rate"])
        feat["resp_rate_max"] = combine_max(chart_long, CHART_ITEMIDS["resp_rate"])
        feat["spo2_min"] = combine_min(chart_long, CHART_ITEMIDS["spo2"]).clip(lower=0, upper=100)

        temp_c = combine_max(chart_long, CHART_ITEMIDS["temp_c"])
        temp_f = combine_max(chart_long, CHART_ITEMIDS["temp_f"])
        temp_f_as_c = (temp_f - 32.0) * 5.0 / 9.0
        feat["temp_max_c"] = (
            pd.concat([temp_c, temp_f_as_c], axis=1).max(axis=1).clip(lower=25, upper=45)
        )

        feat["map_min"] = combine_min(chart_long, CHART_ITEMIDS["map"]).clip(lower=10, upper=250)

        eye = combine_min(chart_long, CHART_ITEMIDS["gcs_eye"])
        verb = combine_min(chart_long, CHART_ITEMIDS["gcs_verb"])
        mot = combine_min(chart_long, CHART_ITEMIDS["gcs_mot"])
        gcs = (eye + verb + mot)
        feat["gcs_min"] = gcs.clip(lower=3, upper=15)

        fio2 = combine_max(chart_long, CHART_ITEMIDS["fio2"])
        fio2 = fio2.where(fio2 <= 1.0, fio2 / 100.0).clip(lower=0.21, upper=1.0)
        feat["fio2_max"] = fio2

        feat["lactate_max"] = combine_max(lab_long, LAB_ITEMIDS["lactate"])
        feat["creatinine_max"] = combine_max(lab_long, LAB_ITEMIDS["creatinine"])
        feat["bilirubin_max"] = combine_max(lab_long, LAB_ITEMIDS["bilirubin"])
        feat["platelets_min"] = combine_min(lab_long, LAB_ITEMIDS["platelets"])
        feat["wbc_max"] = combine_max(lab_long, LAB_ITEMIDS["wbc"])
        feat["wbc_min"] = combine_min(lab_long, LAB_ITEMIDS["wbc"])
        feat["pao2_min"] = combine_min(lab_long, LAB_ITEMIDS["pao2"])
        feat["pf_ratio_min"] = feat["pao2_min"] / feat["fio2_max"]

    with step(log, "loading vasopressors (inputevents)"):
        vaso = load_vasopressors(stays)

    with step(log, "loading urine output (outputevents)"):
        urine = load_urine(stays)

    out = (
        cohort.set_index("stay_id")
        .join(feat)
        .join(vaso)
        .join(urine)
        .reset_index()
    )
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any", "vaso_any"]:
        if c in out.columns:
            out[c] = out[c].fillna(False).astype(bool)

    n_lact = out["lactate_max"].notna().sum()
    n_gcs = out["gcs_min"].notna().sum()
    n_pf = out["pf_ratio_min"].notna().sum()
    log_separator(log)
    log.info("stay_measurements: %s stays", f"{len(out):,}")
    log.info("  lactate present:   %s (%.1f%%)", f"{n_lact:,}", n_lact / len(out) * 100)
    log.info("  GCS present:       %s (%.1f%%)", f"{n_gcs:,}", n_gcs / len(out) * 100)
    log.info("  P/F ratio present: %s (%.1f%%)", f"{n_pf:,}", n_pf / len(out) * 100)
    log.info("  any vasopressor:   %s", f"{int(out['vaso_any'].sum()):,}")

    U.save(out, "04_stay_measurements", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
