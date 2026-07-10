"""
clinical_scores.py
==================
Shared clinical scoring functions used across the sepsis pipeline.

Centralises qSOFA, SIRS, hourly SOFA scoring, and panel helper functions
that were previously duplicated in scripts 08, 11, 14, and 21.

References
----------
- SOFA: Vincent et al. 1996; thresholds per Singer et al. (Sepsis-3) 2016.
- qSOFA: Seymour et al. JAMA 2016.
- SIRS: Bone et al. 1992 / ACCP-SCCM consensus.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def ff(panel: pd.DataFrame, var: str) -> pd.Series:
    """Return the forward-filled column (<var>_ff) if present, else the raw column."""
    ff_col = f"{var}_ff"
    return panel[ff_col] if ff_col in panel.columns else panel[var]


def qsofa(resp_rate: pd.Series, gcs: pd.Series, map_val: pd.Series) -> pd.Series:
    """quickSOFA score (0-3): resp >= 22, GCS < 15, MAP < 70 (proxy for SBP <= 100)."""
    return (
        (resp_rate >= 22).astype(int)
        + (gcs < 15).astype(int)
        + (map_val < 70).astype(int)
    )


def sirs(hr: pd.Series, resp_rate: pd.Series,
         temp_c: pd.Series, wbc: pd.Series) -> pd.Series:
    """SIRS criteria count (0-4): HR > 90, RR > 20, temp > 38 or < 36, WBC > 12 or < 4."""
    return (
        (hr > 90).astype(int)
        + (resp_rate > 20).astype(int)
        + ((temp_c > 38) | (temp_c < 36)).astype(int)
        + ((wbc > 12) | (wbc < 4)).astype(int)
    )


def score_sofa_hourly(panel: pd.DataFrame, *, include_urine: bool = False) -> pd.DataFrame:
    """Score all 6 SOFA organ components hourly from forward-filled panel values.

    Each component scores 0-4; total is their sum (0-24). Missing values
    score 0 (assumed-normal baseline per Sepsis-3 convention).

    Parameters
    ----------
    include_urine : bool
        If True and 'urine_ml' is present, include trailing-24h urine output
        in the renal component. False by default (eICU, early landmarks).
    """
    # --- Respiration: PaO2/FiO2 ratio (mmHg) ---
    pf_ratio = ff(panel, "pf_ratio")
    sofa_resp = np.select(
        [pf_ratio < 100, pf_ratio < 200, pf_ratio < 300, pf_ratio < 400],
        [4, 3, 2, 1], 0)

    # --- Coagulation: platelet count (K/uL) ---
    platelets = ff(panel, "platelets")
    sofa_coag = np.select(
        [platelets < 20, platelets < 50, platelets < 100, platelets < 150],
        [4, 3, 2, 1], 0)

    # --- Liver: bilirubin (mg/dL) ---
    bilirubin = ff(panel, "bilirubin")
    sofa_liver = np.select(
        [bilirubin >= 12, bilirubin >= 6, bilirubin >= 2, bilirubin >= 1.2],
        [4, 3, 2, 1], 0)

    # --- Cardiovascular: MAP and vasopressor doses ---
    mean_ap = ff(panel, "map")
    sofa_cardio = np.where(mean_ap < 70, 1, 0)
    sofa_cardio = np.maximum(sofa_cardio, np.where(
        panel["dobutamine_any"].fillna(False), 2, 0))
    sofa_cardio = np.maximum(sofa_cardio, np.where(
        panel["other_vaso_any"].fillna(False), 3, 0))
    dopamine_rate = panel.get("dopamine_rate", pd.Series(np.nan, index=panel.index))
    dopamine_present = panel["dopamine_any"].fillna(False).to_numpy()
    dopamine_score = np.where(dopamine_rate > 15, 4, np.where(dopamine_rate > 5, 3, 2))
    sofa_cardio = np.maximum(sofa_cardio, np.where(dopamine_present, dopamine_score, 0))
    norepi_epi_rate = panel.get("norepi_epi_rate", pd.Series(np.nan, index=panel.index))
    norepi_epi_present = panel["norepi_epi_any"].fillna(False).to_numpy()
    norepi_epi_score = np.where(norepi_epi_rate > 0.1, 4, 3)
    sofa_cardio = np.maximum(sofa_cardio, np.where(
        norepi_epi_present, norepi_epi_score, 0))

    # --- CNS: Glasgow Coma Scale ---
    gcs_score = ff(panel, "gcs").fillna(15)
    sofa_cns = np.select(
        [gcs_score < 6, gcs_score < 10, gcs_score < 13, gcs_score < 15],
        [4, 3, 2, 1], 0)

    # --- Renal: creatinine (mg/dL) and optionally urine output ---
    creatinine = ff(panel, "creatinine")
    sofa_renal = np.select(
        [creatinine >= 5, creatinine >= 3.5, creatinine >= 2.0, creatinine >= 1.2],
        [4, 3, 2, 1], 0)

    if include_urine and "urine_ml" in panel.columns:
        urine_trailing_24h = (
            panel.groupby("stay_id", sort=False)["urine_ml"]
            .rolling(24, min_periods=24)
            .sum()
            .reset_index(level=0, drop=True)
        )
        sofa_renal = np.maximum(sofa_renal, np.select(
            [urine_trailing_24h < 200, urine_trailing_24h < 500], [4, 3], 0))

    result = pd.DataFrame(
        {
            "sofa_resp": sofa_resp,
            "sofa_coag": sofa_coag,
            "sofa_liver": sofa_liver,
            "sofa_cardio": sofa_cardio,
            "sofa_cns": sofa_cns,
            "sofa_renal": sofa_renal,
        },
        index=panel.index,
    ).astype("int8")
    result["sofa_total"] = result.sum(axis=1).astype("int8")
    return result


def build_hourly_grid(stays: pd.DataFrame, max_hours: int) -> pd.DataFrame:
    """Dense (stay_id, hour) grid, hour 0..min(LOS, max_hours) per stay."""
    h_stay = np.floor(
        np.minimum(stays["los_hours"].to_numpy(), float(max_hours))
    ).astype(int)
    h_stay = np.clip(h_stay, 0, max_hours)
    reps = h_stay + 1
    stay_rep = np.repeat(stays["stay_id"].to_numpy(), reps)
    hour_rep = np.concatenate([np.arange(0, n) for n in reps])
    return pd.DataFrame(
        {"stay_id": stay_rep.astype("int64"), "hour": hour_rep.astype("int64")}
    )


VASO_BOOL_COLS = [
    "norepi_epi_any",
    "dopamine_any",
    "dobutamine_any",
    "other_vaso_any",
    "vaso_any",
]


def normalize_vaso_bools(df: pd.DataFrame, *, add_vaso_any: bool = False) -> None:
    """Ensure vasopressor boolean columns are proper bools, filling NaN as False.

    Handles the CSV round-trip issue where bools become strings.
    Operates in-place.
    """
    cols = VASO_BOOL_COLS if not add_vaso_any else VASO_BOOL_COLS[:-1]
    for c in cols:
        if c in df.columns:
            df[c] = (
                df[c]
                .map({"True": True, "False": False, True: True, False: False})
                .fillna(False)
                .astype(bool)
            )
        else:
            df[c] = False
    if add_vaso_any and "vaso_any" not in df.columns:
        df["vaso_any"] = df[VASO_BOOL_COLS[:-1]].any(axis=1)
    elif "vaso_any" in df.columns:
        df["vaso_any"] = df["vaso_any"].map(
            {"True": True, "False": False, True: True, False: False}
        ).fillna(False).astype(bool)
