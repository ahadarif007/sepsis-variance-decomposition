#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# run_pipeline.R: Master pipeline runner for V2
#
# Usage:
#   Rscript run_pipeline.R [--phase 0-7] [--variant A|B|C|all]
#
# Phases:
#   0: Pre-registration check (00_preregistration.md)
#   1: Setup verification       (01_setup.Rmd)
#   2: Cohort + person-hours    (02_cohort_labels.Rmd + 03_person_hours.Rmd)
#   3: Sample size              (04_sample_size.Rmd)
#   4: Models                   (05_primary_model.Rmd + 06_comparators.Rmd)
#   5: Evaluation               (07_metrics_suite.Rmd)
#   6: External validation      (08_external_validation.Rmd)
#   7: Variance decomp + equity (09_variance_decomposition.Rmd + 10_equity_analysis.Rmd)
#   8: Clinical utility metrics (11_clinical_metrics.Rmd)
#   9: Inference + multiplicity  (12_inference.Rmd)
#   all: run all phases sequentially
#
# Phase 9 attaches cluster-bootstrap intervals to every point estimate and
# applies the multiplicity corrections described in 00_preregistration.md §13.
# It reads only the parquet outputs of earlier phases, so it can be re-run on
# its own. Set V2_BOOT_B=50 for a fast smoke test (results are not reportable).

suppressPackageStartupMessages({
  library(data.table)
  library(rmarkdown)
})

script_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) normalizePath(".")
)

source(file.path(script_dir, "config.R"))
source(file.path(script_dir, "utils.R"))

args <- commandArgs(trailingOnly = TRUE)
requested_phase <- if (any(grepl("--phase", args))) {
  phase_arg <- args[grep("--phase", args) + 1]
  if (phase_arg == "all") "all" else as.integer(phase_arg)
} else "all"

v2_log("======================================================")
v2_log("  V2 Sepsis Prediction Pipeline: Model, Label, or Analyst?")
v2_log("======================================================")
v2_log(sprintf("Project root: %s", PROJECT_ROOT))
v2_log(sprintf("Output dir:   %s", OUTPUT_DIR))
v2_log(sprintf("Requested phase: %s", requested_phase))
v2_log("Label variants: A (Narrow), B (Seymour-Standard), C (Liberal)")

render_rmd <- function(script, out_dir = PDF_DIR) {
  path <- file.path(script_dir, script)
  if (!file.exists(path)) {
    v2_log(sprintf("Script not found: %s", path), level = "ERROR")
    return(invisible(FALSE))
  }
  v2_log(sprintf("\n--- Rendering %s ---", script))
  t_start <- proc.time()
  tryCatch(
    rmarkdown::render(
      input       = path,
      output_dir  = out_dir,
      output_file = sub("\\.Rmd$", ".pdf", basename(path)),
      quiet       = TRUE,
      envir       = new.env(parent = globalenv())
    ),
    error = function(e) {
      v2_log(sprintf("ERROR rendering %s: %s", script, e$message), level = "ERROR")
      if (getOption("v2_stop_on_error", default = FALSE)) stop(e)
    }
  )
  elapsed <- proc.time() - t_start
  v2_log(sprintf("  %s rendered in %.1f seconds.", script, elapsed["elapsed"]))
  invisible(TRUE)
}

run_phase <- function(phase_num) {
  phase_scripts <- list(
    `1` = "01_setup.Rmd",
    `2` = c("02_cohort_labels.Rmd", "03_person_hours.Rmd"),
    `3` = "04_sample_size.Rmd",
    `4` = c("05_primary_model.Rmd", "06_comparators.Rmd"),
    `5` = "07_metrics_suite.Rmd",
    `6` = "08_external_validation.Rmd",
    `7` = c("09_variance_decomposition.Rmd", "10_equity_analysis.Rmd"),
    `8` = "11_clinical_metrics.Rmd",
    `9` = "12_inference.Rmd"
  )

  scripts <- phase_scripts[[as.character(phase_num)]]
  if (is.null(scripts)) {
    v2_log(sprintf("Phase %d not found", phase_num), level = "ERROR")
    return(invisible(FALSE))
  }
  for (script in scripts) render_rmd(script)
  invisible(TRUE)
}

# Phase 0: Pre-registration check
v2_log("\n=== Phase 0: Pre-registration check ===")
prereg_path <- file.path(script_dir, "00_preregistration.md")
if (file.exists(prereg_path)) {
  v2_log("[OK] 00_preregistration.md exists: protocol is locked.")
} else {
  v2_log("[BLOCKING] 00_preregistration.md not found. Create and lock protocol before modelling.",
         level = "ERROR")
  stop("G0 gate: pre-registration document required before modelling.")
}

# Run requested phases
if (requested_phase == "all") {
  for (ph in 1:9) run_phase(ph)
} else {
  run_phase(as.integer(requested_phase))
}

# Cleanup temporary files
tmp_files <- list.files(script_dir, pattern = "\\.Rmd\\.tmp$", full.names = TRUE)
if (length(tmp_files) > 0) {
  file.remove(tmp_files)
  v2_log(sprintf("Cleaned up %d .Rmd.tmp files", length(tmp_files)))
}
html_files <- list.files(PDF_DIR, pattern = "\\.html$", full.names = TRUE)
if (length(html_files) > 0) {
  file.remove(html_files)
  v2_log(sprintf("Cleaned up %d stale .html files from output/pdf/", length(html_files)))
}
tex_files <- list.files(script_dir, pattern = "\\.tex$", full.names = TRUE)
if (length(tex_files) > 0) {
  file.remove(tex_files)
  v2_log(sprintf("Cleaned up %d stray .tex files from project root", length(tex_files)))
}
tex_out <- list.files(PDF_DIR, pattern = "\\.tex$", full.names = TRUE)
if (length(tex_out) > 0) {
  file.remove(tex_out)
  v2_log(sprintf("Cleaned up %d stray .tex files from output/pdf/", length(tex_out)))
}
stray_logs <- list.files(script_dir, pattern = "\\.log$", full.names = TRUE)
if (length(stray_logs) > 0) {
  file.remove(stray_logs)
  v2_log(sprintf("Cleaned up %d stray .log files from project root", length(stray_logs)))
}

# Regenerate the thesis constants file and sync figures, so the LaTeX document
# tracks pipeline output instead of hardcoding it (HANDOFF section 4).
tc <- file.path(script_dir, "thesis_constants.R")
if (file.exists(tc)) {
  v2_log("Regenerating thesis constants...")
  st <- system2("Rscript", tc, stdout = TRUE, stderr = TRUE)
  v2_log(paste(st, collapse = "\n"))
}

# Figure 3.1 (CONSORT) is a .drawio file, and a .drawio cannot hold a macro, so
# its eleven cohort counts are frozen literals generated from the constants.
# Every other number in the thesis re-derives itself on a run; that one cannot,
# so it is refreshed here rather than left to be remembered. Mirrors the block
# in run_pipeline.sh.
consort_gen <- file.path(script_dir, "..", "thesis", "figures-src",
                         "make_consort_drawio.py")
export_fig  <- file.path(script_dir, "..", "thesis", "figures-src",
                         "export_drawio.py")
if (file.exists(consort_gen)) {
  v2_log("Checking frozen figure assets...")
  fresh <- system2("python3", c(shQuote(consort_gen), "--check"),
                   stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(fresh, "status")) && attr(fresh, "status") != 0) {
    v2_log("  Figure 3.1 is STALE against this run; regenerating...")
    system2("python3", shQuote(consort_gen), stdout = TRUE, stderr = TRUE)
    ex <- system2("python3", c(shQuote(export_fig), "--into-figures"),
                  stdout = TRUE, stderr = TRUE)
    if (!is.null(attr(ex, "status")) && attr(ex, "status") != 0) {
      v2_log(paste0("  [WARN] Figure 3.1's source was regenerated but could not ",
                    "be re-exported; the thesis would print stale counts inside ",
                    "an image. Install draw.io and re-run export_drawio.py ",
                    "--into-figures."), level = "WARN")
    } else {
      v2_log("  Figure 3.1 regenerated and re-exported; rebuild the thesis.")
    }
  } else {
    v2_log("  OK  Figure 3.1 still matches the pipeline constants.")
  }
}

v2_log("\n======================================================")
v2_log("  Pipeline complete.")
v2_log(sprintf("  Results and PDF reports in: %s", OUTPUT_DIR))
v2_log("======================================================")
