#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# ===========================================================================
#  thesis_constants.R - emit pipeline results as LaTeX macros
# ===========================================================================
#
#  Why this exists
#  ---------------
#  The thesis used to hardcode every number and keep its own copy of every
#  figure, with nothing reading pipeline output. That is the defect recorded in
#  HANDOFF section 4 ("GBT drift + thesis sync"): on 2026-07-30 a re-run moved
#  every GBT number and the thesis silently kept the old ones. This script
#  closes that loop. It reads the result tables and writes
#
#      ../thesis/pipeline_constants.tex
#
#  as a set of \pc-prefixed LaTeX macros, then syncs output/figures -> images/.
#  The thesis \inputs that file, so re-running the pipeline re-aligns the
#  document automatically.
#
#  This is deliberately NOT a numbered pipeline stage (the author has ruled new
#  stages out). It is a helper alongside config.R / utils.R / clinical_scores.R,
#  invoked at the tail of run_pipeline.{sh,R} and runnable on its own:
#
#      Rscript thesis_constants.R
#
#  Conventions
#  -----------
#  * Every macro is prefixed \pc, so a generated number is visually obvious in
#    the .tex source and can never collide with a thesis-defined command.
#  * Macro names are letters only - LaTeX forbids digits and underscores in
#    control sequences. Variants are A..E; models map primary/gbt/news2/cox/
#    qsofa/sirs -> Primary/Gbt/News/Cox/Qsofa/Sirs; H1..H6 -> HOne..HSix.
#  * Numeric values are wrapped in \ensuremath{} so a leading minus renders as a
#    real minus in both text and math mode.
#  * A quantity whose source row is missing is emitted as \pcMissing, which
#    typesets a bold red ?? - it fails visibly in the PDF instead of silently
#    carrying a stale number. Every miss is also listed on stderr at the end.
# ===========================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(arrow)
})

SCRIPT_DIR <- local({
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
})
DATA_DIR   <- file.path(SCRIPT_DIR, "output", "processed_data")
FIG_DIR    <- file.path(SCRIPT_DIR, "output", "figures")
THESIS_DIR <- normalizePath(file.path(SCRIPT_DIR, "..", "thesis"), mustWork = FALSE)
# The thesis keeps generated LaTeX in its own subdirectory, so that a glance at
# thesis/ separates what is written by hand (chapters/) from what is written by
# this script (generated/). Never edit anything under generated/.
GEN_DIR    <- file.path(THESIS_DIR, "generated")
OUT_TEX    <- file.path(GEN_DIR, "pipeline_constants.tex")
source(file.path(SCRIPT_DIR, "config.R"))


# --------------------------------------------------------------------------- #
# Collection machinery
# --------------------------------------------------------------------------- #
MACROS  <- new.env(parent = emptyenv())
ORDER   <- character(0)
MISSING <- character(0)   # source row absent -> loud red ?? in the PDF
NOTAPP  <- character(0)   # row present, value NA by design -> quiet ---

sec <- function(title) {
  ORDER  <<- c(ORDER, paste0("%%SECTION%%", title))
  invisible(NULL)
}

#' Register one macro.
#' @param name macro name without the \pc prefix (letters only)
#' @param value numeric, character, or NA/NULL for "missing"
#' @param digits decimal places (numeric values only)
#' @param big TRUE to insert LaTeX thousands separators
#' @param raw TRUE to emit the value verbatim, no \ensuremath (for text)
put <- function(name, value, digits = 4, big = FALSE, raw = FALSE) {
  if (!grepl("^[A-Za-z]+$", name))
    stop("macro name must be letters only: ", name)
  if (exists(name, envir = MACROS))
    stop("duplicate macro name: ", name)

  if (is.null(value) || length(value) == 0 ||
      (length(value) == 1 && is.na(value))) {
    # A value can be absent for two very different reasons, and the thesis must
    # treat them differently. If the producing row exists but the cell is NA,
    # the quantity is undefined by design (H2 carries no test statistic; H3 has
    # no p-value because the outcome is absent from the window) and should
    # typeset as an em dash. If the row - or the whole file - is missing, a
    # stage did not run and the number must fail visibly.
    structural <- isTRUE(attr(value, "row_found"))
    assign(name, if (structural) "\\pcNotApplicable" else NA_character_,
           envir = MACROS)
    if (structural) NOTAPP <<- c(NOTAPP, name) else MISSING <<- c(MISSING, name)
    ORDER <<- c(ORDER, name)
    return(invisible(NULL))
  }
  value <- value[1]

  txt <- if (raw || is.character(value) || is.logical(value)) {
    as.character(value)
  } else if (big) {
    sprintf("\\ensuremath{%s}",
            formatC(value, format = "d", big.mark = "{,}"))
  } else {
    # A value that rounds to zero carries no sign: "-0.000" reads as a typo.
    v <- as.numeric(value)
    if (abs(v) < 0.5 * 10^(-digits)) v <- 0
    sprintf("\\ensuremath{%s}", formatC(v, format = "f", digits = digits))
  }
  assign(name, txt, envir = MACROS)
  ORDER <<- c(ORDER, name)
  invisible(NULL)
}

# tolerant readers -----------------------------------------------------------
rd <- function(base) {
  pq <- file.path(DATA_DIR, paste0(base, ".parquet"))
  cs <- file.path(DATA_DIR, paste0(base, ".csv"))
  if (file.exists(pq)) return(as.data.table(arrow::read_parquet(pq)))
  if (file.exists(cs)) return(fread(cs))
  message("  [skip] no such result file: ", base)
  NULL
}

#' Pull a single cell: value of `col` in the unique row matching `...`.
#' Never errors. The result carries a `row_found` attribute so put() can tell
#' "the stage never ran" (no row) from "undefined by design" (row, NA cell).
cell <- function(dt, col, ...) {
  miss <- structure(NA, row_found = FALSE)
  if (is.null(dt) || !nrow(dt) || !(col %in% names(dt))) return(miss)
  cond <- list(...)
  keep <- rep(TRUE, nrow(dt))
  for (k in names(cond)) {
    if (!(k %in% names(dt))) return(miss)
    keep <- keep & (as.character(dt[[k]]) == as.character(cond[[k]]))
  }
  if (!any(keep)) return(miss)
  v <- dt[[col]][keep][1]
  if (length(v) == 1 && is.na(v)) return(structure(NA, row_found = TRUE))
  v
}

MODEL_TOK <- c(primary = "Primary", gbt = "Gbt", news2 = "News",
               cox = "Cox", qsofa = "Qsofa", sirs = "Sirs")
PREREG    <- c("A", "B", "C")
ALT       <- c("D", "E", "F")   # F added by Protocol Amendment 4
HTOK      <- c(H1 = "HOne", H2 = "HTwo", H3 = "HThree",
               H4 = "HFour", H5 = "HFive", H6 = "HSix")

cat("Reading results from", DATA_DIR, "\n")

# --------------------------------------------------------------------------- #
# Provenance
# --------------------------------------------------------------------------- #
sec("Provenance")
put("GeneratedAt", format(Sys.time(), "%Y-%m-%d %H:%M"), raw = TRUE)
mt <- suppressWarnings(file.info(file.path(DATA_DIR, "07_metric_results.parquet"))$mtime)
put("PipelineRunDate",
    if (is.na(mt)) NA else format(mt, "%Y-%m-%d %H:%M"), raw = TRUE)

# --------------------------------------------------------------------------- #
# Cohort and labels
# --------------------------------------------------------------------------- #
sec("Cohort and label variants")
lv <- rd("02_label_variance_table")
put("NStays", cell(lv, "n_stays", variant = "B"), big = TRUE)
for (v in PREREG) {
  put(paste0("NOnsets", v),     cell(lv, "n_sepsis_onsets", variant = v), big = TRUE)
  put(paste0("PctOnsets", v),   cell(lv, "pct_sepsis",      variant = v), digits = 1)
  put(paste0("MedianOnsetH", v),cell(lv, "median_onset_h",  variant = v), digits = 0)
  put(paste0("NDeathsNoSep", v),cell(lv, "n_deaths_no_sep", variant = v), big = TRUE)
  put(paste0("IqrOnsetLoH", v), cell(lv, "iqr_onset_h_lo",  variant = v), digits = 0)
  put(paste0("IqrOnsetHiH", v), cell(lv, "iqr_onset_h_hi",  variant = v), digits = 0)
}

# CONSORT flow (stage 02). These five counts were hardcoded in the figure in
# methodology.tex, with a caption conceding they came from the extraction log.
# They are now a result table like everything else.
local({
  cf <- rd("02_cohort_flow")
  put("ConsortNTotal",       cell(cf, "n", step = "icu_stays_total"),  big = TRUE)
  put("ConsortNAdult",       cell(cf, "n", step = "adult"),            big = TRUE)
  put("ConsortNExclAge",     cell(cf, "n_excluded", step = "adult"),   big = TRUE)
  put("ConsortNFirstStay",   cell(cf, "n", step = "first_icu_stay"),   big = TRUE)
  put("ConsortNExclNotFirst",cell(cf, "n_excluded", step = "first_icu_stay"), big = TRUE)
  put("ConsortNFinal",       cell(cf, "n", step = "min_los"),          big = TRUE)
  put("ConsortNExclLos",     cell(cf, "n_excluded", step = "min_los"), big = TRUE)
  put("ConsortNPatients",    cell(cf, "n_patients", step = "min_los"), big = TRUE)
})

ss <- rd("04_sample_size")
for (v in PREREG) {
  # Independent unit = the stay. This is the adequacy verdict the thesis reports.
  put(paste0("MinNRileyStay", v),  cell(ss, "min_n_riley_stay",  variant = v), big = TRUE)
  put(paste0("StayPrevalence", v), cell(ss, "stay_prevalence",   variant = v), digits = 4)
  put(paste0("RileyMargin", v),    cell(ss, "margin_stay",       variant = v), digits = 2)
  put(paste0("NOnsetEvents", v),   cell(ss, "n_onset_events",    variant = v), big = TRUE)
  put(paste0("Epv", v),            cell(ss, "epv",               variant = v), digits = 1)
  # Design-matrix size, reported alongside. NOT a sample size -- see the note in
  # 04_sample_size.Rmd. MinNRileyPerHour exists so the two parameterisations can
  # be shown together and never silently substituted for one another.
  put(paste0("NTrainPersonH", v),  cell(ss, "n_train_person_h",  variant = v), big = TRUE)
  put(paste0("PerHourRate", v),    cell(ss, "per_hour_event_rate", variant = v), digits = 5)
  put(paste0("MinNRileyPerHour", v), cell(ss, "min_n_riley_perhour", variant = v), big = TRUE)
}
# The training split is the same set of stays under every variant; only the
# label differs. Emitted once so the thesis cannot imply otherwise.
put("NTrainStays", cell(ss, "n_train_stays", variant = "B"), big = TRUE)
put("AnticipatedAuc", cell(ss, "anticipated_auc", variant = "B"), digits = 3)
put("NCandidatePredictors", cell(ss, "n_candidate_preds", variant = "B"), digits = 0)

# label agreement (kappa vs B) - the number reviewers keep assuming
sec("Label agreement (kappa vs Variant B)")
la <- rd("09_label_agreement")
for (v in c("A", "C", "D", "E", "F")) {
  put(paste0("KappaVsB", v),   cell(la, "kappa_vs_B",       variant = v), digits = 3)
  put(paste0("PctAgreeB", v),  cell(la, "pct_agree",        variant = v), digits = 1)
  put(paste0("NPositive", v),  cell(la, "n_positive",       variant = v), big = TRUE)
  put(paste0("PctOnsets", v, "Panel"),
      { np <- cell(la, "n_positive", variant = v); ns <- cell(la, "n_stays", variant = v)
        if (is.na(np) || is.na(ns)) np else 100 * as.numeric(np) / as.numeric(ns) },
      digits = 1)
  put(paste0("SensToB", v),    cell(la, "sensitivity_to_B", variant = v), digits = 3)
  put(paste0("MedianShiftH", v),    cell(la, "median_shift_h",     variant = v), digits = 1)
  put(paste0("PctExactMatch", v),   cell(la, "pct_exact_match",    variant = v), digits = 1)
  put(paste0("MedianAbsShiftH", v), cell(la, "median_abs_shift_h", variant = v), digits = 1)
  put(paste0("IqrShiftLoH", v),     cell(la, "iqr_shift_lo_h",     variant = v), digits = 0)
  put(paste0("IqrShiftHiH", v),     cell(la, "iqr_shift_hi_h",     variant = v), digits = 0)
}
put("NPositiveBPanel", cell(la, "n_positive_B", variant = "A"), big = TRUE)
# Stays E labels that B does not: the "discards two thirds" figure, which was a
# hand-computed literal in the results chapter.
put("NPositiveEExcessOverB",
    { ne <- cell(la, "n_positive", variant = "E"); nb <- cell(la, "n_positive_B", variant = "E")
      if (is.na(ne) || is.na(nb)) ne else as.numeric(ne) - as.numeric(nb) },
    big = TRUE)
put("PctOnsetsBPanel",
    { np <- cell(la, "n_positive_B", variant = "A"); ns <- cell(la, "n_stays", variant = "A")
      if (is.na(np) || is.na(ns)) np else 100 * as.numeric(np) / as.numeric(ns) },
    digits = 1)

# Per-model metrics under the alternative labels, for the limb-comparison table
sec("Alternative-label per-model metrics (unrestricted window)")
altm <- rd("07_metric_results_altlabel")
if (!is.null(altm)) altm <- altm[eval_window == "unrestricted"]
for (v in ALT) {
  put(paste0("AltNEvents", v), cell(altm, "n_sepsis_events", variant = v, model = "primary"), big = TRUE)
  for (m in names(MODEL_TOK)) {
    tok <- paste0(MODEL_TOK[[m]], v)
    put(paste0("AltAurocFull", tok), cell(altm, "auroc", variant = v, model = m))
    put(paste0("AltAuprcFull", tok), cell(altm, "auprc", variant = v, model = m))
  }
}
put("NPositiveB", cell(la, "n_positive_B", variant = "A"), big = TRUE)

# --------------------------------------------------------------------------- #
# Internal temporal-test metrics
# --------------------------------------------------------------------------- #
sec("Internal temporal-test metrics (unrestricted window)")
mr <- rd("07_metric_results")
if (!is.null(mr)) mr <- mr[eval_window == "unrestricted"]
mr_alt <- rd("07_metric_results_altlabel")
if (!is.null(mr_alt)) mr_alt <- mr_alt[eval_window == "unrestricted"]
for (v in PREREG) for (m in names(MODEL_TOK)) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("Auroc", tok),       cell(mr, "auroc",              variant = v, model = m))
  put(paste0("Auprc", tok),       cell(mr, "auprc",              variant = v, model = m))
  put(paste0("Utility", tok),     cell(mr, "utility_normalised", variant = v, model = m), digits = 3)
  ab <- cell(mr, "alert_burden", variant = v, model = m)
  put(paste0("AlertBurden", tok),
      if (is.na(ab)) ab else if (is.infinite(ab)) "\\ensuremath{\\infty}" else ab,
      digits = 1, raw = !is.na(ab) && is.infinite(ab))
}
put("NTestRowsB",   cell(mr, "n_rows",          variant = "B", model = "primary"), big = TRUE)
put("NTestEventsB", cell(mr, "n_sepsis_events", variant = "B", model = "primary"), big = TRUE)
# Per-variant test-set size and event count. Needed wherever the development
# cohort's event rate is stated alongside the external one, which cannot be
# done from Variant B alone once the external label sets differ by variant.
for (v in setdiff(PREREG, "B")) {
  put(paste0("NTestRows", v),   cell(mr, "n_rows",          variant = v, model = "primary"), big = TRUE)
  put(paste0("NTestEvents", v), cell(mr, "n_sepsis_events", variant = v, model = "primary"), big = TRUE)
}

# Utility at the best operating point, not at the arbitrary 0.5 cut-off.
sec("Utility Score at the best threshold (unrestricted window)")
for (v in c(PREREG, ALT)) for (m in names(MODEL_TOK)) {
  src <- if (v %in% PREREG) mr else mr_alt
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("UtilityMax", tok), cell(src, "utility_max", variant = v, model = m),
      digits = 3)
  put(paste0("UtilityOptThreshold", tok),
      cell(src, "utility_opt_threshold", variant = v, model = m), digits = 4)
  ar <- cell(src, "utility_opt_alert_rate", variant = v, model = m)
  put(paste0("UtilityOptAlertPct", tok),
      if (is.na(ar)) ar else 100 * as.numeric(ar), digits = 3)
  ob <- cell(src, "utility_opt_burden", variant = v, model = m)
  put(paste0("UtilityOptBurden", tok),
      if (is.na(ob)) ob else if (is.infinite(ob)) "\\ensuremath{\\infty}" else ob,
      digits = 1, raw = !is.na(ob) && is.infinite(ob))
  dr <- cell(src, "utility_opt_detection", variant = v, model = m)
  put(paste0("UtilityOptDetectPct", tok),
      if (is.na(dr)) dr else 100 * as.numeric(dr), digits = 1)
}

# pre-treatment (treatment-anchored) window -> H3
sec("Treatment-anchored window (H3)")
mr_ta <- rd("07_metric_results")
if (!is.null(mr_ta)) mr_ta <- mr_ta[eval_window == "treatment_anchored"]
put("PreTreatPersonHours", cell(mr_ta, "n_rows",          variant = "B", model = "primary"), big = TRUE)
put("PreTreatOnsets",      cell(mr_ta, "n_sepsis_events", variant = "B", model = "primary"), big = TRUE)

# random split -> H4
sec("Random-split arm (H4)")
rr <- rd("07_metric_results_random")
if (!is.null(rr)) rr <- rr[eval_window == "unrestricted"]
# The random-split arm re-fits only the four estimators that are actually
# fitted (primary, GBT, Cox, NEWS2). qSOFA and SIRS are fixed formulas with no
# training step, so a random-split re-fit of them does not exist by design and
# must render as an em dash rather than a red ??.
for (m in names(MODEL_TOK)) {
  v <- cell(rr, "auroc", variant = "B", model = m)
  if (is.na(v) && m %in% c("qsofa", "sirs")) v <- structure(NA, row_found = TRUE)
  put(paste0("AurocRandom", MODEL_TOK[[m]], "B"), v)
}

# --------------------------------------------------------------------------- #
# Calibration and clinical utility
# --------------------------------------------------------------------------- #
sec("Calibration (stage 11, 1e-6 probability floor)")
cal <- rd("11_calibration_summary")
for (v in PREREG) for (m in c("primary", "gbt", "cox")) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("CalibInt",    tok), cell(cal, "calib_int",    variant = v, model = m), digits = 3)
  put(paste0("CalibSlope",  tok), cell(cal, "calib_slope",  variant = v, model = m), digits = 3)
  put(paste0("Ici",         tok), cell(cal, "ici",          variant = v, model = m), digits = 4)
  put(paste0("Emax",        tok), cell(cal, "emax",         variant = v, model = m), digits = 3)
  put(paste0("BrierScaled", tok), cell(cal, "brier_scaled", variant = v, model = m), digits = 4)
}
put("PrevalenceB", cell(cal, "prevalence", variant = "B", model = "primary"), digits = 5)

# How many distinct probabilities each rule-based score can emit. This is the
# stated reason the three are excluded from the calibration table, and it was
# carried as "18, 4 and 4" -- NEWS2 is 21, and SIRS is 5, not 4. SIRS read 4
# only while the `hr` naming defect capped sirs_score at three of its four
# criteria, so the sentence was a survivor of the Amendment 3 repair. Counted
# from the predictions rather than asserted.
local({
  pc <- rd("06_predictions_comparators_B")
  for (m in c("news2", "qsofa", "sirs")) {
    col <- paste0("pred_", m)
    put(paste0("NDistinct", MODEL_TOK[[if (m == "news2") "news2" else m]]),
        if (is.null(pc) || !(col %in% names(pc))) NA else length(unique(pc[[col]])),
        digits = 0)
  }
})

# The clamped counterparts, from the metric suite's [0.001, 0.999] guard. The
# thesis contrasts these against the 1e-6-floor estimates above to show what the
# conventional clamp costs, and the Variant A figure was carried in the prose as
# a literal 1.169 -- a pre-Amendment-3 value that no longer matches anything the
# pipeline produces. Sourced here so the contrast cannot go stale again.
local({
  mr7 <- rd("07_metric_results")
  if (!is.null(mr7) && "eval_window" %in% names(mr7))
    mr7 <- mr7[eval_window == "unrestricted"]
  for (v in PREREG) {
    put(paste0("CalibSlopeClampedPrimary", v),
        cell(mr7, "calib_slope", variant = v, model = "primary"), digits = 3)
    put(paste0("CalibIntClampedPrimary", v),
        cell(mr7, "calib_intercept", variant = v, model = "primary"), digits = 3)
  }
})

# What the conventional [0.001, 0.999] clamp would overwrite, and the largest
# prediction the model ever emits. Both were literals in the results chapter --
# correct at the time of writing, but exactly the class of number that a refit
# moves and no mechanism catches. Computed from the stored test predictions.
local({
  for (v in PREREG) {
    f <- file.path(DATA_DIR, sprintf("05_predictions_primary_%s.parquet", v))
    r <- if (file.exists(f)) tryCatch({
      d <- as.data.table(arrow::read_parquet(f, col_select = "pred_sepsis"))
      p <- d$pred_sepsis[!is.na(d$pred_sepsis)]
      if (length(p) == 0) NULL else
        list(pct = 100 * mean(p < CALIB_CLAMP_CONVENTIONAL), mx = max(p))
    }, error = function(e) NULL) else NULL
    put(paste0("PctBelowClampPrimary", v), if (is.null(r)) NA else r$pct, digits = 1)
    put(paste0("MaxPredPrimary", v),       if (is.null(r)) NA else r$mx,  digits = 4)
  }
})

# Bounds the prose states as "within X of zero / of one". Computed rather than
# asserted: the intercept bound was written as 0.09 while Variant B's intercept
# is -0.106, so the sentence was false for the primary label.
local({
  ci <- vapply(PREREG, function(v) {
    x <- cell(cal, "calib_int", variant = v, model = "primary")
    if (is.na(x)) NA_real_ else abs(as.numeric(x))
  }, numeric(1))
  cs <- vapply(PREREG, function(v) {
    x <- cell(cal, "calib_slope", variant = v, model = "primary")
    if (is.na(x)) NA_real_ else abs(as.numeric(x) - 1)
  }, numeric(1))
  put("CalibIntMaxAbsPrimary",   if (all(is.na(ci))) NA else max(ci, na.rm = TRUE), digits = 2)
  put("CalibSlopeMaxDevPrimary", if (all(is.na(cs))) NA else max(cs, na.rm = TRUE), digits = 2)
})

sec("Operating points at 80 percent sensitivity")
op <- rd("11_operating_points")
if (!is.null(op) && "target_sens" %in% names(op)) op <- op[abs(target_sens - 0.8) < 1e-9]
for (v in PREREG) for (m in names(MODEL_TOK)) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("Ppv",        tok), cell(op, "ppv",                variant = v, model = m), digits = 4)
  put(paste0("Nne",        tok), cell(op, "nne",                variant = v, model = m), digits = 0)
  put(paste0("FaPerPtDay", tok), cell(op, "fa_per_patient_day", variant = v, model = m), digits = 2)
  put(paste0("Spec",       tok), cell(op, "specificity",        variant = v, model = m), digits = 3)
  put(paste0("AlertsPerPtDay", tok),
      cell(op, "alerts_per_pt_day", variant = v, model = m), digits = 2)
  put(paste0("FpTpRatio",  tok), cell(op, "alert_burden_ratio", variant = v, model = m), digits = 0)
}

sec("Per-patient (event-level) detection at 80 percent per-hour sensitivity")
pl <- rd("11_patient_level_metrics")
if (!is.null(pl) && "target_sens" %in% names(pl)) pl <- pl[abs(target_sens - 0.8) < 1e-9]
put("NTestStays", cell(pl, "n_stays", variant = "B", model = "primary"), big = TRUE)
for (v in PREREG) {
  put(paste0("NSepsisStays", v),
      cell(pl, "n_sepsis_stays", variant = v, model = "primary"), big = TRUE)
  for (m in names(MODEL_TOK)) {
    tok <- paste0(MODEL_TOK[[m]], v)
    put(paste0("Sens", tok),         cell(op, "sensitivity",       variant = v, model = m), digits = 3)
    put(paste0("EpSensWindow", tok), cell(pl, "episode_sens_window", variant = v, model = m), digits = 3)
    put(paste0("EpSensPre", tok),    cell(pl, "episode_sens_pre",    variant = v, model = m), digits = 3)
    put(paste0("PatientPpv", tok),   cell(pl, "patient_ppv",         variant = v, model = m), digits = 3)
    put(paste0("PctStaysAlerted", tok),
        { x <- cell(pl, "frac_stays_alerted", variant = v, model = m)
          if (is.na(x)) x else 100 * as.numeric(x) }, digits = 1)
    put(paste0("FaEpPerPtDay", tok), cell(pl, "fa_episodes_per_pt_day", variant = v, model = m), digits = 2)
  }
}

sec("External operating characteristics (eICU-CRD)")
eop <- rd("11_external_operating_points")
if (!is.null(eop) && "target_sens" %in% names(eop)) eop <- eop[abs(target_sens - 0.8) < 1e-9]
epl <- rd("11_external_patient_level")
if (!is.null(epl) && "target_sens" %in% names(epl)) epl <- epl[abs(target_sens - 0.8) < 1e-9]
put("ExtNStays",       cell(epl, "n_stays",        variant = "B", model = "primary"), big = TRUE)
put("ExtNSepsisStays", cell(epl, "n_sepsis_stays", variant = "B", model = "primary"), big = TRUE)
for (v in PREREG) for (m in c("primary", "news2")) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("ExtSpec",       tok), cell(eop, "specificity",        variant = v, model = m), digits = 3)
  put(paste0("ExtPpv",        tok),
      { x <- cell(eop, "ppv", variant = v, model = m)
        if (is.na(x)) x else sprintf("\\ensuremath{%.2f\\times 10^{-5}}", 1e5 * as.numeric(x)) },
      raw = TRUE)
  put(paste0("ExtNne",        tok), cell(eop, "nne",                variant = v, model = m), big = TRUE)
  put(paste0("ExtFaPerPtDay", tok), cell(eop, "fa_per_patient_day", variant = v, model = m), digits = 2)
  put(paste0("ExtPatientPpv", tok), cell(epl, "patient_ppv",        variant = v, model = m), digits = 5)
}

sec("Lead time")
lt <- rd("11_lead_time_summary")
for (v in PREREG) for (m in names(MODEL_TOK)) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("LeadMedian", tok), cell(lt, "lead_median_h",   variant = v, model = m), digits = 1)
  put(paste0("LeadQXXV",   tok), cell(lt, "lead_q25_h",      variant = v, model = m), digits = 0)
  put(paste0("LeadQLXXV",  tok), cell(lt, "lead_q75_h",      variant = v, model = m), digits = 0)
  put(paste0("FracLeadGeThree", tok), cell(lt, "frac_lead_ge_3h", variant = v, model = m), digits = 3)
  put(paste0("FracLeadGeSix",   tok), cell(lt, "frac_lead_ge_6h", variant = v, model = m), digits = 3)
}

# --------------------------------------------------------------------------- #
# External validation
# --------------------------------------------------------------------------- #
sec("Net benefit at prevalence (stage 11)")
nb <- rd("11_net_benefit_at_prevalence")
for (v in PREREG) for (m in names(MODEL_TOK)) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("NetBenefit", tok),
      { x <- cell(nb, "net_benefit", variant = v, model = m)
        if (is.na(x)) x else if (as.numeric(x) == 0) "\\ensuremath{0}"
        else sprintf("\\ensuremath{%s\\times 10^{%d}}",
                     formatC(as.numeric(x) / 10^floor(log10(abs(as.numeric(x)))),
                             format = "f", digits = 2),
                     floor(log10(abs(as.numeric(x))))) },
      raw = TRUE)
  put(paste0("Snb",        tok), cell(nb, "snb",              variant = v, model = m), digits = 3)
  # The prose reads the standardised net benefit as a percentage of the
  # attainable benefit. Emitted here so the sentence cannot drift from the
  # table: the two used to disagree on all three variants.
  put(paste0("SnbPct",     tok),
      { x <- cell(nb, "snb", variant = v, model = m)
        if (is.na(x)) x else 100 * as.numeric(x) }, digits = 1)
  put(paste0("AlertRate",  tok), cell(nb, "alert_rate",       variant = v, model = m), digits = 3)
  put(paste0("AlertRange", tok), cell(nb, "alert_rate_range", variant = v, model = m), digits = 3)
}

sec("External validation (eICU-CRD)")
# Primary arm: Sepsis-3 conjunction on the microbiology-covered sub-cohort.
# Every quantity here is per-variant, because the external label sets are
# per-variant. Emitting a single row and reusing it across A/B/C would restate
# the defect the variant-invariance guard in stage 08 exists to catch.
ex <- rd("08_external_validation_results")
for (v in PREREG) {
  put(paste0("ExtAurocPrimary", v), cell(ex, "auroc", variant = v, model = "pred_sepsis"))
  put(paste0("ExtAurocNews", v),    cell(ex, "auroc", variant = v, model = "pred_news2"))
  put(paste0("ExtAurocGbt", v),     cell(ex, "auroc", variant = v, model = "pred_gbt"))
  put(paste0("ExtNRows", v),   cell(ex, "n_rows",   variant = v, model = "pred_sepsis"), big = TRUE)
  put(paste0("ExtNEvents", v), cell(ex, "n_events", variant = v, model = "pred_sepsis"), big = TRUE)
}
put("ExtNRows",   cell(ex, "n_rows",   variant = "B", model = "pred_sepsis"), big = TRUE)
put("ExtNEvents", cell(ex, "n_events", variant = "B", model = "pred_sepsis"), big = TRUE)

# Labelling-input coverage: the quantity that bounds how much of eICU-CRD the
# Sepsis-3 anchor can reach at all.
cv <- rd("08_eicu_coverage")
put("ExtNCohortStays",   cell(cv, "n_cohort_stays"),        big = TRUE)
put("ExtNMicroStays",    cell(cv, "n_micro_covered_stays"), big = TRUE)
put("ExtMicroCoverage",  cell(cv, "pct_micro_covered"),     digits = 2)
put("ExtNAbxStays",      cell(cv, "n_abx_stays"),           big = TRUE)
put("ExtAbxCoverage",    cell(cv, "pct_abx_covered"),       digits = 2)
put("ExtNBothLimbStays", cell(cv, "n_both_limbs_stays"),    big = TRUE)
put("ExtBothLimbCoverage", cell(cv, "pct_both_limbs"),      digits = 3)
put("ExtPanelHoursFull", cell(cv, "panel_person_hours_full"),  big = TRUE)
put("ExtPanelHoursMicro",cell(cv, "panel_person_hours_micro"), big = TRUE)
put("ExtMinEvents",      cell(cv, "min_external_events"),   digits = 0)

# The two limbs narrow the cohort in stages, and the stages are reported
# separately so that no single percentage stands in for the whole constraint:
# stays whose suspicion pair fires inside the variant's window, and stays that
# additionally meet the organ-dysfunction criterion.
ls_ <- rd("08_eicu_label_summary")
for (v in PREREG) {
  put(paste0("ExtNSuspicion", v),
      cell(ls_, "n_suspicion", variant = v, anchor = "sepsis3"), big = TRUE)
  put(paste0("ExtNOnsetStays", v),
      cell(ls_, "n_onsets",    variant = v, anchor = "sepsis3"), big = TRUE)
}

# Event-rate reconciliation against the development cohort.
rc <- rd("08_event_rate_reconciliation")
for (v in PREREG) {
  put(paste0("ExtRateMimic", v),
      cell(rc, "events_per_1k_person_h", variant = v, source = "MIMIC-IV temporal test"),
      digits = 3)
  put(paste0("ExtRateEicu", v),
      cell(rc, "events_per_1k_person_h", variant = v, source = "eICU Sepsis-3 (micro-covered)"),
      digits = 3)
  put(paste0("ExtRateRatio", v),
      cell(rc, "rate_ratio_vs_mimic", variant = v, source = "eICU Sepsis-3 (micro-covered)"),
      digits = 3)
  put(paste0("ExtRateEicuAbx", v),
      cell(rc, "events_per_1k_person_h", variant = v, source = "eICU antibiotic-only (full)"),
      digits = 3)
  put(paste0("ExtRateRatioAbx", v),
      cell(rc, "rate_ratio_vs_mimic", variant = v, source = "eICU antibiotic-only (full)"),
      digits = 3)
}

# Sensitivity arm: antibiotic-only anchor on the full cohort. The target is not
# Sepsis-3, so these never substitute for the primary arm.
ab <- rd("08_external_validation_results_abxonly")
for (v in PREREG) {
  put(paste0("ExtAbxAurocPrimary", v), cell(ab, "auroc",    variant = v, model = "pred_sepsis"))
  put(paste0("ExtAbxNEvents", v),      cell(ab, "n_events", variant = v, model = "pred_sepsis"), big = TRUE)
  # The at-risk panel is truncated at each variant's own onset, so the
  # person-hour denominator is NOT shared across A/B/C: it runs 7,656,521 /
  # 7,627,689 / 7,450,975. A single ExtAbxNRows macro used to be emitted from
  # Variant B and printed in all three rows of tab:external_rates, which made
  # the A and C rows arithmetically inconsistent with their own printed rates.
  # Emit it per variant; never re-collapse it.
  put(paste0("ExtAbxNRows", v),        cell(ab, "n_rows",   variant = v, model = "pred_sepsis"), big = TRUE)
}
# DEPRECATED, retained only so the document still compiles until
# tab:external_rates is switched to the per-variant macros above. It is
# Variant B's denominator and is correct for Variant B alone. Delete this line
# once no chapter references \pcExtAbxNRows.
put("ExtAbxNRows", cell(ab, "n_rows", variant = "B", model = "pred_sepsis"), big = TRUE)

# --------------------------------------------------------------------------- #
# Variance decomposition
# --------------------------------------------------------------------------- #
sec("Variance decomposition")
vd <- rd("09_variance_decomposition_table")

# Stage 09 differences AUROCs it has already rounded to four places, so its
# split row read -0.0166 against the bootstrap estimate of -0.0165 that
# tab:confirmatory prints for the same contrast, with the same interval. Same
# quantity, two values, three pages apart. The rows that correspond to a
# confirmatory contrast are therefore taken from 12_confirmatory_tests -- the
# estimator the interval actually belongs to -- and stage 09 supplies only the
# rows that have no hypothesis-level counterpart.
#
# Row by row: ModelClass and Label are spreads, and 12_spread_ci already
# supplies the intervals printed beside them, so the estimate is taken from the
# same object. Split and Metric ARE the H4 and H5 contrasts. Anchoring is
# undefined by design (H3 has no test statistic) and stays with stage 09.
# ModelNull is |primary - GBT|; no chapter prints it, but it carried 0.0130
# against H6's -0.0129, so it is aligned rather than left as a second value.
ct_dec <- rd("12_confirmatory_tests")
sp_dec <- rd("12_spread_ci")
put("SpreadModelClass", cell(sp_dec, "estimate", quantity = "model"))
put("SpreadLabel",      cell(sp_dec, "estimate", quantity = "label"))
put("SpreadAnchoring",  cell(vd,     "spread_auroc", hypothesis = "H3"))
put("SpreadSplit",      cell(ct_dec, "estimate", hypothesis = "H4"))
put("SpreadMetric",     cell(ct_dec, "estimate", hypothesis = "H5"))
put("SpreadModelNull",  cell(ct_dec, "estimate", hypothesis = "H6"))

# --------------------------------------------------------------------------- #
# Confirmatory hypotheses
# --------------------------------------------------------------------------- #
sec("Confirmatory hypotheses (Holm, m=6)")
ct <- rd("12_confirmatory_tests")
for (h in names(HTOK)) {
  tk <- HTOK[[h]]
  # H2 and H3 report counts, not AUROC differences; four decimals on a count
  # reads as a precision claim that is not being made.
  put(paste0(tk, "Est"), cell(ct, "estimate", hypothesis = h),
      digits = if (h %in% c("H2", "H3")) 0 else 4)
  put(paste0(tk, "CiLo"),    cell(ct, "ci_lo",    hypothesis = h))
  put(paste0(tk, "CiHi"),    cell(ct, "ci_hi",    hypothesis = h))
  ph <- cell(ct, "p_holm", hypothesis = h)
  put(paste0(tk, "PHolm"),
      if (is.na(ph)) ph else if (as.numeric(ph) < 0.001) "\\ensuremath{<0.001}"
      else as.numeric(ph),
      digits = 3, raw = !is.na(ph) && as.numeric(ph) < 0.001)
  put(paste0(tk, "Verdict"), cell(ct, "verdict", hypothesis = h), raw = TRUE)
}

sec("H2 coefficient stability counts")
h2 <- rd("12_h2_coefficient_stability")
local({
  tf <- function(x) x %in% c(TRUE, "TRUE")
  put("HTwoNTerms", if (is.null(h2)) NA else nrow(h2),                  digits = 0)
  put("HTwoNSign",  if (is.null(h2)) NA else sum(tf(h2$sign_flip)),     digits = 0)
  put("HTwoNMag",   if (is.null(h2)) NA else sum(tf(h2$mag_flip)),      digits = 0)
})

# Instability split by feature kind: the quantity behind the claim that it is
# the action-derived covariates that are unstable, not physiology in general.
sec("H2 instability by feature kind (Amendment 5)")
hk <- rd("12_h2_stability_by_kind")
for (k in c("action-derived", "physiological")) {
  tok <- if (k == "action-derived") "Action" else "Physio"
  put(paste0("HTwoN",        tok), cell(hk, "n_terms",      kind = k), digits = 0)
  put(paste0("HTwoNUnstable", tok), cell(hk, "n_unstable",  kind = k), digits = 0)
  put(paste0("HTwoPctUnstable", tok), cell(hk, "pct_unstable", kind = k), digits = 1)
}

# Amendment 7: does a flagged coefficient move by more than it is estimated to
# within? Reported beside the pre-registered count, never in place of it. The
# table is generated whole because the flagged set is not a fixed row count --
# a one-macro-per-cell grid would leave unresolved cells or silently drop a
# covariate if the count moved.
sec("H2 instability uncertainty diagnostic (Amendment 7)")
hu <- rd("12_h2_stability_uncertainty")
local({
  tf <- function(x) x %in% c(TRUE, "TRUE")
  n_flag   <- if (is.null(hu)) NA else nrow(hu)
  ex       <- if (is.null(hu)) logical(0) else tf(hu$exceeds_noise)
  act      <- if (is.null(hu)) logical(0) else tf(hu$is_action)
  put("HTwoNFlagged",     n_flag,                                    digits = 0)
  put("HTwoNRobust",      if (is.null(hu)) NA else sum(ex),          digits = 0)
  put("HTwoNNoise",       if (is.null(hu)) NA else sum(!ex),         digits = 0)
  put("HTwoNRobustAction", if (is.null(hu)) NA else sum(ex & act),   digits = 0)
  put("HTwoZMin",  if (is.null(hu)) NA else min(as.numeric(hu$z_ratio), na.rm = TRUE), digits = 2)
  put("HTwoZMax",  if (is.null(hu)) NA else max(as.numeric(hu$z_ratio), na.rm = TRUE), digits = 2)
  # Largest z among those that do NOT clear the threshold: the headroom
  # statement in the results chapter depends on this being well below 1.96.
  put("HTwoZMaxNoise", if (is.null(hu) || !any(!ex)) NA else
        max(as.numeric(hu$z_ratio)[!ex], na.rm = TRUE),              digits = 2)
  put("HTwoZMinRobust", if (is.null(hu) || !any(ex)) NA else
        min(as.numeric(hu$z_ratio)[ex], na.rm = TRUE),               digits = 2)
})


# Protocol Amendment 5: feature ablation
sec("Feature ablation (Protocol Amendment 5)")
ab  <- rd("07_ablation_metrics")
h2a_pre <- rd("05_h2_stability_ablated")
# Dropped-feature count, taken from the two stability tables rather than
# hardcoded, so it can never disagree with what was actually fitted.
put("AblNDropped",
    if (is.null(h2) || is.null(h2a_pre)) NA else nrow(h2) - nrow(h2a_pre),
    digits = 0)
# The two arms' covariate counts, now recorded by stage 07 rather than left NA.
# These are the "8 of 22" and "1 of 14" denominators the thesis quotes.
put("AblNFeatures",     cell(ab, "n_features",      variant = "B", model = "primary"), digits = 0)
put("AblNFeaturesFull", cell(ab, "n_features_full", variant = "B", model = "primary"), digits = 0)
for (v in PREREG) for (m in c("primary", "gbt")) {
  tok <- paste0(if (m == "primary") "Primary" else "Gbt", v)
  put(paste0("AblAuroc",      tok), cell(ab, "auroc",             variant = v, model = m))
  put(paste0("AblDeltaAuroc", tok), cell(ab, "delta_auroc",       variant = v, model = m))
  put(paste0("AblAuprc",      tok), cell(ab, "auprc",             variant = v, model = m))
  put(paste0("AblDeltaAuprc", tok), cell(ab, "delta_auprc",       variant = v, model = m))
  put(paste0("AblUtilityMax", tok), cell(ab, "utility_max",       variant = v, model = m), digits = 3)
  put(paste0("AblDeltaUtility", tok), cell(ab, "delta_utility_max", variant = v, model = m), digits = 3)
}

# Ablated-arm coefficient stability
sec("Ablated-arm coefficient stability (Amendment 5)")
h2a <- h2a_pre
local({
  tf <- function(x) x %in% c(TRUE, "TRUE")
  put("AblHTwoNTerms",    if (is.null(h2a)) NA else nrow(h2a),                 digits = 0)
  put("AblHTwoNSign",     if (is.null(h2a)) NA else sum(tf(h2a$sign_flip)),    digits = 0)
  put("AblHTwoNMag",      if (is.null(h2a)) NA else sum(tf(h2a$mag_flip)),     digits = 0)
  put("AblHTwoNUnstable", if (is.null(h2a)) NA else
        sum(tf(h2a$sign_flip) | tf(h2a$mag_flip)),                             digits = 0)
  put("AblHTwoPctUnstable", if (is.null(h2a) || nrow(h2a) == 0) NA else
        round(100 * sum(tf(h2a$sign_flip) | tf(h2a$mag_flip)) / nrow(h2a), 1), digits = 1)
})

sec("Per-model AUROC intervals, Variant B")
ic <- rd("12_internal_ci")
for (m in names(MODEL_TOK)) {
  tok <- paste0(MODEL_TOK[[m]], "B")
  put(paste0("AurocCiLo", tok), cell(ic, "auroc_lo", model = m))
  put(paste0("AurocCiHi", tok), cell(ic, "auroc_hi", model = m))
  put(paste0("AuprcCi",   tok), cell(ic, "auprc_ci", model = m), raw = TRUE)
}

# --------------------------------------------------------------------------- #
# Protocol Amendment 2 - alternative labels D and E
# --------------------------------------------------------------------------- #
sec("Alternative labels D/E (Protocol Amendment 2)")
al <- rd("12_altlabel_auroc_ci")
aa2 <- rd("09_label_anchor_attribution")
ac <- rd("12_altlabel_contrasts")
for (v in ALT) for (m in c("primary", "gbt")) {
  tok <- paste0(MODEL_TOK[[m]], v)
  put(paste0("AltAuroc",      tok), cell(al, "auroc",       variant = v, model = m))
  put(paste0("AltAurocCi",    tok), cell(al, "auroc_ci",    variant = v, model = m), raw = TRUE)
  put(paste0("AltEventRatio", tok), cell(aa2, "event_rate_ratio", variant = v, model = m), digits = 1)
  put(paste0("AltDelta",      tok), cell(ac, "delta_auroc", variant = v, model = m))
  put(paste0("AltDeltaCiLo",  tok), cell(ac, "ci_lo",       variant = v, model = m))
  put(paste0("AltDeltaCiHi",  tok), cell(ac, "ci_hi",       variant = v, model = m))
  pb <- cell(ac, "p_bh", variant = v, model = m)
  put(paste0("AltDeltaPBh", tok),
      if (is.na(pb)) pb else if (as.numeric(pb) < 0.001) "\\ensuremath{<0.001}"
      else as.numeric(pb),
      digits = 3, raw = !is.na(pb) && as.numeric(pb) < 0.001)
}
aa <- rd("12_anchor_attribution_ci")
for (m in c("primary", "gbt")) {
  tok <- MODEL_TOK[[m]]
  put(paste0("PhiAnchor",     tok), cell(aa, "phi_anchor", model = m), digits = 3)
  put(paste0("PhiAnchorCiLo", tok), cell(aa, "ci_lo",      model = m), digits = 3)
  put(paste0("PhiAnchorCiHi", tok), cell(aa, "ci_hi",      model = m), digits = 3)
}
put("AltFamilySize",
    if (is.null(ac) || !nrow(ac)) NA else nrow(ac), digits = 0)

# --------------------------------------------------------------------------- #
# Protocol Amendment 4 - standard onset timing (variant F) and the
# pre-treatment window across every label definition
# --------------------------------------------------------------------------- #
sec("Pre-treatment window by label variant (Protocol Amendment 4)")
pt <- rd("09_pretreatment_onsets")
for (v in c(PREREG, ALT)) {
  put(paste0("PreTreatOnsetsVar",     v),
      cell(pt, "n_sepsis_events", variant = v, model = "primary"), big = TRUE)
  put(paste0("PreTreatPersonHoursVar", v),
      cell(pt, "n_rows",          variant = v, model = "primary"), big = TRUE)
  for (m in c("primary", "gbt"))
    put(paste0("PreTreatAuroc", MODEL_TOK[[m]], v),
        cell(pt, "auroc", variant = v, model = m))
}

sec("Onset shift under standard min(t_susp, t_SOFA) timing (variant F)")
os <- rd("03_early_onset_shift")
put("FNOnsets",          cell(os, "n_onsets",             variant = "F"), big = TRUE)
put("FNMovedEarlier",    cell(os, "n_moved_earlier",      variant = "F"), big = TRUE)
put("FPctMovedEarlier",  cell(os, "pct_moved_earlier",    variant = "F"), digits = 1)
put("FMedianShiftH",     cell(os, "median_shift_h",       variant = "F"), digits = 1)
put("FQXXVShiftH",       cell(os, "q25_shift_h",          variant = "F"), digits = 1)
put("FMaxShiftH",        cell(os, "max_shift_h",          variant = "F"), digits = 1)
put("FNBeforeAnchor",    cell(os, "n_before_anchor",      variant = "F"), big = TRUE)
put("FNBeforeAnchorTest",cell(os, "n_before_anchor_test", variant = "F"), big = TRUE)

# Stays that only become modellable events under the earlier timing: their
# t_susp falls past the 72 h horizon but their t_SOFA does not. F is a superset
# of B within the horizon, so this difference is non-negative by construction.
local({
  nf <- cell(la, "n_positive",   variant = "F")
  nb <- cell(la, "n_positive_B", variant = "F")
  put("FNExtraInHorizon",
      if (is.na(nf) || is.na(nb)) structure(NA, row_found = TRUE)
      else as.numeric(nf) - as.numeric(nb), big = TRUE)
})

# --------------------------------------------------------------------------- #
# Equity
# --------------------------------------------------------------------------- #
sec("Proportional-hazards (Schoenfeld) test, Variant B")
sch <- rd("06_cox_schoenfeld_B")
put("SchoenfeldChisq", cell(sch, "chisq", covariate = "GLOBAL"), digits = 1)
put("SchoenfeldDf",    cell(sch, "df",    covariate = "GLOBAL"), digits = 0)
put("SchoenfeldP",
    { x <- cell(sch, "p", covariate = "GLOBAL")
      if (is.na(x)) x else sprintf("\\ensuremath{%.1f\\times 10^{%d}}",
                                   as.numeric(x) / 10^floor(log10(as.numeric(x))),
                                   floor(log10(as.numeric(x)))) },
    raw = TRUE)
put("SchoenfeldNViolate",
    if (is.null(sch)) NA else sum(sch$p < 0.05 & sch$covariate != "GLOBAL"), digits = 0)
put("SchoenfeldNCovariates",
    if (is.null(sch)) NA else sum(sch$covariate != "GLOBAL"), digits = 0)

sec("GBT feature importance, Variant B")
fi <- rd("06_gbt_feature_importance_B")
FEAT_TOK <- c(temp_c = "TempC", resp_rate_slope6h = "RespRateSlope",
              map_slope6h = "MapSlope", gcs = "Gcs", hr_slope6h = "HrSlope",
              creatinine = "Creatinine", wbc = "Wbc", hr = "Hr",
              lactate = "Lactate", map = "Map", bilirubin_total = "Bilirubin",
              resp_rate = "RespRate", platelets = "Platelets")
for (f in names(FEAT_TOK)) {
  tok <- FEAT_TOK[[f]]
  put(paste0("GbtGain", tok), cell(fi, "Gain",      Feature = f), digits = 3)
  put(paste0("GbtCover", tok), cell(fi, "Cover",     Feature = f), digits = 3)
  put(paste0("GbtFreq", tok),  cell(fi, "Frequency", Feature = f), digits = 3)
}

sec("Subgroup AUROC by race (top levels by exposure)")
sc8 <- rd("12_subgroup_auroc_ci")
local({
  ordw <- c("One","Two","Three","Four","Five","Six","Seven","Eight")
  na   <- structure(NA, row_found = TRUE)
  rows <- if (is.null(sc8)) NULL else
    unique(sc8[subgroup_col == "race", .(subgroup_val, n_rows, n_events)])[order(-n_rows)]
  for (i in seq_along(ordw)) {
    r  <- if (!is.null(rows) && i <= nrow(rows)) rows[i] else NULL
    tk <- paste0("EquityRace", ordw[i])
    put(paste0(tk, "Name"),    if (is.null(r)) na else r$subgroup_val, raw = TRUE)
    put(paste0(tk, "NRows"),   if (is.null(r)) na else r$n_rows,   big = TRUE)
    put(paste0(tk, "NEvents"), if (is.null(r)) na else r$n_events, big = TRUE)
    for (m in c("primary", "gbt")) {
      lo <- if (is.null(r)) na else cell(sc8, "ci_lo", subgroup_col = "race",
                                         subgroup_val = r$subgroup_val, model = m)
      hi <- if (is.null(r)) na else cell(sc8, "ci_hi", subgroup_col = "race",
                                         subgroup_val = r$subgroup_val, model = m)
      put(paste0(tk, "Auroc", MODEL_TOK[[m]]),
          if (is.null(r)) na else cell(sc8, "auroc", subgroup_col = "race",
                                       subgroup_val = r$subgroup_val, model = m),
          digits = 3)
      put(paste0(tk, "Ci", MODEL_TOK[[m]]),
          if (is.na(lo) || is.na(hi)) na
          else sprintf("\\ensuremath{%.3f\\text{--}%.3f}", as.numeric(lo), as.numeric(hi)),
          raw = TRUE)
    }
  }
})

sec("Subgroup AUROC contrasts against the reference level")
sct <- rd("12_subgroup_auroc_contrasts")
local({
  ordw <- c("One","Two","Three","Four","Five","Six","Seven")
  na   <- structure(NA, row_found = TRUE)
  fmt  <- function(r, col, d = 3)
    if (is.null(r)) na else formatC(as.numeric(r[[col]]), format = "f", digits = d)
  for (m in c("gbt", "primary")) {
    rr <- if (is.null(sct)) NULL else sct[subgroup_col == "race" & model == m][order(p_raw)]
    for (i in seq_along(ordw)) {
      r  <- if (!is.null(rr) && i <= nrow(rr)) rr[i] else NULL
      tk <- paste0("RaceContrast", MODEL_TOK[[m]], ordw[i])
      put(paste0(tk, "Name"),  if (is.null(r)) na else r$subgroup_val, raw = TRUE)
      put(paste0(tk, "Delta"), if (is.null(r)) na else r$delta_auroc, digits = 3)
      put(paste0(tk, "Ci"),
          if (is.null(r)) na
          else sprintf("\\ensuremath{%s\\text{--}%s}", fmt(r, "ci_lo"), fmt(r, "ci_hi")),
          raw = TRUE)
      put(paste0(tk, "P"),  if (is.null(r)) na else r$p_raw, digits = 3)
      put(paste0(tk, "Q"),  if (is.null(r)) na else r$p_bh,  digits = 3)
      put(paste0(tk, "NEvents"),
          if (is.null(r)) na
          else cell(sc8, "n_events", subgroup_col = "race",
                    subgroup_val = r$subgroup_val, model = m), big = TRUE)
    }
  }
  put("EquityNContrastsEOne", if (is.null(sct)) NA else nrow(sct), digits = 0)
  put("EquityNSigEOne",
      if (is.null(sct)) NA else sum(sct$significant_bh, na.rm = TRUE), digits = 0)
})

sec("Subgroup interpretability floor")
local({
  put("MinSubgroupEvents", MIN_SUBGROUP_EVENTS_INTERPRET, digits = 0)
  # The estimation floor, distinct from the interpretation floor above. The
  # methods chapter now states both and says which decides what, so both come
  # from config.R rather than being typed.
  put("MinSubgroupEventsEstimate", MIN_SUBGROUP_EVENTS, digits = 0)
  # Family E1's size after Amendment 6, and its smallest adjusted p-value. Both
  # are quoted in the methods chapter's defence of the reduction.
  local({
    sd8 <- rd("12_subgroup_auroc_contrasts")
    put("NSubgroupContrasts", if (is.null(sd8)) NA else nrow(sd8), digits = 0)
    put("SubgroupMinQ",
        if (is.null(sd8) || !("p_bh" %in% names(sd8))) NA else min(sd8$p_bh, na.rm = TRUE),
        digits = 3)
  })
  n_above <- if (is.null(sc8)) NA else
    nrow(unique(sc8[subgroup_col == "race" &
                    n_events >= MIN_SUBGROUP_EVENTS_INTERPRET, .(subgroup_val)]))
  put("NSubgroupsAboveFloor", n_above, digits = 0)
})

sec("Equity (BH-adjusted subgroup contrasts)")
sa <- rd("12_subgroup_auroc_contrasts")
put("EquityAurocMinQ",
    if (is.null(sa) || !nrow(sa)) NA else min(sa$p_bh, na.rm = TRUE), digits = 3)
put("EquityAurocNSig",
    if (is.null(sa)) NA else sum(sa$significant_bh %in% c(TRUE, "TRUE")), digits = 0)

sl <- rd("12_subgroup_labelsens_contrasts")
if (!is.null(sl) && nrow(sl)) {
  sig <- sl[significant_bh %in% c(TRUE, "TRUE")][order(p_bh)]
  ordw <- c("One", "Two", "Three", "Four")
  for (i in seq_along(ordw)) {
    r  <- if (i <= nrow(sig)) sig[i] else NULL
    na <- structure(NA, row_found = TRUE)
    put(paste0("LabelSensTop", ordw[i], "Name"),
        if (is.null(r)) na else paste(r$subgroup_col, r$subgroup_val), raw = TRUE)
    put(paste0("LabelSensTop", ordw[i], "Delta"),
        if (is.null(r)) na else r$delta_range_pp, digits = 2)
    put(paste0("LabelSensTop", ordw[i], "Q"),
        if (is.null(r)) na else r$p_bh, digits = 3)
  }
  put("LabelSensNSig", nrow(sig), digits = 0)
} else {
  for (w in c("One","Two","Three","Four")) {
    put(paste0("LabelSensTop", w, "Name"),  NA)
    put(paste0("LabelSensTop", w, "Delta"), NA)
    put(paste0("LabelSensTop", w, "Q"),     NA)
  }
  put("LabelSensNSig", NA)
}
# --------------------------------------------------------------------------- #
# Derived quantities that used to be transcribed by hand
#
# Every number below appeared as a literal in a chapter until now. They are
# computed here from the result tables so a re-run cannot leave the prose
# behind. Where a quantity is a difference between two tables (the split-
# optimism deltas), it is computed here rather than added to a pipeline stage:
# no stage owns the comparison, and this file already reads both sides.
# --------------------------------------------------------------------------- #
sec("Spread confidence intervals (decomposition table)")
sp <- rd("12_spread_ci")
for (q in c("label", "model")) {
  tok <- if (q == "label") "SpreadLabel" else "SpreadModelClass"
  put(paste0(tok, "CiLo"), cell(sp, "ci_lo", quantity = q), digits = 3)
  put(paste0(tok, "CiHi"), cell(sp, "ci_hi", quantity = q), digits = 3)
}

sec("Split optimism: random - temporal by model (Variant B)")
local({
  tt <- rd("07_metric_results")
  rr <- rd("07_metric_results_random")
  deltas <- c()
  # qSOFA and SIRS are not re-fitted on the random split (they are rule-based
  # and carry no fitted parameters), so only the four fitted models appear.
  for (m in c("primary", "gbt", "cox", "news2")) {
    a <- cell(tt, "auroc", variant = "B", model = m, eval_window = "unrestricted")
    b <- cell(rr, "auroc", variant = "B", model = m, eval_window = "unrestricted")
    d <- if (is.na(a) || is.na(b)) NA_real_ else as.numeric(b) - as.numeric(a)
    put(paste0("SplitDelta", MODEL_TOK[[m]], "B"), d, digits = 3)
    if (!is.na(d)) deltas <- c(deltas, d)
  }
  # The prose says "each scores lower by X to Y"; both bounds are magnitudes.
  put("SplitDeltaMinAbs", if (length(deltas)) min(abs(deltas)) else NA, digits = 3)
  put("SplitDeltaMaxAbs", if (length(deltas)) max(abs(deltas)) else NA, digits = 3)
})

sec("Equity: the one surviving E1 contrast, and the label-sensitivity range")
local({
  sc <- rd("12_subgroup_auroc_contrasts")
  top <- if (is.null(sc)) NULL else {
    x <- sc[significant_bh %in% c(TRUE, "TRUE")]
    if (nrow(x)) x[order(p_bh)][1] else NULL
  }
  g <- function(col) if (is.null(sc)) structure(NA, row_found = FALSE) else if (is.null(top)) structure(NA, row_found = TRUE) else top[[col]][1]
  put("EquityTopDelta",   g("delta_auroc"), digits = 3)
  put("EquityTopCiLo",    g("ci_lo"),       digits = 3)
  put("EquityTopCiHi",    g("ci_hi"),       digits = 3)
  put("EquityTopQ",       g("p_bh"),        digits = 3)
  put("EquityTopNEvents", g("n_events"),    digits = 0)

  # The four label-sensitivity contrasts that survive BH, named individually in
  # the caption and the paragraph that follows it.
  lsc <- rd("12_subgroup_labelsens_contrasts")
  for (spec in list(c("LabelSensUnknown",   "race",      "UNKNOWN"),
                    c("LabelSensUnable",    "race",      "UNABLE TO OBTAIN"),
                    c("LabelSensSpanish",   "language",  "Spanish"),
                    c("LabelSensPrivate",   "insurance", "Private"))) {
    put(paste0(spec[1], "Pp"),
        cell(lsc, "delta_range_pp", subgroup_col = spec[2], subgroup_val = spec[3]),
        digits = 2)
    put(paste0(spec[1], "Q"),
        cell(lsc, "p_bh", subgroup_col = spec[2], subgroup_val = spec[3]),
        digits = 3)
  }
  # How many of the surviving contrasts are racial. (The family-wide count is
  # already emitted as \pcLabelSensNSig above.)
  nrace <- if (is.null(lsc)) NA else
    sum(lsc$significant_bh %in% c(TRUE, "TRUE") & lsc$subgroup_col == "race")
  put("LabelSensNSigRace", nrace, digits = 0)

  ls_r <- rd("12_subgroup_labelsens_ci")
  rng  <- if (is.null(ls_r)) NULL else ls_r[subgroup_col == "race" &
                                              !(is_reference %in% c(TRUE, "TRUE")),
                                            range_pp]
  put("LabelSensRangeLo", if (length(rng)) min(rng) else NA, digits = 1)
  put("LabelSensRangeHi", if (length(rng)) max(rng) else NA, digits = 1)
})

# --------------------------------------------------------------------------- #
# Generated table bodies
#
# Some tables have too many cells for one-macro-per-cell to be workable (the
# equity tables are ~50 numbers each). Emitting the tabular body itself keeps
# the same guarantee - no figure is ever transcribed by hand - and scales to any
# number of rows. The thesis \input{}s these; the surrounding \begin{table},
# column spec and caption stay in the .tex where they belong.
#
# A body that cannot be built is written as a single \pcMissing row rather than
# left stale or absent, so the failure is visible in the PDF exactly like a
# missing macro.
# --------------------------------------------------------------------------- #
TABLES_WRITTEN <- character(0)
TABLES_MISSING <- character(0)

#' Write a complete tabular environment to ../thesis/table_<name>.tex.
#'
#' The WHOLE environment is emitted, not just the rows. A partial alignment
#' body cannot be \\input reliably: TeX's alignment scanner has to see the
#' `&` and `\\\\` tokens in the same expansion context, and \\input breaks that,
#' which surfaces as "Misplaced \\noalign" at the \\bottomrule. The thesis keeps
#' the surrounding \\begin{table}, caption and label.
#'
#' @param name    file stem
#' @param colspec tabular column specification, e.g. "lrcccc"
#' @param header  character vector of header lines (without the trailing \\\\)
#' @param rows    body rows (without trailing \\\\)
write_table <- function(name, colspec, header, rows) {
  path <- file.path(GEN_DIR, paste0("table_", name, ".tex"))
  if (is.null(rows) || length(rows) == 0) {
    writeLines(c("% GENERATED by thesis_constants.R -- source rows missing",
                 "\\begin{tabular}{l}", "\\pcMissing", "\\end{tabular}"), path)
    TABLES_MISSING <<- c(TABLES_MISSING, name)
    return(invisible(NULL))
  }
  writeLines(c(
    "% GENERATED by thesis_constants.R -- do not edit",
    sprintf("\\begin{tabular}{%s}", colspec),
    "\\toprule",
    paste0(header, " \\\\"),
    "\\midrule",
    paste0(rows, " \\\\"),
    "\\bottomrule",
    "\\end{tabular}"
  ), path)
  TABLES_WRITTEN <<- c(TABLES_WRITTEN, name)
  invisible(NULL)
}

# Numeric formatters for table cells.
f1  <- function(x) formatC(as.numeric(x), format = "f", digits = 1)
f2  <- function(x) formatC(as.numeric(x), format = "f", digits = 2)
big <- function(x) formatC(as.numeric(x), format = "d", big.mark = "{,}")
# LaTeX-safe display name for a subgroup level. The pipeline stores MIMIC's
# raw all-caps codes; the thesis prints prose. An explicit map is used rather
# than a case-folding heuristic because these labels are few, fixed, and read
# badly when title-cased mechanically ("Unable To Obtain").
LEVEL_LABELS <- c(
  "WHITE"                  = "White",
  "UNKNOWN"                = "Unknown",
  "BLACK/AFRICAN AMERICAN" = "Black / African American",
  "OTHER"                  = "Other",
  "UNABLE TO OBTAIN"       = "Unable to obtain",
  "WHITE - OTHER EUROPEAN" = "White -- Other European",
  "ASIAN"                  = "Asian",
  "ASIAN - CHINESE"        = "Asian -- Chinese",
  "HISPANIC/LATINO"        = "Hispanic / Latino",
  "HISPANIC/LATINO - PUERTO RICAN" = "Hispanic / Latino -- Puerto Rican",
  "HISPANIC OR LATINO"     = "Hispanic or Latino"
)
pretty_level <- function(x) {
  x   <- as.character(x)
  out <- unname(LEVEL_LABELS[toupper(trimws(x))])
  # Unmapped level: fall back to sentence case rather than dropping the row,
  # so a new subgroup appears (readably) instead of vanishing.
  fb  <- !is.na(out)
  res <- ifelse(fb, out, paste0(toupper(substring(x, 1, 1)),
                                tolower(substring(x, 2))))
  gsub("&", "\\\\&", gsub(" - ", " -- ", res, fixed = TRUE))
}
signed <- function(x, d = 2) {
  v <- as.numeric(x)
  sprintf("$%s%s$", ifelse(v < 0, "-", "+"),
          formatC(abs(v), format = "f", digits = d))
}

# --- Label sensitivity by racial subgroup (tab:equity_label) ----------------
ls_ci <- rd("12_subgroup_labelsens_ci")
local({
  if (is.null(hu) || nrow(hu) == 0) { write_table("htwouncertainty", "l", "", NULL); return(invisible(NULL)) }
  d  <- hu[order(-as.numeric(hu$z_ratio)), , drop = FALSE]
  tf <- function(x) x %in% c(TRUE, "TRUE")
  esc <- function(s) gsub("_", "\\\\_", as.character(s))
  rows <- sprintf("\\texttt{%s} & %s & %s & %s & %s & %s & %s & %s",
                  esc(d$term),
                  formatC(as.numeric(d$coef_A), format = "f", digits = 4),
                  formatC(as.numeric(d$coef_B), format = "f", digits = 4),
                  formatC(as.numeric(d$coef_C), format = "f", digits = 4),
                  formatC(as.numeric(d$max_diff),  format = "f", digits = 4),
                  formatC(as.numeric(d$pooled_se), format = "f", digits = 4),
                  formatC(as.numeric(d$z_ratio),   format = "f", digits = 2),
                  ifelse(tf(d$is_action), "action", "physiol."))
  write_table("htwouncertainty",
              "lrrrrrrl",
              paste("\\textbf{Covariate} & \\textbf{$\\beta_A$} & \\textbf{$\\beta_B$}",
                    "& \\textbf{$\\beta_C$} & \\textbf{Max diff.} & \\textbf{Pooled SE}",
                    "& \\textbf{Ratio} & \\textbf{Kind}"),
              rows)
})

write_table("equitylabel", "lrcccc",
  paste("\\textbf{Racial group} & \\textbf{Stays} & \\textbf{A (\\%)}",
        "& \\textbf{B (\\%)} & \\textbf{C (\\%)}",
        "& \\textbf{Range (pp, 95\\% CI)}"),
  local({
    if (is.null(ls_ci)) return(NULL)
    r <- ls_ci[subgroup_col == "race"]
    if (!nrow(r)) return(NULL)
    setorder(r, -n_stays)
    sprintf("%s & %s & %s & %s & %s & %s (%s--%s)",
            pretty_level(r$subgroup_val), big(r$n_stays),
            f1(r$pct_A), f1(r$pct_B), f1(r$pct_C),
            f1(r$range_pp), f1(r$range_lo), f1(r$range_hi))
  }))

# --- Label-sensitivity contrasts vs White (tab:equity_label_contrasts) ------
ls_ct <- rd("12_subgroup_labelsens_contrasts")
write_table("equitylabelcontrasts", "lrcrr",
  paste("\\textbf{Racial group} & \\textbf{Stays}",
        "& \\textbf{$\\Delta$ range vs.\\ White (pp, 95\\% CI)}",
        "& \\textbf{$p$} & \\textbf{$q_{\\text{BH}}$}"),
  local({
    if (is.null(ls_ct)) return(NULL)
    r <- ls_ct[subgroup_col == "race"]
    if (!nrow(r)) return(NULL)
    setorder(r, p_bh)
    sig  <- r$significant_bh %in% c(TRUE, "TRUE")
    qtxt <- formatC(as.numeric(r$p_bh), format = "f", digits = 3)
    qtxt <- ifelse(sig, paste0("\\textbf{", qtxt, "}"), qtxt)
    sprintf("%s & %s & %s (%s--%s) & %s & %s",
            pretty_level(r$subgroup_val), big(r$n_stays),
            signed(r$delta_range_pp), signed(r$ci_lo), signed(r$ci_hi),
            formatC(as.numeric(r$p_raw), format = "f", digits = 3), qtxt)
  }))

# --- Subgroup discrimination by racial stratum (tab:equity_performance) -----
# Generated whole rather than macro-per-cell: the number of rows now depends on
# how many strata clear the interpretability floor, so a fixed grid of
# One..Eight macros would either leave red ?? cells or silently hide a stratum.
f3 <- function(x) formatC(as.numeric(x), format = "f", digits = 3)
write_table("equityperformance", "lrrcc",
  paste("\\textbf{Racial stratum} & \\textbf{Rows} & \\textbf{Sepsis}",
        "& \\textbf{GBT AUROC (95\\% CI)} & \\textbf{Primary AUROC (95\\% CI)}"),
  local({
    if (is.null(sc8)) return(NULL)
    r <- unique(sc8[subgroup_col == "race", .(subgroup_val, n_rows, n_events)])
    if (!nrow(r)) return(NULL)
    setorder(r, -n_rows)
    one <- function(lvl, m) {
      x <- sc8[subgroup_col == "race" & subgroup_val == lvl & model == m]
      if (!nrow(x)) return("\\pcMissing")
      sprintf("%s (%s--%s)", f3(x$auroc[1]), f3(x$ci_lo[1]), f3(x$ci_hi[1]))
    }
    # Strata below the floor are shown but flagged: suppressing them would hide
    # which groups the cohort contains and how few events they carry, which is
    # itself the argument for the floor.
    flag <- ifelse(r$n_events < MIN_SUBGROUP_EVENTS_INTERPRET, "$^\\dagger$", "")
    sprintf("%s%s & %s & %s & %s & %s",
            pretty_level(r$subgroup_val), flag, big(r$n_rows), big(r$n_events),
            vapply(r$subgroup_val, one, character(1), m = "gbt"),
            vapply(r$subgroup_val, one, character(1), m = "primary"))
  }))

# --- Subgroup AUROC contrasts (tab:equity_contrasts) ------------------------
# Only strata above the interpretability floor reach this table, because only
# those enter family E1 (see 12_inference.Rmd). The row count is therefore not
# fixed in advance either.
write_table("equitycontrasts", "lrlcrr",
  paste("\\textbf{Racial stratum} & \\textbf{Sepsis} & \\textbf{Model}",
        "& \\textbf{$\\Delta$AUROC vs.\\ reference (95\\% CI)}",
        "& \\textbf{$p$} & \\textbf{$q_{\\text{BH}}$}"),
  local({
    if (is.null(sct)) return(NULL)
    r <- sct[subgroup_col == "race"]
    if (!nrow(r)) return(NULL)
    setorder(r, model, p_raw)
    sig  <- r$significant_bh %in% c(TRUE, "TRUE")
    qtxt <- formatC(as.numeric(r$p_bh), format = "f", digits = 3)
    qtxt <- ifelse(sig, paste0("\\textbf{", qtxt, "}"), qtxt)
    mtok <- unname(MODEL_TOK[as.character(r$model)])
    mtok[is.na(mtok)] <- as.character(r$model)[is.na(mtok)]
    sprintf("%s & %s & %s & %s (%s--%s) & %s & %s",
            pretty_level(r$subgroup_val), big(r$n_events), mtok,
            signed(r$delta_auroc, 3), signed(r$ci_lo, 3), signed(r$ci_hi, 3),
            formatC(as.numeric(r$p_raw), format = "f", digits = 3), qtxt)
  }))


# --------------------------------------------------------------------------- #
# Emit
# --------------------------------------------------------------------------- #
lines <- c(
  "% =====================================================================",
  "%  pipeline_constants.tex - GENERATED FILE, DO NOT EDIT BY HAND",
  "% ---------------------------------------------------------------------",
  "%  Written by sepsis/project/thesis_constants.R at the end of every pipeline",
  "%  run. Edits here are overwritten. To change a number, change the",
  "%  pipeline; to add one, add a put() call in thesis_constants.R.",
  "%",
  "%  Every macro is \\pc-prefixed. A value the pipeline did not produce",
  "%  is defined as \\pcMissing, which typesets a bold red ?? so it cannot",
  "%  slip into the PDF unnoticed.",
  "% =====================================================================",
  "\\ifdefined\\pcConstantsLoaded\\endinput\\fi",
  "\\newcommand{\\pcConstantsLoaded}{}",
  "\\providecommand{\\pcMissing}{\\textbf{\\textcolor{red}{??}}}",
  "\\providecommand{\\pcNotApplicable}{\\textup{n/a}}",
  ""
)
for (item in ORDER) {
  if (startsWith(item, "%%SECTION%%")) {
    lines <- c(lines, "", paste0("% --- ", sub("^%%SECTION%%", "", item), " ---"))
    next
  }
  val <- get(item, envir = MACROS)
  lines <- c(lines, sprintf("\\newcommand{\\pc%s}{%s}", item,
                            if (is.na(val)) "\\pcMissing" else val))
}
lines <- c(lines, "")

if (!dir.exists(THESIS_DIR)) stop("thesis directory not found: ", THESIS_DIR)
if (!dir.exists(GEN_DIR)) dir.create(GEN_DIR, recursive = TRUE)
writeLines(lines, OUT_TEX)

n_def <- length(ORDER) - sum(startsWith(ORDER, "%%SECTION%%"))
cat(sprintf("\nWrote %s\n  %d macros (%d resolved, %d missing)\n",
            OUT_TEX, n_def, n_def - length(MISSING), length(MISSING)))
if (length(MISSING)) {
  cat("\n  !! MISSING - these typeset as a red ?? in the PDF:\n")
  for (m in MISSING) cat("     \\pc", m, "\n", sep = "")
  cat("\n  Usually means the producing stage did not run. Check output/logs/.\n")
}
if (length(TABLES_WRITTEN))
  cat(sprintf("  %d generated table bodies: %s\n", length(TABLES_WRITTEN),
              paste(TABLES_WRITTEN, collapse = ", ")))
if (length(TABLES_MISSING))
  cat(sprintf("  !! %d table bodies could NOT be built: %s\n",
              length(TABLES_MISSING), paste(TABLES_MISSING, collapse = ", ")))

# --------------------------------------------------------------------------- #
# Figure sync - the other half of the manual-sync trap
# --------------------------------------------------------------------------- #
img_dir <- file.path(THESIS_DIR, "images")
if (dir.exists(FIG_DIR) && dir.exists(img_dir)) {
  figs <- list.files(FIG_DIR, pattern = "\\.png$", full.names = TRUE)
  if (length(figs)) {
    ok <- file.copy(figs, img_dir, overwrite = TRUE)
    cat(sprintf("\nSynced %d/%d figures -> %s\n", sum(ok), length(figs), img_dir))
  }
} else {
  message("Figure sync skipped (missing ", FIG_DIR, " or ", img_dir, ")")
}

# --------------------------------------------------------------------------- #
# Exit status: an unresolved macro must be actionable, not decorative
#
# The \pcMissing mechanism makes a gap visible in the PDF, and that worked --
# and then a PDF carrying thirteen red ?? across two chapters was committed
# anyway, because nothing downstream treated the warning as a failure. A
# non-zero exit lets build.sh and run_pipeline.{sh,R} refuse. Draft builds that
# genuinely want the placeholders set V2_ALLOW_MISSING=1.
# --------------------------------------------------------------------------- #
if ((length(MISSING) > 0 || length(TABLES_MISSING) > 0) &&
    !nzchar(Sys.getenv("V2_ALLOW_MISSING"))) {
  cat(sprintf(paste0("\nFAIL: %d unresolved macro(s) and %d unbuilt table body/ies.\n",
                     "      Any of these that a chapter references will typeset as a\n",
                     "      red ?? in index.pdf; build.sh reports which ones those are\n",
                     "      and refuses only on those. Re-run the producing stage, or\n",
                     "      set V2_ALLOW_MISSING=1 to accept them in a draft build.\n"),
              length(MISSING), length(TABLES_MISSING)))
  quit(status = 1L)
}
