#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# ===========================================================================
#  check_consistency.R - cross-file assertions over the generated results
# ===========================================================================
#
#  Why this exists
#  ---------------
#  thesis_constants.R guarantees that a number in the thesis is the number the
#  pipeline produced. It cannot check that two numbers which must agree do
#  agree, and round 11 found several that did not:
#
#    * the decomposition table's split row (-0.0166) against the confirmatory
#      table's H4 estimate (-0.0165) -- same contrast, two estimators, printed
#      three pages apart;
#    * one variant's person-hour denominator printed in all three rows of the
#      antibiotic-only event-rate table, making two rows fail their own
#      arithmetic;
#    * a labelled eICU onset count of 31 against a scored event count of 29,
#      with nothing reconciling them.
#
#  Each check below is an arithmetic or cross-table identity that must hold.
#  A failure is a defect in the results or in how they are being reported, not
#  a style issue. Run after any pipeline execution and before any build:
#
#      Rscript check_consistency.R
#
#  Exit status 0 = all checks pass, 1 = at least one failed.
# ===========================================================================

suppressPackageStartupMessages({ library(data.table); library(arrow) })

SCRIPT_DIR <- local({
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
})
DATA_DIR <- file.path(SCRIPT_DIR, "output", "processed_data")

rd <- function(base) {
  pq <- file.path(DATA_DIR, paste0(base, ".parquet"))
  cs <- file.path(DATA_DIR, paste0(base, ".csv"))
  if (file.exists(pq)) return(as.data.table(arrow::read_parquet(pq)))
  if (file.exists(cs)) return(fread(cs))
  NULL
}

PASS <- 0L; FAIL <- 0L; SKIP <- 0L
chk <- function(label, ok, detail = "") {
  if (is.na(ok)) {
    SKIP <<- SKIP + 1L; cat(sprintf("  SKIP  %s (source missing)\n", label))
  } else if (isTRUE(ok)) {
    PASS <<- PASS + 1L; cat(sprintf("  ok    %s\n", label))
  } else {
    FAIL <<- FAIL + 1L; cat(sprintf("  FAIL  %s\n        %s\n", label, detail))
  }
}
near <- function(a, b, tol = 5e-4) !is.na(a) && !is.na(b) && abs(a - b) <= tol

cat("\nCross-file consistency checks\n")
cat("-----------------------------\n")

# --- 1. The decomposition and the confirmatory family must agree ------------
# Both are printed as tables in the results chapter, three pages apart, for the
# same contrasts. They come from different stages, so nothing but this makes
# them agree.
local({
  ct <- rd("12_confirmatory_tests"); vd <- rd("09_variance_decomposition_table")
  sp <- rd("12_spread_ci")
  if (is.null(ct) || is.null(vd)) { chk("decomposition vs confirmatory", NA); return() }
  g <- function(h) as.numeric(ct[hypothesis == h, estimate][1])
  v <- function(h) as.numeric(vd[hypothesis == h, spread_auroc][1])
  chk("decomposition split row == H4 estimate", near(v("H4"), g("H4")),
      sprintf("09 gives %.6f, 12 gives %.6f -- 09 differences pre-rounded AUROCs",
              v("H4"), g("H4")))
  chk("decomposition transport row == H5 estimate", near(v("H5"), g("H5")),
      sprintf("09 gives %.6f, 12 gives %.6f", v("H5"), g("H5")))
  if (!is.null(sp)) {
    lab <- as.numeric(sp[quantity == "label", estimate][1])
    mod <- as.numeric(sp[quantity == "model", estimate][1])
    chk("H1 estimate == label spread - model spread",
        near(g("H1"), lab - mod, 1e-3),
        sprintf("H1 = %.6f, label - model = %.6f", g("H1"), lab - mod))
  }
})

# --- 2. Every printed rate must equal its own events / person-hours ---------
# The defect this catches: a single denominator macro printed in three rows.
local({
  rc <- rd("08_event_rate_reconciliation")
  if (is.null(rc)) { chk("event-rate arithmetic", NA); return() }
  bad <- rc[, {
    implied <- 1000 * n_events / person_hours
    .(ok = near(implied, events_per_1k_person_h, 1e-3), implied = implied)
  }, by = .(variant, source)][ok == FALSE]
  chk("every event rate == 1000 * events / person-hours", nrow(bad) == 0L,
      paste(capture.output(print(bad)), collapse = "\n        "))
})

# --- 3. The eICU labelled count must reconcile with the scored count --------
local({
  ls8 <- rd("08_eicu_label_summary"); ev <- rd("08_external_validation_results")
  if (is.null(ls8) || is.null(ev)) { chk("eICU onsets vs scored events", NA); return() }
  for (v in c("A", "B", "C")) {
    lab <- as.numeric(ls8[variant == v & anchor == "sepsis3", n_onsets][1])
    sc  <- as.numeric(ev[variant == v & model == "pred_sepsis", n_events][1])
    if ("n_onsets_beyond_panel" %in% names(ev)) {
      beyond <- as.numeric(ev[variant == v & model == "pred_sepsis", n_onsets_beyond_panel][1])
      chk(sprintf("eICU %s: labelled == scored + beyond-panel", v),
          near(lab, sc + beyond, 0.5),
          sprintf("labelled %g, scored %g, beyond-panel %g", lab, sc, beyond))
    } else {
      chk(sprintf("eICU %s: labelled vs scored gap is recorded", v), FALSE,
          sprintf("labelled %g, scored %g, and stage 08 records no reason",
                  lab, sc))
    }
  }
  # No labelled onset may vanish for an unrecorded reason.
  if ("n_events_dropped_na" %in% names(ev))
    chk("no eICU onset hour is dropped for a missing prediction",
        all(ev$n_events_dropped_na == 0, na.rm = TRUE),
        "a labelled onset hour carries no prediction; it is silently unscored")
})

# --- 4. H2's counts must agree across the three files that report them ------
local({
  fl <- rd("12_h2_coefficient_stability"); bk <- rd("12_h2_stability_by_kind")
  un <- rd("12_h2_stability_uncertainty")
  if (is.null(fl) || is.null(bk)) { chk("H2 counts", NA); return() }
  n_unstable <- sum(fl$sign_flip | fl$mag_flip)
  chk("H2 by-kind unstable total == flagged count",
      sum(bk$n_unstable) == n_unstable,
      sprintf("by-kind sums to %d, flags give %d", sum(bk$n_unstable), n_unstable))
  chk("H2 by-kind term total == covariate count",
      sum(bk$n_terms) == nrow(fl),
      sprintf("by-kind sums to %d terms, stability table has %d",
              sum(bk$n_terms), nrow(fl)))
  if (!is.null(un))
    chk("H2 uncertainty diagnostic covers every flagged covariate",
        nrow(un) == n_unstable,
        sprintf("%d flagged, %d in the diagnostic", n_unstable, nrow(un)))
})

# --- 5. The cohort ladder must be monotone and must sum -------------------
local({
  cf <- rd("02_cohort_flow"); lv <- rd("02_label_variance_table")
  if (is.null(cf)) { chk("cohort flow", NA); return() }
  chk("cohort ladder is monotone non-increasing",
      !is.unsorted(rev(cf$n)),
      paste(cf$n, collapse = " -> "))
  ok <- TRUE; det <- ""
  for (i in 2:nrow(cf)) {
    if (!near(cf$n[i], cf$n[i - 1] - cf$n_excluded[i], 0.5)) {
      ok <- FALSE
      det <- sprintf("row %d: %g - %g != %g", i, cf$n[i-1], cf$n_excluded[i], cf$n[i])
    }
  }
  chk("each cohort rung == previous minus its exclusions", ok, det)
  if (!is.null(lv))
    chk("label-variance table uses the final cohort size",
        all(lv$n_stays == cf$n[nrow(cf)]),
        sprintf("cohort ends at %g, label table says %s",
                cf$n[nrow(cf)], paste(unique(lv$n_stays), collapse = ", ")))
})

# --- 6. Panel onsets must never exceed cohort onsets ----------------------
local({
  lv <- rd("02_label_variance_table"); la <- rd("09_label_agreement")
  if (is.null(lv) || is.null(la)) { chk("panel vs cohort onsets", NA); return() }
  ok <- TRUE; det <- character(0)
  for (v in c("A", "C")) {
    coh <- as.numeric(lv[variant == v, n_sepsis_onsets][1])
    pan <- as.numeric(la[variant == v, n_positive][1])
    if (!is.na(coh) && !is.na(pan) && pan > coh) {
      ok <- FALSE
      det <- c(det, sprintf("%s: panel %g > cohort %g", v, pan, coh))
    }
  }
  chk("onsets inside the 72 h panel <= cohort-wide onsets", ok,
      paste(det, collapse = "; "))
})

# --- 7. Family sizes must match the rows actually corrected ---------------
local({
  for (f in c("12_subgroup_auroc_contrasts", "12_subgroup_labelsens_contrasts",
              "12_altlabel_contrasts")) {
    d <- rd(f)
    if (is.null(d) || !("family" %in% names(d))) { chk(paste("family size:", f), NA); next }
    m <- suppressWarnings(as.integer(sub(".*m=([0-9]+).*", "\\1", d$family[1])))
    chk(sprintf("family size declared in %s == nrow", f),
        is.na(m) || m == nrow(d),
        sprintf("declares m=%s, file has %d rows", m, nrow(d)))
  }
})

# --- 8. Combined tables must hold their full variant set ------------------
# Catches a partial pass having truncated a merged table.
local({
  alt <- rd("07_metric_results_altlabel"); cf <- rd("05_coef_all_variants")
  if (!is.null(alt))
    chk("alt-label metrics hold D, E and F",
        all(c("D", "E", "F") %in% unique(alt$variant)),
        sprintf("present: %s", paste(sort(unique(alt$variant)), collapse = ", ")))
  else chk("alt-label metrics hold D, E and F", NA)
  if (!is.null(cf))
    chk("cross-label coefficients hold A, B and C",
        all(c("A", "B", "C") %in% unique(cf$variant)),
        sprintf("present: %s", paste(sort(unique(cf$variant)), collapse = ", ")))
  else chk("cross-label coefficients hold A, B and C", NA)
})

cat("-----------------------------\n")
cat(sprintf("  %d passed, %d failed, %d skipped\n\n", PASS, FAIL, SKIP))
if (FAIL > 0) {
  cat("A failure here means two reported quantities disagree. Fix the source,\n")
  cat("not the check.\n\n")
  quit(status = 1L)
}
