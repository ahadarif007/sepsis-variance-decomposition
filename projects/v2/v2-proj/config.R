# config.R — V2 pipeline configuration
# Single source of truth for all paths, parameters, and label variant definitions.
#
# V2 methodology:
#   - 3 Sepsis-3 onset label variants (Cohen et al., 2024 / Johnson et al., 2018)
#   - Person-hour table with competing events (discharge alive, death without sepsis)
#   - Dynamic discrete-time competing-risks hazard model (multinomial pooled logistic)
#   - Temporal split primary; random split for optimism quantification (Guo et al., 2022)
#   - Treatment-anchored evaluation (Kamran et al., 2024)
#   - PhysioNet Utility Score + calibration as primary metrics (Wang et al., 2025)
#   - NEWS2 as headline rule-based comparator (Evans et al., 2021)
#   - Gradient-boosted trees as mandatory ML comparator (Reyna et al., 2020)

# --------------------------------------------------------------------------- #
# Null-coalescing operator (defined first so it's available everywhere)
# --------------------------------------------------------------------------- #
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

# --------------------------------------------------------------------------- #
# Script directory detection (works in Rscript, source(), and RStudio)
# --------------------------------------------------------------------------- #
.get_script_dir <- function() {
  # Rscript --file= argument (works in all Rscript invocations)
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- args[grep("^--file=", args)]
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]))))
  }
  # Fallback: working directory
  normalizePath(".")
}

SCRIPT_DIR <- .get_script_dir()

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
# Allow override via environment variable
PROJECT_ROOT <- Sys.getenv("MIMIC_RESEARCH_ROOT", unset = "")
if (nchar(PROJECT_ROOT) == 0) {
  # Auto-detect: walk up from script dir until data/mimic-iv-3.1 is found
  candidate <- SCRIPT_DIR
  found <- FALSE
  for (i in 1:10) {
    if (dir.exists(file.path(candidate, "data", "mimic-iv-3.1"))) {
      PROJECT_ROOT <- candidate
      found <- TRUE
      break
    }
    parent <- dirname(candidate)
    if (parent == candidate) break
    candidate <- parent
  }
  if (!found) PROJECT_ROOT <- "/Users/arif/Desktop/RESEARCH"
}
PROJECT_ROOT <- normalizePath(PROJECT_ROOT, mustWork = FALSE)

MIMIC_DIR  <- file.path(PROJECT_ROOT, "data", "mimic-iv-3.1")
HOSP_DIR   <- file.path(MIMIC_DIR, "hosp")
ICU_DIR    <- file.path(MIMIC_DIR, "icu")
EICU_DIR   <- file.path(PROJECT_ROOT, "data", "eicu-collaborative-research-database-2.0")

# V2-specific output directory (co-located with scripts)
OUTPUT_DIR   <- file.path(SCRIPT_DIR, "output")
LOG_DIR      <- file.path(OUTPUT_DIR, "logs")
FIGURES_DIR  <- file.path(OUTPUT_DIR, "figures")
PDF_DIR      <- file.path(OUTPUT_DIR, "pdf")
DATA_DIR     <- file.path(OUTPUT_DIR, "processed_data")
for (.d in c(OUTPUT_DIR, LOG_DIR, FIGURES_DIR, PDF_DIR, DATA_DIR))
  dir.create(.d, recursive = TRUE, showWarnings = FALSE)

# Helper to resolve .gz or plain CSV
resolve_file <- function(dir, name) {
  gz <- file.path(dir, paste0(name, ".gz"))
  if (file.exists(gz)) return(gz)
  file.path(dir, name)
}

hosp_file <- function(name) resolve_file(HOSP_DIR, name)
icu_file  <- function(name) resolve_file(ICU_DIR,  name)

# --------------------------------------------------------------------------- #
# Cohort criteria
# --------------------------------------------------------------------------- #
MIN_AGE              <- 18      # adults only
MIN_ICU_LOS_HOURS    <- 4.0    # drop ultra-short stays
FIRST_ICU_STAY_ONLY  <- TRUE   # keep only first ICU stay per patient
MAX_PANEL_HOURS      <- 72     # right-censor at 72h ICU time
MIN_OBS_HOURS        <- 1      # minimum observation before prediction eligible

# Temporal split by anchor_year_group
# train: early cohorts, test: latest cohort (Guo et al., 2022)
TEMPORAL_TRAIN_GROUPS <- c("2008 - 2010", "2011 - 2013", "2014 - 2016")
TEMPORAL_TEST_GROUPS  <- c("2017 - 2019")

# Random split seed (for optimism quantification only)
RANDOM_SPLIT_SEED <- 42
RANDOM_SPLIT_TEST_FRAC <- 0.25

# --------------------------------------------------------------------------- #
# Three Sepsis-3 onset label variants (pre-registered; Cohen et al., 2024)
# Vary in: (a) ABX-culture window, (b) SOFA delta window, (c) SOFA baseline
# --------------------------------------------------------------------------- #
LABEL_VARIANTS <- list(
  A = list(
    name               = "Narrow",
    # Narrow culture-antibiotic windows (most restrictive)
    abx_before_culture_h = 24,   # ABX started up to 24h BEFORE culture
    culture_before_abx_h = 24,   # culture drawn up to 24h AFTER ABX
    # Narrow SOFA evaluation window around suspicion time
    sofa_window_before_h = 24,
    sofa_window_after_h  = 12,
    # Baseline = admission SOFA (most conservative; can only go up)
    sofa_baseline        = "admission"
  ),
  B = list(
    name               = "Seymour-Standard",
    # Standard Seymour et al. (2016) / Singer et al. Sepsis-3 windows
    abx_before_culture_h = 72,
    culture_before_abx_h = 24,
    sofa_window_before_h = 48,
    sofa_window_after_h  = 24,
    sofa_baseline        = "admission"
  ),
  C = list(
    name               = "Liberal",
    # Widest windows (most permissive; gives largest cohort)
    abx_before_culture_h = 72,
    culture_before_abx_h = 72,
    sofa_window_before_h = 48,
    sofa_window_after_h  = 24,
    # Rolling 24h min baseline (allows re-evaluation; most permissive)
    sofa_baseline        = "rolling_24h"
  )
)

SOFA_INCREASE_THRESHOLD <- 2   # >= 2 SOFA points = organ dysfunction

# Surveillance cultures to exclude from suspected-infection definition
SURVEILLANCE_SPEC_TYPES <- c(
  "MRSA SCREEN", "Staph aureus swab", "Cipro Resistant Screen",
  "CRE Screen", "Swab R/O Yeast Screen", "SWAB - R/O YEAST",
  "C, E, & A Screening"
)

# --------------------------------------------------------------------------- #
# Antibiotics (systemic) for suspected infection
# --------------------------------------------------------------------------- #
ANTIBIOTICS <- c(
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
  "vancomycin", "zosyn", "zyvox"
)

# --------------------------------------------------------------------------- #
# Chart itemids (MIMIC-IV chartevents)
# --------------------------------------------------------------------------- #
CHART_ITEMIDS <- list(
  heart_rate       = 220045L,
  sbp_invasive     = 220050L,
  sbp_noninvasive  = 220179L,
  dbp_invasive     = 220051L,
  dbp_noninvasive  = 220180L,
  map_invasive     = 220052L,
  map_noninvasive  = 220181L,
  resp_rate        = c(220210L, 224690L),
  temp_c           = 223762L,
  temp_f           = 223761L,
  spo2             = 220277L,
  fio2             = 223835L,
  gcs_eye          = 220739L,
  gcs_verbal       = 223900L,
  gcs_motor        = 223901L
)

# Lab itemids (MIMIC-IV labevents)
LAB_ITEMIDS <- list(
  lactate         = 50813L,
  creatinine      = 50912L,
  bilirubin_total = 50885L,
  platelets       = 51265L,
  wbc             = c(51301L, 51300L),
  pao2            = 50821L,
  fio2_lab        = 50816L,
  sodium          = 50983L,
  potassium       = 50971L
)

# Vasopressor itemids (inputevents)
VASOPRESSOR_ITEMIDS <- list(
  norepinephrine = 221906L,
  epinephrine    = 221289L,
  dopamine       = 221662L,
  dobutamine     = 221653L,
  vasopressin    = 222315L,
  phenylephrine  = 221749L
)

# Urine output itemids (outputevents)
URINE_OUTPUT_ITEMIDS <- c(226559L, 226560L, 226561L, 226584L, 226563L,
                           226565L, 226567L, 226557L, 226558L)

# --------------------------------------------------------------------------- #
# Prediction framing (pre-registered; Lauritsen et al., 2021)
# --------------------------------------------------------------------------- #
PREDICTION_HORIZON_H <- 6     # predict onset within next 6h (matches Reyna et al., 2020)
SLOPE_WINDOW_H       <- 6     # rolling slope window

# PhysioNet 2019 Utility Score parameters (Reyna et al., 2020)
UTILITY_TP_MIN  <- -6   # earliest true-positive offset (hours before onset)
UTILITY_TP_MAX  <-  3   # latest true-positive offset (hours after onset)
UTILITY_FN_LATE <- -6   # for late FN penalty calculation

# Alert burden benchmark (Moor et al., 2023): 1.4 false alerts per true alert
ALERT_BURDEN_BENCHMARK <- 1.4

# Expected external AUC degradation (Moor et al., 2023): ~0.085
EXPECTED_EXTERNAL_DEGRADATION <- 0.085

# --------------------------------------------------------------------------- #
# Equity subgroups (Wang, Li, Naidech, & Luo, 2022)
# --------------------------------------------------------------------------- #
EQUITY_VARS <- c("race", "ethnicity", "language", "insurance")

# --------------------------------------------------------------------------- #
# Sample size (Riley et al., 2019) — reference anticipated AUC
# --------------------------------------------------------------------------- #
ANTICIPATED_AUC <- 0.846  # Moor et al. (2023) internal AUC
P_CANDIDATE_PREDICTORS <- 25  # approximate number of candidate predictors
