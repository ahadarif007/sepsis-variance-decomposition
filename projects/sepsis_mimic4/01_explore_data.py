"""
01_explore_data.py
===================
Profiles your MIMIC-IV copy and writes a report to processed_data/. This is the
script to run FIRST. Paste the report back so we can confirm itemids and value
distributions before building the SOFA / labeling / feature stages.

What it does
------------
  1. File inventory (existence + compressed size).
  2. Schema + a few sample rows for every table (huge tables: sample only).
  3. Mines d_items / d_labitems for every sepsis-relevant concept.
  4. Lists sepsis-related ICD codes present in d_icd_diagnoses.
  5. Confirms which candidate itemids from config actually appear in the
     dictionaries (catches stale/missing ids).
  6. Quick cohort size preview from icustays / patients.

Usage
-----
    python 01_explore_data.py                 # fast: dictionaries + samples
    python 01_explore_data.py --count-small   # also count rows of small tables
    python 01_explore_data.py --count-all     # count every table (slow!)
    python 01_explore_data.py --sample 5      # rows shown per table sample
"""
from __future__ import annotations

import argparse
import io
from contextlib import redirect_stdout

import pandas as pd

import config as C
import utils as U

# Tables small enough to count/inspect fully without worry.
SMALL_TABLES = {
    "admissions", "patients", "icustays", "services", "transfers",
    "d_icd_diagnoses", "d_icd_procedures", "d_labitems", "d_items",
    "d_hcpcs", "diagnoses_icd", "procedures_icd", "drgcodes", "caregiver",
    "provider", "microbiologyevents", "omr", "hcpcsevents", "datetimeevents",
    "outputevents", "procedureevents",
}
# Tables large enough that we only ever sample them here.
BIG_TABLES = {"chartevents", "labevents", "inputevents", "ingredientevents",
              "emar", "emar_detail", "pharmacy", "poe", "poe_detail",
              "prescriptions"}

SIZE_COUNT_LIMIT_MB = 200  # under --count-small, count files below this size


def section(title: str) -> None:
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


def inventory() -> None:
    section("1. FILE INVENTORY")
    rows = []
    for name, path in C.FILES.items():
        exists = path.exists()
        size = path.stat().st_size if exists else 0
        rows.append((name, "OK" if exists else "MISSING",
                     U.human_size(size) if exists else "-", str(path)))
    inv = pd.DataFrame(rows, columns=["table", "status", "size", "path"])
    with pd.option_context("display.max_colwidth", 70, "display.width", 200):
        print(inv.to_string(index=False))
    missing = inv[inv.status == "MISSING"]
    if not missing.empty:
        print(f"\n!! {len(missing)} file(s) missing - check paths in config.py")


def schemas(sample_rows: int, count_small: bool, count_all: bool) -> None:
    section("2. SCHEMAS + SAMPLES")
    for name, path in C.FILES.items():
        if not path.exists():
            continue
        print(f"\n--- {name}  ({U.human_size(path.stat().st_size)}) ---")
        try:
            cols = U.peek_header(path)
            print(f"columns ({len(cols)}): {', '.join(cols)}")
        except Exception as e:
            print(f"  (could not read header: {e})")
            continue

        # Sample a few rows (cheap for any file; nrows stops early).
        try:
            sample = U.read_table(path, nrows=sample_rows)
            with pd.option_context("display.max_columns", None,
                                   "display.width", 200,
                                   "display.max_colwidth", 22):
                print(sample.to_string(index=False))
        except Exception as e:
            print(f"  (could not sample: {e})")

        # Optional row counts.
        do_count = count_all or (
            count_small
            and name in SMALL_TABLES
            and path.stat().st_size < SIZE_COUNT_LIMIT_MB * 1024 * 1024
        )
        if do_count:
            try:
                print(f"row count: {U.count_rows(path):,}")
            except Exception as e:
                print(f"  (count failed: {e})")


def mine_dictionaries() -> None:
    section("3. DICTIONARY MINING (sepsis-relevant itemids)")

    # --- d_items (chartevents / inputevents / outputevents / procedureevents) ---
    if C.FILES["d_items"].exists():
        d_items = U.read_table(C.FILES["d_items"])
        print(f"\nd_items has {len(d_items):,} entries. "
              f"linksto values: {sorted(d_items['linksto'].dropna().unique())}")
        for concept, terms in C.DICT_SEARCH_TERMS.items():
            hits = U.search_labels(d_items, terms)
            if hits.empty:
                continue
            print(f"\n[d_items] {concept}:")
            show_cols = [c for c in ["itemid", "label", "abbreviation",
                                     "linksto", "category", "unitname"]
                         if c in hits.columns]
            with pd.option_context("display.max_rows", 40, "display.width", 200,
                                   "display.max_colwidth", 40):
                print(hits[show_cols].to_string(index=False))

    # --- d_labitems (labevents) ---
    if C.FILES["d_labitems"].exists():
        d_lab = U.read_table(C.FILES["d_labitems"])
        print(f"\nd_labitems has {len(d_lab):,} entries.")
        lab_terms = {
            "lactate": ["lactate"],
            "creatinine": ["creatinine"],
            "bilirubin": ["bilirubin"],
            "platelets": ["platelet"],
            "wbc": ["white blood", "wbc", "leukocyte"],
            "blood gas": ["po2", "pco2", "ph", "bicarbonate", "base excess"],
            "bun/urea": ["urea nitrogen", "bun"],
            "inflammatory": ["c-reactive", "procalcitonin"],
            "coagulation": ["inr", "prothrombin"],
        }
        for concept, terms in lab_terms.items():
            hits = U.search_labels(d_lab, terms)
            if hits.empty:
                continue
            print(f"\n[d_labitems] {concept}:")
            show_cols = [c for c in ["itemid", "label", "fluid", "category"]
                         if c in hits.columns]
            with pd.option_context("display.max_rows", 40, "display.width", 200,
                                   "display.max_colwidth", 40):
                print(hits[show_cols].to_string(index=False))


def sepsis_icd_codes() -> None:
    section("4. SEPSIS ICD CODES PRESENT IN d_icd_diagnoses")
    if not C.FILES["d_icd_diagnoses"].exists():
        print("d_icd_diagnoses missing.")
        return
    d = U.read_table(C.FILES["d_icd_diagnoses"], dtype={"icd_code": "string"})
    title = d["long_title"].astype("string").str.lower()
    mask = title.str.contains("sepsis|septic|septicemia|septicaemia",
                              na=False, regex=True)
    hits = d[mask]
    print(f"{len(hits)} matching code(s):")
    with pd.option_context("display.max_rows", 80, "display.width", 200,
                           "display.max_colwidth", 70):
        print(hits.to_string(index=False))


def verify_candidate_itemids() -> None:
    section("5. VERIFY CANDIDATE ITEMIDS FROM config.py")

    if C.FILES["d_items"].exists():
        d_items = U.read_table(C.FILES["d_items"])
        valid = set(d_items["itemid"].tolist())
        label_by_id = dict(zip(d_items["itemid"], d_items["label"]))

        def _check(group_name: str, mapping: dict) -> None:
            print(f"\n[{group_name}]")
            for concept, ids in mapping.items():
                statuses = []
                for i in ids:
                    if i in valid:
                        statuses.append(f"{i}=OK ({label_by_id.get(i)})")
                    else:
                        statuses.append(f"{i}=MISSING")
                print(f"  {concept:20s} -> {', '.join(statuses)}")

        _check("CHART_ITEMIDS", C.CHART_ITEMIDS)
        _check("VASOPRESSOR_ITEMIDS", C.VASOPRESSOR_ITEMIDS)
        print("\n[URINE_OUTPUT_ITEMIDS]")
        for i in C.URINE_OUTPUT_ITEMIDS:
            tag = f"OK ({label_by_id.get(i)})" if i in valid else "MISSING"
            print(f"  {i} -> {tag}")

    if C.FILES["d_labitems"].exists():
        d_lab = U.read_table(C.FILES["d_labitems"])
        valid_lab = set(d_lab["itemid"].tolist())
        label_by_id = dict(zip(d_lab["itemid"], d_lab["label"]))
        print("\n[LAB_ITEMIDS]")
        for concept, ids in C.LAB_ITEMIDS.items():
            statuses = []
            for i in ids:
                if i in valid_lab:
                    statuses.append(f"{i}=OK ({label_by_id.get(i)})")
                else:
                    statuses.append(f"{i}=MISSING")
            print(f"  {concept:18s} -> {', '.join(statuses)}")


def cohort_preview() -> None:
    section("6. COHORT SIZE PREVIEW")
    try:
        icustays = U.read_table(C.FILES["icustays"])
        patients = U.read_table(C.FILES["patients"])
    except Exception as e:
        print(f"could not load cohort tables: {e}")
        return

    n_stays = len(icustays)
    n_patients = icustays["subject_id"].nunique()
    print(f"icustays rows:            {n_stays:,}")
    print(f"unique patients (icu):    {n_patients:,}")
    if "los" in icustays.columns:
        los = pd.to_numeric(icustays["los"], errors="coerce")
        print(f"ICU LOS (days) median:    {los.median():.2f}  "
              f"[p25 {los.quantile(.25):.2f}, p75 {los.quantile(.75):.2f}]")
        keep_los = (los * 24 >= C.MIN_ICU_LOS_HOURS).sum()
        print(f"stays >= {C.MIN_ICU_LOS_HOURS}h LOS:       {keep_los:,}")

    if "anchor_age" in patients.columns:
        adults = patients[patients["anchor_age"] >= C.MIN_AGE]["subject_id"]
        adult_stays = icustays[icustays["subject_id"].isin(set(adults))]
        print(f"adult (>= {C.MIN_AGE}) icu stays:  {len(adult_stays):,}")

    if C.FIRST_ICU_STAY_ONLY and "intime" in icustays.columns:
        first = (icustays.sort_values("intime")
                 .groupby("subject_id", as_index=False).first())
        print(f"first-stay-only count:    {len(first):,}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Profile MIMIC-IV for sepsis work.")
    ap.add_argument("--sample", type=int, default=3,
                    help="rows to show per table sample (default 3)")
    ap.add_argument("--count-small", action="store_true",
                    help="also count rows of small tables")
    ap.add_argument("--count-all", action="store_true",
                    help="count rows of EVERY table (slow)")
    args = ap.parse_args()

    buf = io.StringIO()
    with redirect_stdout(buf):
        print("MIMIC-IV v3.1 - SEPSIS DATA EXPLORATION REPORT")
        print(f"project root: {C.PROJECT_ROOT}")
        inventory()
        schemas(args.sample, args.count_small, args.count_all)
        mine_dictionaries()
        sepsis_icd_codes()
        verify_candidate_itemids()
        cohort_preview()
        print("\n" + "=" * 78)
        print("DONE. Send this whole report back to refine the next stages:")
        print(" - which itemids are confirmed (section 5)")
        print(" - any MISSING ids that need new candidates (sections 3 & 5)")
        print(" - cohort sizes (section 6) so we can set thresholds")
        print("=" * 78)

    report = buf.getvalue()
    print(report)  # to console
    out_path = C.OUTPUT_DIR / "exploration_report.txt"
    out_path.write_text(report)
    U.log(f"report saved -> {out_path}")


if __name__ == "__main__":
    main()
