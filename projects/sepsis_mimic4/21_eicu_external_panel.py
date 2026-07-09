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
processed_data/landmark_h6_eicu.csv   same schema as landmark_h6.csv
"""
from __future__ import annotations

import gzip

import numpy as np
import pandas as pd

import config as C
import utils as U

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
def _parse_age(s: pd.Series) -> pd.Series:
    a = s.astype("string").str.extract(r"(\d+)")[0]
    a = pd.to_numeric(a, errors="coerce")
    # eICU stores "> 89" for ages above 89; mapped to 90 for consistency.
    a = a.where(~s.astype("string").str.contains(">", na=False), 90)
    return a


def build_cohort() -> pd.DataFrame:
    U.log("loading eICU patient table ...")
    pat = pd.read_csv(
        EICU_DIR / "patient.csv.gz",
        usecols=["patientunitstayid", "uniquepid", "patienthealthsystemstayid",
                 "gender", "age", "unitvisitnumber", "unitdischargeoffset",
                 "hospitaldischargestatus", "hospitaladmitoffset"],
        low_memory=False,
    )
    pat["age"] = _parse_age(pat["age"])
    pat["los_hours"] = pd.to_numeric(pat["unitdischargeoffset"],
                                     errors="coerce") / 60.0
    pat["gender"] = pat["gender"].map({"Female": "F", "Male": "M"})
    pat["hospital_expire_flag"] = (
        pat["hospitaldischargestatus"].astype("string").str.strip()
        .eq("Expired").fillna(False).astype(int))

    n0 = len(pat)
    pat = pat[pat["age"] >= C.MIN_AGE]
    n1 = len(pat)
    pat = pat[pat["los_hours"] >= C.MIN_ICU_LOS_HOURS]
    n2 = len(pat)
    # First ICU stay per patient: smallest visit number, then earliest admit.
    pat = (pat.sort_values(["unitvisitnumber", "hospitaladmitoffset"])
             .groupby("uniquepid", as_index=False).first())
    n3 = len(pat)
    U.log(f"  adults >= {C.MIN_AGE}: {n0:,} -> {n1:,}")
    U.log(f"  LOS >= {C.MIN_ICU_LOS_HOURS}h: {n1:,} -> {n2:,}")
    U.log(f"  first ICU stay/patient: {n2:,} -> {n3:,}")
    return pat[["patientunitstayid", "uniquepid", "gender", "age",
                "los_hours", "hospital_expire_flag"]].rename(
        columns={"patientunitstayid": "stay_id"})


# --------------------------------------------------------------------------- #
# 2. Streaming hourly aggregation of a big offset-keyed eICU table
# --------------------------------------------------------------------------- #
def _hour_of(offset_min: pd.Series) -> pd.Series:
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
        g = long.groupby(["stay_id", "hour", "var"])["value"].agg(
            vmin="min", vmax="max", vsum="sum", vcount="count").reset_index()
        partials.append(g)
        if len(partials) >= 30:
            partials = [_fold(partials)]
    U.log(f"  {path.name}: scanned {total:,} rows")
    if not partials:
        return pd.DataFrame(columns=["stay_id", "hour", "var",
                                     "vmin", "vmax", "vsum", "vcount"])
    return _fold(partials)


def _fold(partials):
    allp = pd.concat(partials, ignore_index=True)
    return allp.groupby(["stay_id", "hour", "var"]).agg(
        vmin=("vmin", "min"), vmax=("vmax", "max"),
        vsum=("vsum", "sum"), vcount=("vcount", "sum")).reset_index()


def reduce_var(long, var, how):
    sub = long[long["var"] == var]
    if sub.empty:
        return pd.Series(dtype="float64")
    g = sub.groupby(["stay_id", "hour"])
    if how == "mean":
        gg = g.agg(vsum=("vsum", "sum"), vcount=("vcount", "sum"))
        return (gg["vsum"] / gg["vcount"]).rename("value")
    if how == "min":
        return g["vmin"].min().rename("value")
    if how == "max":
        return g["vmax"].max().rename("value")
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
        name = chunk["drugname"].astype("string").str.lower()
        kind = pd.Series(pd.NA, index=chunk.index, dtype="string")
        for sub, grp in VASO_KINDS.items():
            kind = kind.mask(name.str.contains(sub, na=False, regex=False), grp)
        sub = chunk[kind.notna()].copy()
        if sub.empty:
            continue
        sub["kind"] = kind[kind.notna()]
        sub["hour"] = _hour_of(sub["infusionoffset"])
        sub = sub[(sub["hour"] >= 0) & (sub["hour"] <= MAX_H)]
        sub["is_wb"] = name.loc[sub.index].str.contains("mcg/kg/min",
                                                        na=False, regex=False)
        sub["rate"] = pd.to_numeric(sub["drugrate"], errors="coerce")
        rows.append(sub[["patientunitstayid", "hour", "kind", "is_wb", "rate"]])
    if not rows:
        return pd.DataFrame(columns=["stay_id", "hour"])
    iv = pd.concat(rows, ignore_index=True).rename(
        columns={"patientunitstayid": "stay_id"})
    out = pd.DataFrame(index=iv.groupby(["stay_id", "hour"]).size().index)
    for g in ["norepi_epi", "dopamine", "dobutamine", "other_vaso"]:
        present = (iv[iv["kind"] == g].groupby(["stay_id", "hour"]).size()
                   .reindex(out.index).fillna(0) > 0)
        out[f"{g}_any"] = present
    # dose-dependent rates (only meaningful when charted in mcg/kg/min)
    wb = iv[iv["is_wb"]]
    out["norepi_epi_rate"] = (wb[wb["kind"] == "norepi_epi"]
                              .groupby(["stay_id", "hour"])["rate"].max())
    out["dopamine_rate"] = (wb[wb["kind"] == "dopamine"]
                            .groupby(["stay_id", "hour"])["rate"].max())
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any"]:
        out[c] = out[c].fillna(False).astype(bool)
    return out.reset_index()


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
        pair = susp.merge(micro.rename(columns={"patientunitstayid": "stay_id"}),
                          on="stay_id", how="left")
        d = pair["t_cx_h"] - pair["t_abx_h"]
        arm1 = (d >= 0) & (d <= C.ABX_BEFORE_CULTURE_HOURS)     # cx after abx
        arm2 = (d < 0) & (-d <= C.CULTURE_BEFORE_ABX_HOURS)     # cx before abx
        pair["t_susp"] = np.where(arm2, pair["t_cx_h"], pair["t_abx_h"])
        pair["ok"] = (arm1 | arm2).fillna(False)
        # prefer a culture-confirmed suspicion time; else antibiotic time
        confirmed = (pair[pair["ok"]].sort_values("t_susp")
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
    h_stay = np.floor(np.minimum(cohort["los_hours"].to_numpy(),
                                 float(MAX_H))).astype(int)
    h_stay = np.clip(h_stay, 0, MAX_H)
    reps = h_stay + 1
    stay_rep = np.repeat(cohort["stay_id"].to_numpy(), reps)
    hour_rep = np.concatenate([np.arange(0, n) for n in reps])
    return pd.DataFrame({"stay_id": stay_rep.astype("int64"),
                         "hour": hour_rep.astype("int64")})


def score_sofa(panel):
    """Same logic as 08_onset_label.score_sofa (urine omitted: requires 24h of
    record and never fires at the h6 landmark)."""
    def ff(v):
        return panel[f"{v}_ff"] if f"{v}_ff" in panel.columns else panel[v]

    pf = ff("pf_ratio")
    resp = np.select([pf < 100, pf < 200, pf < 300, pf < 400], [4, 3, 2, 1], 0)
    plt = ff("platelets")
    coag = np.select([plt < 20, plt < 50, plt < 100, plt < 150], [4, 3, 2, 1], 0)
    bil = ff("bilirubin")
    liver = np.select([bil >= 12, bil >= 6, bil >= 2, bil >= 1.2], [4, 3, 2, 1], 0)
    mp = ff("map")
    cardio = np.where(mp < 70, 1, 0)
    cardio = np.maximum(cardio, np.where(panel["dobutamine_any"].fillna(False), 2, 0))
    cardio = np.maximum(cardio, np.where(panel["other_vaso_any"].fillna(False), 3, 0))
    dop = panel.get("dopamine_rate", pd.Series(np.nan, index=panel.index))
    dop_any = panel["dopamine_any"].fillna(False).to_numpy()
    dop_score = np.where(dop > 15, 4, np.where(dop > 5, 3, 2))
    cardio = np.maximum(cardio, np.where(dop_any, dop_score, 0))
    ne = panel.get("norepi_epi_rate", pd.Series(np.nan, index=panel.index))
    ne_any = panel["norepi_epi_any"].fillna(False).to_numpy()
    ne_score = np.where(ne > 0.1, 4, 3)
    cardio = np.maximum(cardio, np.where(ne_any, ne_score, 0))
    gcs = ff("gcs").fillna(15)
    cns = np.select([gcs < 6, gcs < 10, gcs < 13, gcs < 15], [4, 3, 2, 1], 0)
    cr = ff("creatinine")
    renal = np.select([cr >= 5, cr >= 3.5, cr >= 2.0, cr >= 1.2], [4, 3, 2, 1], 0)
    out = pd.DataFrame({"sofa_resp": resp, "sofa_coag": coag, "sofa_liver": liver,
                        "sofa_cardio": cardio, "sofa_cns": cns,
                        "sofa_renal": renal}, index=panel.index).astype("int8")
    out["sofa_total"] = out.sum(axis=1).astype("int8")
    return out


def _hourly_qsofa(rr, gcs, mp):
    return ((rr >= 22).astype(int) + (gcs < 15).astype(int)
            + (mp < 70).astype(int))


def _hourly_sirs(hr, rr, temp, wbc):
    return ((hr > 90).astype(int) + (rr > 20).astype(int)
            + ((temp > 38) | (temp < 36)).astype(int)
            + ((wbc > 12) | (wbc < 4)).astype(int))


def main():
    cohort = build_cohort()
    keep_ids = set(cohort["stay_id"].astype("int64"))
    U.log(f"eICU cohort: {len(cohort):,} stays")

    # ---- long hourly measurements ----
    meas = pd.concat([get_vitals(keep_ids), get_nursecharting(keep_ids),
                      get_labs(keep_ids)], ignore_index=True)

    U.log("folding variables onto the hourly grid ...")
    panel = build_grid(cohort).set_index(["stay_id", "hour"])
    reductions = {"hr": "mean", "resp_rate": "mean", "spo2": "min",
                  "map": "min", "temp_c": "mean", "gcs": "min",
                  "lactate": "max", "creatinine": "max", "wbc": "max",
                  "platelets": "min", "bilirubin": "max", "pao2": "min",
                  "fio2": "max"}
    for var, how in reductions.items():
        panel[var] = reduce_var(meas, var, how)
    panel = panel.reset_index()

    # ---- unit handling (mirror 07) ----
    panel["temp_c"] = panel["temp_c"].clip(lower=25, upper=45)
    panel["fio2"] = panel["fio2"].where(panel["fio2"] <= 1.0,
                                        panel["fio2"] / 100.0).clip(0.21, 1.0)
    panel["map"] = panel["map"].clip(lower=10, upper=250)
    panel["spo2"] = panel["spo2"].clip(lower=0, upper=100)
    panel["gcs"] = panel["gcs"].clip(lower=3, upper=15)
    panel["pf_ratio"] = panel["pao2"] / panel["fio2"]

    # ---- vasopressors ----
    vaso = get_vaso(keep_ids)
    if not vaso.empty:
        panel = panel.merge(vaso, on=["stay_id", "hour"], how="left")
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any"]:
        panel[c] = panel[c].fillna(False).astype(bool) if c in panel else False

    # ---- forward-fill within stay ----
    U.log("forward-filling core variables ...")
    panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
    g = panel.groupby("stay_id", sort=False)
    for v in CORE_VARS:
        if v in panel.columns:
            panel[f"{v}_ff"] = g[v].ffill()

    # ---- hourly SOFA + onset labelling ----
    U.log("scoring hourly SOFA + locating onset ...")
    sofa = score_sofa(panel)
    panel = pd.concat([panel, sofa], axis=1)

    susp_hour = suspected_infection(keep_ids)
    panel["susp_hour"] = panel["stay_id"].map(susp_hour)
    has_susp = panel["stay_id"].map(susp_hour.notna()).fillna(False)
    in_win = (panel["hour"] >= (panel["susp_hour"] - SUSP_BEFORE_H)) & \
             (panel["hour"] <= (panel["susp_hour"] + SUSP_AFTER_H))
    cand = (panel["sofa_total"] >= SOFA_THRESH) & in_win & has_susp
    onset = panel.loc[cand].groupby("stay_id")["hour"].min().rename("onset_hour")

    # ---- landmark table at h6 (mirror export_for_report in 08) ----
    U.log("building the hour-6 landmark table ...")
    def ff(v):
        return panel[f"{v}_ff"] if f"{v}_ff" in panel.columns else panel[v]

    lm = panel[panel["hour"] == LANDMARK_H].copy()
    onset_h_lm = lm["stay_id"].map(onset)
    at_risk = onset_h_lm.isna() | (onset_h_lm > LANDMARK_H)
    lm = lm[at_risk].copy()

    lmf = pd.DataFrame({"stay_id": lm["stay_id"].to_numpy()})
    for v in ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
              "lactate", "creatinine", "wbc", "pf_ratio"]:
        lmf[v] = ff(v)[lm.index].to_numpy()
    lmf["sofa_total"] = lm["sofa_total"].to_numpy()
    h0 = panel[panel["hour"] == 0]
    for v in ["hr", "resp_rate", "map", "spo2"]:
        v0 = pd.Series(ff(v)[h0.index].to_numpy(), index=h0["stay_id"].to_numpy())
        base = lmf["stay_id"].map(v0).to_numpy()
        lmf[f"{v}_slope6"] = lmf[v].to_numpy() - base
    lmf["qsofa"] = _hourly_qsofa(lmf["resp_rate"], lmf["gcs"], lmf["map"])
    lmf["sirs"] = _hourly_sirs(lmf["hr"], lmf["resp_rate"], lmf["temp_c"],
                               lmf["wbc"])
    lmf = lmf.merge(cohort[["stay_id", "age", "gender", "hospital_expire_flag"]],
                    on="stay_id", how="left")
    o = lmf["stay_id"].map(onset)
    lmf["event"] = o.notna().astype(int)
    lmf["onset_within_h"] = ((o > LANDMARK_H) &
                             (o <= LANDMARK_H + HORIZON_H)).astype(int)

    out = C.OUTPUT_DIR / "landmark_h6_eicu.csv"
    lmf.to_csv(out, index=False)
    U.log("=" * 60)
    U.log(f"wrote {out.name}: {len(lmf):,} at-risk stays @ h6, "
          f"onset-within-12h rate {lmf['onset_within_h'].mean():.3f} "
          f"({int(lmf['onset_within_h'].sum()):,} events)")
    U.log(f"  any later onset: {int(lmf['event'].sum()):,} "
          f"({lmf['event'].mean():.3f})")


if __name__ == "__main__":
    main()
