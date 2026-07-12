"""
14_realtime_holdout.py - Analysis 4 (data substrate)
=================================================
Builds an all-hours feature stream for a random holdout of stays, enabling
the landmark supermodel to emit hourly risk at every hour (not just the 6
landmark grid points). This is the input the PhysioNet-2019 utility score
and alarm-burden analysis require.

Features match 11_landmark_stack.py exactly (landmark_time = current hour).
For each holdout stay, every hour h in [6, last_pred_hour] is emitted,
where last_pred_hour is onset_hour (septic) or censor_hour (non-septic).

Output: processed_data/14_realtime_holdout_features.parquet
        processed_data/realtime_holdout_ids.csv (holdout stay_ids, so
        15_realtime_eval.R trains on the complement to avoid leakage)
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
import utils as U
from clinical_scores import ff, qsofa, sirs
from logging_utils import setup_logging, step, log_separator

N_HOLDOUT = 6000
START_H = 6
SLOPE_LOOKBACK_H = 6
SEED = 486649


def main():
    log = setup_logging("14_realtime_holdout")

    with step(log, "loading labelled hourly panel + cohort"):
        panel = pd.read_parquet(C.OUTPUT_DIR / "08_hourly_labeled.parquet")
        panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
        cohort = U.load("02_cohort", C.OUTPUT_DIR)[
            ["stay_id", "age", "gender", "hospital_expire_flag"]]

    onset = panel.groupby("stay_id")["onset_hour"].first()
    censor = panel.groupby("stay_id")["hour"].max()

    rng = np.random.default_rng(SEED)
    all_stay_ids = np.array(sorted(panel["stay_id"].unique()))
    holdout_ids = rng.choice(all_stay_ids, size=min(N_HOLDOUT, len(all_stay_ids)), replace=False)
    pd.DataFrame({"stay_id": np.sort(holdout_ids)}).to_csv(
        C.OUTPUT_DIR / "14_realtime_holdout_ids.csv", index=False)
    log.info("holdout sample: %s / %s stays (seed=%d)",
             f"{len(holdout_ids):,}", f"{len(all_stay_ids):,}", SEED)

    with step(log, "building holdout feature stream"):
        holdout_panel = panel[panel["stay_id"].isin(holdout_ids)].copy()
        onset_values = onset.reindex(holdout_panel["stay_id"].values).to_numpy()
        censor_values = censor.reindex(holdout_panel["stay_id"].values).to_numpy()
        # Each stay is scored up to onset (septic) or censor (non-septic).
        last_pred_hour = np.where(np.isnan(onset_values), censor_values, onset_values)
        in_range = ((holdout_panel["hour"].to_numpy() >= START_H)
                    & (holdout_panel["hour"].to_numpy() <= last_pred_hour))
        holdout_panel = holdout_panel[in_range].copy()

        VITALS_LABS = ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
                       "lactate", "creatinine", "wbc", "pf_ratio"]
        SLOPE_VARS = ["hr", "resp_rate", "map", "spo2"]

        features = pd.DataFrame({"stay_id": holdout_panel["stay_id"].to_numpy(),
                                  "hour": holdout_panel["hour"].to_numpy()})
        features["landmark_time"] = holdout_panel["hour"].to_numpy()
        for var in VITALS_LABS:
            features[var] = ff(holdout_panel, var).to_numpy()
        features["sofa_total"] = holdout_panel["sofa_total"].to_numpy()

        # 6h slope: look up each variable's value 6 hours ago via composite key.
        for var in SLOPE_VARS:
            ff_values = ff(panel, var)
            composite_key = panel["stay_id"].to_numpy() * 100000 + panel["hour"].to_numpy()
            value_by_key = pd.Series(ff_values.to_numpy(), index=composite_key)
            current_key = features["stay_id"].to_numpy() * 100000 + features["hour"].to_numpy()
            lookback_key = features["stay_id"].to_numpy() * 100000 + (features["hour"].to_numpy() - SLOPE_LOOKBACK_H)
            features[f"{var}_slope6"] = features[var].to_numpy() - value_by_key.reindex(lookback_key).to_numpy()

        features["qsofa"] = qsofa(features["resp_rate"], features["gcs"], features["map"]).to_numpy()
        features["sirs"] = sirs(features["hr"], features["resp_rate"], features["temp_c"], features["wbc"]).to_numpy()
        features = features.merge(cohort, on="stay_id", how="left")
        features["onset_hour"] = onset.reindex(features["stay_id"].values).to_numpy()

    log_separator(log)
    log.info("holdout: %s stays, %s stay-hours scored (hours %d..onset/censor)",
             f"{len(holdout_ids):,}", f"{len(features):,}", START_H)
    U.save(features, "14_realtime_holdout_features", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
