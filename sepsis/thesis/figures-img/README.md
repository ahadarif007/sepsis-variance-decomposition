# figures-img — compiled figures used by the thesis

Generated output. Do not hand-edit; regenerate with:

    python3 figures-src/export_drawio.py --into-figures

`.pdf` is what the chapters `\includegraphics`; `.png` (300 dpi) is for slides,
the screencast and quick review. `drawio/` holds comparison renders when
`export_drawio.py` is run without `--into-figures`.

`fig3.1_consort.pdf` contains cohort counts frozen from the pipeline. If the
pipeline is re-run, see `figures-src/README.md` before trusting it.
