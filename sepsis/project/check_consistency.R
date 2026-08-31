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

# --- 8. The analysis register must have one row per analysis --------------
# The thesis states that the register is written by the inference stage from
# the objects it corrects, and reproduces it as a table. A duplicated row makes
# the printed table and the machine-readable file disagree on how many analyses
# the study ran, which is the one thing the register exists to settle. Stage 12
# once added the Amendment 7 diagnostic twice; this is the assertion that would
# have caught it.
local({
  reg <- rd("12_analysis_register")
  if (is.null(reg)) { chk("analysis register", NA); return() }
  dup <- reg[duplicated(analysis), unique(analysis)]
  chk("no analysis name appears twice in the register", length(dup) == 0L,
      sprintf("duplicated: %s", paste(dup, collapse = "; ")))
  # Two rows under different names reporting into the same table are the same
  # analysis registered twice, which the name check cannot see. Stage 12 added
  # the Amendment 7 diagnostic as both "H2 instability uncertainty diagnostic"
  # and "H2 instability vs. estimation noise (Amendment 7)", and the printed
  # table in the thesis has one row where the file had two.
  dst <- reg[duplicated(reported_in), unique(reported_in)]
  chk("no two register rows report into the same table", length(dst) == 0L,
      sprintf("shared destination: %s -- rows: %s",
              paste(dst, collapse = "; "),
              paste(reg[reported_in %in% dst, analysis], collapse = " | ")))
  chk("every register row carries a status",
      all(reg$status %in% c("confirmatory", "exploratory", "descriptive")),
      sprintf("unexpected status values: %s",
              paste(setdiff(unique(reg$status),
                            c("confirmatory", "exploratory", "descriptive")),
                    collapse = ", ")))
})

# --- 9. Comparative claims the thesis states in words ---------------------
# The generator guarantees that a number in the thesis is the number the
# pipeline produced. It cannot check a sentence *about* those numbers, and
# round 12 found four defects of exactly that kind: a gap described as "less
# than one hundredth" that was 0.0142, a ratio described as twentyfold that was
# eleven, two counts that summed to seven against a stated total of six, and an
# emphasis on sign reversals that the uncertainty diagnostic does not support.
#
# Each check below is a claim the thesis makes in words, written as a predicate
# on the result tables. If a re-run makes one of these sentences false, this is
# what says so. Add one whenever a chapter asserts a relation rather than a
# value.
local({
  fl <- rd("12_h2_coefficient_stability"); un <- rd("12_h2_stability_uncertainty")
  if (is.null(fl)) { chk("H2 count arithmetic", NA) } else {
    n_sign <- sum(fl$sign_flip); n_mag <- sum(fl$mag_flip)
    n_both <- sum(fl$sign_flip & fl$mag_flip)
    n_unst <- sum(fl$sign_flip | fl$mag_flip)
    # conclusion.tex: "N reverse sign and M change magnitude ... which is why
    # the two counts sum to seven across six covariates".
    chk("H2: sign + magnitude - overlap == unstable total",
        n_sign + n_mag - n_both == n_unst,
        sprintf("%d + %d - %d != %d", n_sign, n_mag, n_both, n_unst))
    chk("H2: exactly one covariate meets both criteria", n_both == 1L,
        sprintf("%d covariates meet both; the prose says one", n_both))
  }
  # evaluation.tex sec:h2_uncertainty: "Those that do not clear the threshold
  # include ... both sign reversals: bilirubin and vasopressor exposure carry
  # the two smallest ratios in the table."
  if (!is.null(fl) && !is.null(un) && "z_ratio" %in% names(un)) {
    flipped <- sub("TRUE$", "", fl[sign_flip == TRUE, term])
    uterm   <- sub("TRUE$", "", un$term)
    two_smallest <- uterm[order(un$z_ratio)][seq_len(min(2L, nrow(un)))]
    chk("H2: the two smallest noise ratios are the two sign reversals",
        setequal(two_smallest, flipped),
        sprintf("smallest ratios: %s; sign reversals: %s",
                paste(two_smallest, collapse = ", "), paste(flipped, collapse = ", ")))
    chk("H2: no sign reversal exceeds its own pooled SE",
        all(un[uterm %in% flipped, z_ratio] < 1),
        sprintf("ratios for sign reversals: %s",
                paste(round(un[uterm %in% flipped, z_ratio], 2), collapse = ", ")))
  }
})

local({
  sp <- rd("12_spread_ci")
  if (is.null(sp)) { chk("model spread vs label spread", NA); return() }
  lab <- as.numeric(sp[quantity == "label", estimate][1])
  mod <- as.numeric(sp[quantity == "model", estimate][1])
  # conclusion.tex "more than tenfold"; evaluation.tex and discussion.tex
  # "roughly an order of magnitude".
  chk("model-class spread is at least tenfold the label spread",
      !is.na(lab) && !is.na(mod) && lab > 0 && mod / lab >= 10,
      sprintf("model %.4f / label %.4f = %.1fx, and the thesis says tenfold",
              mod, lab, mod / lab))
})

local({
  um <- rd("07_utility_max")
  if (is.null(um)) { chk("utility ceiling", NA); return() }
  pre <- um[variant %in% c("A", "B", "C") & eval_window == "unrestricted" &
              split_type == "temporal"]
  if (!nrow(pre)) { chk("utility ceiling", NA); return() }
  top <- pre[which.max(utility_normalised)]
  # abstract.tex: "no model exceeds <GbtB> under the primary label, or <GbtC>
  # under any pre-registered variant". Both halves are asserted here.
  chk("utility ceiling over pre-registered variants is GBT under Variant C",
      top$model == "gbt" && top$variant == "C",
      sprintf("highest is %s/%s at %.4f", top$model, top$variant,
              top$utility_normalised))
  b <- pre[variant == "B"][which.max(utility_normalised)]
  chk("utility ceiling under the primary label is GBT under Variant B",
      b$model == "gbt",
      sprintf("highest under B is %s at %.4f", b$model, b$utility_normalised))
})

local({
  um <- rd("07_utility_max")
  if (is.null(um)) { chk("burden range over positive maxima", NA); return() }
  u <- um[eval_window == "unrestricted" & split_type == "temporal" &
          variant %in% c("A", "B", "C") &
          as.numeric(utility_normalised) > 0 & is.finite(as.numeric(alert_burden))]
  if (!nrow(u)) { chk("burden range over positive maxima", NA); return() }
  lo <- u[which.min(as.numeric(alert_burden))]
  hi <- u[which.max(as.numeric(alert_burden))]
  # evaluation.tex, sec:utility_threshold: "Every maximum that is positive at
  # all is attained at between <primary/C> and <GBT/B> false alerts per true
  # alert, twenty to thirty-seven times the benchmark." Both endpoints are
  # named by macro and the multiples are typed, so a refit can falsify the
  # sentence without touching a number in it.
  chk("burden range endpoints are primary/C and GBT/B",
      identical(as.character(lo$model), "primary") && identical(as.character(lo$variant), "C") &&
      identical(as.character(hi$model), "gbt")     && identical(as.character(hi$variant), "B"),
      sprintf("min %s/%s at %.2f; max %s/%s at %.2f",
              lo$model, lo$variant, as.numeric(lo$alert_burden),
              hi$model, hi$variant, as.numeric(hi$alert_burden)))
  # 1.4 is Moor et al.'s benchmark. Written literally rather than read from
  # config.R, because this script deliberately reads only files on disk: its
  # job is to check outputs against each other, not against the configuration
  # that produced them.
  mult <- range(as.numeric(u$alert_burden)) / 1.4
  chk("burden range is twenty to thirty-seven times the benchmark",
      mult[1] >= 20 && mult[1] < 21 && mult[2] >= 36 && mult[2] < 38,
      sprintf("multiples run %.1fx to %.1fx", mult[1], mult[2]))
})

local({
  am <- rd("07_ablation_metrics")
  if (is.null(am)) { chk("ablation bound", NA); return() }
  d <- abs(as.numeric(am$delta_auroc))
  w <- am[which.max(d)]
  # evaluation.tex, sec:ablation: the largest ablation cost "for either model
  # under any variant" is quoted by macro, and the macro names a specific
  # model/variant cell. If the extreme moves, the sentence points at the wrong
  # cell while still typesetting a real number.
  chk("largest ablation |delta AUROC| is primary under Variant C",
      identical(as.character(w$model), "primary") && identical(as.character(w$variant), "C"),
      sprintf("largest is %s/%s at %.4f", w$model, w$variant, as.numeric(w$delta_auroc)))
  chk("every ablation |delta AUROC| is below 0.01",
      all(d < 0.01), sprintf("max |delta| = %.4f", max(d)))
})

# --- Protocol Amendment 10: the three claims the new intervals now carry -----
local({
  ac <- rd("12_ablation_ci")
  if (is.null(ac) || !nrow(ac)) { chk("ablation interval claims", NA); return() }
  tf <- function(x) x %in% c(TRUE, "TRUE")
  n_excl <- sum(tf(ac$excludes_zero))
  # evaluation.tex, sec:ablation: the prose now says the ablation cost is small
  # but REAL, and quotes the count of contrasts excluding zero as a macro. If
  # every interval came to cover zero the sentence would be arguing against
  # itself, and the macro alone would not say so.
  chk("at least one ablation contrast excludes zero",
      n_excl > 0, sprintf("%d of %d exclude zero", n_excl, nrow(ac)))
  chk("no ablation |delta AUROC| interval reaches 0.01 in magnitude",
      all(abs(as.numeric(ac$delta_auroc)) < 0.01),
      sprintf("max |delta| = %.4f", max(abs(as.numeric(ac$delta_auroc)))))
})

local({
  cal <- rd("12_calibration_ci")
  if (is.null(cal) || !nrow(cal)) { chk("absolute calibration claims", NA); return() }
  # evaluation.tex, sec:calibration_results now names WHICH variants cover the
  # absolute targets: slope covers 1 under A and B but not C, intercept covers
  # 0 under C but not A and B. Both are relations a re-run can move, and the
  # paragraph's whole point is that exactly one target is missed per variant.
  g <- function(v, col) suppressWarnings(as.numeric(cal[variant == v][[col]][1]))
  slope_ok <- function(v) g(v, "slope_lo") <= 1 && g(v, "slope_hi") >= 1
  int_ok   <- function(v) g(v, "int_lo")   <= 0 && g(v, "int_hi")   >= 0
  chk("calibration slope covers 1 under A and B but not C",
      slope_ok("A") && slope_ok("B") && !slope_ok("C"),
      paste(sprintf("%s slope [%.3f, %.3f]", cal$variant,
                    as.numeric(cal$slope_lo), as.numeric(cal$slope_hi)), collapse = "; "))
  chk("calibration intercept covers 0 under C but not A and B",
      int_ok("C") && !int_ok("A") && !int_ok("B"),
      paste(sprintf("%s int [%.3f, %.3f]", cal$variant,
                    as.numeric(cal$int_lo), as.numeric(cal$int_hi)), collapse = "; "))
  chk("exactly one absolute calibration target is missed under each variant",
      all(vapply(c("A", "B", "C"),
                 function(v) xor(!slope_ok(v), !int_ok(v)), logical(1))),
      "slope-covers-1 and intercept-covers-0 must differ within each variant")
})

local({
  cc <- rd("12_calibration_contrasts")
  if (is.null(cc) || !nrow(cc)) { chk("calibration contrast claims", NA); return() }
  tf <- function(x) x %in% c(TRUE, "TRUE")
  # evaluation.tex, sec:calibration_results: the paragraph now says the SLOPE
  # contrasts cover zero and that the Liberal INTERCEPT contrast does not. Both
  # halves are relations, not values, so no macro protects either of them.
  chk("no cross-label calibration SLOPE contrast excludes zero",
      !any(tf(cc$slope_excludes_zero)),
      paste(sprintf("%s vs %s: %s", cc$variant, cc$reference, cc$slope_ci), collapse = "; "))
  ci_c <- cc[as.character(variant) == "C"]
  chk("the Liberal calibration INTERCEPT contrast excludes zero",
      nrow(ci_c) == 1 && tf(ci_c$int_excludes_zero),
      if (nrow(ci_c) == 1) sprintf("C vs B intercept %s", ci_c$int_ci) else "no C row")
})

local({
  tr <- rd("12_altlabel_transport_ci")
  if (is.null(tr) || !nrow(tr)) { chk("Variant D transport claims", NA); return() }
  # evaluation.tex, sec:external_altlabel: both drops are said to be "of the
  # order of" Moor et al.'s 0.085. Read here as within a factor of two of it.
  d <- as.numeric(tr$delta_auroc)
  chk("both Variant D transport drops are within a factor of two of 0.085",
      all(d > 0.0425 & d < 0.17),
      paste(sprintf("%s %.4f", tr$model, d), collapse = "; "))

  # evaluation.tex, sec:external_altlabel names the internal AUROC, the external
  # AUROC and the difference as three separate macros drawn from three separate
  # tables. A reader will subtract them. They must agree.
  am <- rd("07_metric_results_altlabel")
  # Two eval_window rows exist per model; the thesis quotes the unrestricted
  # one, which is also what thesis_constants.R filters to for AltAurocFull*.
  if (!is.null(am) && "eval_window" %in% names(am))
    am <- am[eval_window == "unrestricted"]
  ex <- rd("08_external_validation_results_altlabel")
  if (!is.null(am) && !is.null(ex)) {
    ok <- TRUE; detail <- character(0)
    for (i in seq_len(nrow(tr))) {
      mm <- as.character(tr$model[i])
      pc <- if (mm == "primary") "pred_sepsis" else "pred_gbt"
      ai <- suppressWarnings(as.numeric(am[variant == "D" & model == mm, auroc][1]))
      ae <- suppressWarnings(as.numeric(ex[variant == "D" & model == pc, auroc][1]))
      if (is.na(ai) || is.na(ae)) next
      good <- abs((ai - ae) - as.numeric(tr$delta_auroc[i])) < 5e-4
      ok <- ok && good
      detail <- c(detail, sprintf("%s: %.4f - %.4f = %.4f vs delta %.4f",
                                  mm, ai, ae, ai - ae, as.numeric(tr$delta_auroc[i])))
    }
    chk("Variant D transport delta equals internal minus external AUROC",
        ok, paste(detail, collapse = "; "))
  }
})

local({
  ct <- rd("12_confirmatory_tests")
  if (is.null(ct) || !nrow(ct)) { chk("H6 limb claims", NA); return() }
  h6 <- ct[as.character(hypothesis) == "H6"]
  if (!nrow(h6) || !"p_limb_lower" %in% names(h6)) { chk("H6 limb claims", NA); return() }
  # evaluation.tex, sec:h6: the section now says the LOWER limb is the
  # informative one and that neither limb clears its boundary. Both follow from
  # the sign of the estimate, which a re-run can move.
  chk("H6's lower limb is the smaller of the two",
      as.numeric(h6$p_limb_lower) <= as.numeric(h6$p_limb_upper),
      sprintf("upper %.3f, lower %.3f",
              as.numeric(h6$p_limb_upper), as.numeric(h6$p_limb_lower)))
  chk("neither H6 limb clears its boundary at 0.05",
      as.numeric(h6$p_limb_lower) >= 0.05 && as.numeric(h6$p_limb_upper) >= 0.05,
      sprintf("upper %.3f, lower %.3f",
              as.numeric(h6$p_limb_upper), as.numeric(h6$p_limb_lower)))
})

local({
  ab <- rd("08_external_validation_results_abxonly")
  if (is.null(ab) || !nrow(ab)) { chk("abx-only model ordering", NA); return() }
  g <- ab[model == "pred_gbt",   .(variant, gbt   = as.numeric(auroc))]
  n <- ab[model == "pred_news2", .(variant, news2 = as.numeric(auroc))]
  p <- ab[model == "pred_sepsis",.(variant, prim  = as.numeric(auroc))]
  m <- merge(merge(g, n, by = "variant"), p, by = "variant")
  # discussion.tex, sec:external_interpretability: in the antibiotic-only arm a
  # bedside score "ranks ahead of the boosted model under the two narrower
  # labels and level with it under the Liberal one", and the primary model
  # stays ahead of NEWS2 throughout. Amendment 8 refits GBT, so both relations
  # can change and neither is protected by a macro.
  chk("abx-only arm: NEWS2 is not below GBT under any label",
      all(m$news2 >= m$gbt),
      paste(sprintf("%s: news2 %.4f vs gbt %.4f", m$variant, m$news2, m$gbt),
            collapse = "; "))
  chk("abx-only arm: the primary model leads NEWS2 under every label",
      all(m$prim > m$news2),
      paste(sprintf("%s: primary %.4f vs news2 %.4f", m$variant, m$prim, m$news2),
            collapse = "; "))
})

local({
  sct <- rd("12_subgroup_auroc_contrasts")
  if (is.null(sct) || !nrow(sct)) { chk("E1 smallest-q contrast", NA); return() }
  top <- sct[order(as.numeric(p_bh), as.numeric(p_raw))][1]
  # evaluation.tex, sec:equity: "The smallest adjusted value in the family
  # belongs to a contrast on insurance rather than on race", and the paragraph
  # after it names that contrast. Both sentences become false if a re-run moves
  # the ordering, and neither is protected by a macro on its own.
  chk("smallest adjusted p in family E1 is an insurance contrast",
      identical(as.character(top$subgroup_col), "insurance"),
      sprintf("smallest q is %s/%s at q = %.3f",
              top$subgroup_col, top$subgroup_val, as.numeric(top$p_bh)))
  # Same section: "No contrast is significant, on race or on any other
  # variable." The table caption states it for the whole family, not just race.
  chk("no contrast in family E1 survives BH",
      !any(sct$significant_bh %in% c(TRUE, "TRUE")),
      sprintf("%d of %d contrasts flagged significant",
              sum(sct$significant_bh %in% c(TRUE, "TRUE")), nrow(sct)))
})

local({
  la <- rd("09_label_agreement")
  if (is.null(la)) { chk("kappa ordering", NA); return() }
  ka <- as.numeric(la[variant == "A", kappa_vs_B][1])
  kc <- as.numeric(la[variant == "C", kappa_vs_B][1])
  # abstract, conclusion: "the two narrowest readings agree at ONLY kappa=...".
  # The "only" depends on A-vs-B being the lower of the two Sepsis-3 pairings.
  chk("kappa(A,B) is the lower of the two Sepsis-3 pairings",
      !is.na(ka) && !is.na(kc) && ka < kc,
      sprintf("kappa(A,B) = %.3f, kappa(C,B) = %.3f", ka, kc))
})

# --- 10. Combined tables must hold their full variant set -----------------
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
