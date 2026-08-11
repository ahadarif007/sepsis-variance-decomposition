#!/usr/bin/env Rscript
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# ===========================================================================
#  check_thesis_margins.R - does anything actually run past the text block?
# ===========================================================================
#
#  Why this exists
#  ---------------
#  LaTeX cannot answer this question for a table. A `tabular` is typeset at its
#  natural width, so there is no target width for it to be overfull *against*:
#  it silently runs past the right margin and `Overfull \hbox` never fires.
#  Round 8 found seven tables and two TikZ diagrams over the margin with zero
#  LaTeX warnings; round 12 found another at 40 pt, on a page an examiner
#  reads early.
#
#  The only reliable check is to measure the built PDF. This script reads the
#  glyph bounding boxes out of `index.pdf`, infers the text block's right edge
#  from the document itself, and reports any page that passes it.
#
#      Rscript check_thesis_margins.R [path/to/index.pdf]
#
#  Exit status 0 = nothing overruns, 1 = at least one page does, 0 with a SKIP
#  notice if `pdftotext` is not installed (it ships with poppler).
# ===========================================================================

TOLERANCE_PT <- 2      # ignore sub-typographic overruns
EXEMPT_PAGES <- c(1L)  # the ATU title page sets its own \newgeometry for the
                       # green left bar, so its text legitimately extends
                       # further right than the body text block.

SCRIPT_DIR <- local({
  a <- commandArgs(trailingOnly = FALSE)
  m <- grep("^--file=", a, value = TRUE)
  if (length(m)) dirname(normalizePath(sub("^--file=", "", m[1]))) else getwd()
})

args <- commandArgs(trailingOnly = TRUE)
PDF <- if (length(args)) args[1] else
  file.path(SCRIPT_DIR, "..", "thesis", "index.pdf")

cat("\nMargin check\n------------\n")

if (!file.exists(PDF)) {
  cat(sprintf("  SKIP  %s not found; build the thesis first\n\n", PDF))
  quit(status = 0L)
}
if (nzchar(Sys.which("pdftotext")) == FALSE) {
  cat("  SKIP  pdftotext not on PATH (install poppler) -- margins unchecked\n\n")
  quit(status = 0L)
}

xml <- suppressWarnings(
  system2("pdftotext", c("-bbox", shQuote(normalizePath(PDF)), "-"),
          stdout = TRUE, stderr = FALSE))
if (!length(xml)) {
  cat("  SKIP  pdftotext produced no output -- margins unchecked\n\n")
  quit(status = 0L)
}

# One <page> element per page; every <word> carries an xMax.
txt   <- paste(xml, collapse = "\n")
parts <- strsplit(txt, "<page ", fixed = TRUE)[[1]]
if (length(parts) < 2L) {
  cat("  SKIP  no page elements found -- margins unchecked\n\n")
  quit(status = 0L)
}
parts <- parts[-1]

page_max <- vapply(parts, function(p) {
  v <- regmatches(p, gregexpr('xMax="([0-9.]+)"', p))[[1]]
  if (!length(v)) return(NA_real_)
  max(as.numeric(sub('xMax="([0-9.]+)"', "\\1", v)))
}, numeric(1), USE.NAMES = FALSE)

body <- page_max[-EXEMPT_PAGES]
body <- body[!is.na(body)]
if (!length(body)) {
  cat("  SKIP  no measurable pages -- margins unchecked\n\n")
  quit(status = 0L)
}

# The right edge of the text block is the value justified body text lands on,
# so it is the *mode* of the per-page maxima, not their mean or median: pages
# ending mid-paragraph pull an average well left of the true edge.
tally <- table(round(body, 1))
edge  <- as.numeric(names(tally)[which.max(tally)])

over <- which(!is.na(page_max) & page_max > edge + TOLERANCE_PT &
              !(seq_along(page_max) %in% EXEMPT_PAGES))

cat(sprintf("  text block right edge: %.1f pt (on %d of %d pages)\n",
            edge, max(tally), length(body)))
cat(sprintf("  pages exempt by design: %s\n",
            paste(EXEMPT_PAGES, collapse = ", ")))

if (!length(over)) {
  cat(sprintf("  ok    no page passes the text block by more than %g pt\n\n",
              TOLERANCE_PT))
  quit(status = 0L)
}

cat(sprintf("\n  FAIL  %d page(s) run past the text block:\n", length(over)))
for (p in over) {
  words <- regmatches(parts[p],
                      gregexpr('xMax="([0-9.]+)"[^>]*>([^<]*)</word>', parts[p]))[[1]]
  wide <- character(0)
  if (length(words)) {
    xm <- as.numeric(sub('xMax="([0-9.]+)".*', "\\1", words))
    wd <- sub('.*>([^<]*)</word>', "\\1", words)
    wide <- unique(wd[xm > edge + TOLERANCE_PT])
  }
  cat(sprintf("        p%-4d %7.1f pt (+%.1f)  %s\n", p, page_max[p],
              page_max[p] - edge,
              paste(utils::head(wide, 5), collapse = " ")))
}
cat("\n  A table is the usual cause, and LaTeX does not warn about it: a\n")
cat("  tabular is set at its natural width, so it has no target width to be\n")
cat("  overfull against. Wrap it as \\adjustbox{max width=\\textwidth}{...},\n")
cat("  which is inert unless the natural width exceeds the text block.\n\n")
quit(status = 1L)
