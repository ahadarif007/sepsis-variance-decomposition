"""
08_onset_label.py
=================
Turns the hourly panel (script 07) into a **time-resolved sepsis label** — the
piece the static pipeline never had. It computes SOFA every hour, locates the
hour sepsis begins, and emits a per-hour prediction target aligned for
*early* warning, plus a stay-level time-to-onset summary for survival analysis.

Onset definition (Sepsis-3, operationalised as in Seymour et al. 2016 /
PhysioNet 2019)
  * SOFA is scored each hour from the forward-filled panel values; a component
    with no data yet scores 0 (assumed-normal baseline, per Sepsis-3).
  * Suspected infection contributes t_suspicion (script 03), expressed as an
    hour relative to ICU intime.
  * t_sepsis = the FIRST hour at which hourly SOFA >= SOFA_INCREASE_THRESHOLD
    that falls inside the suspicion window [susp_hour - 48h, susp_hour + 24h].
    A stay with such an hour (within the 72h panel horizon) is a sepsis case.

Per-hour target (early warning)
  For a septic stay with onset hour t*, label_t = 1 for t >= t* - PRED_EARLY_H
  (so the model is rewarded for flagging sepsis up to PRED_EARLY_H hours early)
  and 0 before that. Non-septic stays are label_t = 0 throughout. We also keep
  time_to_onset = t* - t for time-to-event work.

Outputs
-------
processed_data/hourly_labeled.parquet   panel + SOFA(+components) + label + time_to_onset
processed_data/onset_summary.csv        one row per stay: onset/censor hour, event,
                                        competing death/discharge — for survival analysis
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

import config as C
import utils as U

PRED_EARLY_H = 6                 # reward detection up to 6h before onset
SUSP_BEFORE_H = 48               # suspicion window: SOFA rise from 48h before ...
SUSP_AFTER_H = 24                # ... to 24h after t_suspicion
LANDMARK_H = 6                   # early-prediction landmark: condition on first 6h
LANDMARK_HORIZON_H = 12          # predict incident onset within 12h of the landmark
SAMPLE_STAYS = 2500              # stays exported (long) for ACF / HMM / time-varying Cox


# --------------------------------------------------------------------------- #
# Hourly SOFA (vectorised over panel rows, using forward-filled values)
# --------------------------------------------------------------------------- #
def _col(panel: pd.DataFrame, base: str) -> pd.Series:
    """Prefer the forward-filled column; fall back to raw if absent."""
    return panel[f"{base}_ff"] if f"{base}_ff" in panel.columns else panel[base]


def score_sofa(panel: pd.DataFrame) -> pd.DataFrame:
    pf = _col(panel, "pf_ratio")
    resp = np.select([pf < 100, pf < 200, pf < 300, pf < 400], [4, 3, 2, 1], 0)

    plt = _col(panel, "platelets")
    coag = np.select([plt < 20, plt < 50, plt < 100, plt < 150], [4, 3, 2, 1], 0)

    bil = _col(panel, "bilirubin")
    liver = np.select([bil >= 12, bil >= 6, bil >= 2, bil >= 1.2], [4, 3, 2, 1], 0)

    mp = _col(panel, "map")
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

    gcs = _col(panel, "gcs").fillna(15)
    cns = np.select([gcs < 6, gcs < 10, gcs < 13, gcs < 15], [4, 3, 2, 1], 0)

    cr = _col(panel, "creatinine")
    renal = np.select([cr >= 5, cr >= 3.5, cr >= 2.0, cr >= 1.2], [4, 3, 2, 1], 0)
    # urine over the trailing 24h (only once >=24h of record exists)
    if "urine_ml" in panel.columns:
        u24 = (panel.groupby("stay_id", sort=False)["urine_ml"]
               .rolling(24, min_periods=24).sum()
               .reset_index(level=0, drop=True))
        renal = np.maximum(renal, np.select(
            [u24 < 200, u24 < 500], [4, 3], 0))

    out = pd.DataFrame({
        "sofa_resp": resp, "sofa_coag": coag, "sofa_liver": liver,
        "sofa_cardio": cardio, "sofa_cns": cns, "sofa_renal": renal},
        index=panel.index).astype("int8")
    out["sofa_total"] = out.sum(axis=1).astype("int8")
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Hourly SOFA + sepsis onset labels.")
    args = ap.parse_args()

    U.log("loading hourly panel + suspected infection + cohort ...")
    panel = pd.read_parquet(C.OUTPUT_DIR / "hourly_panel.parquet")
    panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
    susp = U.load("suspected_infection", C.OUTPUT_DIR, parse_dates=["t_suspicion"])
    cohort = U.load("cohort", C.OUTPUT_DIR,
                    parse_dates=["intime", "outtime", "deathtime"])

    U.log("scoring hourly SOFA ...")
    sofa = score_sofa(panel)
    panel = pd.concat([panel, sofa], axis=1)

    # suspicion hour relative to intime (>=0)
    intime = cohort.set_index("stay_id")["intime"]
    susp = susp.copy()
    susp["susp_hour"] = ((susp["t_suspicion"]
                          - susp["stay_id"].map(intime)).dt.total_seconds()
                         / 3600.0)
    susp_hour = susp.set_index("stay_id")["susp_hour"]
    panel["susp_hour"] = panel["stay_id"].map(susp_hour)
    has_susp = panel["stay_id"].map(susp_hour.notna()).fillna(False)

    U.log("locating sepsis onset hour ...")
    # candidate onset: SOFA>=thresh AND inside suspicion window
    in_win = (panel["hour"] >= (panel["susp_hour"] - SUSP_BEFORE_H)) & \
             (panel["hour"] <= (panel["susp_hour"] + SUSP_AFTER_H))
    cand = (panel["sofa_total"] >= C.SOFA_INCREASE_THRESHOLD) & in_win & has_susp
    onset = (panel.loc[cand].groupby("stay_id")["hour"].min()
             .rename("onset_hour"))
    panel["onset_hour"] = panel["stay_id"].map(onset)
    panel["sepsis3"] = panel["stay_id"].map(onset.notna()).fillna(False)

    # per-hour early-warning label + time to onset
    panel["time_to_onset"] = panel["onset_hour"] - panel["hour"]
    panel["label"] = ((panel["sepsis3"]) &
                      (panel["hour"] >= panel["onset_hour"] - PRED_EARLY_H)
                      ).astype("int8")

    # ---- stay-level onset summary for survival analysis ----
    U.log("building stay-level onset summary ...")
    last_hour = panel.groupby("stay_id")["hour"].max().rename("censor_hour")
    summ = cohort[["stay_id", "subject_id", "age", "gender",
                   "los_hours", "hospital_expire_flag"]].merge(
        last_hour, on="stay_id", how="inner")
    summ["onset_hour"] = summ["stay_id"].map(onset)
    summ["event"] = summ["onset_hour"].notna().astype(int)   # 1 = sepsis onset
    # time-to-event: onset hour if event, else censoring hour
    summ["t_event"] = np.where(summ["event"] == 1,
                               summ["onset_hour"], summ["censor_hour"])
    # competing outcome: died within the horizon without sepsis onset
    summ["death_no_sepsis"] = ((summ["event"] == 0) &
                               (summ["hospital_expire_flag"] == 1)).astype(int)
    # competing-risk status: 0 censored, 1 sepsis, 2 death-without-sepsis
    summ["status_cr"] = np.where(summ["event"] == 1, 1,
                                 np.where(summ["death_no_sepsis"] == 1, 2, 0))

    # ---- report ----
    n_stay = panel["stay_id"].nunique()
    n_sep = int(onset.notna().sum())
    U.log("=" * 56)
    U.log(f"labelled panel: {len(panel):,} stay-hours, {n_stay:,} stays")
    U.log(f"  suspected infection stays: {int(has_susp.groupby(panel['stay_id']).first().sum()):,}")
    U.log(f"  sepsis-3 (onset found):    {n_sep:,} ({n_sep/n_stay:.1%})")
    U.log(f"  positive stay-hours:       {int(panel['label'].sum()):,} "
          f"({panel['label'].mean():.1%})")
    med_onset = summ.loc[summ.event == 1, "onset_hour"].median()
    U.log(f"  median onset hour (septic): {med_onset:.0f}h")
    U.log(f"  competing deaths (no sepsis): {int(summ['death_no_sepsis'].sum()):,}")

    out_pq = C.OUTPUT_DIR / "hourly_labeled.parquet"
    panel.to_parquet(out_pq, index=False)
    U.log(f"wrote {out_pq.name} ({U.human_size(out_pq.stat().st_size)})")
    U.save(summ, "onset_summary", C.OUTPUT_DIR, fmt="csv")

    export_for_report(panel, summ, cohort)


# --------------------------------------------------------------------------- #
# R-friendly derived exports (small CSVs the longitudinal report reads, so the
# report needs no parquet reader). All computed off the labelled panel.
# --------------------------------------------------------------------------- #
def _hourly_qsofa(row_rr, row_gcs, row_map) -> np.ndarray:
    # qSOFA (MAP<70 used as a proxy for SBP<=100, since the panel carries MAP).
    return ((row_rr >= 22).astype(int) + (row_gcs < 15).astype(int)
            + (row_map < 70).astype(int))


def _hourly_sirs(hr, rr, temp, wbc) -> np.ndarray:
    return ((hr > 90).astype(int) + (rr > 20).astype(int)
            + ((temp > 38) | (temp < 36)).astype(int)
            + ((wbc > 12) | (wbc < 4)).astype(int))


def export_for_report(panel: pd.DataFrame, summ: pd.DataFrame,
                      cohort: pd.DataFrame) -> None:
    U.log("exporting R-friendly derived tables for the report ...")

    def ff(v):
        return panel[f"{v}_ff"] if f"{v}_ff" in panel.columns else panel[v]

    # ---- 1) trajectory means: mean hourly physiology by sepsis group ----
    traj = (panel.assign(hr=ff("hr"), map=ff("map"), resp_rate=ff("resp_rate"),
                         sofa=panel["sofa_total"])
            .groupby(["hour", "sepsis3"])[["hr", "map", "resp_rate", "sofa"]]
            .mean().reset_index())
    traj = traj[traj["hour"] <= 48]
    U.save(traj, "traj_means", C.OUTPUT_DIR, fmt="csv")

    # ---- 2) landmark cohort at hour LANDMARK_H (early-prediction design) ----
    lm = panel[panel["hour"] == LANDMARK_H].copy()
    keep = summ.set_index("stay_id")
    lm = lm[lm["stay_id"].isin(keep.index)]
    # at-risk = reached the landmark and not already septic by then
    onset_h = lm["stay_id"].map(summ.set_index("stay_id")["onset_hour"])
    at_risk = onset_h.isna() | (onset_h > LANDMARK_H)
    lm = lm[at_risk].copy()
    lmf = pd.DataFrame({"stay_id": lm["stay_id"].to_numpy()})
    for v in ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
              "lactate", "creatinine", "wbc", "pf_ratio"]:
        lmf[v] = ff(v)[lm.index].to_numpy()
    lmf["sofa_total"] = lm["sofa_total"].to_numpy()
    # first-6h trajectory slopes (deterioration signal): value@6h - value@0h.
    h0 = panel[panel["hour"] == 0]
    for v in ["hr", "resp_rate", "map", "spo2"]:
        v0 = pd.Series(ff(v)[h0.index].to_numpy(), index=h0["stay_id"].to_numpy())
        lmf[f"{v}_slope6"] = lmf["stay_id"].map(v0).to_numpy()
        lmf[f"{v}_slope6"] = lmf[v].to_numpy() - lmf[f"{v}_slope6"]
    lmf["qsofa"] = _hourly_qsofa(lmf["resp_rate"], lmf["gcs"], lmf["map"])
    lmf["sirs"] = _hourly_sirs(lmf["hr"], lmf["resp_rate"],
                               lmf["temp_c"], lmf["wbc"])
    # static
    lmf = lmf.merge(cohort[["stay_id", "age", "gender", "hospital_expire_flag"]],
                    on="stay_id", how="left")
    o = lmf["stay_id"].map(summ.set_index("stay_id")["onset_hour"])
    cens = lmf["stay_id"].map(summ.set_index("stay_id")["censor_hour"])
    lmf["event"] = o.notna().astype(int)                       # incident onset after LM
    lmf["t_event"] = np.where(lmf["event"] == 1, o, cens) - LANDMARK_H
    lmf["t_event"] = lmf["t_event"].clip(lower=0.5)            # Cox needs >0
    lmf["onset_within_h"] = ((o > LANDMARK_H) &
                             (o <= LANDMARK_H + LANDMARK_HORIZON_H)).astype(int)
    died = lmf["hospital_expire_flag"].fillna(0).astype(int)
    lmf["status_cr"] = np.where(lmf["event"] == 1, 1,
                                np.where(died == 1, 2, 0))
    U.save(lmf, "landmark_h6", C.OUTPUT_DIR, fmt="csv")
    U.log(f"  landmark cohort at hour {LANDMARK_H}: {len(lmf):,} at-risk stays, "
          f"{int(lmf['event'].sum()):,} later onset "
          f"({lmf['event'].mean():.1%}); within {LANDMARK_HORIZON_H}h: "
          f"{int(lmf['onset_within_h'].sum()):,}")

    # ---- 3) sampled long panel for ACF / HMM / time-varying Cox ----
    rng = np.random.default_rng(486649)
    ids = summ["stay_id"].to_numpy()
    samp = set(rng.choice(ids, size=min(SAMPLE_STAYS, len(ids)), replace=False))
    sp = panel[panel["stay_id"].isin(samp)].copy()
    cols = pd.DataFrame({
        "stay_id": sp["stay_id"].to_numpy(), "hour": sp["hour"].to_numpy(),
        "hr": ff("hr")[sp.index].to_numpy(), "map": ff("map")[sp.index].to_numpy(),
        "resp_rate": ff("resp_rate")[sp.index].to_numpy(),
        "temp_c": ff("temp_c")[sp.index].to_numpy(),
        "lactate": ff("lactate")[sp.index].to_numpy(),
        "sofa_total": sp["sofa_total"].to_numpy(),
        "onset_hour": sp["onset_hour"].to_numpy(),
        "sepsis3": sp["sepsis3"].to_numpy(),
        "label": sp["label"].to_numpy()})
    U.save(cols, "panel_sample_long", C.OUTPUT_DIR, fmt="csv")


if __name__ == "__main__":
    main()
