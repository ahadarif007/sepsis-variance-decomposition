#!/bin/bash
cd "$(dirname "$0")"

pdflatex -interaction=nonstopmode index.tex
biber index
pdflatex -interaction=nonstopmode index.tex
pdflatex -interaction=nonstopmode index.tex

# clean build artifacts
rm -f index.aux index.bbl index.bcf index.blg index.lof index.log index.lot \
      index.out index.run.xml index.toc \
      abstract.aux acknowledgments.aux appendix.aux conclusion.aux design.aux \
      declaration.aux \
      discussion.aux evaluation.aux introduction.aux methodology.aux review.aux

echo "Done → index.pdf"
