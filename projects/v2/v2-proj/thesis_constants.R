#!/usr/bin/env Rscript
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
#      ../v2-thesis/pipeline_constants.tex
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
THESIS_DIR <- normalizePath(file.path(SCRIPT_DIR, "..", "v2-thesis"), mustWork = FALSE)
OUT_TEX    <- file.path(THESIS_DIR, "pipeline_constants.tex")

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

ss <- rd("04_sample_size")
for (v in PREREG) {
  put(paste0("NTrainPersonH", v), cell(ss, "n_train_person_h", variant = v), big = TRUE)
  put(paste0("MinNRiley", v),     cell(ss, "min_n_riley",      variant = v), big = TRUE)
  put(paste0("Epv", v),           cell(ss, "epv",              variant = v), digits = 1)
  put(paste0("NOnsetEvents", v),  cell(ss, "n_onset_events",   variant = v), big = TRUE)
  put(paste0("PerHourRate", v),   cell(ss, "per_hour_event_rate", variant = v), digits = 5)
}

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
        else sprintf("\\ensuremath{%.2f\\times 10^{-4}}", 1e4 * as.numeric(x)) },
      raw = TRUE)
  put(paste0("Snb",        tok), cell(nb, "snb",              variant = v, model = m), digits = 3)
  put(paste0("AlertRate",  tok), cell(nb, "alert_rate",       variant = v, model = m), digits = 3)
  put(paste0("AlertRange", tok), cell(nb, "alert_rate_range", variant = v, model = m), digits = 3)
}

sec("External validation (eICU-CRD)")
ex <- rd("08_external_validation_results")
for (v in PREREG) {
  put(paste0("ExtAurocPrimary", v), cell(ex, "auroc", variant = v, model = "pred_sepsis"))
  put(paste0("ExtAurocNews", v),    cell(ex, "auroc", variant = v, model = "pred_news2"))
}
put("ExtNRows",   cell(ex, "n_rows",   variant = "B", model = "pred_sepsis"), big = TRUE)
put("ExtNEvents", cell(ex, "n_events", variant = "B", model = "pred_sepsis"), big = TRUE)

# --------------------------------------------------------------------------- #
# Variance decomposition
# --------------------------------------------------------------------------- #
sec("Variance decomposition")
vd <- rd("09_variance_decomposition_table")
dec <- c(ModelClass = "-", Label = "H1", Anchoring = "H3",
         Split = "H4", Metric = "H5", ModelNull = "H6")
for (nm in names(dec))
  put(paste0("Spread", nm), cell(vd, "spread_auroc", hypothesis = dec[[nm]]))

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
# Emit
# --------------------------------------------------------------------------- #
lines <- c(
  "% =====================================================================",
  "%  pipeline_constants.tex - GENERATED FILE, DO NOT EDIT BY HAND",
  "% ---------------------------------------------------------------------",
  "%  Written by v2-proj/thesis_constants.R at the end of every pipeline",
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
  "\\providecommand{\\pcNotApplicable}{\\textup{---}}",
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
writeLines(lines, OUT_TEX)

n_def <- length(ORDER) - sum(startsWith(ORDER, "%%SECTION%%"))
cat(sprintf("\nWrote %s\n  %d macros (%d resolved, %d missing)\n",
            OUT_TEX, n_def, n_def - length(MISSING), length(MISSING)))
if (length(MISSING)) {
  cat("\n  !! MISSING - these typeset as a red ?? in the PDF:\n")
  for (m in MISSING) cat("     \\pc", m, "\n", sep = "")
  cat("\n  Usually means the producing stage did not run. Check output/logs/.\n")
}

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
