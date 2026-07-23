"""
utility_score.py — PhysioNet 2019 Utility Score (Reyna et al., 2020)

Implements the exact scoring logic from the PhysioNet/Computing in Cardiology
Challenge 2019 for evaluating real-time sepsis prediction models.

The score rewards timely prediction and penalises:
- Late predictions (after onset)
- Missed detections (no alert before onset)
- False alarms (alerts for non-sepsis patients)

This score CAN be negative — negative utility means the model does net harm
relative to issuing no alerts at all. This is the metric that revealed the
collapse documented by Wang et al. (2025): median Utility Score +0.381 →
−0.164 from internal to external validation, while AUROC barely moved.

Reyna et al. (2020) specify:
  - u_tp(t, t_sepsis): reward for TP alert at time t (hours before onset)
  - u_fp: penalty for FP alert (-0.05)
  - u_fn: penalty for missed detection (-1.0 for each hour missed)
  - u_tn: no reward/penalty for correct non-alert

Usage:
    python utility_score.py --pred_file predictions_primary_B.parquet \
                             --out_file utility_score_primary_B.csv

Or import:
    from utility_score import compute_physionet_utility
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
import numpy as np
import pandas as pd

# --------------------------------------------------------------------------- #
# Utility score parameters (Reyna et al., 2020)
# --------------------------------------------------------------------------- #
U_TP_MAX_LEAD   = 12    # hours before onset: max lead time for TP reward
U_TP_HORIZON    = -6    # hours before onset: minimum lead for maximum reward
U_TP_LATE_MAX   =  3    # hours after onset: still counts as late TP
U_FP_PENALTY    = -0.05 # per false-positive alert-hour
U_FN_PENALTY    = -1.0  # per missed onset (no alert in window)
U_TN            =  0.0  # no reward for correct non-alert


def u_tp(t_alert: float, t_onset: float) -> float:
    """Utility for a true-positive alert at t_alert, given onset at t_onset."""
    dt = t_onset - t_alert  # positive if alert is BEFORE onset
    if dt >= U_TP_MAX_LEAD:
        return -0.05  # too early — before the useful warning window
    elif dt >= U_TP_HORIZON:
        # Linear reward from max_lead to horizon: from -0.05 to 1.0
        slope = (1.0 - (-0.05)) / (U_TP_HORIZON - U_TP_MAX_LEAD)
        return -0.05 + slope * (dt - U_TP_MAX_LEAD)
    elif dt >= 0:
        # Alert at or after onset but before +3h: still a TP but penalty
        return 1.0
    elif dt >= -U_TP_LATE_MAX:
        # Late alert (within 3h after onset)
        return -0.05 * abs(dt)
    else:
        # Way after onset: treated as FP
        return U_FP_PENALTY


def compute_physionet_utility(
    df: pd.DataFrame,
    pred_col: str,
    onset_col: str = "onset_hour",
    hour_col: str = "hour",
    stay_col: str = "stay_id",
    event_col: str = "event",
    threshold: float = 0.5,
) -> dict:
    """
    Compute the PhysioNet Utility Score for a person-hour prediction table.

    Parameters
    ----------
    df : DataFrame with one row per (stay_id, hour)
    pred_col : column with continuous probability score
    onset_col : column with sepsis onset hour (NA if no sepsis)
    threshold : alert threshold (default 0.5)

    Returns
    -------
    dict with:
        utility_total        : sum of utilities across all stays
        utility_max          : maximum possible utility (sum over sepsis stays)
        utility_normalised   : utility_total / utility_max (if > 0 else NaN)
        n_stays              : total stays evaluated
        n_sepsis_stays       : stays with sepsis onset
        n_alerts_total       : total alert-hours
    """
    df = df.copy()
    df["alert"] = (df[pred_col] >= threshold).astype(int)

    stays = df[stay_col].unique()
    U_total = 0.0
    U_max   = 0.0
    n_alerts = 0

    for stay_id in stays:
        rows = df[df[stay_col] == stay_id].sort_values(hour_col)
        onset_h = rows[onset_col].iloc[0] if not rows[onset_col].isna().all() else np.nan
        hours  = rows[hour_col].values
        alerts = rows["alert"].values
        preds  = rows[pred_col].values

        alert_hours = hours[alerts == 1]
        n_alerts += len(alert_hours)

        if not np.isnan(onset_h):
            # Sepsis stay
            # TP window: onset_h - 12 to onset_h + 3
            tp_early = alert_hours[(alert_hours >= onset_h - U_TP_MAX_LEAD) &
                                    (alert_hours <= onset_h)]
            tp_late  = alert_hours[(alert_hours > onset_h) &
                                    (alert_hours <= onset_h + U_TP_LATE_MAX)]
            fp_early = alert_hours[alert_hours < onset_h - U_TP_MAX_LEAD]

            if len(tp_early) > 0:
                # Best TP = earliest (most lead time)
                best_alert = min(tp_early)
                U_stay = u_tp(best_alert, onset_h)
                # FP penalties for non-best TP alerts
                U_stay += U_FP_PENALTY * (len(tp_early) - 1)
            elif len(tp_late) > 0:
                # Late TP
                U_stay = U_FP_PENALTY * len(tp_late)
            else:
                # FN
                U_stay = U_FN_PENALTY

            # FP before TP window
            U_stay += U_FP_PENALTY * len(fp_early)
            U_total += U_stay
            U_max   += 1.0  # max possible utility for a sepsis stay
        else:
            # Non-sepsis stay: all alerts are FP
            U_total += U_FP_PENALTY * len(alert_hours)
            # No contribution to U_max

    utility_normalised = U_total / U_max if U_max > 0 else float("nan")

    sepsis_stays = df.groupby(stay_col)[onset_col].first().notna().sum()

    return {
        "utility_total":       round(U_total, 4),
        "utility_max":         round(U_max,   4),
        "utility_normalised":  round(utility_normalised, 4),
        "n_stays":             len(stays),
        "n_sepsis_stays":      int(sepsis_stays),
        "n_alerts_total":      int(n_alerts),
    }


def compute_utility_by_threshold(df, pred_col, thresholds=None, **kwargs):
    """Compute utility across a range of thresholds (for threshold selection)."""
    if thresholds is None:
        thresholds = np.arange(0.1, 0.9, 0.05)
    results = []
    for t in thresholds:
        res = compute_physionet_utility(df, pred_col, threshold=t, **kwargs)
        res["threshold"] = round(t, 2)
        results.append(res)
    return pd.DataFrame(results)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def main():
    parser = argparse.ArgumentParser(
        description="PhysioNet 2019 Utility Score for sepsis prediction models"
    )
    parser.add_argument("--pred_file", required=True,
                        help="Parquet file with predictions (stay_id, hour, event, pred_<model>, onset_hour)")
    parser.add_argument("--pred_col", default="pred_sepsis",
                        help="Column name for predictions (default: pred_sepsis)")
    parser.add_argument("--threshold", type=float, default=0.5,
                        help="Alert threshold (default: 0.5)")
    parser.add_argument("--out_file", required=True,
                        help="Output CSV path for results")
    parser.add_argument("--sweep_thresholds", action="store_true",
                        help="Also compute utility across a range of thresholds")
    args = parser.parse_args()

    pred_path = Path(args.pred_file)
    if not pred_path.exists():
        print(f"ERROR: {pred_path} not found", file=sys.stderr)
        sys.exit(1)

    print(f"Loading predictions from {pred_path}...", file=sys.stderr)
    df = pd.read_parquet(pred_path)
    print(f"  {len(df):,} rows, {df['stay_id'].nunique():,} stays", file=sys.stderr)

    if args.pred_col not in df.columns:
        print(f"ERROR: Column '{args.pred_col}' not in dataframe. "
              f"Available: {list(df.columns)}", file=sys.stderr)
        sys.exit(1)

    print(f"Computing Utility Score (threshold={args.threshold})...", file=sys.stderr)
    result = compute_physionet_utility(df, args.pred_col, threshold=args.threshold)
    result["pred_col"]  = args.pred_col
    result["threshold"] = args.threshold
    result["source"]    = str(pred_path.name)

    print("\n=== PhysioNet Utility Score ===")
    for k, v in result.items():
        print(f"  {k}: {v}")

    out_df = pd.DataFrame([result])

    if args.sweep_thresholds:
        sweep = compute_utility_by_threshold(df, args.pred_col)
        sweep["pred_col"] = args.pred_col
        sweep["source"]   = str(pred_path.name)
        out_df = pd.concat([out_df, sweep], ignore_index=True)
        print(f"\nThreshold sweep:")
        print(sweep[["threshold","utility_normalised","n_alerts_total"]].to_string())

    out_path = Path(args.out_file)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(out_path, index=False)
    print(f"\nSaved to {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
