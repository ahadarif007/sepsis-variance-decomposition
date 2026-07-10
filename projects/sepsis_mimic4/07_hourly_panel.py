"""
07_hourly_panel.py
==================
Temporal substrate for real-time sepsis prediction. Resamples every cohort
stay onto a regular hourly grid, emitting one row per (stay_id, hour) with
the physiology observed in that hour. Scripts 08, 09, and the real-time
model all build on this table.

Design
------
* Horizon: hours 0..min(LOS, MAX_PANEL_HOURS) from ICU intime.
  The panel is right-censored at MAX_PANEL_HOURS.
* Each variable is aggregated per hour (count-weighted mean, or hourly
  min/max for "worst" variables), leaving NaN where nothing was charted.
* Per stay and core variable we add:
    <var>       hourly measured value (NaN if not measured)
    <var>_ff    last-observation-carried-forward within the stay
    <var>_tsl   hours since that variable was last measured
  _ff is the causal "known" value at each hour; _tsl encodes irregular
  sampling, which is itself a severity signal.
* Big tables (chartevents, labevents) are streamed in chunks; a partial
  aggregator keeps memory bounded.

Unit handling mirrors script 04: temperature F->C, FiO2 %->fraction,
MAP/GCS/SpO2 clipping, GCS = sum of three components.

Output
------
processed_data/hourly_panel.parquet    one row per stay-hour
processed_data/hourly_panel_sample.csv first ~40 stays, for inspection
"""
from __future__ import annotations

import argparse
from typing import Iterable, Sequence

import numpy as np
import pandas as pd

import config as C
import utils as U
from clinical_scores import build_hourly_grid
from logging_utils import setup_logging, step, log_separator

# --------------------------------------------------------------------------- #
# Horizon
# --------------------------------------------------------------------------- #
MAX_PANEL_HOURS = 72          # right-censor each stay at 72h of ICU time
LAB_LOOKBACK_H = 6.0          # labs from intime-6h count toward hour 0

# (itemids, hourly reduction): "mean" = count-weighted, "min"/"max" = worst value.
CHART_VARS = {
    "hr":        ([220045], "mean"),
    "resp_rate": ([220210, 224690], "mean"),
    "spo2":      ([220277], "min"),
    "map":       ([220052, 220181], "min"),
    "fio2":      ([223835], "max"),
    "temp_c":    ([223762], "mean"),      # celsius itemid
    "temp_f":    ([223761], "mean"),      # fahrenheit itemid (converted below)
    "gcs_eye":   ([220739], "min"),
    "gcs_verb":  ([223900], "min"),
    "gcs_mot":   ([223901], "min"),
}
LAB_VARS = {
    "lactate":    ([50813], "max"),
    "creatinine": ([50912], "max"),
    "bilirubin":  ([50885], "max"),
    "platelets":  ([51265], "min"),
    "wbc":        ([51301, 51300], "max"),
    "pao2":       ([50821], "min"),
}
VASOPRESSOR_ITEMIDS = {
    "norepinephrine": 221906, "epinephrine": 221289, "dopamine": 221662,
    "dobutamine": 221653, "vasopressin": 222315, "phenylephrine": 221749,
}

# Variables that receive _ff / _tsl companions (needed for SOFA and modelling).
CORE_VARS = ["hr", "resp_rate", "spo2", "map", "temp_c", "fio2", "gcs",
             "pao2", "pf_ratio", "lactate", "creatinine", "bilirubin",
             "platelets", "wbc"]


# --------------------------------------------------------------------------- #
# Streaming hourly aggregator
# --------------------------------------------------------------------------- #
def stream_hourly_agg(
    path,
    itemids: Iterable[int],
    windows: pd.DataFrame,
    key_col: str,
    time_col: str = "charttime",
    value_col: str = "valuenum",
    max_hours: int = MAX_PANEL_HOURS,
    chunksize: int = 2_000_000,
) -> pd.DataFrame:
    """Stream a gzipped event table, accumulating per-(stay_id, itemid, hour)
    partial aggregates (vmin, vmax, vsum, vcount).

    windows : DataFrame with [key_col, stay_id, intime, win_end].
    Returns : long DataFrame with [stay_id, itemid, hour, vmin, vmax, vsum, vcount].
    """
    want = set(int(i) for i in itemids)
    window_columns: list[str] = []
    for col_name in [key_col, "stay_id", "intime", "win_end"]:
        if col_name not in window_columns:
            window_columns.append(col_name)
    win = windows[window_columns].copy()
    win[key_col] = pd.to_numeric(win[key_col], errors="coerce")
    win = win.dropna(subset=[key_col])
    win[key_col] = win[key_col].astype("int64")

    reader = pd.read_csv(
        path, usecols=[key_col, time_col, "itemid", value_col],
        parse_dates=[time_col],
        chunksize=chunksize, low_memory=False,
    )
    try:
        from tqdm import tqdm
        reader = tqdm(reader, desc=f"scan {path.name}", unit="chunk")
    except Exception:
        pass

    partials: list[pd.DataFrame] = []
    total = 0
    for chunk in reader:
        total += len(chunk)
        sub = chunk[chunk["itemid"].isin(want)]
        if sub.empty:
            continue
        sub = sub.dropna(subset=[key_col, value_col]).copy()
        sub[key_col] = pd.to_numeric(sub[key_col], errors="coerce")
        sub[value_col] = pd.to_numeric(sub[value_col], errors="coerce")
        sub = sub.dropna(subset=[key_col, value_col])
        if sub.empty:
            continue
        sub[key_col] = sub[key_col].astype("int64")

        merged = sub.merge(win, on=key_col, how="inner")
        if merged.empty:
            continue
        relative_hours = (merged[time_col] - merged["intime"]).dt.total_seconds() / 3600.0
        merged = merged.assign(hour=np.floor(relative_hours).astype("int64"))
        merged = merged[(merged["hour"] >= 0) & (merged["hour"] <= max_hours) &
                        (merged[time_col] <= merged["win_end"])]
        if merged.empty:
            continue
        grouped = merged.groupby(["stay_id", "itemid", "hour"])[value_col].agg(
            vmin="min", vmax="max", vsum="sum", vcount="count").reset_index()
        partials.append(grouped)
        # Periodically fold partials to keep memory bounded.
        if len(partials) >= 40:
            partials = [_combine_partials(partials)]

    U.log(f"{path.name}: scanned {total:,} rows")
    if not partials:
        return pd.DataFrame(
            columns=["stay_id", "itemid", "hour", "vmin", "vmax", "vsum", "vcount"])
    return _combine_partials(partials)


def _combine_partials(partials: list[pd.DataFrame]) -> pd.DataFrame:
    allp = pd.concat(partials, ignore_index=True)
    return allp.groupby(["stay_id", "itemid", "hour"]).agg(
        vmin=("vmin", "min"), vmax=("vmax", "max"),
        vsum=("vsum", "sum"), vcount=("vcount", "sum")).reset_index()


def fold_variable(long: pd.DataFrame, itemids: Sequence[int], how: str) -> pd.Series:
    """Reduce long partials for one variable to a per-(stay_id, hour) Series."""
    sub = long[long["itemid"].isin([int(i) for i in itemids])]
    if sub.empty:
        return pd.Series(dtype="float64")
    if how == "mean":
        g = sub.groupby(["stay_id", "hour"]).agg(
            vsum=("vsum", "sum"), vcount=("vcount", "sum"))
        return (g["vsum"] / g["vcount"]).rename("value")
    if how == "min":
        return sub.groupby(["stay_id", "hour"])["vmin"].min().rename("value")
    if how == "max":
        return sub.groupby(["stay_id", "hour"])["vmax"].max().rename("value")
    raise ValueError(how)


# --------------------------------------------------------------------------- #
# Vasopressors and urine, binned to the hourly grid
# --------------------------------------------------------------------------- #
def hourly_vaso(stays: pd.DataFrame) -> pd.DataFrame:
    """Per (stay_id, hour): weight-based rates and presence flags, expanded
    across each infusion's [starttime, endtime] span."""
    stay_windows = stays.set_index("stay_id")[["intime", "win_end"]]
    keep = set(VASOPRESSOR_ITEMIDS.values())
    cols = ["stay_id", "itemid", "starttime", "endtime", "rate", "rateuom"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["inputevents"], usecols=cols,
                             parse_dates=["starttime", "endtime"],
                             chunksize=1_000_000,
                             low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep)]
        sub = sub[sub["stay_id"].isin(stay_windows.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour"])
    infusions = pd.concat(rows, ignore_index=True).join(stay_windows, on="stay_id")
    infusions["rate"] = pd.to_numeric(infusions["rate"], errors="coerce")
    infusions = infusions.dropna(subset=["starttime"])
    infusions["endtime"] = infusions["endtime"].fillna(infusions["starttime"])
    # Hour span each infusion covers (clipped to [0, MAX]).
    start_hour = np.floor((infusions["starttime"] - infusions["intime"]).dt.total_seconds() / 3600.0)
    end_hour = np.floor((infusions["endtime"] - infusions["intime"]).dt.total_seconds() / 3600.0)
    infusions["start_hour"] = np.clip(start_hour, 0, MAX_PANEL_HOURS).astype("int64")
    infusions["end_hour"] = np.clip(end_hour, 0, MAX_PANEL_HOURS).astype("int64")
    infusions = infusions[(end_hour >= 0) & (start_hour <= MAX_PANEL_HOURS)]

    # Expand each infusion row to all hours it covers.
    expanded: list[pd.DataFrame] = []
    for drug_name, item_id in VASOPRESSOR_ITEMIDS.items():
        drug_rows = infusions[infusions["itemid"] == item_id]
        if drug_rows.empty:
            continue
        reps = (drug_rows["end_hour"] - drug_rows["start_hour"] + 1).clip(lower=1).astype(int)
        stay_rep = np.repeat(drug_rows["stay_id"].to_numpy(), reps)
        rate_rep = np.repeat(drug_rows["rate"].to_numpy(), reps)
        uom_rep = np.repeat(drug_rows["rateuom"].to_numpy(), reps)
        hour_rep = np.concatenate([np.arange(a, b + 1)
                                   for a, b in zip(drug_rows["start_hour"], drug_rows["end_hour"])])
        expanded.append(pd.DataFrame({
            "stay_id": stay_rep, "hour": hour_rep, "drug": drug_name,
            "rate": rate_rep, "rateuom": uom_rep}))
    if not expanded:
        return pd.DataFrame(columns=["stay_id", "hour"])
    all_infusions = pd.concat(expanded, ignore_index=True)
    all_infusions["weight_based_rate"] = np.where(
        all_infusions["rateuom"] == "mcg/kg/min", all_infusions["rate"], np.nan)

    grouped = all_infusions.groupby(["stay_id", "hour"])
    result = pd.DataFrame(index=grouped.size().index)
    norepi_epi = all_infusions[all_infusions["drug"].isin(["norepinephrine", "epinephrine"])]
    dopamine = all_infusions[all_infusions["drug"] == "dopamine"]
    result["norepi_epi_rate"] = norepi_epi.groupby(["stay_id", "hour"])["weight_based_rate"].max()
    result["dopamine_rate"] = dopamine.groupby(["stay_id", "hour"])["weight_based_rate"].max()
    result["norepi_epi_any"] = norepi_epi.groupby(["stay_id", "hour"]).size().reindex(result.index).fillna(0) > 0
    result["dopamine_any"] = dopamine.groupby(["stay_id", "hour"]).size().reindex(result.index).fillna(0) > 0
    result["dobutamine_any"] = all_infusions[all_infusions["drug"] == "dobutamine"].groupby(["stay_id", "hour"]).size().reindex(result.index).fillna(0) > 0
    result["other_vaso_any"] = all_infusions[all_infusions["drug"].isin(["phenylephrine", "vasopressin"])].groupby(["stay_id", "hour"]).size().reindex(result.index).fillna(0) > 0
    for col in ["norepi_epi_any", "dopamine_any", "dobutamine_any", "other_vaso_any"]:
        result[col] = result[col].fillna(False).astype(bool)
    result["vaso_any"] = result[["norepi_epi_any", "dopamine_any",
                                 "dobutamine_any", "other_vaso_any"]].any(axis=1)
    return result.reset_index()


def hourly_urine(stays: pd.DataFrame) -> pd.DataFrame:
    """Per (stay_id, hour): urine volume (mL) charted in that hour."""
    stay_windows = stays.set_index("stay_id")[["intime", "win_end"]]
    keep = set(C.URINE_OUTPUT_ITEMIDS)
    cols = ["stay_id", "itemid", "charttime", "value"]
    rows: list[pd.DataFrame] = []
    for chunk in pd.read_csv(C.FILES["outputevents"], usecols=cols,
                             parse_dates=["charttime"],
                             chunksize=1_000_000, low_memory=False):
        sub = chunk[chunk["itemid"].isin(keep)]
        sub = sub[sub["stay_id"].isin(stay_windows.index)]
        if not sub.empty:
            rows.append(sub)
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour", "urine_ml"])
    urine_events = pd.concat(rows, ignore_index=True).join(stay_windows, on="stay_id")
    relative_hours = (urine_events["charttime"] - urine_events["intime"]).dt.total_seconds() / 3600.0
    urine_events = urine_events.assign(hour=np.floor(relative_hours).astype("int64"))
    urine_events = urine_events[(urine_events["hour"] >= 0) & (urine_events["hour"] <= MAX_PANEL_HOURS)]
    urine_events["value"] = pd.to_numeric(urine_events["value"], errors="coerce").clip(lower=0)
    return (urine_events.groupby(["stay_id", "hour"])["value"].sum()
            .rename("urine_ml").reset_index())


# --------------------------------------------------------------------------- #
# Panel assembly
# --------------------------------------------------------------------------- #
def build_grid(stays: pd.DataFrame) -> pd.DataFrame:
    """Dense (stay_id, hour) grid. Delegates to clinical_scores.build_hourly_grid."""
    return build_hourly_grid(stays, MAX_PANEL_HOURS)


def add_ff_tsl(panel: pd.DataFrame, var: str) -> None:
    """Add <var>_ff (LOCF within stay) and <var>_tsl (hours since measured)."""
    g = panel.groupby("stay_id", sort=False)
    panel[f"{var}_ff"] = g[var].ffill()
    measured = panel[var].notna()
    hour_when_meas = panel["hour"].where(measured)
    panel[f"{var}_tsl"] = (panel["hour"]
                           - hour_when_meas.groupby(panel["stay_id"]).ffill())


def main() -> None:
    ap = argparse.ArgumentParser(description="Build the hourly patient panel.")
    ap.add_argument("--limit", type=int, default=None,
                    help="only process the first N stays (debug)")
    args = ap.parse_args()

    log = setup_logging("07_hourly_panel")

    with step(log, "loading cohort"):
        cohort = U.load("02_cohort", C.OUTPUT_DIR, parse_dates=["intime", "outtime"])
        cohort["hadm_id"] = pd.to_numeric(cohort["hadm_id"], errors="coerce")
        stays = cohort[["stay_id", "subject_id", "hadm_id", "intime",
                        "los_hours"]].copy()
        stays["stay_id"] = stays["stay_id"].astype("int64")
        if args.limit:
            stays = stays.head(args.limit).copy()
            log.info("debug mode: limited to first %d stays", args.limit)
        stays["win_end"] = stays["intime"] + pd.Timedelta(hours=MAX_PANEL_HOURS)
    log.info("cohort: %s stays; horizon %dh", f"{len(stays):,}", MAX_PANEL_HOURS)

    chart_windows = stays[["stay_id", "intime", "win_end"]].copy()
    lab_windows = (stays.dropna(subset=["hadm_id"])
                   .assign(intime=stays["intime"] - pd.Timedelta(hours=LAB_LOOKBACK_H))
                   [["hadm_id", "stay_id", "intime", "win_end"]]
                   .drop_duplicates("hadm_id"))

    chart_ids = [i for ids, _ in CHART_VARS.values() for i in ids]
    with step(log, "streaming chartevents"):
        chart_long = stream_hourly_agg(C.FILES["chartevents"], chart_ids,
                                       chart_windows, key_col="stay_id")

    lab_ids = [i for ids, _ in LAB_VARS.values() for i in ids]
    with step(log, "streaming labevents"):
        lab_long = stream_hourly_agg(C.FILES["labevents"], lab_ids,
                                     lab_windows, key_col="hadm_id")

    with step(log, "folding variables onto hourly grid"):
        panel = build_grid(stays).set_index(["stay_id", "hour"])
        for var, (ids, how) in CHART_VARS.items():
            s = fold_variable(chart_long, ids, how)
            panel[var] = s
        for var, (ids, how) in LAB_VARS.items():
            s = fold_variable(lab_long, ids, how)
            panel[var] = s
        panel = panel.reset_index()

    with step(log, "unit conversions"):
        tf_as_c = (panel["temp_f"] - 32.0) * 5.0 / 9.0
        panel["temp_c"] = panel[["temp_c"]].join(tf_as_c.rename("tfc")).max(axis=1)
        panel["temp_c"] = panel["temp_c"].clip(lower=25, upper=45)
        panel = panel.drop(columns=["temp_f"])
        panel["fio2"] = panel["fio2"].where(panel["fio2"] <= 1.0,
                                            panel["fio2"] / 100.0).clip(0.21, 1.0)
        panel["map"] = panel["map"].clip(lower=10, upper=250)
        panel["spo2"] = panel["spo2"].clip(lower=0, upper=100)
        panel["gcs"] = (panel["gcs_eye"] + panel["gcs_verb"]
                        + panel["gcs_mot"]).clip(lower=3, upper=15)
        panel = panel.drop(columns=["gcs_eye", "gcs_verb", "gcs_mot"])
        panel["pf_ratio"] = panel["pao2"] / panel["fio2"]

    with step(log, "binning vasopressors (inputevents)"):
        vaso = hourly_vaso(stays)

    with step(log, "binning urine (outputevents)"):
        urine = hourly_urine(stays)

    if not vaso.empty:
        panel = panel.merge(vaso, on=["stay_id", "hour"], how="left")
    if not urine.empty:
        panel = panel.merge(urine, on=["stay_id", "hour"], how="left")
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any", "vaso_any"]:
        if c in panel.columns:
            panel[c] = panel[c].fillna(False).astype(bool)
        else:
            panel[c] = False
    panel["urine_ml"] = panel.get("urine_ml", pd.Series(index=panel.index)).fillna(0.0)

    with step(log, "computing forward-fill + time-since-last"):
        panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
        for var in CORE_VARS:
            if var in panel.columns:
                add_ff_tsl(panel, var)

    float_cols = panel.select_dtypes(include=["float64"]).columns
    panel[float_cols] = panel[float_cols].astype("float32")

    log_separator(log)
    n_stays = panel['stay_id'].nunique()
    log.info("hourly_panel: %s stay-hours across %s stays (mean %.1f h/stay)",
             f"{len(panel):,}", f"{n_stays:,}", len(panel) / n_stays)
    for v in ["hr", "map", "lactate", "gcs", "pf_ratio"]:
        cov = panel[v].notna().mean()
        log.info("  hourly coverage %-10s: %.1f%% of hours measured", v, cov * 100)

    out_pq = C.OUTPUT_DIR / "07_hourly_panel.parquet"
    panel.to_parquet(out_pq, index=False)
    log.info("saved %s (%s)", out_pq.name, U.human_size(out_pq.stat().st_size))

    sample_ids = stays["stay_id"].head(40)
    panel[panel["stay_id"].isin(sample_ids)].to_csv(
        C.OUTPUT_DIR / "07_hourly_panel_sample.csv", index=False)
    log.info("saved 07_hourly_panel_sample.csv (first 40 stays)")


if __name__ == "__main__":
    main()
