"""
05_sofa_sepsis3.py
==================
Turns the first-24h measurements (script 04) into SOFA component scores, a total
SOFA, and the Sepsis-3 label, then writes the analysis matrix the R report uses.

SOFA (Vincent et al. 1996; thresholds as in Singer et al., Sepsis-3, 2016).
Each organ system scores 0-4; total is their sum (0-24).

  Respiration  PaO2/FiO2 (mmHg)   >=400:0  <400:1  <300:2  <200:3  <100:4
  Coagulation  platelets (K/uL)   >=150:0  <150:1  <100:2  <50:3   <20:4
  Liver        bilirubin (mg/dL)  <1.2:0   1.2-1.9:1  2.0-5.9:2  6.0-11.9:3  >=12:4
  Cardiovasc.  MAP / vasopressors (see code; doses in mcg/kg/min)
  CNS          GCS                15:0  13-14:1  10-12:2  6-9:3  <6:4
  Renal        creatinine (mg/dL) / urine (mL/24h)

Operational notes (intentional, documented simplifications)
  * Respiration ignores the strict "with respiratory support" requirement on
    scores 3-4 (ventilation status is not reconstructed here).
  * Cardiovascular maps phenylephrine / vasopressin presence to a score of 3
    (they aren't in the original dopamine/epi/norepi dose table).
  * A component with no data scores 0 (assumed normal), per the Sepsis-3
    convention of an assumed-zero baseline.

Sepsis-3 label
  baseline SOFA assumed 0  =>  organ dysfunction := total SOFA >= 2
  sepsis3      = suspected_infection (script 03)  AND  total SOFA >= SOFA_INCREASE_THRESHOLD
  septic_shock = sepsis3  AND  any vasopressor  AND  lactate > SEPTIC_SHOCK_LACTATE_MMOL

Output
------
processed_data/05_analysis_matrix.parquet   (one row per stay: demographics + first-24h
features + SOFA components + labels). This is the file the .Rmd report reads.
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

import config as C
import utils as U
from logging_utils import setup_logging, step, log_separator


def score_respiration(df: pd.DataFrame) -> pd.Series:
    """PaO2/FiO2 ratio -> SOFA respiration score (0-4)."""
    pf_ratio = df["pf_ratio_min"]
    return pd.Series(np.select(
        [pf_ratio < 100, pf_ratio < 200, pf_ratio < 300, pf_ratio < 400],
        [4, 3, 2, 1], default=0), index=df.index)


def score_coagulation(df: pd.DataFrame) -> pd.Series:
    """Platelet count (K/uL) -> SOFA coagulation score (0-4)."""
    platelets = df["platelets_min"]
    return pd.Series(np.select(
        [platelets < 20, platelets < 50, platelets < 100, platelets < 150],
        [4, 3, 2, 1], default=0), index=df.index)


def score_liver(df: pd.DataFrame) -> pd.Series:
    """Bilirubin (mg/dL) -> SOFA liver score (0-4)."""
    bilirubin = df["bilirubin_max"]
    return pd.Series(np.select(
        [bilirubin >= 12, bilirubin >= 6, bilirubin >= 2, bilirubin >= 1.2],
        [4, 3, 2, 1], default=0), index=df.index)


def score_cardio(df: pd.DataFrame) -> pd.Series:
    """MAP + vasopressor doses (mcg/kg/min) -> SOFA cardiovascular score (0-4)."""
    num_stays = len(df)
    score = np.zeros(num_stays, dtype=int)

    score = np.maximum(score, np.where(df["map_min"] < 70, 1, 0))
    score = np.maximum(score, np.where(df["dobutamine_any"].fillna(False), 2, 0))
    score = np.maximum(score, np.where(df["other_vaso_any"].fillna(False), 3, 0))

    dopamine_rate = df["dopamine_max_rate"]
    dopamine_present = df["dopamine_any"].fillna(False).to_numpy()
    dopamine_score = np.where(dopamine_rate > 15, 4, np.where(dopamine_rate > 5, 3, 2))
    score = np.maximum(score, np.where(dopamine_present, dopamine_score, 0))

    norepi_epi_rate = df["norepi_epi_max_rate"]
    norepi_epi_present = df["norepi_epi_any"].fillna(False).to_numpy()
    # > 0.1 mcg/kg/min -> score 4, else score 3
    norepi_epi_score = np.where(norepi_epi_rate > 0.1, 4, 3)
    score = np.maximum(score, np.where(norepi_epi_present, norepi_epi_score, 0))

    return pd.Series(score, index=df.index)


def score_cns(df: pd.DataFrame) -> pd.Series:
    """Glasgow Coma Scale -> SOFA CNS score (0-4). NaN GCS assumed 15 (normal)."""
    gcs_score = df["gcs_min"]
    return pd.Series(np.select(
        [gcs_score < 6, gcs_score < 10, gcs_score < 13, gcs_score < 15],
        [4, 3, 2, 1], default=0), index=df.index)


def score_renal(df: pd.DataFrame) -> pd.Series:
    """Creatinine (mg/dL) and 24h urine (mL) -> SOFA renal score (0-4)."""
    creatinine = df["creatinine_max"]
    creatinine_score = np.select(
        [creatinine >= 5, creatinine >= 3.5, creatinine >= 2.0, creatinine >= 1.2],
        [4, 3, 2, 1], default=0)
    urine_24h = df["urine_24h_ml"]
    urine_valid = urine_24h.notna() & (urine_24h > 0)
    urine_score = np.select(
        [urine_valid & (urine_24h < 200), urine_valid & (urine_24h < 500)],
        [4, 3], default=0)
    return pd.Series(np.maximum(creatinine_score, urine_score), index=df.index)


def main() -> None:
    ap = argparse.ArgumentParser(description="SOFA scoring + Sepsis-3 labels.")
    ap.parse_args()

    log = setup_logging("05_sofa_sepsis3")

    with step(log, "loading stay_measurements + suspected_infection"):
        df = U.load("04_stay_measurements", C.OUTPUT_DIR)
        susp = U.load("03_suspected_infection", C.OUTPUT_DIR)
        susp_ids = set(susp["stay_id"].astype("int64"))

    from clinical_scores import normalize_vaso_bools
    normalize_vaso_bools(df)

    with step(log, "scoring SOFA components"):
        df["sofa_resp"] = score_respiration(df)
        df["sofa_coag"] = score_coagulation(df)
        df["sofa_liver"] = score_liver(df)
        df["sofa_cardio"] = score_cardio(df)
        df["sofa_cns"] = score_cns(df)
        df["sofa_renal"] = score_renal(df)
        sofa_cols = ["sofa_resp", "sofa_coag", "sofa_liver",
                     "sofa_cardio", "sofa_cns", "sofa_renal"]
        df["sofa_total"] = df[sofa_cols].sum(axis=1)

    with step(log, "applying Sepsis-3 labels"):
        df["suspected_infection"] = df["stay_id"].astype("int64").isin(susp_ids)
        df["sepsis3"] = df["suspected_infection"] & (df["sofa_total"] >= C.SOFA_INCREASE_THRESHOLD)
        df["septic_shock"] = (
            df["sepsis3"]
            & df["vaso_any"].fillna(False)
            & (df["lactate_max"] > C.SEPTIC_SHOCK_LACTATE_MMOL)
        )

    total_stays = len(df)
    log_separator(log)
    log.info("FINAL: %s ICU stays", f"{total_stays:,}")
    log.info("  suspected infection: %s (%.1f%%)",
             f"{int(df['suspected_infection'].sum()):,}",
             df['suspected_infection'].mean() * 100)
    log.info("  SOFA total median: %.0f [p25 %.0f, p75 %.0f]",
             df['sofa_total'].median(),
             df['sofa_total'].quantile(.25),
             df['sofa_total'].quantile(.75))
    log.info("  Sepsis-3 positive: %s (%.1f%%)",
             f"{int(df['sepsis3'].sum()):,}", df['sepsis3'].mean() * 100)
    log.info("  septic shock: %s (%.1f%%)",
             f"{int(df['septic_shock'].sum()):,}", df['septic_shock'].mean() * 100)
    log.info("  mortality by group (in-hospital):")
    for is_septic, group_df in df.groupby("sepsis3"):
        tag = "sepsis-3" if is_septic else "no sepsis"
        log.info("    %-10s n=%s  mortality=%.1f%%  SOFA=%.1f",
                 tag, f"{len(group_df):,}",
                 group_df['hospital_expire_flag'].mean() * 100,
                 group_df['sofa_total'].mean())
    log.info("  SOFA component means (septic vs not):")
    for component in sofa_cols:
        septic_mean = df.loc[df.sepsis3, component].mean()
        non_septic_mean = df.loc[~df.sepsis3, component].mean()
        log.info("    %-12s septic=%.2f  non=%.2f",
                 component, septic_mean, non_septic_mean)

    U.save(df, "05_analysis_matrix", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
