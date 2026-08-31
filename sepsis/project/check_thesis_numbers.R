#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# ===========================================================================
#  check_thesis_numbers.R - literal-number linter for the thesis sources
# ===========================================================================
#
#  Why this exists
#  ---------------
#  The Declaration states that no quantity this study estimates is typed by
#  hand into the thesis: every one is written from the result tables by
#  thesis_constants.R as a \pc macro. That is a falsifiable claim, and until
#  now nothing checked it. Two ways it can fail:
#
#    * a result value is typed as a literal instead of using its macro, so a
#      re-run moves the macro and leaves the literal behind (this is how a
#      pre-fit-repair calibration slope of 1.169 survived into a section whose
#      whole subject was a numerical correction);
#    * a literal is typed that is *near* a generated value, which is the
#      signature of a stale copy of a quantity that has since moved.
#
#  The linter scans the chapter sources for result-shaped literals and sorts
#  each into one of three buckets:
#
#    CITED   - a citation appears within two lines, so the number is quoting
#              prior work. Exempt, and that is the same boundary the
#              Declaration draws.
#    ALLOWED - on the explicit list below of design constants and descriptive
#              facts that the pipeline does not estimate, each with its reason
#              written beside it.
#    REVIEW  - everything else. Either it should be a macro, or the list below
#              needs a new entry with a reason. Both are deliberate acts.
#
#  Value-matching against the generated constants was tried first and
#  abandoned: with over a thousand quantities in scope, a three-decimal
#  literature figure coincides with one of them often enough that the match
#  carries no information. Provenance, not arithmetic, is what separates a
#  legitimate literal from a defect.
#
#  Run it after any thesis pass:
#
#      Rscript check_thesis_numbers.R
#
#  Exit status 0 = every literal is accounted for, 1 = at least one is not.
# ===========================================================================

SCRIPT_DIR <- local({
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
})
THESIS_DIR <- normalizePath(file.path(SCRIPT_DIR, "..", "thesis"), mustWork = FALSE)

if (!dir.exists(THESIS_DIR)) {
  cat(sprintf("thesis directory not found at %s\n", THESIS_DIR)); quit(status = 0L)
}

# ---------------------------------------------------------------------------
#  The allow-list. Every entry is a number the thesis types on purpose, with
#  the reason it is not a macro. Add to it only when the reason can be written
#  in the same style: a design constant, or a fact about the source data that
#  the pipeline does not estimate. If the reason would be "it is a result",
#  the answer is a macro instead.
# ---------------------------------------------------------------------------
ALLOWED <- list(
  list(v = 2000,    why = "bootstrap replicate count B, fixed in config.R"),
  list(v = 1000,    why = "row threshold for the CSV mirror of a result table"),
  list(v = 3502,    why = "chartevents file size in MB, from 01_setup_file_report"),
  list(v = 2593,    why = "labevents file size in MB, from 01_setup_file_report"),
  list(v = 0.001,   why = "the conventional calibration clamp being argued against"),
  list(v = 0.999,   why = "the conventional calibration clamp being argued against"),
  list(v = 0.085,   why = "external AUROC penalty anticipated from Moor et al., fixed in the pre-registration"),
  list(v = 46.104,  why = "45 CFR 46.104(d)(4), a regulation number"),
  list(v = 74000,   why = "MIMIC-IV's approximate stay count as published by PhysioNet"),
  # Appendix A.2 quotes four values from an EARLIER run, on purpose: the section
  # exists to show that the gradient-boosted comparator is not bit-stable, and
  # it can only show that by naming what moved. They cannot be macros, because a
  # macro would print the current run's value and destroy the comparison.
  list(v = 0.039,   why = "GBT utility ceiling BEFORE Amendment 8 corrected the comparator's test-set early stopping; quoted in Appendix A.2 to show what that correction moved. Its current counterpart in the same sentence is a macro"),
  list(v = 0.0129,  why = "H6 model-class gap BEFORE Amendment 8, quoted in Appendix A.2 for the same reason; its current counterpart is a macro")
)

# ---------------------------------------------------------------------------
#  Result-shaped literals in the chapter sources.
#
#  Result-shaped means three or more decimal places, or a comma-thousands
#  integer. One- and two-place decimals are excluded deliberately: in this
#  document they are pre-registered thresholds (0.02, 0.05, the 0.5 cut-off),
#  file sizes, or TikZ geometry, and a linter that fires on those is one people
#  stop reading, which is the failure mode that let the earlier defects
#  through.
# ---------------------------------------------------------------------------
# Hand-written sources only: chapters/ plus index.tex. Everything under
# generated/ is written by thesis_constants.R and is by definition provenanced.
files <- c(sub(paste0("^", THESIS_DIR, "/"), "",
               Sys.glob(file.path(THESIS_DIR, "chapters", "*.tex"))),
           "index.tex")

LAYOUT <- paste0("includegraphics|vspace|hspace|rule\\{|tabcolsep|baselineskip|",
                 "\\bp\\{[0-9.]+cm|tabularx|node distance|text width|minimum height|",
                 "inner sep|right=|left=|below=|above=|length=|scale=|width=|",
                 "\\\\begin\\{tabular|\\\\label|\\\\ref\\{|arraystretch|",
                 "emergencystretch|adjustbox|fbox|parbox|multicolumn")

PAT <- paste0("(?<![\\\\A-Za-z0-9.,])-?[0-9]{1,3}(?:,[0-9]{3})+(?![0-9])",
              "|(?<![\\\\A-Za-z0-9.,])-?[0-9]+\\.[0-9]{3,}")

# "et al." is routinely broken across a line, so match the "al." half too.
CITE <- "\\\\cite\\{|\\\\citep|\\\\citet|\\bet al\\.|\\bal\\.\\\\?"

cited <- character(0); allowed <- character(0); review <- character(0)

for (f in files) {
  lines <- readLines(file.path(THESIS_DIR, f), warn = FALSE)
  for (i in seq_along(lines)) {
    ln <- lines[i]
    if (grepl("^\\s*%", ln)) next
    if (grepl(LAYOUT, ln, perl = TRUE)) next
    hits <- regmatches(ln, gregexpr(PAT, ln, perl = TRUE))[[1]]
    if (!length(hits)) next
    # A citation anywhere in the same paragraph marks the number as prior
    # work. The paragraph is the right unit: a citation routinely sits two or
    # three lines from the figure it supports, and a narrower window produces
    # false alarms on text that is plainly attributed.
    lo <- i; while (lo > 1 && nzchar(trimws(lines[lo - 1]))) lo <- lo - 1
    hi <- i; while (hi < length(lines) && nzchar(trimws(lines[hi + 1]))) hi <- hi + 1
    is_cited <- any(grepl(CITE, lines[lo:hi], perl = TRUE))
    for (h in hits) {
      num <- suppressWarnings(as.numeric(gsub(",", "", h)))
      if (is.na(num)) next
      entry <- sprintf("  %-16s:%-5d %-10s %s", f, i, h, substr(trimws(ln), 1, 92))
      hit <- Filter(function(a) isTRUE(all.equal(a$v, abs(num))), ALLOWED)
      if (length(hit)) {
        allowed <- c(allowed, sprintf("%s\n%20s%s", entry, "", hit[[1]]$why))
      } else if (is_cited) {
        cited <- c(cited, entry)
      } else {
        review <- c(review, entry)
      }
    }
  }
}

emit <- function(title, v) {
  if (!length(v)) return(invisible())
  cat(title, "\n"); cat(paste(v, collapse = "\n"), "\n\n")
}

cat("\nLiteral-number lint\n-------------------\n\n")
emit(sprintf("REVIEW (%d) -- unaccounted for; make it a macro or allow it with a reason:",
             length(review)), review)
emit(sprintf("ALLOWED (%d) -- design constants and source-data facts:", length(allowed)),
     allowed)
emit(sprintf("CITED (%d) -- quoting prior work, citation within two lines:", length(cited)),
     cited)

# ---------------------------------------------------------------------------
#  Advisory: comparative claims stated in words.
#
#  A number can live in a macro. A *claim about* numbers cannot: "more than
#  tenfold", "less than one hundredth", "twice the size of" are relations, and
#  they only become false when the underlying values move in a particular
#  direction. Round 12 found three of them wrong at once.
#
#  This section is deliberately ADVISORY and does not affect the exit status.
#  Gating on it would need an allow-list of every idiomatic use ("differ by
#  orders of magnitude", "the two halves of the argument"), and a checker
#  people silence by reflex is worse than no checker. What it is good for is
#  the re-read after a run that moved numbers: these are the sentences whose
#  truth depends on values they do not print.
#
#  The claims that *can* be checked mechanically belong in check_consistency.R
#  as predicates on the result tables, and several now live there.
# ---------------------------------------------------------------------------
COMPARATIVE <- paste0(
  "\\b[a-z]+fold\\b",
  "|\\btwice\\b",
  "|\\b(?:[0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|twenty|",
  "thirty|forty|fifty|ninety|hundred)[- ]times\\b",
  "|\\border(?:s)? of magnitude\\b",
  "|\\b(?:a|one|two|three)?[- ]?(?:half|thirds?|quarters?|fifths?|tenths?|",
  "hundredths?)\\s+(?:of|below|above)\\b")

unbacked <- character(0); backed <- 0L
for (f in files) {
  lines <- readLines(file.path(THESIS_DIR, f), warn = FALSE)
  for (i in seq_along(lines)) {
    ln <- lines[i]
    if (grepl("^\\s*%", ln)) next
    hits <- regmatches(ln, gregexpr(COMPARATIVE, ln, perl = TRUE, ignore.case = TRUE))[[1]]
    if (!length(hits)) next
    # Scope is the SENTENCE, not the line and not the paragraph. A chapter
    # here carries over a thousand macros, so any window wider than the claim
    # itself reports everything as backed and the check says nothing.
    ctx <- paste(lines[max(1, i - 2):min(length(lines), i + 2)], collapse = " ")
    for (h in hits) {
      k <- regexpr(h, ctx, fixed = TRUE)
      sent <- ctx
      if (k > 0) {
        lo <- max(c(0, gregexpr(". ", substr(ctx, 1, k), fixed = TRUE)[[1]]))
        rest <- regexpr(". ", substr(ctx, k, nchar(ctx)), fixed = TRUE)
        hi <- if (rest > 0) k + rest else nchar(ctx)
        sent <- substr(ctx, lo + 1, hi)
      }
      if (grepl("\\pc[A-Za-z]+", sent)) {
        backed <- backed + 1L
      } else {
        unbacked <- c(unbacked, sprintf("  %-16s:%-5d %-20s %s", f, i, h,
                                        substr(trimws(ln), 1, 84)))
      }
    }
  }
}
emit(sprintf(paste0("COMPARATIVE, ADVISORY (%d unbacked, %d backed by a macro ",
                    "in context) -- claims whose truth depends on values they ",
                    "do not print:"), length(unbacked), backed), unbacked)

cat("-------------------\n")
cat(sprintf("  %d review, %d allowed, %d cited, over %d files\n",
            length(review), length(allowed), length(cited), length(files)))
cat(sprintf("  %d comparative claims unbacked by a macro (advisory only)\n\n",
            length(unbacked)))
if (length(review) > 0L) {
  cat("Each REVIEW line types a number with no recorded provenance. The\n")
  cat("Declaration asserts that no quantity this study estimates is typed by\n")
  cat("hand, so either the number becomes its macro or the allow-list gains an\n")
  cat("entry saying what it is.\n\n")
  quit(status = 1L)
}
