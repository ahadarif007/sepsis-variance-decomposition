# figures-src — editable sources for the hand-drawn figures

Pipeline-generated figures do **not** live here. Those are written into
`project/output/figures/` and synced to `images/` by `thesis_constants.R`.
Never hand-edit one and never copy one into this folder.

## draw.io is the source of truth

All four hand-drawn figures are `.drawio` files. The thesis includes the
exported PDFs; there is no TikZ left, so there is exactly one place to edit.

    figures-src/fig3.1_consort.drawio          (edit here)
        │  python3 figures-src/export_drawio.py --into-figures
        ▼
    figures-img/fig3.1_consort.pdf             (generated)
        │  \includegraphics in chapters/06.Methodology.tex
        ▼
    index.pdf

| Figure | Source | Included by |
|---|---|---|
| 2.1 PRISMA-style flow | `fig2.1_prisma.drawio` | `05.Review.tex` |
| 2.2 Label variance | `fig2.2_label_variance_concept.drawio` | `05.Review.tex` |
| 3.1 CONSORT flow | `fig3.1_consort.drawio` (**generated**) | `06.Methodology.tex` |
| 4.1 Pipeline DAG | `fig4.1_pipeline_dag.drawio` | `07.Design.tex` |

## Editing a figure

1. Open the `.drawio` in draw.io.
2. Edit and save.
3. `python3 figures-src/export_drawio.py --into-figures`
4. `./build.sh`

Without step 3 the thesis keeps showing the old image.

Type is set in **Times New Roman** so figures match the thesis body, which is
Computer Modern (pdflatex's default; no font package is loaded). Font sizes are
tuned so that labels land near footnote size once the image is scaled into the
text block. Keep both if you add shapes, or the new element will read as
foreign.

## Figure 3.1 carries frozen numbers, and that is checkable

Figure 3.1 was drawn from eleven `\pc` macros — `\pcConsortNTotal`,
`\pcConsortNExclNotFirst`, `\pcConsortNFirstStay`, `\pcConsortNExclLos`,
`\pcConsortNFinal`, `\pcNOnsetsA/B/C`, `\pcPctOnsetsA/B/C`. A `.drawio` cannot
hold a macro, so those counts are now frozen literals. This was accepted because
pipeline execution is frozen.

Two things keep it honest:

**The numbers are generated, not typed.** `make_consort_drawio.py` reads them
out of `generated/pipeline_constants.tex`, so the diagram provably matches the
run behind it.

    python3 figures-src/make_consort_drawio.py          # regenerate
    python3 figures-src/make_consort_drawio.py --check  # detect staleness

**Staleness fails loudly.** `--check` compares all eleven frozen values against
the current constants and exits non-zero if any moved. **If the pipeline is ever
re-run, run `--check`, then regenerate and re-export.** This is the one hazard
the draw.io conversion introduces; it is detectable rather than silent, but it
is not automatic.

Note that regenerating overwrites any manual layout changes made to
`fig3.1_consort.drawio` in draw.io. Change the generator, not the output.

## Scripts

| Script | Does |
|---|---|
| `export_drawio.py` | renders `.drawio` → PDF + PNG. `--into-figures` writes into `figures-img/` (what the thesis uses); without it, into `figures-img/drawio/` for comparison |
| `make_consort_drawio.py` | regenerates Figure 3.1 from the pipeline constants; `--check` detects staleness |

Both need the draw.io desktop app at `/Applications/draw.io.app`
(`brew install --cask drawio`).
