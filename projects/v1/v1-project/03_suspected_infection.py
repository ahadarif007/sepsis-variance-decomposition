"""
03_suspected_infection.py
=========================
Detects suspected infection per the Sepsis-3 definition:
  a qualifying antibiotic order AND a culture sampled within the Sepsis-3
  time window around that order.

Sepsis-3 timing (Seymour et al. JAMA 2016):
  Arm 1 - abx first : culture drawn <= ABX_BEFORE_CULTURE_HOURS (72h) after abx start
           -> t_suspicion = t_abx
  Arm 2 - culture first : abx started <= CULTURE_BEFORE_ABX_HOURS (24h) after culture
           -> t_suspicion = t_culture

For each ICU stay in cohort.csv we find the EARLIEST qualifying pair
and record t_suspicion, the triggering antibiotic, and the culture type.

Output
------
processed_data/03_suspected_infection.parquet
  stay_id, subject_id, hadm_id, t_suspicion, t_abx, t_culture,
  abx_drug, spec_type_desc
"""
from __future__ import annotations

import argparse

import pandas as pd

import config as C
import utils as U
from logging_utils import setup_logging, step, log_separator

# Hours before ICU admission to include pre-ICU events.
PRE_ICU_BUFFER_HOURS = 48


def load_cohort() -> pd.DataFrame:
    return U.load("02_cohort", C.OUTPUT_DIR, parse_dates=["intime", "outtime"])[
        ["stay_id", "subject_id", "hadm_id", "intime", "outtime"]
    ]


def load_antibiotics(cohort_hadm: set) -> pd.DataFrame:
    """Stream prescriptions in chunks; keep antibiotic rows for cohort admissions."""
    cols = ["subject_id", "hadm_id", "starttime", "drug"]
    kept: list[pd.DataFrame] = []
    total = 0
    for chunk in pd.read_csv(
        C.FILES["prescriptions"],
        usecols=cols,
        parse_dates=["starttime"],
        chunksize=500_000,
        low_memory=False,
    ):
        total += len(chunk)
        sub = chunk[chunk["hadm_id"].isin(cohort_hadm)].copy()
        if sub.empty:
            continue
        mask = U.match_antibiotics(sub["drug"], C.ANTIBIOTICS)
        sub = sub[mask]
        if not sub.empty:
            kept.append(sub)

    U.log(f"prescriptions: scanned {total:,} rows, "
          f"kept {sum(len(k) for k in kept):,} antibiotic rows")
    if kept:
        df = pd.concat(kept, ignore_index=True).dropna(subset=["starttime"])
        df["hadm_id"] = df["hadm_id"].astype(int)
        return df
    return pd.DataFrame(columns=cols)


def load_cultures(cohort_hadm: set) -> pd.DataFrame:
    """Load microbiologyevents; deduplicate to one row per unique specimen draw."""
    cols = ["subject_id", "hadm_id", "charttime", "chartdate", "spec_type_desc"]
    df = U.read_table(
        C.FILES["microbiologyevents"],
        columns=cols,
        parse_dates=["charttime", "chartdate"],
    )
    df = df[df["hadm_id"].isin(cohort_hadm)].copy()

    # Drop surveillance / colonization screens (e.g. MRSA SCREEN). These are
    # not diagnostic infection cultures and should not trigger suspected
    # infection under Sepsis-3. Controlled by config (default: exclude).
    if getattr(C, "EXCLUDE_SURVEILLANCE_CULTURES", False):
        surv = {s.lower().strip() for s in C.SURVEILLANCE_SPEC_TYPES}
        spec_norm = df["spec_type_desc"].astype("string").str.lower().str.strip()
        is_surv = spec_norm.isin(surv)
        U.log(f"excluding {int(is_surv.sum()):,} surveillance-screen specimens "
              f"({', '.join(sorted(C.SURVEILLANCE_SPEC_TYPES))})")
        df = df[~is_surv].copy()

    # Fill missing charttime from chartdate (midnight of that date).
    missing = df["charttime"].isna()
    df.loc[missing, "charttime"] = pd.to_datetime(df.loc[missing, "chartdate"])
    df = df.dropna(subset=["charttime"])
    df["hadm_id"] = df["hadm_id"].astype(int)

    # One row per unique specimen draw (deduplicate by subject+hadm+time+type).
    df = (
        df.sort_values("charttime")
        .drop_duplicates(
            subset=["subject_id", "hadm_id", "charttime", "spec_type_desc"]
        )
        [["subject_id", "hadm_id", "charttime", "spec_type_desc"]]
        .reset_index(drop=True)
    )
    U.log(f"cultures: {len(df):,} unique specimen draws in cohort")
    return df


def find_suspicion(
    cohort: pd.DataFrame,
    abx: pd.DataFrame,
    cultures: pd.DataFrame,
) -> pd.DataFrame:
    """
    Cross-join antibiotics x cultures within each hadm_id, apply Sepsis-3
    time windows, and return the earliest qualifying t_suspicion per stay.
    """
    abx = abx.rename(columns={"starttime": "t_abx", "drug": "abx_drug"})
    cultures = cultures.rename(columns={"charttime": "t_culture"})

    # Merge both event tables onto cohort via hadm_id.
    merged = (
        cohort[["stay_id", "subject_id", "hadm_id", "intime", "outtime"]]
        .merge(abx[["hadm_id", "t_abx", "abx_drug"]], on="hadm_id", how="inner")
        .merge(
            cultures[["hadm_id", "t_culture", "spec_type_desc"]],
            on="hadm_id",
            how="inner",
        )
    )
    U.log(f"raw abxxculture pairs in cohort: {len(merged):,}")

    if merged.empty:
        U.log("WARNING: no abx-culture pairs found in cohort")
        return pd.DataFrame()

    # Restrict both events to a window around the ICU stay.
    window_start = merged["intime"] - pd.Timedelta(hours=PRE_ICU_BUFFER_HOURS)
    merged = merged[
        (merged["t_abx"]     >= window_start) & (merged["t_abx"]     <= merged["outtime"]) &
        (merged["t_culture"] >= window_start) & (merged["t_culture"] <= merged["outtime"])
    ].copy()
    U.log(f"after ICU-window filter: {len(merged):,} pairs")

    diff_h = (merged["t_culture"] - merged["t_abx"]).dt.total_seconds() / 3600.0

    # Arm 1: abx starts first, culture within 72h after.
    arm1 = merged[(diff_h >= 0) & (diff_h <= C.ABX_BEFORE_CULTURE_HOURS)].copy()
    arm1["t_suspicion"] = arm1["t_abx"]

    # Arm 2: culture drawn first, abx within 24h after.
    arm2 = merged[(diff_h < 0) & (-diff_h <= C.CULTURE_BEFORE_ABX_HOURS)].copy()
    arm2["t_suspicion"] = arm2["t_culture"]

    pairs = pd.concat([arm1, arm2], ignore_index=True)
    U.log(f"qualifying pairs (within Sepsis-3 windows): {len(pairs):,}")

    if pairs.empty:
        U.log("WARNING: no qualifying abx-culture pairs within time windows")
        return pd.DataFrame()

    # Earliest suspicion time per stay.
    pairs = pairs.sort_values("t_suspicion")
    result = pairs.groupby("stay_id", as_index=False).first()

    keep_cols = [
        "stay_id", "subject_id", "hadm_id",
        "t_suspicion", "t_abx", "t_culture", "abx_drug", "spec_type_desc",
    ]
    return result[[c for c in keep_cols if c in result.columns]]


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Detect suspected infection (Sepsis-3) per ICU stay."
    )
    ap.parse_args()

    log = setup_logging("03_suspected_infection")

    with step(log, "loading cohort"):
        cohort = load_cohort()
        cohort["hadm_id"] = cohort["hadm_id"].dropna().astype(int)
        cohort_hadm = set(cohort["hadm_id"].dropna().astype(int))
    log.info("cohort: %s stays, %s unique hadm_ids",
             f"{len(cohort):,}", f"{len(cohort_hadm):,}")

    with step(log, "loading antibiotic prescriptions (streaming)"):
        abx = load_antibiotics(cohort_hadm)
    log.info("antibiotics: %s orders across %s admissions",
             f"{len(abx):,}", f"{abx['hadm_id'].nunique():,}")

    with step(log, "loading culture draws"):
        cultures = load_cultures(cohort_hadm)

    with step(log, "pairing antibiotics x cultures (Sepsis-3 windows)"):
        result = find_suspicion(cohort, abx, cultures)

    if result.empty:
        log.error("no suspected infection records produced — check inputs")
        return

    n_stays = cohort["stay_id"].nunique()
    n_susp = result["stay_id"].nunique()
    log_separator(log)
    log.info("suspected infection: %s / %s stays (%.1f%%)",
             f"{n_susp:,}", f"{n_stays:,}", n_susp / n_stays * 100)

    top_specs = result["spec_type_desc"].value_counts().head(10)
    log.info("top culture types:")
    for spec, cnt in top_specs.items():
        log.info("  %-35s %s", spec, f"{cnt:,}")

    top_abx = result["abx_drug"].value_counts().head(10)
    log.info("top triggering antibiotics:")
    for drug, cnt in top_abx.items():
        log.info("  %-35s %s", drug, f"{cnt:,}")

    U.save(result, "03_suspected_infection", C.OUTPUT_DIR)


if __name__ == "__main__":
    main()
