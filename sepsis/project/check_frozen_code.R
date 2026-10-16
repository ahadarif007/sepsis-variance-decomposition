#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# ===========================================================================
#  check_frozen_code.R - confirm that no code producing a reported quantity
#  changed between two repository states
# ===========================================================================
#
#  Usage (from the repository root):
#    Rscript sepsis/project/check_frozen_code.R frozen-2026-08-31 submission-2026-10-16
#
#  Two checks are made, and nothing else is claimed:
#
#   1. Every R code chunk of the twelve pipeline notebooks
#      (sepsis/project/NN_*.Rmd), header line included, is compared as text.
#      Narrative text outside the chunks is not compared.
#   2. Every other file that computes or writes a reported quantity, or fixes
#      the software environment, is compared byte for byte by its git blob
#      hash. Tools that only check the thesis or draw its diagrams are out of
#      scope.
#
#  Prints one line per file and exits with status 0 only if all are identical.
#  Uses base R and git only.

PROJECT <- "sepsis/project"
EXECUTED_FILES <- file.path(PROJECT, c(
  "config.R", "utils.R", "clinical_scores.R", "run_pipeline.R",
  "run_pipeline.sh", "freeze.sh", "thesis_constants.R", "check_consistency.R",
  "utility_score.py", "install_requirements.R", "requirements.txt",
  "requirements-python.txt"
))

git <- function(...) {
  out <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(out, "status"))) return(NULL)
  out
}

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  stop("usage: Rscript sepsis/project/check_frozen_code.R <from-ref> <to-ref>")
}
refs <- args
for (r in refs) {
  sha <- git("rev-parse", "--verify", "--quiet", paste0(r, "^{commit}"))
  if (is.null(sha)) stop(sprintf("not a commit in this repository: %s", r))
  cat(sprintf("%-24s %s\n", r, sha))
}
cat("\n")

r_chunks <- function(lines) {
  keep <- logical(length(lines))
  inside <- FALSE
  for (i in seq_along(lines)) {
    if (!inside && grepl("^\\s*```\\{r", lines[i])) {
      inside <- TRUE
      keep[i] <- TRUE
    } else if (inside) {
      keep[i] <- TRUE
      if (grepl("^\\s*```\\s*$", lines[i])) inside <- FALSE
    }
  }
  lines[keep]
}

notebooks <- function(ref) {
  files <- git("ls-tree", "-r", "--name-only", "--full-tree", ref)
  grep(sprintf("^%s/[0-9]{2}_[^/]*\\.Rmd$", PROJECT), files, value = TRUE)
}

failures <- 0L
report <- function(ok, what, path) {
  cat(sprintf("%-9s %-14s %s\n", if (ok) "identical" else "DIFFERS", what, path))
  if (!ok) failures <<- failures + 1L
}

nbs <- sort(union(notebooks(refs[1]), notebooks(refs[2])))
if (length(nbs) == 0) stop("no pipeline notebooks found")
for (nb in nbs) {
  a <- git("show", paste0(refs[1], ":", nb))
  b <- git("show", paste0(refs[2], ":", nb))
  ok <- !is.null(a) && !is.null(b) && identical(r_chunks(a), r_chunks(b))
  report(ok, "R chunks", nb)
}

for (f in EXECUTED_FILES) {
  a <- git("rev-parse", "--verify", "--quiet", paste0(refs[1], ":", f))
  b <- git("rev-parse", "--verify", "--quiet", paste0(refs[2], ":", f))
  ok <- !is.null(a) && !is.null(b) && identical(a, b)
  report(ok, "whole file", f)
}

cat("\n")
if (failures > 0) {
  cat(sprintf("FAIL: %d file(s) differ.\n", failures))
  quit(status = 1)
}
cat(sprintf("OK: %d notebooks and %d executed files are identical.\n",
            length(nbs), length(EXECUTED_FILES)))
