"""
11_landmark_stack.py - Tier 2 (data substrate)
===============================================
Builds the stacked multi-landmark dataset for a dynamic-prediction supermodel
(van Houwelingen 2007). Script 08 fits a single landmark at hour 6; a real-time
system must emit risk at every hour. The landmark supermodel repeats the hour-6
construction at a grid of landmark times s, stacking them with s as a covariate.
Script 12_supermodel.R then fits one penalized model with smooth s-interactions
so that plugging in the current hour gives an hourly-updating risk.

At each landmark hour s (LANDMARK_GRID):
  * eligible stays = reached hour s and not yet septic by s (at-risk)
  * features   = forward-filled physiology at s, SOFA, qSOFA, SIRS,
                 6h trajectory slopes (value@s - value@(s-6)), demographics
  * label      = incident onset within (s, s+HORIZON]
Reproduces 08_onset_label.py's hour-6 rows exactly when s == 6.

Output: processed_data/11_landmark_stack.parquet  (one row per stay x landmark)
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
import utils as U
from clinical_scores import ff, qsofa, sirs
from logging_utils import setup_logging, step, log_separator

LANDMARK_GRID = [6, 12, 18, 24, 36, 48]
HORIZON_H = 12
SLOPE_LOOKBACK_H = 6


def main() -> None:
    log = setup_logging("11_landmark_stack")

    with step(log, "loading labelled hourly panel + cohort"):
        panel = pd.read_parquet(C.OUTPUT_DIR / "08_hourly_labeled.parquet")
        panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
        cohort = U.load("02_cohort", C.OUTPUT_DIR)[
            ["stay_id", "age", "gender", "hospital_expire_flag"]]
    log.info("panel: %s stay-hours, %s stays",
             f"{len(panel):,}", f"{panel['stay_id'].nunique():,}")

    onset = panel.groupby("stay_id")["onset_hour"].first()
    censor = panel.groupby("stay_id")["hour"].max()

    VITALS_LABS = ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
                   "lactate", "creatinine", "wbc", "pf_ratio"]
    SLOPE_VARS = ["hr", "resp_rate", "map", "spo2"]

    # Pre-index panel rows by hour for fast lookup at each landmark.
    needed_hours = set(LANDMARK_GRID) | {lm - SLOPE_LOOKBACK_H for lm in LANDMARK_GRID}
    by_hour = {h: panel[panel["hour"] == h].set_index("stay_id") for h in needed_hours}

    blocks = []
    for landmark_hour in LANDMARK_GRID:
        rows_at_landmark = by_hour[landmark_hour]
        if rows_at_landmark.empty:
            log.warning("no stays observed at landmark hour %d", landmark_hour)
            continue
        onset_hours = onset.reindex(rows_at_landmark.index)
        at_risk = onset_hours.isna() | (onset_hours > landmark_hour)
        eligible = rows_at_landmark[at_risk.values]
        features = pd.DataFrame({"stay_id": eligible.index.to_numpy()})
        features["landmark_time"] = landmark_hour
        for var in VITALS_LABS:
            features[var] = ff(eligible, var).to_numpy()
        features["sofa_total"] = eligible["sofa_total"].to_numpy()
        # 6h trajectory slopes: value@landmark - value@(landmark - 6)
        lookback_rows = by_hour[landmark_hour - SLOPE_LOOKBACK_H]
        for var in SLOPE_VARS:
            past_values = ff(lookback_rows, var).reindex(eligible.index).to_numpy() \
                if not lookback_rows.empty else np.full(len(eligible), np.nan)
            features[f"{var}_slope6"] = features[var].to_numpy() - past_values
        features["qsofa"] = qsofa(features["resp_rate"], features["gcs"], features["map"]).to_numpy()
        features["sirs"] = sirs(features["hr"], features["resp_rate"], features["temp_c"], features["wbc"]).to_numpy()
        onset_at_eligible = onset.reindex(eligible.index)
        features["onset_within_h"] = ((onset_at_eligible > landmark_hour)
                                      & (onset_at_eligible <= landmark_hour + HORIZON_H)).astype(int).to_numpy()
        event_indicator = onset_at_eligible.notna().astype(int)
        censor_hours = censor.reindex(eligible.index)
        time_to_event = np.where(event_indicator == 1, onset_at_eligible, censor_hours) - landmark_hour
        features["event"] = event_indicator.to_numpy()
        features["t_event"] = np.clip(time_to_event, 0.5, None)
        blocks.append(features)
        log.info("  s=%2dh: %6s at-risk, %5s onset within %dh (%.1f%%)",
                 landmark_hour, f"{len(features):,}",
                 f"{int(features['onset_within_h'].sum()):,}",
                 HORIZON_H, features['onset_within_h'].mean() * 100)

    stack = pd.concat(blocks, ignore_index=True)
    stack = stack.merge(cohort, on="stay_id", how="left")
    log_separator(log)
    log.info("stacked landmark dataset: %s rows across %d landmarks, %s stays",
             f"{len(stack):,}", len(LANDMARK_GRID),
             f"{stack['stay_id'].nunique():,}")
    U.save(stack, "11_landmark_stack", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
