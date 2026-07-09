"""
11_landmark_stack.py  --  TIER 2 (data substrate)
==================================================
Builds the STACKED multi-landmark dataset for a dynamic-prediction *supermodel*
(van Houwelingen 2007, README ref 7). Script 08 fit a single landmark at hour 6;
a real-time system must emit a risk at EVERY hour. The landmark supermodel is
the purely-statistical way to do that: repeat the hour-6 landmark construction
at a grid of landmark times s, stack them into one long dataset with s as a
covariate, and (in 12_supermodel.R) fit ONE penalized model with smooth
s-interactions so plugging in the current hour gives an hourly-updating risk.

At each landmark hour s (LANDMARK_GRID):
  * eligible stays = reached hour s AND not yet septic by s (at-risk),
  * features   = forward-filled physiology at hour s, hourly SOFA, qSOFA, SIRS,
                 and 6h trajectory slopes (value@s - value@(s-6)), + demographics,
  * label      = incident onset within (s, s+HORIZON].
This reproduces 08_onset_label.py's hour-6 rows exactly when s == 6.

Output: processed_data/landmark_stack.csv  (one row per stay x landmark)
Run from projects/sepsis_mimic4/ with the framework python3 (pandas).
"""
from __future__ import annotations

import numpy as np
import pandas as pd

import config as C
import utils as U

LANDMARK_GRID = [6, 12, 18, 24, 36, 48]   # hours at which we make a prediction
HORIZON_H = 12                            # predict onset within this many hours
SLOPE_LOOKBACK_H = 6                      # trajectory slope window


def ff(panel: pd.DataFrame, v: str) -> pd.Series:
    return panel[f"{v}_ff"] if f"{v}_ff" in panel.columns else panel[v]


def qsofa(rr, gcs, mp):
    # quickSOFA: resp rate >=22, GCS <15, and MAP <70 as a proxy for SBP <=100
    # (chartevents has no routine SBP field at this granularity -- see README).
    return ((rr >= 22).astype(int) + (gcs < 15).astype(int)
            + (mp < 70).astype(int))


def sirs(hr, rr, temp, wbc):
    # SIRS: HR >90, resp rate >20, temp outside [36, 38]C, WBC outside [4, 12] K/uL.
    return ((hr > 90).astype(int) + (rr > 20).astype(int)
            + ((temp > 38) | (temp < 36)).astype(int)
            + ((wbc > 12) | (wbc < 4)).astype(int))


def main() -> None:
    U.log("loading labelled hourly panel + cohort ...")
    panel = pd.read_parquet(C.OUTPUT_DIR / "hourly_labeled.parquet")
    panel = panel.sort_values(["stay_id", "hour"]).reset_index(drop=True)
    cohort = U.load("cohort", C.OUTPUT_DIR)[
        ["stay_id", "age", "gender", "hospital_expire_flag"]]

    onset = panel.groupby("stay_id")["onset_hour"].first()   # NaN if never septic
    censor = panel.groupby("stay_id")["hour"].max()          # last observed hour

    VITALS_LABS = ["hr", "resp_rate", "map", "spo2", "temp_c", "gcs",
                   "lactate", "creatinine", "wbc", "pf_ratio"]
    SLOPE_VARS = ["hr", "resp_rate", "map", "spo2"]

    # index panels by (stay_id, hour) for O(1) lookback lookups
    by_hour = {h: panel[panel["hour"] == h].set_index("stay_id")
               for h in set(LANDMARK_GRID) | {s - SLOPE_LOOKBACK_H
                                              for s in LANDMARK_GRID}}

    blocks = []
    for s in LANDMARK_GRID:
        at_s = by_hour[s]
        if at_s.empty:
            continue
        oh = onset.reindex(at_s.index)
        at_risk = oh.isna() | (oh > s)          # not yet septic by s
        cur = at_s[at_risk.values]
        f = pd.DataFrame({"stay_id": cur.index.to_numpy()})
        f["landmark_time"] = s
        for v in VITALS_LABS:
            f[v] = ff(cur, v).to_numpy()
        f["sofa_total"] = cur["sofa_total"].to_numpy()
        # 6h trajectory slopes = value@s - value@(s-6)
        prev = by_hour[s - SLOPE_LOOKBACK_H]
        for v in SLOPE_VARS:
            past = ff(prev, v).reindex(cur.index).to_numpy() if not prev.empty \
                else np.full(len(cur), np.nan)
            f[f"{v}_slope6"] = f[v].to_numpy() - past
        f["qsofa"] = qsofa(f["resp_rate"], f["gcs"], f["map"]).to_numpy()
        f["sirs"] = sirs(f["hr"], f["resp_rate"], f["temp_c"], f["wbc"]).to_numpy()
        # label: incident onset within (s, s+HORIZON]
        oh_c = onset.reindex(cur.index)
        f["onset_within_h"] = ((oh_c > s) & (oh_c <= s + HORIZON_H)).astype(int).to_numpy()
        # also carry time-to-event from this landmark (for landmark-Cox option)
        ev = oh_c.notna().astype(int)
        cens = censor.reindex(cur.index)
        te = np.where(ev == 1, oh_c, cens) - s
        f["event"] = ev.to_numpy()
        f["t_event"] = np.clip(te, 0.5, None)
        blocks.append(f)
        U.log(f"  s={s:>2}h: {len(f):>6,} at-risk, "
              f"{int(f['onset_within_h'].sum()):>5,} onset within {HORIZON_H}h "
              f"({f['onset_within_h'].mean():.1%})")

    stack = pd.concat(blocks, ignore_index=True)
    stack = stack.merge(cohort, on="stay_id", how="left")
    U.log(f"stacked landmark dataset: {len(stack):,} rows across "
          f"{len(LANDMARK_GRID)} landmarks, {stack['stay_id'].nunique():,} stays")
    U.save(stack, "landmark_stack", C.OUTPUT_DIR, fmt="csv")


if __name__ == "__main__":
    main()
