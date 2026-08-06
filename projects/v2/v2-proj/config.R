# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
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

# --------------------------------------------------------------------------- #
# Alternative (non-Sepsis-3) label definitions — Protocol Amendment 2
#
# All three pre-registered variants above are Sepsis-3 interpretations sharing
# one culture-plus-antibiotic suspicion anchor, so their mutual disagreement is
# partly definitional rather than empirical. These two variants break the
# Sepsis-3 conjunction (suspected infection AND organ dysfunction) into its two
# limbs so the contribution of the treatment anchor can be measured:
#
#   E  anchor limb alone     — the suspicion-of-infection time itself, with the
#                              SOFA criterion removed. Depends only on clinician
#                              treatment behaviour, not on physiology.
#   D  dysfunction limb alone — first hour of acute organ dysfunction relative to
#                              the ICU-admission baseline, with no infection
#                              criterion and with treatment-derived SOFA
#                              components (vasopressors) excluded. Contains no
#                              treatment timestamp of any kind.
#
# Protocol Amendment 4 adds a third:
#
#   F  early-onset timing    — Variant B's membership exactly (the Sepsis-3
#                              conjunction is unchanged, so the same stays are
#                              septic), but the onset *time* is the standard
#                              min(t_susp, t_SOFA) of Seymour et al. (2016) and
#                              the PhysioNet/CinC 2019 Challenge (Reyna et al.,
#                              2020) instead of t_susp alone. It isolates the
#                              timing branch that variants A-C drop, and it is
#                              the only variant in the Sepsis-3 family whose
#                              onset can precede the treatment anchor.
#
# They are deliberately held OUTSIDE LABEL_VARIANTS: H1 and the variance
# decomposition are defined on the pre-registered A/B/C family and must not
# absorb post-hoc variants.
# --------------------------------------------------------------------------- #
ALT_LABEL_VARIANTS <- list(
  D = list(
    name          = "Deterioration",
    type          = "deterioration",
    # Onset is derived per hour in 03_person_hours.Rmd, where the hourly panel
    # exists; the physiology-only SOFA baseline is the stay's first
    # DETERIORATION_BASELINE_H + 1 hours, mirroring the "admission" baseline
    # used by variants A and B.
    sofa_baseline = "admission"
  ),
  E = list(
    name                 = "Anchor-Only",
    type                 = "anchor_only",
    # Identical suspicion windows to Variant B, so E is exactly B's anchor limb.
    abx_before_culture_h = 72,
    culture_before_abx_h = 24
  ),
  # Quoted so the name can never be confused with R's `F` (FALSE).
  "F" = list(
    name                 = "Sepsis-3 Early-Onset",
    type                 = "sepsis3_early",
    # Suspicion and SOFA windows identical to Variant B: membership is B's,
    # only the onset timestamp differs. Stage 02 builds the cohort exactly as
    # for B; stage 03 then moves each onset back to the first hour inside the
    # SOFA evaluation window at which the >= 2-point rise is already present.
    abx_before_culture_h = 72,
    culture_before_abx_h = 24,
    sofa_window_before_h = 48,
    sofa_window_after_h  = 24,
    sofa_baseline        = "admission"
  )
)

# Hours 0..DETERIORATION_BASELINE_H form the ICU-admission SOFA baseline window
# for every variant whose onset is derived on the hourly panel (D and F). Four
# hours of panel time is the same span stage 02 uses for its "admission"
# baseline (intime .. intime + 4 h), so the two agree by construction.
DETERIORATION_BASELINE_H <- 3

# Every variant the pipeline knows about, pre-registered first.
ALL_VARIANTS <- c(names(LABEL_VARIANTS), names(ALT_LABEL_VARIANTS))

#' Restrict the per-variant loops in stages 02-07 to a subset.
#'
#' Set V2_VARIANTS to a comma-separated list (e.g. V2_VARIANTS=D,E) to add or
#' refresh variants without refitting the others. This matters because the
#' XGBoost comparator is not bit-stable across runs, so an incidental refit of
#' A/B/C would silently move every GBT-dependent number in the thesis. Unset
#' (the default) runs all variants, so a clean end-to-end run is unaffected.
active_variants <- function(all_ids = ALL_VARIANTS) {
  sel <- Sys.getenv("V2_VARIANTS", "")
  if (!nzchar(sel)) return(all_ids)
  keep <- trimws(strsplit(sel, ",", fixed = TRUE)[[1]])
  unknown <- setdiff(keep, all_ids)
  if (length(unknown) > 0)
    stop("V2_VARIANTS names unknown variants: ", paste(unknown, collapse = ", "))
  intersect(all_ids, keep)
}

# --------------------------------------------------------------------------- #
# Action-derived features — Protocol Amendment 5 (post-hoc)
#
# The thesis argues that the Sepsis-3 label is constituted by clinician action.
# The same objection applies to part of the feature set. Two kinds of predictor
# are records of clinician behaviour rather than of physiology:
#
#   vasopressor exposure   — a treatment, not a measurement
#   *_measured indicators  — whether a test was ORDERED in that hour, which is
#                            a record of clinical attention; the value carries
#                            physiology, the indicator carries the decision to
#                            look
#
# These are held here so the ablation arm can drop exactly this set and no
# other. Note the boundary: the forward-filled lab VALUES are retained, even
# though a value exists only because someone ordered the test. Dropping them
# too would remove most of the laboratory signal and confound the ablation with
# a loss of physiological information, so the ablation is deliberately the
# narrower and more conservative one — it removes the features that encode
# *only* clinician behaviour.
# --------------------------------------------------------------------------- #
ACTION_DERIVED_FEATURES <- c(
  "vaso_any", "norepi_epi_any",
  "lactate_measured", "creatinine_measured", "bilirubin_total_measured",
  "platelets_measured", "wbc_measured", "pf_ratio_measured"
)

#' Restrict the fitting stages (05, 06) to one arm.
#'
#' "full" is the pre-registered specification; "ablated" drops
#' ACTION_DERIVED_FEATURES. Set V2_ARMS=ablated to add or refresh the ablation
#' WITHOUT refitting the main models — the same reasoning as V2_VARIANTS. This
#' matters because the main fits are what every headline number in the thesis
#' rests on, and the safest way to leave them untouched is not to re-execute
#' them at all.
active_arms <- function(all_arms = c("full", "ablated")) {
  sel <- Sys.getenv("V2_ARMS", "")
  if (!nzchar(sel)) return(all_arms)
  keep <- trimws(strsplit(sel, ",", fixed = TRUE)[[1]])
  unknown <- setdiff(keep, all_arms)
  if (length(unknown) > 0)
    stop("V2_ARMS names unknown arms: ", paste(unknown, collapse = ", "))
  intersect(all_arms, keep)
}

#' The feature vector for one arm, given the full declared set.
arm_features <- function(features, arm) {
  if (identical(arm, "ablated")) setdiff(features, ACTION_DERIVED_FEATURES) else features
}

#' Filename suffix for an arm ("" for the main arm, so existing paths are
#' unchanged and no downstream stage has to learn about arms it does not use).
arm_suffix <- function(arm) if (identical(arm, "ablated")) "_ablated" else ""

#' Look up a variant's definition in either family.
variant_def <- function(vid) {
  if (!is.null(LABEL_VARIANTS[[vid]])) LABEL_VARIANTS[[vid]] else ALT_LABEL_VARIANTS[[vid]]
}

#' A variant's display name.
variant_name <- function(vid) variant_def(vid)$name

#' A variant's label family: "sepsis3" for the pre-registered A/B/C, otherwise
#' the alternative-label type.
variant_type <- function(vid) {
  ty <- variant_def(vid)$type
  if (is.null(ty)) "sepsis3" else ty
}

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
# eICU-CRD drug capture (stage 08)
#
# eICU has no itemid vocabulary; drugs are free-text `drugname` strings spread
# across two tables that must BOTH be read:
#
#   medication.csv.gz   physician orders (oral and IV), `drugstartoffset`
#   infusionDrug.csv.gz continuous infusions,           `infusionoffset`
#
# Vasopressors and a large share of the intravenous antibiotics (vancomycin,
# piperacillin-tazobactam, cefepime) are recorded as infusions and appear in
# medication.csv.gz inconsistently or not at all, so reading only that table
# both under-counts the infection anchor and leaves the SOFA cardiovascular
# component permanently at its no-pressor value.
#
# Matching is by substring against these patterns (see `match_antibiotics()`),
# which is the same mechanism ANTIBIOTICS uses on MIMIC-IV `drug`.
# --------------------------------------------------------------------------- #
EICU_VASOPRESSORS <- c(
  "norepinephrine", "levophed", "epinephrine", "adrenaline",
  "dopamine", "dobutamine", "vasopressin", "pitressin",
  "phenylephrine", "neosynephrine", "neo-synephrine"
)

# The two agents that score 3 rather than 2 on the SOFA cardiovascular
# component. "norepinephrine" is a superstring of "epinephrine", so a match on
# either pattern lands in this set by construction, which is the intended
# behaviour: both are level-3 agents.
EICU_NOREPI_EPI <- c("norepinephrine", "levophed", "epinephrine", "adrenaline")

# --------------------------------------------------------------------------- #
# Physiological plausibility ranges
# --------------------------------------------------------------------------- #
# MIMIC-IV chartevents carries transcription errors of several orders of
# magnitude (observed maxima before this filter: heart rate 5,113,280;
# respiratory rate 7,000,400; SpO2 9,765,430; MAP 8,999,090 with 662 negative
# values; temperature 2,686 C). Left in place these are infinite-leverage rows
# that make the primary model's likelihood completely separated, so the
# unpenalised MLE diverges and the fitted coefficients are not identified.
# Values outside the range are set to NA *before* forward-fill, so an
# implausible reading is treated as a missing reading rather than a real one.
PLAUSIBLE_RANGES <- list(
  hr              = c(20,   300),
  resp_rate       = c(0,     80),
  spo2            = c(50,   100),
  map             = c(10,   250),
  sbp             = c(30,   300),
  dbp_invasive    = c(10,   200),
  dbp_noninvasive = c(10,   200),
  temp_c          = c(25,    45),
  fio2            = c(0.21,   1),
  gcs             = c(3,     15),
  lactate         = c(0,     40),
  creatinine      = c(0,     30),
  bilirubin_total = c(0,     70),
  platelets       = c(0,  2000),
  wbc             = c(0,   500),
  pao2            = c(20,  700),
  pf_ratio        = c(10,  1000),
  sodium          = c(80,   200),
  potassium       = c(1,     12)
)

#' Set implausible values to NA in place, and report how many were dropped.
#'
#' @param dt      data.table holding the columns
#' @param ranges  named list of c(lo, hi); only names present in `dt` are used
#' @param label   text used in the log line
apply_plausibility <- function(dt, ranges = PLAUSIBLE_RANGES, label = "panel") {
  hit <- 0L
  for (col in intersect(names(ranges), names(dt))) {
    lo <- ranges[[col]][1]; hi <- ranges[[col]][2]
    bad <- which(!is.na(dt[[col]]) & (dt[[col]] < lo | dt[[col]] > hi))
    if (length(bad)) {
      data.table::set(dt, i = bad, j = col, value = NA_real_)
      hit <- hit + length(bad)
      cat(sprintf("    %-16s %d values outside [%g, %g] -> NA\n",
                  col, length(bad), lo, hi))
    }
  }
  cat(sprintf("  Plausibility filter (%s): %d values set to NA\n", label, hit))
  invisible(dt)
}

# --------------------------------------------------------------------------- #
# Primary-model fitting (Protocol Amendment 3)
# --------------------------------------------------------------------------- #
# The unpenalised specification is completely separated: driven to a tight
# tolerance the MLE diverges (|beta| ~ 1e15 under every label variant), so the
# point at which nnet's BFGS stops is arbitrary and the fitted coefficients are
# not identified. Under Variant B it stopped in a degenerate region and returned
# a temporal-test AUROC of 0.607 against 0.746 for an identified fit.
#
# A small ridge penalty makes the penalised log-likelihood strictly concave, so
# the maximum is unique and the fit is reproducible. The value is deliberately
# small: across a 20-point ridge path the test AUROC moved by less than 0.02 for
# every variant, so no result depends on this constant.
PRIMARY_MODEL_DECAY <- 1e-4
PRIMARY_MODEL_MAXIT <- 1000

# --------------------------------------------------------------------------- #
# Prediction framing (pre-registered; Lauritsen et al., 2021)
# --------------------------------------------------------------------------- #
PREDICTION_HORIZON_H <- 6     # predict onset within next 6h (matches Reyna et al., 2020)
SLOPE_WINDOW_H       <- 6     # rolling slope window

# PhysioNet 2019 Utility Score parameters (Reyna et al., 2020)
UTILITY_TP_MIN  <- -6   # earliest true-positive offset (hours before onset)
UTILITY_TP_MAX  <-  3   # latest true-positive offset (hours after onset)
UTILITY_FN_LATE <- -6   # for late FN penalty calculation
UTILITY_FP      <- -0.05  # per false-alert hour
UTILITY_FN      <- -1.0   # per undetected sepsis stay

# The reported Utility Score is normalised against the two reference strategies
# of Reyna et al. (2020): the inaction strategy (never alert), which earns
# UTILITY_FN per sepsis stay, and the optimal strategy, which earns the maximum
# true-positive reward on every sepsis stay and raises no false alert. After
#   (U - U_inaction) / (U_optimal - U_inaction)
# a score of 1 is a perfect forecaster, 0 is exactly the no-alert strategy, and
# a negative score is worse than issuing no alerts at all.
UTILITY_TP_MAX_REWARD <- 1.0

# Threshold sweep. The default 0.5 cut-off is not an operating point any
# deployment would choose at an hourly event rate below 0.5 per cent, so the
# Utility Score is also reported at its maximum over a grid of thresholds. The
# grid is defined on the *alert rate* (fraction of person-hours alerted) rather
# than on the probability scale, so it adapts to each model's calibration and
# spans everything from one alert in 10^5 person-hours to alerting on half of
# them.
UTILITY_SWEEP_MIN_RATE <- 1e-5
UTILITY_SWEEP_MAX_RATE <- 0.5
UTILITY_SWEEP_N_GRID   <- 60

# Alert burden benchmark (Moor et al., 2023): 1.4 false alerts per true alert
ALERT_BURDEN_BENCHMARK <- 1.4

# Expected external AUC degradation (Moor et al., 2023): ~0.085
EXPECTED_EXTERNAL_DEGRADATION <- 0.085

# Minimum external event count below which an external AUROC is reported but
# not interpreted. Riley et al. (2021) and Collins et al. (2024, TRIPOD+AI)
# both put the floor for a stable external discrimination estimate at about 100
# events; below it the confidence interval is wider than any effect the study
# is trying to detect, and a point estimate invites over-reading. Stage 08
# flags every variant that falls under this floor and stage 12 carries the flag
# into the H5 verdict.
MIN_EXTERNAL_EVENTS <- 100L

# --------------------------------------------------------------------------- #
# Equity subgroups (Wang, Li, Naidech, & Luo, 2022)
# --------------------------------------------------------------------------- #
EQUITY_VARS <- c("race", "ethnicity", "language", "insurance")

# --------------------------------------------------------------------------- #
# Inference, uncertainty, and multiplicity control
# (Protocol Amendment 1, 2026-07-30 — see 00_preregistration.md §13.
#  Added after unblinding; the amendment itself is therefore not pre-specified.)
# --------------------------------------------------------------------------- #

# Stay-level (cluster) bootstrap: person-hours are nested within ICU stays, so
# the resampling unit is the stay, never the row.
BOOT_SEED        <- 42L
BOOT_B_MAIN      <- 2000L   # internal contrasts (MIMIC-IV temporal test set)
BOOT_B_SUBGROUP  <- 2000L   # subgroup / equity analyses
BOOT_B_EXTERNAL  <- 1000L   # eICU-CRD (7.9M person-hours; fewer replicates)
CI_LEVEL         <- 0.95

# Confirmatory family: the six pre-registered hypotheses. Family size is fixed
# at six even where a hypothesis yields no test statistic, so the correction is
# never made less strict by a hypothesis turning out to be untestable.
CONFIRMATORY_FAMILY_SIZE <- 6L
FWER_ALPHA               <- 0.05   # Holm-Bonferroni across the confirmatory family
FDR_Q                    <- 0.05   # Benjamini-Hochberg within each exploratory family

# Subgroup analyses are exploratory. Each subgroup is contrasted against the
# largest level of its own variable, which is chosen empirically and recorded.
MIN_SUBGROUP_ROWS   <- 50L   # minimum person-hours to ESTIMATE a subgroup AUROC
MIN_SUBGROUP_EVENTS <- 5L    # minimum onsets to ESTIMATE a subgroup AUROC
MAX_SUBGROUP_LEVELS <- 8L    # top-N levels per equity variable (matches 10_equity_analysis)

# Interpretability floor for subgroup discrimination. Distinct from the two
# constants above, which govern whether an estimate is *computed*; this one
# governs whether it is *interpreted*.
#
# Below this event count the confidence interval on a subgroup AUROC is wider
# than any disparity the study could act on, so the estimate is tabulated (so
# that the composition of the cohort stays visible) but is not interpreted, is
# excluded from every statement about spread, and -- importantly -- is excluded
# from exploratory family E1, so the BH correction is applied over the contrasts
# the study is willing to read rather than over every level that happens to
# exist.
#
# Set equal to MIN_EXTERNAL_EVENTS deliberately: same question (is this event
# count enough to interpret an AUROC?), same warrant (Riley et al. 2019;
# Collins et al. 2024), so the two floors must not drift apart.
MIN_SUBGROUP_EVENTS_INTERPRET <- MIN_EXTERNAL_EVENTS

# --------------------------------------------------------------------------- #
# Sample size (Riley et al., 2019) — reference anticipated AUC
# --------------------------------------------------------------------------- #
ANTICIPATED_AUC <- 0.846  # Moor et al. (2023) internal AUC
P_CANDIDATE_PREDICTORS <- 25  # approximate number of candidate predictors
