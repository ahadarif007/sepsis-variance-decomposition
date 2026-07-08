"""
05_sofa_sepsis3.py
==================
Turns the first-24h measurements (script 04) into SOFA component scores, a total
SOFA, and the Sepsis-3 label — then writes the analysis matrix the R report uses.

SOFA (Vincent et al. 1996; thresholds as in Singer et al., Sepsis-3, 2016).
Each organ system scores 0–4; total is their sum (0–24).

  Respiration  PaO2/FiO2 (mmHg)   >=400:0  <400:1  <300:2  <200:3  <100:4
  Coagulation  platelets (K/uL)   >=150:0  <150:1  <100:2  <50:3   <20:4
  Liver        bilirubin (mg/dL)  <1.2:0   1.2-1.9:1  2.0-5.9:2  6.0-11.9:3  >=12:4
  Cardiovasc.  MAP / vasopressors (see code; doses in mcg/kg/min)
  CNS          GCS                15:0  13-14:1  10-12:2  6-9:3  <6:4
  Renal        creatinine (mg/dL) / urine (mL/24h)

Operational notes (intentional, documented simplifications)
  * Respiration ignores the strict "with respiratory support" requirement on
    scores 3–4 (we don't reconstruct ventilation status here).
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
processed_data/analysis_matrix.csv   (one row per stay: demographics + first-24h
features + SOFA components + labels) — this is the file the .Rmd report reads.
"""
from __future__ import annotations

import argparse

import numpy as np
import pandas as pd

import config as C
import utils as U


def score_respiration(df: pd.DataFrame) -> pd.Series:
    pf = df["pf_ratio_min"]
    return pd.Series(np.select(
        [pf < 100, pf < 200, pf < 300, pf < 400],
        [4, 3, 2, 1], default=0), index=df.index)


def score_coagulation(df: pd.DataFrame) -> pd.Series:
    plt = df["platelets_min"]
    return pd.Series(np.select(
        [plt < 20, plt < 50, plt < 100, plt < 150],
        [4, 3, 2, 1], default=0), index=df.index)


def score_liver(df: pd.DataFrame) -> pd.Series:
    b = df["bilirubin_max"]
    return pd.Series(np.select(
        [b >= 12, b >= 6, b >= 2, b >= 1.2],
        [4, 3, 2, 1], default=0), index=df.index)


def score_cardio(df: pd.DataFrame) -> pd.Series:
    n = len(df)
    score = np.zeros(n, dtype=int)

    # MAP < 70 -> at least 1
    score = np.maximum(score, np.where(df["map_min"] < 70, 1, 0))

    # dobutamine (any) -> 2 ; phenylephrine/vasopressin -> 3
    score = np.maximum(score, np.where(df["dobutamine_any"].fillna(False), 2, 0))
    score = np.maximum(score, np.where(df["other_vaso_any"].fillna(False), 3, 0))

    # dopamine by dose
    dop_rate = df["dopamine_max_rate"]
    dop_any = df["dopamine_any"].fillna(False).to_numpy()
    dop_score = np.where(dop_rate > 15, 4, np.where(dop_rate > 5, 3, 2))
    score = np.maximum(score, np.where(dop_any, dop_score, 0))

    # norepinephrine / epinephrine by dose (>0.1 mcg/kg/min -> 4 else 3)
    ne_rate = df["norepi_epi_max_rate"]
    ne_any = df["norepi_epi_any"].fillna(False).to_numpy()
    ne_score = np.where(ne_rate > 0.1, 4, 3)
    score = np.maximum(score, np.where(ne_any, ne_score, 0))

    return pd.Series(score, index=df.index)


def score_cns(df: pd.DataFrame) -> pd.Series:
    g = df["gcs_min"]
    # NaN GCS -> assume 15 -> 0
    return pd.Series(np.select(
        [g < 6, g < 10, g < 13, g < 15],
        [4, 3, 2, 1], default=0), index=df.index)


def score_renal(df: pd.DataFrame) -> pd.Series:
    cr = df["creatinine_max"]
    cr_score = np.select(
        [cr >= 5, cr >= 3.5, cr >= 2.0, cr >= 1.2],
        [4, 3, 2, 1], default=0)
    u = df["urine_24h_ml"]
    u_valid = u.notna() & (u > 0)          # treat 0 / missing as "not measured"
    u_score = np.select(
        [u_valid & (u < 200), u_valid & (u < 500)],
        [4, 3], default=0)
    return pd.Series(np.maximum(cr_score, u_score), index=df.index)


def main() -> None:
    ap = argparse.ArgumentParser(description="SOFA scoring + Sepsis-3 labels.")
    ap.add_argument("--parquet", action="store_true", help="also write a parquet copy")
    args = ap.parse_args()

    U.log("loading stay_measurements + suspected_infection ...")
    df = U.load("stay_measurements", C.OUTPUT_DIR)
    susp = U.load("suspected_infection", C.OUTPUT_DIR)
    susp_ids = set(susp["stay_id"].astype("int64"))

    # bool columns come back from CSV as strings/objects — normalise.
    for c in ["norepi_epi_any", "dopamine_any", "dobutamine_any",
              "other_vaso_any", "vaso_any"]:
        if c in df.columns:
            df[c] = df[c].map({"True": True, "False": False, True: True,
                               False: False}).fillna(False).astype(bool)

    U.log("scoring SOFA components ...")
    df["sofa_resp"] = score_respiration(df)
    df["sofa_coag"] = score_coagulation(df)
    df["sofa_liver"] = score_liver(df)
    df["sofa_cardio"] = score_cardio(df)
    df["sofa_cns"] = score_cns(df)
    df["sofa_renal"] = score_renal(df)
    sofa_cols = ["sofa_resp", "sofa_coag", "sofa_liver",
                 "sofa_cardio", "sofa_cns", "sofa_renal"]
    df["sofa_total"] = df[sofa_cols].sum(axis=1)

    # Sepsis-3 labels
    df["suspected_infection"] = df["stay_id"].astype("int64").isin(susp_ids)
    df["sepsis3"] = df["suspected_infection"] & (df["sofa_total"] >= C.SOFA_INCREASE_THRESHOLD)
    df["septic_shock"] = (
        df["sepsis3"]
        & df["vaso_any"].fillna(False)
        & (df["lactate_max"] > C.SEPTIC_SHOCK_LACTATE_MMOL)
    )

    # ---- summary ----
    n = len(df)
    U.log("=" * 56)
    U.log(f"FINAL: {n:,} ICU stays")
    U.log(f"  suspected infection: {int(df['suspected_infection'].sum()):,} "
          f"({df['suspected_infection'].mean():.1%})")
    U.log(f"  SOFA total median:   {df['sofa_total'].median():.0f}  "
          f"[p25 {df['sofa_total'].quantile(.25):.0f}, "
          f"p75 {df['sofa_total'].quantile(.75):.0f}]")
    U.log(f"  Sepsis-3 positive:   {int(df['sepsis3'].sum()):,} "
          f"({df['sepsis3'].mean():.1%})")
    U.log(f"  septic shock:        {int(df['septic_shock'].sum()):,} "
          f"({df['septic_shock'].mean():.1%})")
    U.log("  mortality by group (in-hospital):")
    for lab, sub in df.groupby("sepsis3"):
        tag = "sepsis-3" if lab else "no sepsis"
        U.log(f"    {tag:<10s} n={len(sub):,}  "
              f"mortality={sub['hospital_expire_flag'].mean():.1%}  "
              f"SOFA={sub['sofa_total'].mean():.1f}")
    U.log("  SOFA component means (septic vs not):")
    for cmp in sofa_cols:
        s = df.loc[df.sepsis3, cmp].mean()
        ns = df.loc[~df.sepsis3, cmp].mean()
        U.log(f"    {cmp:<12s} septic={s:.2f}  non={ns:.2f}")

    U.save(df, "analysis_matrix", C.OUTPUT_DIR, fmt="csv")
    if args.parquet:
        U.save(df, "analysis_matrix", C.OUTPUT_DIR, fmt="parquet")


if __name__ == "__main__":
    main()
