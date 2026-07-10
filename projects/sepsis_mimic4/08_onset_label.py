"""
08_onset_label.py
=================
Computes hourly SOFA from the panel (script 07), locates Sepsis-3 onset,
and emits a per-hour prediction target plus a stay-level survival summary.

Onset definition (Sepsis-3, per Seymour et al. 2016 / PhysioNet 2019)
  * SOFA is scored each hour from forward-filled panel values; missing
    components score 0 (assumed-normal baseline, per Sepsis-3).
  * Suspected infection time t_suspicion comes from script 03, expressed
    as hours relative to ICU intime.
  * t_sepsis = first hour with SOFA >= SOFA_INCREASE_THRESHOLD inside
    [t_suspicion - 48h, t_suspicion + 24h].

Per-hour target (early warning)
  For a septic stay with onset hour t*, label = 1 for t >= t* - PRED_EARLY_H
  (rewarding detection up to PRED_EARLY_H hours early) and 0 before.
  Non-septic stays are 0 throughout.

Outputs
-------
processed_data/hourly_labeled.parquet   panel + SOFA + label + time_to_onset
processed_data/08_onset_summary.parquet  one row per stay: onset/censor hour,
                                        event, competing death/discharge
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

import config as C
import utils as U
from clinical_scores import ff, qsofa, sirs, score_sofa_hourly
from logging_utils import setup_logging, step, log_separator

PRED_EARLY_H = 6                 # reward detection up to 6h before onset
SUSP_BEFORE_H = 48               # suspicion window: SOFA rise from 48h before ...
SUSP_AFTER_H = 24                # ... to 24h after t_suspicion
LANDMARK_H = 6                   # early-prediction landmark: condition on first 6h
LANDMARK_HORIZON_H = 12          # predict incident onset within 12h of the landmark
SAMPLE_STAYS = 2500              # stays exported (long) for ACF / HMM / time-varying Cox


# Hourly SOFA scoring is now in clinical_scores.score_sofa_hourly.


def main() -> None:
    ap = argparse.ArgumentParser(description="Hourly SOFA + sepsis onset labels.")
    args = ap.parse_args()

    log = setup_logging("08_onset_label")

    with step(log, "loading hourly panel + suspected infection + cohort"):
        panel = pd.read_parquet(C.OUTPUT_DIR / "07_hourly_panel.parquet")
        panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
        susp = U.load("03_suspected_infection", C.OUTPUT_DIR, parse_dates=["t_suspicion"])
        cohort = U.load("02_cohort", C.OUTPUT_DIR,
                        parse_dates=["intime", "outtime", "deathtime"])
    log.info("panel: %s stay-hours, %s stays",
             f"{len(panel):,}", f"{panel['stay_id'].nunique():,}")

    with step(log, "scoring hourly SOFA"):
        sofa = score_sofa_hourly(panel, include_urine=True)
        panel = pd.concat([panel, sofa], axis=1)

    intime = cohort.set_index("stay_id")["intime"]
    susp = susp.copy()
    susp["susp_hour"] = ((susp["t_suspicion"]
                          - susp["stay_id"].map(intime)).dt.total_seconds()
                         / 3600.0)
    susp_hour = susp.set_index("stay_id")["susp_hour"]
    panel["susp_hour"] = panel["stay_id"].map(susp_hour)
    has_susp = panel["stay_id"].map(susp_hour.notna()).fillna(False)

    with step(log, "locating sepsis onset hour"):
        in_win = (panel["hour"] >= (panel["susp_hour"] - SUSP_BEFORE_H)) & \
                 (panel["hour"] <= (panel["susp_hour"] + SUSP_AFTER_H))
        cand = (panel["sofa_total"] >= C.SOFA_INCREASE_THRESHOLD) & in_win & has_susp
        onset = (panel.loc[cand].groupby("stay_id")["hour"].min()
                 .rename("onset_hour"))
        panel["onset_hour"] = panel["stay_id"].map(onset)
        panel["sepsis3"] = panel["stay_id"].map(onset.notna()).fillna(False)

        panel["time_to_onset"] = panel["onset_hour"] - panel["hour"]
        panel["label"] = ((panel["sepsis3"]) &
                          (panel["hour"] >= panel["onset_hour"] - PRED_EARLY_H)
                          ).astype("int8")

    with step(log, "building stay-level onset summary"):
        last_hour = panel.groupby("stay_id")["hour"].max().rename("censor_hour")
        summ = cohort[["stay_id", "subject_id", "age", "gender",
                       "los_hours", "hospital_expire_flag"]].merge(
            last_hour, on="stay_id", how="inner")
        summ["onset_hour"] = summ["stay_id"].map(onset)
        summ["event"] = summ["onset_hour"].notna().astype(int)
        summ["t_event"] = np.where(summ["event"] == 1,
                                   summ["onset_hour"], summ["censor_hour"])
        summ["death_no_sepsis"] = ((summ["event"] == 0) &
                                   (summ["hospital_expire_flag"] == 1)).astype(int)
        summ["status_cr"] = np.where(summ["event"] == 1, 1,
                                     np.where(summ["death_no_sepsis"] == 1, 2, 0))

    n_stay = panel["stay_id"].nunique()
    n_sep = int(onset.notna().sum())
    log_separator(log)
    log.info("labelled panel: %s stay-hours, %s stays",
             f"{len(panel):,}", f"{n_stay:,}")
    log.info("  suspected infection stays: %s",
             f"{int(has_susp.groupby(panel['stay_id']).first().sum()):,}")
    log.info("  sepsis-3 (onset found): %s (%.1f%%)",
             f"{n_sep:,}", n_sep / n_stay * 100)
    log.info("  positive stay-hours: %s (%.1f%%)",
             f"{int(panel['label'].sum()):,}", panel['label'].mean() * 100)
    med_onset = summ.loc[summ.event == 1, "onset_hour"].median()
    log.info("  median onset hour (septic): %.0fh", med_onset)
    log.info("  competing deaths (no sepsis): %s",
             f"{int(summ['death_no_sepsis'].sum()):,}")

    out_pq = C.OUTPUT_DIR / "08_hourly_labeled.parquet"
    panel.to_parquet(out_pq, index=False)
    log.info("saved %s (%s)", out_pq.name, U.human_size(out_pq.stat().st_size))
    U.save(summ, "08_onset_summary", C.OUTPUT_DIR)

    with step(log, "exporting R-friendly derived tables"):
        export_for_report(panel, summ, cohort)


# --------------------------------------------------------------------------- #
# Derived exports (small CSVs consumed by the R reports)
# --------------------------------------------------------------------------- #
# qSOFA and SIRS scoring moved to clinical_scores.qsofa / clinical_scores.sirs.


def export_for_report(panel: pd.DataFrame, summ: pd.DataFrame,
                      cohort: pd.DataFrame) -> None:
    def _ff(v):
        return ff(panel, v)

    # ---- 1) trajectory means: mean hourly physiology by sepsis group ----
    traj = (panel.assign(hr=_ff("hr"), map=_ff("map"), resp_rate=_ff("resp_rate"),
                         sofa=panel["sofa_total"])
            .groupby(["hour", "sepsis3"])[["hr", "map", "resp_rate", "sofa"]]
            .mean().reset_index())
    traj = traj[traj["hour"] <= 48]
    U.save(traj, "08_traj_means", C.OUTPUT_DIR, fmt="csv")

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
        lmf[v] = _ff(v)[lm.index].to_numpy()
    lmf["sofa_total"] = lm["sofa_total"].to_numpy()
    h0 = panel[panel["hour"] == 0]
    for v in ["hr", "resp_rate", "map", "spo2"]:
        v0 = pd.Series(_ff(v)[h0.index].to_numpy(), index=h0["stay_id"].to_numpy())
        lmf[f"{v}_slope6"] = lmf["stay_id"].map(v0).to_numpy()
        lmf[f"{v}_slope6"] = lmf[v].to_numpy() - lmf[f"{v}_slope6"]
    lmf["qsofa"] = qsofa(lmf["resp_rate"], lmf["gcs"], lmf["map"])
    lmf["sirs"] = sirs(lmf["hr"], lmf["resp_rate"],
                       lmf["temp_c"], lmf["wbc"])
    # static
    lmf = lmf.merge(cohort[["stay_id", "age", "gender", "hospital_expire_flag"]],
                    on="stay_id", how="left")
    onset_mapped = lmf["stay_id"].map(summ.set_index("stay_id")["onset_hour"])
    censor_mapped = lmf["stay_id"].map(summ.set_index("stay_id")["censor_hour"])
    lmf["event"] = onset_mapped.notna().astype(int)
    lmf["t_event"] = np.where(lmf["event"] == 1, onset_mapped, censor_mapped) - LANDMARK_H
    lmf["t_event"] = lmf["t_event"].clip(lower=0.5)
    lmf["onset_within_h"] = ((onset_mapped > LANDMARK_H) &
                             (onset_mapped <= LANDMARK_H + LANDMARK_HORIZON_H)).astype(int)
    died = lmf["hospital_expire_flag"].fillna(0).astype(int)
    lmf["status_cr"] = np.where(lmf["event"] == 1, 1,
                                np.where(died == 1, 2, 0))
    U.save(lmf, "08_landmark_h6", C.OUTPUT_DIR)

    rng = np.random.default_rng(486649)
    ids = summ["stay_id"].to_numpy()
    samp = set(rng.choice(ids, size=min(SAMPLE_STAYS, len(ids)), replace=False))
    sp = panel[panel["stay_id"].isin(samp)].copy()
    cols = pd.DataFrame({
        "stay_id": sp["stay_id"].to_numpy(), "hour": sp["hour"].to_numpy(),
        "hr": _ff("hr")[sp.index].to_numpy(), "map": _ff("map")[sp.index].to_numpy(),
        "resp_rate": _ff("resp_rate")[sp.index].to_numpy(),
        "temp_c": _ff("temp_c")[sp.index].to_numpy(),
        "lactate": _ff("lactate")[sp.index].to_numpy(),
        "sofa_total": sp["sofa_total"].to_numpy(),
        "onset_hour": sp["onset_hour"].to_numpy(),
        "sepsis3": sp["sepsis3"].to_numpy(),
        "label": sp["label"].to_numpy()})
    U.save(cols, "08_panel_sample_long", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
