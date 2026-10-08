#!/bin/bash
# Builds the defence deck. Every result number on the slides is a \pc macro
# from the thesis's generated constants, and every figure is the thesis's own,
# so both are re-copied from ../thesis before each build and the deck can never
# drift from the document it presents.
set -e
cd "$(dirname "$0")"
THESIS=../thesis

echo "=== Sync from thesis ==="
mkdir -p generated images
cp "$THESIS/generated/pipeline_constants.tex"   generated/
cp "$THESIS/bibliography/references.bib"        references.bib
for f in 07_utility_threshold_sweep.png 09_label_anchor_attribution.png \
         atu-logo-green.png atu-logo-navy.png atu-logo-teal.png; do
  cp "$THESIS/images/$f" images/
done
for f in fig2.2_label_variance_concept.pdf fig3.1_consort.pdf \
         fig4.1_pipeline_dag.pdf; do
  cp "$THESIS/figures-img/$f" images/
done

echo "=== Pass 1: initial compile ==="
pdflatex -interaction=nonstopmode index.tex || true

echo "=== Pass 2: bibliography ==="
biber index || true

echo "=== Pass 3: resolve references ==="
pdflatex -interaction=nonstopmode index.tex || true

echo "=== Pass 4: final ==="
pdflatex -interaction=nonstopmode index.tex

# A macro the pipeline did not produce typesets as a red ?? (\pcMissing).
if grep -q "pcMissing" generated/pipeline_constants.tex && \
   grep -qE "Undefined control sequence" index.log; then
  echo "WARNING: undefined control sequence in the deck"; fi
grep -E "Undefined control sequence|Citation .* undefined" index.log || true

# clean build artifacts
rm -f index.aux index.bbl index.bcf index.blg index.lof index.log index.lot \
      index.out index.run.xml index.toc index.nav index.snm index.vrb \
      texput.log

echo "Done → index.pdf"
