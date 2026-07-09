"""
config.py
=========
Single source of truth for the MIMIC-IV v3.1 sepsis pipeline.

Everything that the rest of the pipeline depends on (paths, ICD codes, candidate
itemids, antibiotic names, cohort thresholds, Sepsis-3 time windows) lives here
so you only ever edit one file.

PATH RESOLUTION
---------------
The project root is found automatically by walking up from this file until a
folder containing `data/mimic-iv-3.1` is located. Override with the env var:

    export MIMIC_RESEARCH_ROOT=/Users/arif/RESEARCH

NOTE ON ITEMIDS
---------------
The itemid lists below are *candidates* based on standard MIMIC-IV metavision
ids. DO NOT trust them blindly. Run `01_explore_data.py`, which mines the
`d_items` / `d_labitems` dictionaries and confirms which ids actually exist in
your copy of the data. We refine these together from that output.
"""
from __future__ import annotations

import os
from pathlib import Path

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
def _find_project_root(start: Path) -> Path:
    env = os.environ.get("MIMIC_RESEARCH_ROOT")
    if env:
        return Path(env).expanduser().resolve()
    for candidate in [start, *start.parents]:
        if (candidate / "data" / "mimic-iv-3.1").is_dir():
            return candidate
    # Fallback: assume the scripts sit one level under the project root.
    return start.parent


PROJECT_ROOT = _find_project_root(Path(__file__).resolve().parent)

MIMIC_DIR  = PROJECT_ROOT / "data" / "mimic-iv-3.1"
HOSP_DIR   = MIMIC_DIR / "hosp"
ICU_DIR    = MIMIC_DIR / "icu"
OUTPUT_DIR = PROJECT_ROOT / "processed_data"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)


def hosp(name: str) -> Path:
    return HOSP_DIR / name


def icu(name: str) -> Path:
    return ICU_DIR / name


# Every table in the dataset, keyed by a short name used throughout the pipeline.
FILES: dict[str, Path] = {
    # --- hosp module ---
    "admissions":         hosp("admissions.csv"),
    "d_hcpcs":            hosp("d_hcpcs.csv"),
    "d_icd_diagnoses":    hosp("d_icd_diagnoses.csv"),
    "d_icd_procedures":   hosp("d_icd_procedures.csv"),
    "d_labitems":         hosp("d_labitems.csv"),
    "diagnoses_icd":      hosp("diagnoses_icd.csv"),
    "drgcodes":           hosp("drgcodes.csv"),
    "emar":               hosp("emar.csv"),
    "emar_detail":        hosp("emar_detail.csv"),
    "hcpcsevents":        hosp("hcpcsevents.csv"),
    "labevents":          hosp("labevents.csv"),
    "microbiologyevents": hosp("microbiologyevents.csv"),
    "omr":                hosp("omr.csv"),
    "patients":           hosp("patients.csv"),
    "pharmacy":           hosp("pharmacy.csv"),
    "poe":                hosp("poe.csv"),
    "poe_detail":         hosp("poe_detail.csv"),
    "prescriptions":      hosp("prescriptions.csv"),
    "procedures_icd":     hosp("procedures_icd.csv"),
    "provider":           hosp("provider.csv"),
    "services":           hosp("services.csv"),
    "transfers":          hosp("transfers.csv"),
    # --- icu module ---
    "caregiver":          icu("caregiver.csv"),
    "chartevents":        icu("chartevents.csv"),
    "d_items":            icu("d_items.csv"),
    "datetimeevents":     icu("datetimeevents.csv"),
    "icustays":           icu("icustays.csv"),
    "ingredientevents":   icu("ingredientevents.csv"),
    "inputevents":        icu("inputevents.csv"),
    "outputevents":       icu("outputevents.csv"),
    "procedureevents":    icu("procedureevents.csv"),
}

# --------------------------------------------------------------------------- #
# Cohort criteria
# --------------------------------------------------------------------------- #
MIN_AGE = 18                  # adults only
MIN_ICU_LOS_HOURS = 4.0       # drop ultra-short stays (likely incomplete)
FIRST_ICU_STAY_ONLY = True    # keep only each patient's first ICU stay

# --------------------------------------------------------------------------- #
# Sepsis-3 definition parameters
# --------------------------------------------------------------------------- #
# Suspected infection = an antibiotic order and a culture sampled close in time.
# (Seymour et al., JAMA 2016; Singer et al., Sepsis-3.)
ABX_BEFORE_CULTURE_HOURS = 72   # culture drawn up to 72h AFTER antibiotic start
CULTURE_BEFORE_ABX_HOURS = 24   # antibiotic started up to 24h AFTER culture

SOFA_INCREASE_THRESHOLD = 2     # >= 2 point rise in SOFA = organ dysfunction
# Septic shock = sepsis + vasopressors + lactate > 2 mmol/L (after fluids).
SEPTIC_SHOCK_LACTATE_MMOL = 2.0

# Surveillance / colonization screens are NOT diagnostic infection cultures and
# are excluded from the suspected-infection definition (standard Sepsis-3
# phenotyping; Seymour et al. 2016 pair antibiotics with body-fluid *cultures*,
# not admission surveillance swabs). Including MRSA SCREEN inflated suspected
# infection to 51.5% of the cohort. Matched case-insensitively, exact string.
# Set EXCLUDE_SURVEILLANCE_CULTURES = False to revert to the old behaviour.
EXCLUDE_SURVEILLANCE_CULTURES = True
SURVEILLANCE_SPEC_TYPES = {
    "MRSA SCREEN",            # nasal surveillance swab for MRSA colonization
    "Staph aureus swab",      # same MRSA nares surveillance under another label
    "Cipro Resistant Screen", # antibiotic-resistance surveillance
    "CRE Screen",             # carbapenem-resistant Enterobacteriaceae surveillance
    "Swab R/O Yeast Screen",  # colonization screen
    "SWAB - R/O YEAST",       # colonization screen
    "C, E, & A Screening",    # colonization screen
}
# Deliberately NOT excluded: "SWAB" (diagnostic wound/site cultures) and
# "Rapid Respiratory Viral Screen & Culture" (diagnostic test for active
# respiratory infection).

# Window around suspicion time over which we evaluate the SOFA delta.
SOFA_WINDOW_BEFORE_HOURS = 48
SOFA_WINDOW_AFTER_HOURS  = 24

# --------------------------------------------------------------------------- #
# Sepsis ICD codes (used ONLY as a secondary / comparison label, not Sepsis-3)
# --------------------------------------------------------------------------- #
# ICD-9
SEPSIS_ICD9 = {
    "99591",  # sepsis
    "99592",  # severe sepsis
    "78552",  # septic shock
}
SEPSIS_ICD9_PREFIXES = ("038",)  # septicemia 038.xx

# ICD-10
SEPSIS_ICD10_PREFIXES = (
    "A40",    # streptococcal sepsis
    "A41",    # other sepsis
    "R6520",  # severe sepsis without septic shock
    "R6521",  # severe sepsis with septic shock
)

# --------------------------------------------------------------------------- #
# Antibiotics (systemic) for suspected-infection detection
# Matched as case-insensitive substrings against prescriptions.drug
# Canonical Sepsis-3 antibiotic list (abbreviated but representative).
# --------------------------------------------------------------------------- #
ANTIBIOTICS = [
    "adoxa", "amikacin", "amikin", "amoxicillin", "amphotericin", "ampicillin",
    "augmentin", "avelox", "azactam", "azithromycin", "aztreonam", "bactrim",
    "biaxin", "cayston", "cefazolin", "cefepime", "cefotan", "cefotetan",
    "cefotaxime", "cefpodoxime", "ceftaroline", "cefadroxil", "ceftazidime",
    "ceftriaxone", "cefuroxime", "cephalexin", "chloramphenicol", "cipro",
    "ciprofloxacin", "claforan", "clarithromycin", "cleocin", "clindamycin",
    "colistin", "coly-mycin", "cubicin", "daptomycin", "dicloxacillin",
    "doryx", "doxycycline", "erythromycin", "flagyl", "fortaz", "furadantin",
    "garamycin", "gentamicin", "imipenem", "kanamycin", "keflex", "levaquin",
    "levofloxacin", "linezolid", "macrobid", "macrodantin", "maxipime",
    "mefoxin", "meropenem", "methicillin", "metronidazole", "minocycline",
    "moxifloxacin", "nafcillin", "neomycin", "nitrofurantoin", "norfloxacin",
    "ofloxacin", "omnicef", "oxacillin", "penicillin", "piperacillin",
    "polymyxin", "rifampin", "rocephin", "septra", "streptomycin",
    "sulfadiazine", "sulfamethoxazole", "tazobactam", "tetracycline",
    "timentin", "tobramycin", "trimethoprim", "unasyn", "vancocin",
    "vancomycin", "zosyn", "zyvox",
]

# --------------------------------------------------------------------------- #
# Candidate itemids (VERIFY with 01_explore_data.py before relying on these)
# --------------------------------------------------------------------------- #
# chartevents (icu/d_items)
CHART_ITEMIDS = {
    "heart_rate":        [220045],
    "sbp_invasive":      [220050],
    "sbp_noninvasive":   [220179],
    "dbp_invasive":      [220051],
    "dbp_noninvasive":   [220180],
    "map_invasive":      [220052],
    "map_noninvasive":   [220181],
    "resp_rate":         [220210, 224690],
    "temp_c":            [223762],
    "temp_f":            [223761],
    "spo2":              [220277],
    "fio2":              [223835],
    "gcs_eye":           [220739],
    "gcs_verbal":        [223900],
    "gcs_motor":         [223901],
    "weight_admit":      [226512],
    "weight_daily":      [224639],
    "height":            [226730],
}

# labevents (hosp/d_labitems)
LAB_ITEMIDS = {
    "lactate":           [50813],
    "creatinine":        [50912],
    "bilirubin_total":   [50885],
    "platelets":         [51265],
    "wbc":               [51301, 51300],
    "hemoglobin":        [51222],
    "pao2":              [50821],
    "paco2":             [50818],
    "ph_blood":          [50820],
    "bicarbonate":       [50882],
    "bun":               [51006],
    "sodium":            [50983],
    "potassium":         [50971],
    "glucose":           [50931],
    "inr":               [51237],
    "crp":               [50889],
}

# inputevents vasopressors (icu/d_items) — units matter for SOFA cardio scoring
VASOPRESSOR_ITEMIDS = {
    "norepinephrine":    [221906],
    "epinephrine":       [221289],
    "dopamine":          [221662],
    "dobutamine":        [221653],
    "vasopressin":       [222315],
    "phenylephrine":     [221749],
}

# outputevents urine (icu/d_items) — confirm full list via explorer
URINE_OUTPUT_ITEMIDS = [
    226559,  # Foley
    226560,  # Void
    226561,  # Condom Cath
    226584,  # Ileoconduit
    226563,  # Suprapubic
    226565,  # R Nephrostomy
    226567,  # Straight Cath
    226557,  # L Nephrostomy
    226558,  # Ureteral Stent
]

# Keyword groups used by the explorer to mine the dictionaries.
DICT_SEARCH_TERMS = {
    "blood pressure": ["blood pressure", "arterial pressure", "abp", "nbp", " map"],
    "heart rate":     ["heart rate"],
    "respiration":    ["respiratory rate", "resp rate", "spo2", "o2 sat",
                       "fio2", "inspired o2"],
    "temperature":    ["temperature"],
    "gcs":            ["gcs", "glasgow", "eye opening", "verbal response",
                       "motor response"],
    "weight/height":  ["weight", "height"],
    "lactate":        ["lactate"],
    "renal":          ["creatinine", "bun", "urea", "urine"],
    "liver":          ["bilirubin"],
    "coagulation":    ["platelet", "inr", "pt "],
    "blood gas":      ["po2", "pco2", "ph", "bicarbonate", "base excess"],
    "vasopressors":   ["norepinephrine", "epinephrine", "dopamine",
                       "dobutamine", "vasopressin", "phenylephrine",
                       "levophed", "neosynephrine"],
}
