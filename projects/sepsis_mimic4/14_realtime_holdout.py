"""
14_realtime_holdout.py  --  TIER 4 (data substrate)
====================================================
Builds an ALL-HOURS feature stream for a random holdout of stays, so the
landmark supermodel can emit an hourly risk at every hour (not just the 6
landmark points) -- the input the PhysioNet-2019 utility score and the
alarm-burden analysis need.

Features are IDENTICAL to 11_landmark_stack.py (only 'landmark_time' becomes the
current hour). For each holdout stay we emit every hour h in [6, last_pred_hour],
where last_pred_hour = onset_hour (septic) or censor_hour (non-septic): we score
from hour 6 (need 6h of history for slopes) until onset or discharge.

Output: processed_data/realtime_holdout_features.csv
        (+ processed_data/realtime_holdout_ids.csv : the stay_ids held out, so
         15_realtime_eval.R trains the supermodel on everyone else -> no leakage)
Run from projects/sepsis_mimic4/ with framework python3.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
import utils as U

N_HOLDOUT = 6000
START_H = 6
SLOPE_LOOKBACK_H = 6
SEED = 486649


def ff(panel, v):
    return panel[f"{v}_ff"] if f"{v}_ff" in panel.columns else panel[v]


def qsofa(rr, gcs, mp):
    # quickSOFA: resp rate >=22, GCS <15, and MAP <70 as a proxy for SBP <=100.
    return (rr >= 22).astype(int) + (gcs < 15).astype(int) + (mp < 70).astype(int)


def sirs(hr, rr, temp, wbc):
    # SIRS: HR >90, resp rate >20, temp outside [36, 38]C, WBC outside [4, 12] K/uL.
    return ((hr > 90).astype(int) + (rr > 20).astype(int)
            + ((temp > 38) | (temp < 36)).astype(int)
            + ((wbc > 12) | (wbc < 4)).astype(int))


def main():
    U.log("loading labelled hourly panel + cohort ...")
    panel = pd.read_parquet(C.OUTPUT_DIR / "hourly_labeled.parquet")
    panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
    cohort = U.load("cohort", C.OUTPUT_DIR)[
        ["stay_id", "age", "gender", "hospital_expire_flag"]]

    onset = panel.groupby("stay_id")["onset_hour"].first()
    censor = panel.groupby("stay_id")["hour"].max()

    rng = np.random.default_rng(SEED)
    ids = np.array(sorted(panel["stay_id"].unique()))
    hold = rng.choice(ids, size=min(N_HOLDOUT, len(ids)), replace=False)
    pd.DataFrame({"stay_id": np.sort(hold)}).to_csv(
        C.OUTPUT_DIR / "realtime_holdout_ids.csv", index=False)

    sub = panel[panel["stay_id"].isin(hold)].copy()
    # last hour we score for each stay: onset (septic) else censor
    last_pred = onset.reindex(sub["stay_id"].values).to_numpy()
    cens_v = censor.reindex(sub["stay_id"].values).to_numpy()
    last_pred = np.where(np.isnan(last_pred), cens_v, last_pred)
    keep = (sub["hour"].to_numpy() >= START_H) & (sub["hour"].to_numpy() <= last_pred)
    sub = sub[keep].copy()

    VITALS_LABS = ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
                   "lactate", "creatinine", "wbc", "pf_ratio"]
    SLOPE_VARS = ["hr", "resp_rate", "map", "spo2"]

    out = pd.DataFrame({"stay_id": sub["stay_id"].to_numpy(),
                        "hour": sub["hour"].to_numpy()})
    out["landmark_time"] = sub["hour"].to_numpy()
    for v in VITALS_LABS:
        out[v] = ff(sub, v).to_numpy()
    out["sofa_total"] = sub["sofa_total"].to_numpy()

    # 6h slopes: value@h - value@(h-6). Build a (stay,hour)->value map per var.
    for v in SLOPE_VARS:
        val = ff(panel, v)
        key = panel["stay_id"].to_numpy() * 100000 + panel["hour"].to_numpy()
        m = pd.Series(val.to_numpy(), index=key)
        cur_key = out["stay_id"].to_numpy() * 100000 + out["hour"].to_numpy()
        prev_key = out["stay_id"].to_numpy() * 100000 + (out["hour"].to_numpy() - SLOPE_LOOKBACK_H)
        out[f"{v}_slope6"] = out[v].to_numpy() - m.reindex(prev_key).to_numpy()

    out["qsofa"] = qsofa(out["resp_rate"], out["gcs"], out["map"]).to_numpy()
    out["sirs"] = sirs(out["hr"], out["resp_rate"], out["temp_c"], out["wbc"]).to_numpy()
    out = out.merge(cohort, on="stay_id", how="left")
    # carry the truth for utility scoring
    out["onset_hour"] = onset.reindex(out["stay_id"].values).to_numpy()

    U.log(f"holdout: {len(hold):,} stays, {len(out):,} stay-hours scored "
          f"(hours {START_H}..onset/censor)")
    U.save(out, "realtime_holdout_features", C.OUTPUT_DIR, fmt="csv")


if __name__ == "__main__":
    main()
