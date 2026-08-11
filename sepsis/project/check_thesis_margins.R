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
#  glyph bounding boxes out of `index.pdf`, infers the text block from the
#  document itself, and reports any page that passes it.
#
#  Two things this has to get right, both learned by getting them wrong:
#
#    * `book` is TWO-SIDED by default, so odd and even pages have different
#      right edges (the binding offset). A single edge inferred over all pages
#      is whichever parity happened to be more numerous, and the check then
#      passes or fails by luck. Each parity gets its own edge.
#    * The bottom margin needs checking too, and it is the more damaging of the
#      two: a long table inside a [H] float cannot break across pages, so it
#      does not overflow by millimetres, it runs off the sheet. Three did.
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

measure <- function(attr) {
  vapply(parts, function(p) {
    v <- regmatches(p, gregexpr(sprintf('%s="([0-9.]+)"', attr), p))[[1]]
    if (!length(v)) return(NA_real_)
    max(as.numeric(sub(sprintf('%s="([0-9.]+)"', attr), "\\1", v)))
  }, numeric(1), USE.NAMES = FALSE)
}
page_right  <- measure("xMax")
page_bottom <- measure("yMax")
np <- length(parts)
idx <- seq_len(np)

# The edge of the text block is the value justified text lands on, so it is the
# MODE of the per-page maxima, not their mean or median: pages ending
# mid-paragraph pull an average well left of the true edge.
mode_of <- function(v) {
  v <- v[!is.na(v)]
  if (!length(v)) return(NA_real_)
  t <- table(round(v, 1))
  as.numeric(names(t)[which.max(t)])
}

odd  <- setdiff(idx[idx %% 2 == 1], EXEMPT_PAGES)
even <- setdiff(idx[idx %% 2 == 0], EXEMPT_PAGES)
edge_odd  <- mode_of(page_right[odd])
edge_even <- mode_of(page_right[even])
edge_bot  <- mode_of(page_bottom[setdiff(idx, EXEMPT_PAGES)])

cat(sprintf("  right edge: %.1f pt (odd pages), %.1f pt (even pages)\n",
            edge_odd, edge_even))
cat(sprintf("  bottom edge: %.1f pt\n", edge_bot))
cat(sprintf("  pages exempt by design: %s\n", paste(EXEMPT_PAGES, collapse = ", ")))

edge_for <- ifelse(idx %% 2 == 1, edge_odd, edge_even)
over_r <- setdiff(which(!is.na(page_right) &
                        page_right > edge_for + TOLERANCE_PT), EXEMPT_PAGES)
over_b <- setdiff(which(!is.na(page_bottom) &
                        page_bottom > edge_bot + TOLERANCE_PT), EXEMPT_PAGES)

if (!length(over_r) && !length(over_b)) {
  cat(sprintf("  ok    no page passes the text block by more than %g pt\n\n",
              TOLERANCE_PT))
  quit(status = 0L)
}

words_beyond <- function(p, attr, limit) {
  m <- regmatches(parts[p],
                  gregexpr(sprintf('%s="([0-9.]+)"[^>]*>([^<]*)</word>', attr),
                           parts[p]))[[1]]
  if (!length(m)) return(character(0))
  v <- as.numeric(sub(sprintf('.*%s="([0-9.]+)".*', attr), "\\1", m))
  w <- sub(".*>([^<]*)</word>", "\\1", m)
  unique(w[v > limit])
}

if (length(over_r)) {
  cat(sprintf("\n  FAIL  %d page(s) run past the RIGHT edge:\n", length(over_r)))
  for (p in over_r)
    cat(sprintf("        p%-4d %7.1f pt (+%.1f)  %s\n", p, page_right[p],
                page_right[p] - edge_for[p],
                paste(utils::head(words_beyond(p, "xMax", edge_for[p] + TOLERANCE_PT), 5),
                      collapse = " ")))
}
if (length(over_b)) {
  cat(sprintf("\n  FAIL  %d page(s) run past the BOTTOM edge:\n", length(over_b)))
  for (p in over_b)
    cat(sprintf("        p%-4d %7.1f pt (+%.1f)  %s\n", p, page_bottom[p],
                page_bottom[p] - edge_bot,
                paste(utils::head(words_beyond(p, "yMax", edge_bot + TOLERANCE_PT), 6),
                      collapse = " ")))
  cat("\n  A long table inside a [H] float is the usual cause of a bottom\n")
  cat("  overrun: [H] forbids the float from moving and a tabular cannot break\n")
  cat("  across pages, so a table taller than the text block runs off the\n")
  cat("  sheet. Use longtable, which breaks.\n")
}
if (length(over_r)) {
  cat("\n  For a RIGHT overrun a table is the usual cause, and LaTeX does not\n")
  cat("  warn: a tabular is set at its natural width, so it has no target width\n")
  cat("  to be overfull against. Wrap it as \\adjustbox{max width=\\textwidth}{...},\n")
  cat("  which is inert unless the natural width exceeds the text block. A long\n")
  cat("  \\texttt{} path is the other cause: it cannot hyphenate, so give it\n")
  cat("  \\allowbreak break points.\n")
}
cat("\n")
quit(status = 1L)
