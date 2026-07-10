"""
21_eicu_external_panel.py
=========================
External validation: rebuilds the hour-6 landmark table on the eICU
Collaborative Research Database v2.0. The frozen MIMIC-IV Tier-1 nomogram
(processed_data/tier1_coefs.csv) is scored on this independent, multi-centre
US ICU population.

The output mirrors landmark_h6.csv column-for-column, so 22_external_validation.Rmd
applies exactly the same feature design.

Replicated identically (mirrors 02/03/07/08)
---------------------------------------------
* Cohort: adults (>=18), ICU LOS >= 4h, first ICU stay per patient.
* Hourly panel (hours 0-72), per-variable hourly reduction then forward-fill,
  6h trajectory slopes = v@6 - v@0.
* Hourly SOFA scored identically to 08_onset_label.score_sofa.
* Onset = first hour SOFA >= 2 inside [t_susp - 48h, t_susp + 24h];
  landmark at h6; at-risk = not septic by h6; target = onset in (6h, 18h].

Cross-dataset adaptation (documented in README)
------------------------------------------------
Suspected infection: eICU's microLab table covers only ~1.5% of stays,
while medication covers ~83%. Requiring a culture would make the label
untransportable. We trigger suspected infection on the first qualifying
antibiotic order, refining via Seymour arms when a culture is available.
This is a property of eICU's data capture, not of the model.

eICU times are minute offsets from unit admission (hour = floor(offset / 60)).

Output
------
processed_data/landmark_h6_eicu.parquet   same schema as landmark_h6.csv
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
import utils as U
from clinical_scores import (
    build_hourly_grid, ff, normalize_vaso_bools, qsofa,
    score_sofa_hourly, sirs,
)
from logging_utils import setup_logging, step, log_cohort_filter, log_separator

EICU_DIR = C.PROJECT_ROOT / "data" / "eicu-collaborative-research-database-2.0"

MAX_H = 72                     # right-censor each stay at 72h of ICU time
LANDMARK_H = 6
HORIZON_H = 12                 # predict incident onset within 12h of the landmark
SUSP_BEFORE_H = 48
SUSP_AFTER_H = 24
SOFA_THRESH = C.SOFA_INCREASE_THRESHOLD    # >= 2

# eICU lab names -> (canonical var, hourly reduction). Units match MIMIC
# except FiO2 (percent -> fraction, converted below).
LAB_MAP = {
    "lactate":          ("lactate", "max"),
    "creatinine":       ("creatinine", "max"),
    "WBC x 1000":       ("wbc", "max"),
    "platelets x 1000": ("platelets", "min"),
    "total bilirubin":  ("bilirubin", "max"),
    "paO2":             ("pao2", "min"),
    "FiO2":             ("fio2", "max"),
}

CORE_VARS = ["hr", "resp_rate", "spo2", "map", "temp_c", "gcs",
             "pao2", "fio2", "pf_ratio", "lactate", "creatinine",
             "bilirubin", "platelets", "wbc"]

VASO_KINDS = {                 # substring match on lower(drugname) -> group
    "norepinephrine": "norepi_epi", "levophed": "norepi_epi",
    "epinephrine": "norepi_epi",
    "dopamine": "dopamine",
    "dobutamine": "dobutamine",
    "vasopressin": "other_vaso", "phenylephrine": "other_vaso",
    "neosynephrine": "other_vaso",
}


# --------------------------------------------------------------------------- #
# 1. Cohort (mirrors 02_extract_cohort.py, eICU-native)
# --------------------------------------------------------------------------- #
def _parse_age(age_series: pd.Series) -> pd.Series:
    """Parse eICU age strings (e.g. '65', '> 89') to numeric. Ages > 89 mapped to 90."""
    numeric_part = age_series.astype("string").str.extract(r"(\d+)")[0]
    age = pd.to_numeric(numeric_part, errors="coerce")
    age = age.where(~age_series.astype("string").str.contains(">", na=False), 90)
    return age


def build_cohort() -> pd.DataFrame:
    import logging
    log = logging.getLogger("21_eicu_external_panel")

    with step(log, "loading eICU patient table"):
        pat = pd.read_csv(
            EICU_DIR / "patient.csv.gz",
            usecols=["patientunitstayid", "uniquepid", "patienthealthsystemstayid",
                     "gender", "age", "unitvisitnumber", "unitdischargeoffset",
                     "hospitaldischargestatus", "hospitaladmitoffset"],
            low_memory=False,
        )
    log.info("raw patient rows: %s", f"{len(pat):,}")
    pat["age"] = _parse_age(pat["age"])
    pat["los_hours"] = pd.to_numeric(pat["unitdischargeoffset"],
                                     errors="coerce") / 60.0
    pat["gender"] = pat["gender"].map({"Female": "F", "Male": "M"})
    pat["hospital_expire_flag"] = (
        pat["hospitaldischargestatus"].astype("string").str.strip()
        .eq("Expired").fillna(False).astype(int))

    n0 = len(pat)
    pat = pat[pat["age"] >= C.MIN_AGE]
    log_cohort_filter(log, f"age >= {C.MIN_AGE}", n0, len(pat))
    n1 = len(pat)
    pat = pat[pat["los_hours"] >= C.MIN_ICU_LOS_HOURS]
    log_cohort_filter(log, f"LOS >= {C.MIN_ICU_LOS_HOURS}h", n1, len(pat))
    n2 = len(pat)
    pat = (pat.sort_values(["unitvisitnumber", "hospitaladmitoffset"])
             .groupby("uniquepid", as_index=False).first())
    log_cohort_filter(log, "first ICU stay/patient", n2, len(pat))
    return pat[["patientunitstayid", "uniquepid", "gender", "age",
                "los_hours", "hospital_expire_flag"]].rename(
        columns={"patientunitstayid": "stay_id"})


# --------------------------------------------------------------------------- #
# 2. Streaming hourly aggregation of a big offset-keyed eICU table
# --------------------------------------------------------------------------- #
def _hour_of(offset_min: pd.Series) -> pd.Series:
    """Convert eICU minute-offset to hour (floor)."""
    return np.floor(pd.to_numeric(offset_min, errors="coerce") / 60.0)


def stream_hourly(path, usecols, off_col, keep_ids, extract, chunksize=3_000_000):
    """Generic streaming aggregator. `extract(chunk)` returns a long frame with
    columns [stay_id, hour, var, value]; we accumulate min/max/sum/count."""
    partials: list[pd.DataFrame] = []
    total = 0
    reader = pd.read_csv(path, usecols=usecols, chunksize=chunksize,
                         low_memory=False)
    try:
        from tqdm import tqdm
        reader = tqdm(reader, desc=f"scan {path.name}", unit="chunk")
    except Exception:
        pass
    for chunk in reader:
        total += len(chunk)
        chunk = chunk[chunk["patientunitstayid"].isin(keep_ids)]
        if chunk.empty:
            continue
        chunk = chunk.assign(hour=_hour_of(chunk[off_col]))
        chunk = chunk[(chunk["hour"] >= 0) & (chunk["hour"] <= MAX_H)]
        if chunk.empty:
            continue
        long = extract(chunk)
        long = long.dropna(subset=["value"])
        if long.empty:
            continue
        grouped = long.groupby(["stay_id", "hour", "var"])["value"].agg(
            vmin="min", vmax="max", vsum="sum", vcount="count").reset_index()
        partials.append(grouped)
        if len(partials) >= 30:
            partials = [_fold(partials)]
    U.log(f"  {path.name}: scanned {total:,} rows")
    if not partials:
        return pd.DataFrame(columns=["stay_id", "hour", "var",
                                     "vmin", "vmax", "vsum", "vcount"])
    return _fold(partials)


def _fold(partials):
    """Combine partial aggregates by re-aggregating across chunks."""
    combined = pd.concat(partials, ignore_index=True)
    return combined.groupby(["stay_id", "hour", "var"]).agg(
        vmin=("vmin", "min"), vmax=("vmax", "max"),
        vsum=("vsum", "sum"), vcount=("vcount", "sum")).reset_index()


def reduce_var(long, var, how):
    """Reduce long-format aggregates for one variable to per-(stay_id, hour) values."""
    var_rows = long[long["var"] == var]
    if var_rows.empty:
        return pd.Series(dtype="float64")
    grouped = var_rows.groupby(["stay_id", "hour"])
    if how == "mean":
        totals = grouped.agg(vsum=("vsum", "sum"), vcount=("vcount", "sum"))
        return (totals["vsum"] / totals["vcount"]).rename("value")
    if how == "min":
        return grouped["vmin"].min().rename("value")
    if how == "max":
        return grouped["vmax"].max().rename("value")
    raise ValueError(how)


# --------------------------------------------------------------------------- #
# 3. Vitals, GCS, labs, vasopressors
# --------------------------------------------------------------------------- #
def get_vitals(keep_ids):
    U.log("streaming vitalPeriodic (heavy) ...")

    def extract_vp(chunk):
        frames = []
        for col, var in [("heartrate", "hr"), ("respiration", "resp_rate"),
                         ("sao2", "spo2"), ("temperature", "temp_c"),
                         ("systemicmean", "map")]:
            v = pd.to_numeric(chunk[col], errors="coerce")
            frames.append(pd.DataFrame({"stay_id": chunk["patientunitstayid"],
                                        "hour": chunk["hour"], "var": var,
                                        "value": v}))
        return pd.concat(frames, ignore_index=True)

    vp = stream_hourly(
        EICU_DIR / "vitalPeriodic.csv.gz",
        usecols=["patientunitstayid", "observationoffset", "heartrate",
                 "respiration", "sao2", "temperature", "systemicmean"],
        off_col="observationoffset", keep_ids=keep_ids, extract=extract_vp)

    U.log("streaming vitalAperiodic (noninvasive MAP) ...")

    def extract_va(chunk):
        v = pd.to_numeric(chunk["noninvasivemean"], errors="coerce")
        return pd.DataFrame({"stay_id": chunk["patientunitstayid"],
                             "hour": chunk["hour"], "var": "map", "value": v})

    va = stream_hourly(
        EICU_DIR / "vitalAperiodic.csv.gz",
        usecols=["patientunitstayid", "observationoffset", "noninvasivemean"],
        off_col="observationoffset", keep_ids=keep_ids, extract=extract_va)
    return pd.concat([vp, va], ignore_index=True)


def get_nursecharting(keep_ids):
    """GCS Total and Celsius temperature from nurseCharting, which is the
    primary temperature source in eICU (vitalPeriodic charts it sparsely)."""
    U.log("streaming nurseCharting for GCS Total + temperature ...")

    def extract_nc(chunk):
        label = chunk["nursingchartcelltypevallabel"].astype("string")
        name = chunk["nursingchartcelltypevalname"].astype("string")
        val = pd.to_numeric(chunk["nursingchartvalue"], errors="coerce")
        gcs = (label == "Glasgow coma score") & (name == "GCS Total")
        tmp = name == "Temperature (C)"
        frames = []
        if gcs.any():
            frames.append(pd.DataFrame({"stay_id": chunk["patientunitstayid"][gcs],
                                        "hour": chunk["hour"][gcs], "var": "gcs",
                                        "value": val[gcs]}))
        if tmp.any():
            frames.append(pd.DataFrame({"stay_id": chunk["patientunitstayid"][tmp],
                                        "hour": chunk["hour"][tmp], "var": "temp_c",
                                        "value": val[tmp]}))
        if not frames:
            return pd.DataFrame(columns=["stay_id", "hour", "var", "value"])
        return pd.concat(frames, ignore_index=True)

    return stream_hourly(
        EICU_DIR / "nurseCharting.csv.gz",
        usecols=["patientunitstayid", "nursingchartoffset",
                 "nursingchartcelltypevallabel", "nursingchartcelltypevalname",
                 "nursingchartvalue"],
        off_col="nursingchartoffset", keep_ids=keep_ids, extract=extract_nc)


def get_labs(keep_ids):
    U.log("streaming lab table ...")

    def extract_lab(chunk):
        sub = chunk[chunk["labname"].isin(LAB_MAP.keys())].copy()
        sub["var"] = sub["labname"].map(lambda x: LAB_MAP[x][0])
        sub["value"] = pd.to_numeric(sub["labresult"], errors="coerce")
        return sub[["patientunitstayid", "hour", "var", "value"]].rename(
            columns={"patientunitstayid": "stay_id"})

    return stream_hourly(
        EICU_DIR / "lab.csv.gz",
        usecols=["patientunitstayid", "labresultoffset", "labname", "labresult"],
        off_col="labresultoffset", keep_ids=keep_ids, extract=extract_lab)


def get_vaso(keep_ids):
    """Per (stay_id, hour): vasopressor presence flags and mcg/kg/min rates
    for the dose-dependent SOFA cardiovascular component."""
    U.log("streaming infusionDrug for vasopressors ...")
    rows = []
    for chunk in pd.read_csv(EICU_DIR / "infusionDrug.csv.gz",
                             usecols=["patientunitstayid", "infusionoffset",
                                      "drugname", "drugrate"],
                             chunksize=1_000_000, low_memory=False):
        chunk = chunk[chunk["patientunitstayid"].isin(keep_ids)]
        if chunk.empty:
            continue
        drug_name_lower = chunk["drugname"].astype("string").str.lower()
        vaso_group = pd.Series(pd.NA, index=chunk.index, dtype="string")
        for substring, group in VASO_KINDS.items():
            vaso_group = vaso_group.mask(
                drug_name_lower.str.contains(substring, na=False, regex=False), group)
        matched = chunk[vaso_group.notna()].copy()
        if matched.empty:
            continue
        matched["kind"] = vaso_group[vaso_group.notna()]
        matched["hour"] = _hour_of(matched["infusionoffset"])
        matched = matched[(matched["hour"] >= 0) & (matched["hour"] <= MAX_H)]
        matched["is_weight_based"] = drug_name_lower.loc[matched.index].str.contains(
            "mcg/kg/min", na=False, regex=False)
        matched["rate"] = pd.to_numeric(matched["drugrate"], errors="coerce")
        rows.append(matched[["patientunitstayid", "hour", "kind", "is_weight_based", "rate"]])
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour"])
    infusions = pd.concat(rows, ignore_index=True).rename(
        columns={"patientunitstayid": "stay_id"})
    result = pd.DataFrame(index=infusions.groupby(["stay_id", "hour"]).size().index)
    for group in ["norepi_epi", "dopamine", "dobutamine", "other_vaso"]:
        present = (infusions[infusions["kind"] == group].groupby(["stay_id", "hour"]).size()
                   .reindex(result.index).fillna(0) > 0)
        result[f"{group}_any"] = present
    weight_based = infusions[infusions["is_weight_based"]]
    result["norepi_epi_rate"] = (weight_based[weight_based["kind"] == "norepi_epi"]
                                 .groupby(["stay_id", "hour"])["rate"].max())
    result["dopamine_rate"] = (weight_based[weight_based["kind"] == "dopamine"]
                               .groupby(["stay_id", "hour"])["rate"].max())
    for col in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
                "other_vaso_any"]:
        result[col] = result[col].fillna(False).astype(bool)
    return result.reset_index()


# --------------------------------------------------------------------------- #
# 4. Suspected infection (eICU adaptation; see module docstring)
# --------------------------------------------------------------------------- #
def suspected_infection(keep_ids):
    U.log("detecting suspected infection (antibiotics +/- culture) ...")
    # Antibiotic orders.
    abx_rows = []
    for chunk in pd.read_csv(EICU_DIR / "medication.csv.gz",
                             usecols=["patientunitstayid", "drugstartoffset",
                                      "drugname"],
                             chunksize=1_000_000, low_memory=False):
        chunk = chunk[chunk["patientunitstayid"].isin(keep_ids)]
        if chunk.empty:
            continue
        mask = U.match_antibiotics(chunk["drugname"], C.ANTIBIOTICS)
        sub = chunk[mask]
        if not sub.empty:
            abx_rows.append(sub)
    abx = pd.concat(abx_rows, ignore_index=True)
    abx["t_abx_h"] = pd.to_numeric(abx["drugstartoffset"], errors="coerce") / 60.0
    abx = abx.dropna(subset=["t_abx_h"])
    # keep antibiotics within [-48h, +MAX_H] of the ICU stay window
    abx = abx[(abx["t_abx_h"] >= -SUSP_BEFORE_H) & (abx["t_abx_h"] <= MAX_H)]
    first_abx = abx.groupby("patientunitstayid")["t_abx_h"].min()

    # Cultures (present for a minority of stays; used to refine timing only).
    micro = pd.read_csv(EICU_DIR / "microLab.csv.gz",
                        usecols=["patientunitstayid", "culturetakenoffset"],
                        low_memory=False)
    micro = micro[micro["patientunitstayid"].isin(keep_ids)]
    micro["t_cx_h"] = pd.to_numeric(micro["culturetakenoffset"],
                                    errors="coerce") / 60.0
    micro = micro.dropna(subset=["t_cx_h"])

    U.log(f"  stays with >=1 qualifying antibiotic: {first_abx.notna().sum():,}")
    U.log(f"  stays with >=1 culture:               "
          f"{micro['patientunitstayid'].nunique():,}")

    # Refine t_suspicion via Sepsis-3 arms when a culture is in-window,
    # otherwise fall back to the first antibiotic time.
    susp = first_abx.rename("t_abx_h").reset_index().rename(
        columns={"patientunitstayid": "stay_id"})
    if not micro.empty:
        paired = susp.merge(micro.rename(columns={"patientunitstayid": "stay_id"}),
                            on="stay_id", how="left")
        culture_abx_gap_h = paired["t_cx_h"] - paired["t_abx_h"]
        # Arm 1: culture drawn after abx, within 72h
        arm1 = (culture_abx_gap_h >= 0) & (culture_abx_gap_h <= C.ABX_BEFORE_CULTURE_HOURS)
        # Arm 2: culture drawn before abx, within 24h
        arm2 = (culture_abx_gap_h < 0) & (-culture_abx_gap_h <= C.CULTURE_BEFORE_ABX_HOURS)
        paired["t_susp"] = np.where(arm2, paired["t_cx_h"], paired["t_abx_h"])
        paired["qualifies"] = (arm1 | arm2).fillna(False)
        confirmed = (paired[paired["qualifies"]].sort_values("t_susp")
                     .groupby("stay_id")["t_susp"].first())
        susp["susp_hour"] = susp["stay_id"].map(confirmed)
        susp["susp_hour"] = susp["susp_hour"].fillna(susp["t_abx_h"])
    else:
        susp["susp_hour"] = susp["t_abx_h"]
    return susp.set_index("stay_id")["susp_hour"]


# --------------------------------------------------------------------------- #
# 5. Panel assembly + forward-fill
# --------------------------------------------------------------------------- #
def build_grid(cohort):
    return build_hourly_grid(cohort, MAX_H)


def score_sofa(panel):
    """Delegates to clinical_scores.score_sofa_hourly (urine omitted)."""
    return score_sofa_hourly(panel, include_urine=False)


_hourly_qsofa = qsofa
_hourly_sirs = sirs


def main():
    log = setup_logging("21_eicu_external_panel")

    cohort = build_cohort()
    keep_ids = set(cohort["stay_id"].astype("int64"))
    log.info("eICU cohort: %s stays", f"{len(cohort):,}")

    with step(log, "streaming long hourly measurements"):
        meas = pd.concat([get_vitals(keep_ids), get_nursecharting(keep_ids),
                          get_labs(keep_ids)], ignore_index=True)
    log.info("measurements: %s rows total", f"{len(meas):,}")

    with step(log, "folding variables onto hourly grid"):
        panel = build_grid(cohort).set_index(["stay_id", "hour"])
        reductions = {"hr": "mean", "resp_rate": "mean", "spo2": "min",
                      "map": "min", "temp_c": "mean", "gcs": "min",
                      "lactate": "max", "creatinine": "max", "wbc": "max",
                      "platelets": "min", "bilirubin": "max", "pao2": "min",
                      "fio2": "max"}
        for var, how in reductions.items():
            panel[var] = reduce_var(meas, var, how)
        panel = panel.reset_index()

    with step(log, "unit conversions"):
        panel["temp_c"] = panel["temp_c"].clip(lower=25, upper=45)
        panel["fio2"] = panel["fio2"].where(panel["fio2"] <= 1.0,
                                            panel["fio2"] / 100.0).clip(0.21, 1.0)
        panel["map"] = panel["map"].clip(lower=10, upper=250)
        panel["spo2"] = panel["spo2"].clip(lower=0, upper=100)
        panel["gcs"] = panel["gcs"].clip(lower=3, upper=15)
        panel["pf_ratio"] = panel["pao2"] / panel["fio2"]

    with step(log, "streaming vasopressors (infusionDrug)"):
        vaso = get_vaso(keep_ids)
    if not vaso.empty:
        panel = panel.merge(vaso, on=["stay_id", "hour"], how="left")
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any"]:
        panel[c] = panel[c].fillna(False).astype(bool) if c in panel else False

    with step(log, "forward-filling core variables"):
        panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
        g = panel.groupby("stay_id", sort=False)
        for v in CORE_VARS:
            if v in panel.columns:
                panel[f"{v}_ff"] = g[v].ffill()

    with step(log, "scoring hourly SOFA + locating onset"):
        sofa = score_sofa(panel)
        panel = pd.concat([panel, sofa], axis=1)

    with step(log, "detecting suspected infection"):
        susp_hour = suspected_infection(keep_ids)
    panel["susp_hour"] = panel["stay_id"].map(susp_hour)
    has_susp = panel["stay_id"].map(susp_hour.notna()).fillna(False)
    in_win = (panel["hour"] >= (panel["susp_hour"] - SUSP_BEFORE_H)) & \
             (panel["hour"] <= (panel["susp_hour"] + SUSP_AFTER_H))
    cand = (panel["sofa_total"] >= SOFA_THRESH) & in_win & has_susp
    onset = panel.loc[cand].groupby("stay_id")["hour"].min().rename("onset_hour")

    with step(log, "building hour-6 landmark table"):
        def _ff(v):
            return ff(panel, v)

        lm = panel[panel["hour"] == LANDMARK_H].copy()
        onset_h_lm = lm["stay_id"].map(onset)
        at_risk = onset_h_lm.isna() | (onset_h_lm > LANDMARK_H)
        lm = lm[at_risk].copy()

        lmf = pd.DataFrame({"stay_id": lm["stay_id"].to_numpy()})
        for v in ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
                  "lactate", "creatinine", "wbc", "pf_ratio"]:
            lmf[v] = _ff(v)[lm.index].to_numpy()
        lmf["sofa_total"] = lm["sofa_total"].to_numpy()
        h0 = panel[panel["hour"] == 0]
        for v in ["hr", "resp_rate", "map", "spo2"]:
            v0 = pd.Series(_ff(v)[h0.index].to_numpy(), index=h0["stay_id"].to_numpy())
            base = lmf["stay_id"].map(v0).to_numpy()
            lmf[f"{v}_slope6"] = lmf[v].to_numpy() - base
        lmf["qsofa"] = _hourly_qsofa(lmf["resp_rate"], lmf["gcs"], lmf["map"])
        lmf["sirs"] = _hourly_sirs(lmf["hr"], lmf["resp_rate"], lmf["temp_c"],
                                   lmf["wbc"])
        lmf = lmf.merge(cohort[["stay_id", "age", "gender", "hospital_expire_flag"]],
                        on="stay_id", how="left")
        onset_mapped = lmf["stay_id"].map(onset)
        lmf["event"] = onset_mapped.notna().astype(int)
        lmf["onset_within_h"] = ((onset_mapped > LANDMARK_H) &
                                 (onset_mapped <= LANDMARK_H + HORIZON_H)).astype(int)

    out_path = C.OUTPUT_DIR / "21_landmark_h6_eicu.parquet"
    lmf.to_parquet(out_path, index=False)
    log_separator(log)
    log.info("saved %s: %s at-risk stays @ h6, onset-within-12h rate %.3f (%s events)",
             out_path.name, f"{len(lmf):,}", lmf['onset_within_h'].mean(),
             f"{int(lmf['onset_within_h'].sum()):,}")
    log.info("  any later onset: %s (%.3f)",
             f"{int(lmf['event'].sum()):,}", lmf['event'].mean())


if __name__ == "__main__":
    main()
