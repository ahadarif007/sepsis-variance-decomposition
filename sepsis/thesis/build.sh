#!/bin/bash
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Refuse to build a PDF that would carry visible placeholders.
#
# thesis_constants.R emits \pcMissing (a bold red ??) for any quantity the
# pipeline did not produce. That mechanism worked as designed and was then
# ignored: a committed index.pdf carried thirteen red ?? across two chapters
# and a table whose entire body was one placeholder, because nothing stopped
# the build. Now something does. Set V2_ALLOW_MISSING=1 for a deliberate draft.
# ---------------------------------------------------------------------------
#
# Only a macro a chapter actually *uses* can put a ?? on a page. An unresolved
# macro that nothing references is a pipeline note, not a document defect, and
# blocking on it would train everyone to pass V2_ALLOW_MISSING=1 by reflex --
# which is how the placeholders got into a committed PDF in the first place.
# So: referenced-and-unresolved blocks, unreferenced-and-unresolved warns.
if [ -z "${V2_ALLOW_MISSING:-}" ]; then
  CHAPTERS=$(ls ./chapters/*.tex ./index.tex 2>/dev/null)
  BLOCKING=""
  UNUSED=""
  for m in $(grep -o 'newcommand{\\pc[A-Za-z]*}{\\pcMissing}' generated/pipeline_constants.tex 2>/dev/null |
             sed 's/newcommand{\\\(pc[A-Za-z]*\)}{.*/\1/'); do
    # Trailing guard so \pcHTwoZMin does not match \pcHTwoZMinRobust.
    if grep -qE "\\\\${m}([^A-Za-z]|$)" $CHAPTERS 2>/dev/null; then
      BLOCKING="$BLOCKING $m"
    else
      UNUSED="$UNUSED $m"
    fi
  done

  PLACEHOLDER_TABLES=$(grep -l '\\pcMissing' ./generated/table_*.tex 2>/dev/null)

  if [ -n "$UNUSED" ]; then
    echo "NOTE: unresolved macros that no chapter references (harmless in the PDF):"
    for m in $UNUSED; do echo "  \\$m"; done
    echo ""
  fi

  if [ -n "$BLOCKING" ] || [ -n "$PLACEHOLDER_TABLES" ]; then
    echo "REFUSING TO BUILD — these WOULD typeset as a red ?? on the page:"
    for m in $BLOCKING; do echo "  \\$m"; done
    for t in $PLACEHOLDER_TABLES; do echo "  $t (generated table body is a placeholder)"; done
    echo ""
    echo "Re-run the producing stage, or set V2_ALLOW_MISSING=1 for a draft build."
    exit 1
  fi
fi

pdflatex -interaction=nonstopmode index.tex
biber index
pdflatex -interaction=nonstopmode index.tex
pdflatex -interaction=nonstopmode index.tex

# ---------------------------------------------------------------------------
# Report before cleaning. The log is deleted below, so anything not surfaced
# here is invisible -- which is how a document with undefined references could
# be built and committed without anyone seeing a warning.
# ---------------------------------------------------------------------------
count_in_log() { grep -acE "$1" index.log 2>/dev/null | head -1 || true; }
N_ERR=$(count_in_log '^! ')
N_REF=$(count_in_log 'Reference .* undefined')
N_CIT=$(count_in_log 'Citation .* undefined')
N_ERR=${N_ERR:-0}; N_REF=${N_REF:-0}; N_CIT=${N_CIT:-0}
N_PAGE=$(grep -aoE 'Output written on index\.pdf \([0-9]+ pages' index.log 2>/dev/null | grep -oE '[0-9]+' | head -1)
# pdfTeX writes its own warnings, and they are not LaTeX errors, so nothing
# above catches them. A duplicated PDF destination means two objects claim one
# anchor and a link silently goes to the wrong one; 53 of them went unnoticed
# because this line did not exist.
N_DUP=$(grep -ac 'destination with the same identifier' index.log 2>/dev/null || true)
N_DUP=${N_DUP:-0}
echo ""
echo "------------------------------------------------------------"
echo "  Pages: ${N_PAGE:-?}   Errors: $N_ERR   Undefined refs: $N_REF   Undefined citations: $N_CIT   Duplicate PDF destinations: $N_DUP"
if [ "$N_DUP" -gt 0 ]; then
  echo "  !! $N_DUP duplicate PDF destination(s). Two objects claim one anchor,"
  echo "     so a link resolves to the wrong one. Usual cause: a package that"
  echo "     hyperref must patch (float, longtable) loaded AFTER hyperref."
  grep -ao 'name{[A-Za-z0-9._]*}) has been already used' index.log | sort -u | head -5 | sed 's/^/     /'
fi
if [ "$N_ERR" -gt 0 ] || [ "$N_REF" -gt 0 ] || [ "$N_CIT" -gt 0 ]; then
  echo "  !! Not clean. Offending lines:"
  grep -aE '^! |Reference .* undefined|Citation .* undefined' index.log | sort -u | sed 's/^/     /' | head -20
fi
echo "------------------------------------------------------------"

# ---------------------------------------------------------------------------
# Measure the PDF. LaTeX cannot answer this one: a tabular is set at its
# natural width, so it has no target width to be overfull against and runs
# past the right margin in silence. Round 8 found nine such objects with zero
# warnings and round 12 found another at 40 pt, so the check is a measurement
# of the built file rather than a reading of the log.
# ---------------------------------------------------------------------------
Rscript ../project/check_thesis_margins.R index.pdf
MARGIN_STATUS=$?

# clean build artifacts
rm -f index.aux index.bbl index.bcf index.blg index.lof index.log index.lot \
      index.out index.run.xml index.toc
rm -f chapters/*.aux generated/*.aux

echo "Done → index.pdf"
exit $MARGIN_STATUS
