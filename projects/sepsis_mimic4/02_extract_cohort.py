"""
02_extract_cohort.py
====================
Builds the base ICU cohort from the small tables only (icustays, patients,
admissions). Safe to run on any machine; it never touches chartevents/labevents.

Pipeline
--------
  1. Load icustays + patients + admissions.
  2. Compute approximate age at ICU admission (anchor_age + year offset).
  3. Apply inclusion criteria from config:
        - adults (age >= MIN_AGE)
        - ICU LOS >= MIN_ICU_LOS_HOURS
        - first ICU stay per patient (optional)
  4. Attach mortality flags (in-hospital + ICU).
  5. Save -> processed_data/02_cohort.parquet

Output columns
--------------
  subject_id, hadm_id, stay_id, gender, age, first_careunit, last_careunit,
  intime, outtime, los_hours, admittime, dischtime, deathtime,
  hospital_expire_flag, died_in_icu, admission_type, race

Usage
-----
    python 02_extract_cohort.py
    python 02_extract_cohort.py
"""
from __future__ import annotations

import argparse

import pandas as pd

import config as C
import utils as U
from logging_utils import setup_logging, step, log_cohort_filter, log_separator


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


def apply_criteria(df: pd.DataFrame, logger) -> pd.DataFrame:
    logger.info("applying inclusion criteria ...")
    before = len(df)

    count_before = len(df)
    df = df[df["age"] >= C.MIN_AGE]
    log_cohort_filter(logger, f"age >= {C.MIN_AGE}", count_before, len(df))

    count_before = len(df)
    df = df[df["los_hours"] >= C.MIN_ICU_LOS_HOURS]
    log_cohort_filter(logger, f"LOS >= {C.MIN_ICU_LOS_HOURS}h", count_before, len(df))

    if C.FIRST_ICU_STAY_ONLY:
        count_before = len(df)
        df = (df.sort_values("intime")
                .groupby("subject_id", as_index=False)
                .first())
        log_cohort_filter(logger, "first ICU stay only", count_before, len(df))

    logger.info("inclusion criteria complete: %s -> %s stays",
                f"{before:,}", f"{len(df):,}")
    return df


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.parse_args()

    log = setup_logging("02_extract_cohort")

    with step(log, "loading icustays / patients / admissions"):
        icustays, patients, admissions = load_inputs()
    log.info("loaded icustays=%s  patients=%s  admissions=%s",
             f"{len(icustays):,}", f"{len(patients):,}", f"{len(admissions):,}")

    with step(log, "building cohort"):
        cohort = build_cohort(icustays, patients, admissions)
    cohort = apply_criteria(cohort, log)

    keep_cols = [
        "subject_id", "hadm_id", "stay_id", "gender", "age",
        "first_careunit", "last_careunit", "intime", "outtime", "los_hours",
        "admittime", "dischtime", "deathtime", "hospital_expire_flag",
        "died_in_icu", "admission_type", "race",
    ]
    cohort = cohort[[c for c in keep_cols if c in cohort.columns]]

    log_separator(log)
    log.info("FINAL COHORT: %s ICU stays / %s patients",
             f"{len(cohort):,}", f"{cohort['subject_id'].nunique():,}")
    log.info("  female: %.1f%%  age median: %.0f",
             (cohort['gender'] == 'F').mean() * 100, cohort['age'].median())
    log.info("  in-hospital mortality: %.1f%%",
             cohort['hospital_expire_flag'].mean() * 100)
    log.info("  ICU mortality: %.1f%%", cohort['died_in_icu'].mean() * 100)

    U.save(cohort, "02_cohort", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
