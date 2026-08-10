#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Abdul Ahad
# run_pipeline.sh
# Run all numbered Rmd scripts in the pipeline in order.
# Each Rmd is rendered to PDF and the full R log is captured.
#
# Usage:
#   ./run_pipeline.sh              # render all numbered Rmds
#   ./run_pipeline.sh 01 02 03     # render only matching prefixes
#   ./run_pipeline.sh --phase 2    # render by phase group (see PHASES below)
#
# Environment:
#   V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07
#     Restricts the per-variant loops in stages 02-07 to the named label
#     variants. Use it to add or refresh a variant without refitting the
#     others: XGBoost is not bit-stable across runs, so an incidental refit of
#     A/B/C would silently move every GBT-dependent number in the thesis.
#     Unset (the default) runs every variant.
#
# Output:
#   PDF reports   → output/
#   Full run log  → pipeline_run.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"
PDF_DIR="${OUTPUT_DIR}/pdf"
LOG_FILE="${LOG_DIR}/pipeline_run.log"
mkdir -p "$LOG_DIR" "$PDF_DIR" "${OUTPUT_DIR}/figures" "${OUTPUT_DIR}/processed_data"

# ---------------------------------------------------------------------------
# Phase groupings (mirrors run_pipeline.R phases)
# ---------------------------------------------------------------------------
phase_scripts() {
  case "$1" in
    1) echo "01" ;;
    2) echo "02 03" ;;
    3) echo "04" ;;
    4) echo "05 06" ;;
    5) echo "07" ;;
    6) echo "08" ;;
    7) echo "09 10" ;;
    *) echo "Unknown phase: $1" >&2; exit 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Collect which Rmd files to run
# ---------------------------------------------------------------------------
cd "$SCRIPT_DIR"

PREFIXES=()

if [[ $# -gt 0 && "$1" == "--phase" ]]; then
  shift
  for ph in "$@"; do
    for prefix in $(phase_scripts "$ph"); do
      PREFIXES+=("$prefix")
    done
  done
elif [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    PREFIXES+=("$arg")
  done
else
  # Auto-discover all numbered Rmds
  for f in [0-9][0-9]_*.Rmd; do
    [ -f "$f" ] && PREFIXES+=("${f%%_*}")
  done
fi

# Deduplicate, preserve order
PREFIXES=($(printf '%s\n' "${PREFIXES[@]}" | awk '!seen[$0]++'))

# Resolve prefixes → actual Rmd files
RMD_FILES=()
for prefix in "${PREFIXES[@]}"; do
  found=false
  for f in ${prefix}_*.Rmd; do
    if [ -f "$f" ]; then
      RMD_FILES+=("$f")
      found=true
      break
    fi
  done
  if ! $found; then
    echo "WARNING: no Rmd found for prefix ${prefix}" >&2
  fi
done

if [ ${#RMD_FILES[@]} -eq 0 ]; then
  echo "No Rmd files to render." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Pre-registration gate
# ---------------------------------------------------------------------------
if [ ! -f "${SCRIPT_DIR}/00_preregistration.md" ]; then
  echo "ERROR: 00_preregistration.md not found." >&2
  echo "Create and lock the pre-registration document before running models." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
START_TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "======================================================" | tee "$LOG_FILE"
echo "  V2 Pipeline: ${START_TS}" | tee -a "$LOG_FILE"
echo "  Scripts: ${RMD_FILES[*]}" | tee -a "$LOG_FILE"
echo "  Output:  ${OUTPUT_DIR}/" | tee -a "$LOG_FILE"
echo "======================================================" | tee -a "$LOG_FILE"

SUCCESS=0
FAILED=0
FAILED_LIST=()

for rmd in "${RMD_FILES[@]}"; do
  base="${rmd%.Rmd}"
  pdf_out="${PDF_DIR}/${base}.pdf"
  step_log="${LOG_DIR}/${base}.log"

  echo "" | tee -a "$LOG_FILE"
  echo "── $(date '+%H:%M:%S')  Rendering: ${rmd} ──" | tee -a "$LOG_FILE"

  T0=$(date +%s)

  if Rscript --vanilla -e "
    setwd('${SCRIPT_DIR}')
    rmarkdown::render(
      input      = '${rmd}',
      output_dir = '${PDF_DIR}',
      output_file = '${base}.pdf',
      quiet      = FALSE,
      envir      = new.env(parent = globalenv())
    )
  " > "${step_log}" 2>&1; then
    T1=$(date +%s)
    ELAPSED=$(( T1 - T0 ))
    echo "  OK  ${pdf_out}  (${ELAPSED}s)" | tee -a "$LOG_FILE"
    SUCCESS=$(( SUCCESS + 1 ))
  else
    T1=$(date +%s)
    ELAPSED=$(( T1 - T0 ))
    echo "  FAILED  (${ELAPSED}s): see ${step_log}" | tee -a "$LOG_FILE"
    # Show last 20 lines of R error to terminal
    echo "  Last error output:" | tee -a "$LOG_FILE"
    tail -20 "${step_log}" | tee -a "$LOG_FILE"
    FAILED=$(( FAILED + 1 ))
    FAILED_LIST+=("$rmd")
  fi

  # Append step log into the master log
  echo "" >> "$LOG_FILE"
  echo "---- R log: ${rmd} ----" >> "$LOG_FILE"
  cat "${step_log}" >> "$LOG_FILE"
done

# ---------------------------------------------------------------------------
# Cleanup temporary / stale files
#
# xelatex writes its .log into the working directory, and tinytex only keeps it
# when the LaTeX run emitted warnings, which is why stray logs appeared for
# some scripts and not others. The R logs we care about are already in
# output/logs/, so the LaTeX build artefacts are removed here (mirrors the
# cleanup block in run_pipeline.R).
# ---------------------------------------------------------------------------
find "$SCRIPT_DIR" -maxdepth 1 -name '*.Rmd.tmp' -delete 2>/dev/null
find "$PDF_DIR" -maxdepth 1 -name '*.html' -delete 2>/dev/null
for ext in log tex aux toc out; do
  find "$SCRIPT_DIR" -maxdepth 1 -name "*.${ext}" -delete 2>/dev/null
  find "$PDF_DIR"    -maxdepth 1 -name "*.${ext}" -delete 2>/dev/null
done
find "$SCRIPT_DIR" -maxdepth 1 -name '*.knit.md' -delete 2>/dev/null

# ---------------------------------------------------------------------------
# Thesis alignment
#
# Regenerate ../thesis/pipeline_constants.tex from the result tables and
# sync output/figures -> ../thesis/images. This is what keeps the thesis
# from drifting away from the pipeline (HANDOFF section 4). Skipped when a
# stage failed, because half-written results would produce a constants file
# that looks authoritative but is not.
# ---------------------------------------------------------------------------
CONSTANTS_INCOMPLETE=0
INCONSISTENT=0
if [ $FAILED -eq 0 ]; then
  echo "" | tee -a "$LOG_FILE"
  echo "Regenerating thesis constants..." | tee -a "$LOG_FILE"
  # thesis_constants.R exits non-zero when a macro or a generated table body is
  # unresolved. That is a real problem -- it means the PDF would carry a red ??
  # -- but it is NOT a pipeline failure, and under `set -euo pipefail` an
  # unguarded non-zero here would abort the script before it printed the
  # summary of a run that actually succeeded. Capture it and report it below.
  if Rscript "$SCRIPT_DIR/thesis_constants.R" 2>&1 | tee -a "$LOG_FILE"; then
    CONSTANTS_INCOMPLETE=0
  else
    CONSTANTS_INCOMPLETE=1
  fi

  # Cross-file arithmetic. The macro system guarantees a number is the one the
  # pipeline produced; it cannot check that two numbers which must agree do.
  echo "" | tee -a "$LOG_FILE"
  echo "Checking cross-file consistency..." | tee -a "$LOG_FILE"
  if Rscript "$SCRIPT_DIR/check_consistency.R" 2>&1 | tee -a "$LOG_FILE"; then
    INCONSISTENT=0
  else
    INCONSISTENT=1
  fi
else
  echo "" | tee -a "$LOG_FILE"
  echo "Skipping thesis-constants regeneration (a stage failed)." | tee -a "$LOG_FILE"
  echo "Run 'Rscript thesis_constants.R' by hand once the run is clean." | tee -a "$LOG_FILE"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
END_TS=$(date '+%Y-%m-%d %H:%M:%S')
echo "" | tee -a "$LOG_FILE"
echo "======================================================" | tee -a "$LOG_FILE"
echo "  Done: ${SUCCESS} succeeded, ${FAILED} failed  [${END_TS}]" | tee -a "$LOG_FILE"
if [ ${#FAILED_LIST[@]} -gt 0 ]; then
  echo "  FAILED: ${FAILED_LIST[*]}" | tee -a "$LOG_FILE"
fi
echo "  PDF reports: ${PDF_DIR}/" | tee -a "$LOG_FILE"
echo "  Full log:     ${LOG_FILE}" | tee -a "$LOG_FILE"
if [ $CONSTANTS_INCOMPLETE -ne 0 ]; then
  echo "" | tee -a "$LOG_FILE"
  echo "  !! Every stage succeeded, but the thesis constants are INCOMPLETE." | tee -a "$LOG_FILE"
  echo "     Some macros or table bodies are unresolved; the generator output" | tee -a "$LOG_FILE"
  echo "     above lists them. Run thesis/build.sh to see which of them a" | tee -a "$LOG_FILE"
  echo "     chapter actually references -- those are the ones that would put" | tee -a "$LOG_FILE"
  echo "     a red ?? on a page, and build.sh refuses on them." | tee -a "$LOG_FILE"
fi
if [ $INCONSISTENT -ne 0 ]; then
  echo "" | tee -a "$LOG_FILE"
  echo "  !! Cross-file consistency checks FAILED. Two reported quantities" | tee -a "$LOG_FILE"
  echo "     disagree; see the check output above. Fix the source, not the check." | tee -a "$LOG_FILE"
fi

echo "======================================================" | tee -a "$LOG_FILE"

[ $FAILED -eq 0 ] || exit 1
[ $CONSTANTS_INCOMPLETE -eq 0 ] || exit 2
[ $INCONSISTENT -eq 0 ] || exit 3
