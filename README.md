# Model, Label, or Analyst? A Variance Decomposition of Real-Time Sepsis Onset Prediction on MIMIC-IV

**Abdul Ahad** · M.Sc. in Computing · Atlantic Technological University (ATU), Galway
Student ID G00486649

---

## What this is

A pre-registered variance-decomposition study of real-time sepsis onset
prediction on MIMIC-IV v3.1, with external validation on eICU-CRD v2.0.

Most of this literature fixes the sepsis label, fixes the train/test split,
reports AUROC, and compares models. This study treats the label, the split, the
prediction-time anchor and the evaluation metric as **variables**, and measures
how much of the reported performance each of them accounts for relative to the
choice of model.

**Research question.** In real-time sepsis onset prediction on MIMIC-IV, how is
performance partitioned between (a) model class and (b) the analyst's
discretionary choices — label operationalisation, temporal versus random split,
prediction-time anchoring, and evaluation metric?

Six hypotheses (H1–H6) were pre-registered before any modelling. Three Sepsis-3
label variants (A Narrow, B Seymour-Standard, C Liberal) are the primary
analysis; three further variants (D, E, F) were added under disclosed protocol
amendments to separate definitional from empirical label variance.

> **This repository contains code only.** No MIMIC-IV or eICU-CRD record,
> derived table, or fitted model is included. The PhysioNet Credentialed Health
> Data Use Agreement prohibits redistribution of the underlying data.

---

## Repository layout

```
RESEARCH/
├── projects/v2/
│   ├── v2-proj/        ← the analysis pipeline (R + Python)
│   ├── v2-thesis/      ← the thesis (LaTeX)
│   ├── v2-lr-rp/       ← companion critical literature review
│   └── feedback/       ← internal development record
└── data/               ← NOT tracked; you supply this (see below)
```

### The pipeline — `projects/v2/v2-proj/`

| File | Role |
|---|---|
| `00_preregistration.md` | The pre-registration, including the G0 analysis gate and Protocol Amendments 1–5, each dated and disclosed as post-hoc |
| `config.R` | **Sole source of truth** for every constant: label-variant parameters, feature lists, plausibility ranges, seeds, bootstrap sizes, multiplicity families, event floors |
| `utils.R` | Shared helpers, including `require_features()` (errors rather than silently dropping a declared predictor) and `check_multinom_fit()` |
| `clinical_scores.R` | SOFA, NEWS2, qSOFA, SIRS |
| `01_setup.Rmd` … `12_inference.Rmd` | The twelve pipeline stages, in execution order |
| `run_pipeline.sh` / `run_pipeline.R` | Orchestration; runs all stages or a named subset |
| `thesis_constants.R` | Reads the result tables and emits every number in the thesis as a LaTeX macro |
| `utility_score.py` | Reference implementation of the PhysioNet Utility Score, maintained as a mirror of the R scoring rule |

| # | Stage | Phase |
|---|---|---|
| 01 | Setup — verify source tables | 1 |
| 02 | Cohort and labels — five variants | 2 |
| 03 | Person-hour panel (streams ~6 GB) | 2 |
| 04 | Sample size (Riley et al.) | 3 |
| 05 | Primary model — multinomial discrete-time competing risks | 4 |
| 06 | Comparators — GBT, Cox, NEWS2/qSOFA/SIRS | 4 |
| 07 | Metrics suite, including the utility threshold sweep | 5 |
| 08 | External validation on eICU-CRD | 6 |
| 09 | Variance decomposition and label-anchor attribution | 7 |
| 10 | Equity analysis | 7 |
| 11 | Clinical metrics — calibration, DCA, operating points, lead time | 8 |
| 12 | Inference — cluster bootstrap, Holm + BH, analysis register | 9 |

---

## Running it

### Prerequisites

- **R 4.5+** with the packages listed in `requirements.txt` /
  `projects/v2/v2-proj/`
- **Python 3.12+** with `pandas` (for the Utility Score mirror only)
- **TeX** providing `xelatex` and `pdflatex` + `biber` (to build the thesis)
- **Both databases**, obtained independently through PhysioNet credentialing:
  - MIMIC-IV v3.1 → `data/mimic-iv-3.1/{hosp,icu}/*.csv.gz`
  - eICU-CRD v2.0 → `data/eicu-collaborative-research-database-2.0/`

`config.R` walks up the tree to locate `data/`; override with the
`MIMIC_RESEARCH_ROOT` environment variable if it lives elsewhere.

### Full run

```bash
cd projects/v2/v2-proj
./run_pipeline.sh
```

Runs stages 01–12 in order and, on success, regenerates the thesis constants
and figures. Roughly 60 minutes end to end; stage 05 dominates, and stage 03
streams about 6 GB.

### Partial runs

```bash
./run_pipeline.sh 10 11 12          # named stages only
Rscript run_pipeline.R --phase 4    # a whole phase
V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07   # restrict the variant loop
V2_ARMS=ablated ./run_pipeline.sh 05 06            # restrict the fitting arm
```

Two cautions, both learned the hard way and documented at the call sites:
stage 07 must always run **unrestricted** (it rewrites the alternative-label
metric table from whatever ran), and stages 05/06 should be restricted with
`V2_VARIANTS` when adding a variant, because gradient-boosted tree fitting is
not bit-stable and an incidental refit moves every GBT number.

### Building the thesis

```bash
cd projects/v2/v2-proj && Rscript thesis_constants.R
cd ../v2-thesis && ./build.sh
```

---

## Reproducibility

Every seed is fixed in `config.R`, and the train/test partition is defined by
admission year rather than by sampling, so it is invariant. A repeated run
reproduces the reported estimates exactly, with one documented exception:
gradient-boosted tree fitting is not bit-reproducible across differing library
builds, so the GBT rows serve as an explicit consistency check on any re-run.

**No result number in the thesis is typed by hand.** `thesis_constants.R` reads
the result tables and writes every reported quantity into
`v2-thesis/pipeline_constants.tex` as a LaTeX macro, which the document
includes; larger tables are generated whole. A quantity the pipeline did not
produce typesets as a conspicuous marker rather than as a stale value, so a
partial run cannot silently leave an outdated number in the text.

---

## Findings in brief

- **Model class dominates discrimination, not the label.** The model-class
  spread is roughly ten times the label spread, and the interval on the
  difference excludes zero — the reverse of the pre-registered hypothesis.
- **An interpretable hazard model matches gradient-boosted trees** to within the
  pre-registered equivalence margin, and is marginally ahead on point
  estimates. This is the strongest positive result in the study.
- **What the label determines is which cohort exists**, not how learnable it is:
  the two narrowest Sepsis-3 readings agree on which stays are septic at
  κ = 0.267 despite near-identical prevalence.
- **The empty pre-treatment window is a property of the onset rule**, not of the
  patients. Under a conjunction onset rule it is a theorem; timed as the
  standard specifies, the same stays yield pre-treatment onsets.
- **No model reaches a deployable operating point.** Swept across the whole
  threshold grid, the utility ceiling sits a few per cent above issuing no
  alerts, at tens of false alerts per true one.

All four testable hypotheses are non-confirmations. Full numbers, intervals and
multiplicity-corrected verdicts are in the thesis.

---

## Ethics and data access

Both databases are de-identified and publicly available to credentialed
researchers under the PhysioNet Credentialed Health Data Use Agreement. This
analysis is retrospective and observational, involves no patient contact and no
intervention, and required no additional ethical approval beyond that
agreement. Its terms — including the prohibition on redistribution and on
attempted re-identification — were observed throughout, and `.gitignore` is
configured so that no patient-derived file can be committed.

## Licence

The pipeline source code written for this study is released under the
**Apache License 2.0** — see [`LICENSE`](LICENSE).

The grant is scoped, and [`NOTICE`](NOTICE) states the boundary in full. In
short:

- **Covered** — everything under `projects/v2/v2-proj/` and
  `projects/v1/v1-project/`, plus the repository documentation. All of it was
  written for this study.
- **Not covered** — the ATU thesis template and brand assets in
  `projects/v2/v2-thesis/` (reproduced only so the thesis will typeset; ATU's
  rights, not mine), and the MIMIC-IV and eICU-CRD databases, which are not in
  this repository and cannot be redistributed under any licence.
- **Thesis text and figures** are scholarly prose, not software. They are
  available for reading, citation and academic reuse with attribution, and are
  not placed under Apache-2.0. Please cite rather than reproduce.
- **Published methods** (SOFA, Sepsis-3 criteria, NEWS2, qSOFA, SIRS, the
  PhysioNet Utility Score, Riley's sample-size criteria, pooled logistic
  regression, decision-curve analysis) are implemented here from their published
  definitions. The implementations are original and Apache-2.0; the methods
  belong to their authors and are cited in `NOTICE` and in the thesis. Nothing
  was copied or adapted from a third party's source.

This is research software. It is not a medical device, has not been validated
for clinical use, and must not be used to inform the care of any patient.
