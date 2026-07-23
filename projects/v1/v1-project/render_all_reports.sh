#!/usr/bin/env bash
# render_all_reports.sh
# Knit every Rmd in this directory into reports/ (PDF + log).
#
# Usage:
#   ./render_all_reports.sh              # render all Rmds
#   ./render_all_reports.sh 06 09 20     # render only matching prefixes

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/reports"
mkdir -p "$REPORT_DIR"

cd "$SCRIPT_DIR"

# Collect Rmd files (all or filtered by prefix args).
if [ $# -eq 0 ]; then
    RMD_FILES=(*.Rmd)
else
    RMD_FILES=()
    for prefix in "$@"; do
        for f in ${prefix}*.Rmd; do
            [ -f "$f" ] && RMD_FILES+=("$f")
        done
    done
fi

if [ ${#RMD_FILES[@]} -eq 0 ]; then
    echo "No Rmd files found."
    exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║  Rendering ${#RMD_FILES[@]} Rmd file(s) → reports/              ║"
echo "╚══════════════════════════════════════════════════════╝"

SUCCESS=0
FAILED=0

for rmd in "${RMD_FILES[@]}"; do
    base="${rmd%.Rmd}"
    pdf_out="${REPORT_DIR}/${base}.pdf"
    log_out="${REPORT_DIR}/${base}.log"

    echo ""
    echo "── Rendering: ${rmd} ──"

    # Knit with R; capture both R output and LaTeX log.
    if Rscript -e "
        rmarkdown::render(
            '${rmd}',
            output_dir = '${REPORT_DIR}',
            output_file = '${base}.pdf',
            clean = FALSE,
            quiet = FALSE
        )
    " > "${log_out}" 2>&1; then
        echo "  ✓ ${pdf_out}"

        # Append the LaTeX .log if it was generated (bookdown leaves it).
        tex_log="${base}.log"
        if [ -f "$tex_log" ] && [ "$tex_log" != "$log_out" ]; then
            echo "" >> "${log_out}"
            echo "════ LaTeX log ════" >> "${log_out}"
            cat "$tex_log" >> "${log_out}"
        fi

        SUCCESS=$((SUCCESS + 1))
    else
        echo "  ✗ FAILED — see ${log_out}"
        FAILED=$((FAILED + 1))
    fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Done: ${SUCCESS} succeeded, ${FAILED} failed"
echo "  Output: ${REPORT_DIR}/"
echo "════════════════════════════════════════════════════════"

# Clean up intermediate .tex files left by bookdown.
rm -f *.tex 2>/dev/null || true
