"""
02_extract_cohort.py
====================
Builds the base ICU cohort from the small tables only (icustays, patients,
admissions). Safe to run on any machine — it never touches chartevents/labevents.

Pipeline
--------
  1. Load icustays + patients + admissions.
  2. Compute approximate age at ICU admission (anchor_age + year offset).
  3. Apply inclusion criteria from config:
        - adults (age >= MIN_AGE)
        - ICU LOS >= MIN_ICU_LOS_HOURS
        - first ICU stay per patient (optional)
  4. Attach mortality flags (in-hospital + ICU).
  5. Save -> processed_data/cohort.csv

Output columns
--------------
  subject_id, hadm_id, stay_id, gender, age, first_careunit, last_careunit,
  intime, outtime, los_hours, admittime, dischtime, deathtime,
  hospital_expire_flag, died_in_icu, admission_type, race

Usage
-----
    python 02_extract_cohort.py
    python 02_extract_cohort.py --parquet  # also write a typed parquet copy
"""
from __future__ import annotations

import argparse

import pandas as pd

import config as C
import utils as U


def load_inputs() -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    icustays = U.read_table(
        C.FILES["icustays"],
        columns=["subject_id", "hadm_id", "stay_id", "first_careunit",
                 "last_careunit", "intime", "outtime", "los"],
        parse_dates=["intime", "outtime"],
    )
    patients = U.read_table(
        C.FILES["patients"],
        columns=["subject_id", "gender", "anchor_age", "anchor_year", "dod"],
        parse_dates=["dod"],
    )
    admissions = U.read_table(
        C.FILES["admissions"],
        columns=["subject_id", "hadm_id", "admittime", "dischtime", "deathtime",
                 "admission_type", "race", "hospital_expire_flag"],
        parse_dates=["admittime", "dischtime", "deathtime"],
    )
    return icustays, patients, admissions


def build_cohort(icustays, patients, admissions) -> pd.DataFrame:
    df = icustays.merge(patients, on="subject_id", how="left")
    df = df.merge(admissions, on=["subject_id", "hadm_id"], how="left")

    # LOS in hours (icustays.los is in days). Fall back to intime/outtime delta.
    los_hours = pd.to_numeric(df["los"], errors="coerce") * 24.0
    delta = (df["outtime"] - df["intime"]).dt.total_seconds() / 3600.0
    df["los_hours"] = los_hours.fillna(delta)

    # Approximate age at admission. MIMIC-IV deidentifies dates by shifting them
    # per-patient; anchor_age is the age in anchor_year. Adjust by the gap
    # between admission year and anchor_year.
    adm_year = df["admittime"].dt.year
    year_gap = (adm_year - df["anchor_year"]).fillna(0)
    df["age"] = df["anchor_age"].fillna(0) + year_gap
    df["age"] = df["age"].clip(lower=0)
    # MIMIC caps ages >89 at 91; keep that quirk visible rather than masking it.

    # Mortality flags.
    df["died_in_icu"] = (
        df["deathtime"].notna()
        & (df["deathtime"] >= df["intime"])
        & (df["deathtime"] <= df["outtime"])
    )

    return df


def apply_criteria(df: pd.DataFrame) -> pd.DataFrame:
    before = len(df)
    log = []

    df = df[df["age"] >= C.MIN_AGE]
    log.append(f"age >= {C.MIN_AGE}: {before} -> {len(df)}")

    n = len(df)
    df = df[df["los_hours"] >= C.MIN_ICU_LOS_HOURS]
    log.append(f"LOS >= {C.MIN_ICU_LOS_HOURS}h: {n} -> {len(df)}")

    if C.FIRST_ICU_STAY_ONLY:
        n = len(df)
        df = (df.sort_values("intime")
                .groupby("subject_id", as_index=False)
                .first())
        log.append(f"first ICU stay only: {n} -> {len(df)}")

    U.log("inclusion criteria applied:")
    for line in log:
        U.log("  " + line)
    return df


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--parquet", action="store_true", help="also write cohort.parquet")
    args = ap.parse_args()

    U.log("loading icustays / patients / admissions ...")
    icustays, patients, admissions = load_inputs()
    U.log(f"icustays={len(icustays):,}  patients={len(patients):,}  "
          f"admissions={len(admissions):,}")

    cohort = build_cohort(icustays, patients, admissions)
    cohort = apply_criteria(cohort)

    keep_cols = [
        "subject_id", "hadm_id", "stay_id", "gender", "age",
        "first_careunit", "last_careunit", "intime", "outtime", "los_hours",
        "admittime", "dischtime", "deathtime", "hospital_expire_flag",
        "died_in_icu", "admission_type", "race",
    ]
    cohort = cohort[[c for c in keep_cols if c in cohort.columns]]

    # Quick summary.
    U.log("=" * 50)
    U.log(f"FINAL COHORT: {len(cohort):,} ICU stays / "
          f"{cohort['subject_id'].nunique():,} patients")
    U.log(f"  female: {(cohort['gender'] == 'F').mean():.1%}  "
          f"age median: {cohort['age'].median():.0f}")
    U.log(f"  in-hospital mortality: {cohort['hospital_expire_flag'].mean():.1%}")
    U.log(f"  ICU mortality: {cohort['died_in_icu'].mean():.1%}")

    U.save(cohort, "cohort", C.OUTPUT_DIR, fmt="csv")
    if args.parquet:
        U.save(cohort, "cohort", C.OUTPUT_DIR, fmt="parquet")


if __name__ == "__main__":
    main()
