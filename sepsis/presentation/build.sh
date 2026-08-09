#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Pass 1: initial compile ==="
pdflatex -interaction=nonstopmode index.tex || true

echo "=== Pass 2: bibliography ==="
biber index || true

echo "=== Pass 3: resolve references ==="
pdflatex -interaction=nonstopmode index.tex || true

echo "=== Pass 4: final ==="
pdflatex -interaction=nonstopmode index.tex

# clean build artifacts
rm -f index.aux index.bbl index.bcf index.blg index.lof index.log index.lot \
      index.out index.run.xml index.toc index.nav index.snm index.vrb \
      texput.log \
      abstract.aux acknowledgments.aux conclusion.aux design.aux \
      evaluation.aux introduction.aux methodology.aux review.aux

echo "Done → index.pdf"
