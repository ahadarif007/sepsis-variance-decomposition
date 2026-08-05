"""
utility_score.py — PhysioNet 2019 Utility Score (Reyna et al., 2020)

Standalone reference implementation of the scoring rule used by
`07_metrics_suite.Rmd`, kept in step with the R version so that any prediction
table can be scored outside the pipeline. The R notebook is what produces
`07_metric_results.parquet`; this module exists for ad-hoc checks and for
scoring prediction files that never enter the pipeline.

Scoring rule, per stay
----------------------
    sepsis stay alerted in [onset + U_TP_MIN, onset]
        + lead / PREDICTION_HORIZON, where lead is the warning time of the
        *earliest* alert in that window. A full-horizon warning scores 1;
        an alert that only coincides with onset scores 0.
    sepsis stay alerted only in (onset, onset + U_TP_MAX]
        U_FP per late alert hour.
    sepsis stay never alerted in either window
        U_FN.
    any alert hour outside a reward window, on any stay
        U_FP.

Normalisation
-------------
The raw total is referenced to the two strategies of Reyna et al. (2020):

    U_inaction = U_FN         x n_sepsis_stays     (never alert)
    U_optimal  = U_TP_MAX_REW x n_sepsis_stays     (perfect, no false alarms)
    normalised = (U - U_inaction) / (U_optimal - U_inaction)

so that 1 is a perfect forecaster, 0 is *exactly* the no-alert strategy, and a
negative score is worse than issuing no alerts at all. The inaction baseline
must appear in both numerator and denominator: dividing the raw total by the
optimum alone scores a model that raises no alert at -1 rather than 0, which
contradicts the definition of the metric.

Thresholds
----------
At an hourly event rate below 0.5 per cent, no model's predicted probability
approaches 0.5, so a fixed 0.5 cut-off scores the no-alert strategy rather than
the model. `sweep_thresholds` walks a grid defined on the *alert rate* — the
fraction of person-hours alerted — which adapts to each model's calibration,
and reports the maximum achievable utility along with the operating point that
attains it.

Usage:
    python utility_score.py --pred_file 05_predictions_primary_B.parquet \
                            --out_file utility_primary_B.csv --sweep_thresholds

Or import:
    from utility_score import compute_physionet_utility, utility_curve
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

# --------------------------------------------------------------------------- #
# Scoring parameters — mirror config.R
# --------------------------------------------------------------------------- #
PREDICTION_HORIZON = 6      # hours; the prediction horizon of the study
U_TP_MIN           = -6     # earliest true-positive offset (hours before onset)
U_TP_MAX           = 3      # latest true-positive offset (hours after onset)
U_FP               = -0.05  # per false-alert hour
U_FN               = -1.0   # per undetected sepsis stay
U_TP_MAX_REWARD    = 1.0    # reward for a full-horizon warning

SWEEP_MIN_RATE = 1e-5
SWEEP_MAX_RATE = 0.5
SWEEP_N_GRID   = 60


def threshold_grid(p: np.ndarray, n_grid: int = SWEEP_N_GRID) -> np.ndarray:
    """Thresholds spanning alert rates from SWEEP_MIN_RATE to SWEEP_MAX_RATE."""
    p = np.asarray(p, dtype=float)
    p = p[np.isfinite(p)]
    if p.size == 0:
        return np.empty(0)
    rates = np.exp(np.linspace(np.log(SWEEP_MIN_RATE), np.log(SWEEP_MAX_RATE), n_grid))
    taus = np.quantile(p, 1.0 - rates, method="inverted_cdf")
    return np.unique(np.concatenate([taus, [0.5]]))


def utility_curve(
    df: pd.DataFrame,
    pred_col: str,
    thresholds,
    onset_col: str = "onset_hour",
    hour_col: str = "hour",
    stay_col: str = "stay_id",
    event_col: str = "event",
) -> pd.DataFrame:
    """
    Score every threshold in one pass.

    The per-stay reward is monotone in a falling threshold, so the whole grid
    costs one sort plus a single traversal of the reward-window rows.

    Returns one row per threshold with the normalised score, the alert volume,
    the fraction of septic stays detected in the reward window, and the
    per-hour alert burden.
    """
    p = pd.to_numeric(df[pred_col], errors="coerce").to_numpy(dtype=float)
    ok = np.isfinite(p)

    p = p[ok]
    stay = df[stay_col].to_numpy()[ok]
    hour = pd.to_numeric(df[hour_col], errors="coerce").to_numpy(dtype=float)[ok]
    onset = pd.to_numeric(df[onset_col], errors="coerce").to_numpy(dtype=float)[ok]
    y_hr = (pd.to_numeric(df[event_col], errors="coerce").to_numpy()[ok] == 1)

    taus = np.unique(np.asarray(list(thresholds), dtype=float))[::-1]
    has_onset = ~np.isnan(onset)
    sep_stays, sep_idx = np.unique(stay[has_onset], return_inverse=True)
    n_sep = sep_stays.size

    cols = ["threshold", "n_alerts", "alert_rate", "n_sepsis_stays",
            "n_detected_stays", "detection_rate", "utility_total",
            "utility_normalised", "alert_burden"]
    if n_sep == 0 or taus.size == 0 or p.size == 0:
        return pd.DataFrame({c: [] for c in cols})

    in_early = has_onset & (hour >= onset + U_TP_MIN) & (hour <= onset)
    in_late = has_onset & (hour > onset) & (hour <= onset + U_TP_MAX)

    # Map reward-window rows onto the sepsis-stay index used by the accumulator.
    stay_to_si = {s: i for i, s in enumerate(sep_stays)}
    ev_si = np.array([stay_to_si[s] for s in
                      np.concatenate([stay[in_early], stay[in_late]])], dtype=int)
    ev_p = np.concatenate([p[in_early], p[in_late]])
    ev_v = np.concatenate([(onset[in_early] - hour[in_early]) / PREDICTION_HORIZON,
                           np.full(int(in_late.sum()), np.nan)])
    ev_late = np.concatenate([np.zeros(int(in_early.sum()), dtype=bool),
                              np.ones(int(in_late.sum()), dtype=bool)])
    order = np.argsort(-ev_p, kind="stable")
    ev_si, ev_p, ev_v, ev_late = ev_si[order], ev_p[order], ev_v[order], ev_late[order]

    p_all = np.sort(p)
    p_tp = np.sort(p[y_hr])

    def count_ge(sorted_x: np.ndarray, tau: float) -> int:
        return int(sorted_x.size - np.searchsorted(sorted_x, tau, side="left"))

    best = np.full(n_sep, np.nan)
    late_cnt = np.zeros(n_sep, dtype=int)
    sum_best = 0.0
    n_det = 0
    late_undet = 0        # late alerts on stays not (yet) detected
    n_undet_late = 0      # undetected stays carrying >= 1 late alert
    n_reward_alerts = 0

    j = 0
    rows = []
    for tau in taus:
        while j < ev_p.size and ev_p[j] >= tau:
            si = ev_si[j]
            if ev_late[j]:
                late_cnt[si] += 1
                if np.isnan(best[si]):
                    late_undet += 1
                    if late_cnt[si] == 1:
                        n_undet_late += 1
            else:
                v = ev_v[j]
                if np.isnan(best[si]):
                    best[si] = v
                    sum_best += v
                    n_det += 1
                    if late_cnt[si] > 0:
                        late_undet -= late_cnt[si]
                        n_undet_late -= 1
                elif v > best[si]:
                    sum_best += v - best[si]
                    best[si] = v
            n_reward_alerts += 1
            j += 1

        n_alerts = count_ge(p_all, tau)
        n_tp_hr = count_ge(p_tp, tau)

        u_raw = (sum_best
                 + U_FP * late_undet
                 + U_FN * (n_sep - n_det - n_undet_late)
                 + U_FP * (n_alerts - n_reward_alerts))

        u_inaction = U_FN * n_sep
        u_optimal = U_TP_MAX_REWARD * n_sep

        rows.append({
            "threshold": float(tau),
            "n_alerts": n_alerts,
            "alert_rate": n_alerts / p.size,
            "n_sepsis_stays": n_sep,
            "n_detected_stays": n_det,
            "detection_rate": n_det / n_sep,
            "utility_total": u_raw,
            "utility_normalised": (u_raw - u_inaction) / (u_optimal - u_inaction),
            "alert_burden": np.inf if n_tp_hr == 0 else (n_alerts - n_tp_hr) / n_tp_hr,
        })

    return pd.DataFrame(rows, columns=cols).sort_values("threshold").reset_index(drop=True)


def compute_physionet_utility(
    df: pd.DataFrame,
    pred_col: str,
    onset_col: str = "onset_hour",
    hour_col: str = "hour",
    stay_col: str = "stay_id",
    event_col: str = "event",
    threshold: float = 0.5,
) -> dict:
    """Score a single operating point. See module docstring for the rule."""
    curve = utility_curve(df, pred_col, [threshold], onset_col=onset_col,
                          hour_col=hour_col, stay_col=stay_col, event_col=event_col)
    if curve.empty:
        return {"utility_total": float("nan"), "utility_max": float("nan"),
                "utility_normalised": float("nan"), "n_stays": df[stay_col].nunique(),
                "n_sepsis_stays": 0, "n_alerts_total": 0}
    row = curve.iloc[0]
    return {
        "utility_total":      round(float(row["utility_total"]), 4),
        "utility_max":        round(U_TP_MAX_REWARD * float(row["n_sepsis_stays"]), 4),
        "utility_normalised": round(float(row["utility_normalised"]), 4),
        "n_stays":            int(df[stay_col].nunique()),
        "n_sepsis_stays":     int(row["n_sepsis_stays"]),
        "n_alerts_total":     int(row["n_alerts"]),
    }


def compute_utility_by_threshold(df, pred_col, thresholds=None, **kwargs):
    """Utility across a grid of thresholds, for threshold selection."""
    if thresholds is None:
        thresholds = threshold_grid(pd.to_numeric(df[pred_col], errors="coerce").to_numpy())
    return utility_curve(df, pred_col, thresholds, **kwargs)


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
                        help="Also sweep the threshold grid and report the maximum achievable utility")
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
    result["pred_col"] = args.pred_col
    result["threshold"] = args.threshold
    result["source"] = str(pred_path.name)

    print("\n=== PhysioNet Utility Score ===")
    for k, v in result.items():
        print(f"  {k}: {v}")

    out_df = pd.DataFrame([result])

    if args.sweep_thresholds:
        sweep = compute_utility_by_threshold(df, args.pred_col)
        real = sweep[sweep["n_alerts"] > 0]
        out_df = pd.concat([out_df, sweep.assign(pred_col=args.pred_col,
                                                 source=str(pred_path.name))],
                           ignore_index=True)
        print("\nThreshold sweep:")
        print(sweep[["threshold", "alert_rate", "detection_rate",
                     "utility_normalised", "alert_burden"]].to_string(index=False))
        if not real.empty:
            best = real.loc[real["utility_normalised"].idxmax()]
            print(f"\nMaximum achievable utility: {best['utility_normalised']:.4f} "
                  f"at threshold {best['threshold']:.5g} "
                  f"(alert rate {best['alert_rate']:.4%}, "
                  f"{best['detection_rate']:.1%} of septic stays detected, "
                  f"alert burden {best['alert_burden']:.1f}:1)")

    out_path = Path(args.out_file)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_df.to_csv(out_path, index=False)
    print(f"\nSaved to {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
