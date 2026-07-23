#!/usr/bin/env bash
# run_pipeline.sh
# Run all numbered Rmd scripts in the pipeline in order.
# Each Rmd is rendered to PDF and the full R log is captured.
#
# Usage:
#   ./run_pipeline.sh              # render all numbered Rmds
#   ./run_pipeline.sh 01 02 03     # render only matching prefixes
#   ./run_pipeline.sh --phase 2    # render by phase group (see PHASES below)
#
# Output:
#   PDF reports   → output/
#   Full run log  → pipeline_run.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOG_FILE="${SCRIPT_DIR}/pipeline_run.log"
mkdir -p "$OUTPUT_DIR"

# ---------------------------------------------------------------------------
# Phase groupings (mirrors run_pipeline.R phases)
# ---------------------------------------------------------------------------
phase_scripts() {
  case "$1" in
    1) echo "01" ;;
    2) echo "02 03" ;;
    3) echo "07" ;;
    4) echo "08 09" ;;
    5) echo "10" ;;
    6) echo "11" ;;
    7) echo "12 13" ;;
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
echo "  V2 Pipeline — ${START_TS}" | tee -a "$LOG_FILE"
echo "  Scripts: ${RMD_FILES[*]}" | tee -a "$LOG_FILE"
echo "  Output:  ${OUTPUT_DIR}/" | tee -a "$LOG_FILE"
echo "======================================================" | tee -a "$LOG_FILE"

SUCCESS=0
FAILED=0
FAILED_LIST=()

for rmd in "${RMD_FILES[@]}"; do
  base="${rmd%.Rmd}"
  pdf_out="${OUTPUT_DIR}/${base}.pdf"
  step_log="${OUTPUT_DIR}/${base}.log"

  echo "" | tee -a "$LOG_FILE"
  echo "── $(date '+%H:%M:%S')  Rendering: ${rmd} ──" | tee -a "$LOG_FILE"

  T0=$(date +%s)

  if Rscript --vanilla -e "
    setwd('${SCRIPT_DIR}')
    rmarkdown::render(
      input      = '${rmd}',
      output_dir = '${OUTPUT_DIR}',
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
    echo "  FAILED  (${ELAPSED}s)  — see ${step_log}" | tee -a "$LOG_FILE"
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
# ---------------------------------------------------------------------------
find "$SCRIPT_DIR" -maxdepth 1 -name '*.Rmd.tmp' -delete 2>/dev/null
find "$OUTPUT_DIR" -maxdepth 1 -name '*.html' -delete 2>/dev/null

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
echo "  PDF reports: ${OUTPUT_DIR}/" | tee -a "$LOG_FILE"
echo "  Full log:     ${LOG_FILE}" | tee -a "$LOG_FILE"
echo "======================================================" | tee -a "$LOG_FILE"

[ $FAILED -eq 0 ] || exit 1
