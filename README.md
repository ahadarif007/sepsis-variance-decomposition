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
discretionary choices: label operationalisation, temporal versus random split,
prediction-time anchoring, and evaluation metric?

Six hypotheses (H1–H6) were pre-registered before any of the modelling reported
here. Three Sepsis-3
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
├── sepsis/
│   ├── project/        ← the analysis pipeline (R + Python)
│   └── thesis/         ← the thesis (LaTeX)
└── data/               ← NOT tracked; you supply this (see below)
```

The working documents for the project (the engineering handoff, the review
rounds and the companion critical literature review) are deliberately not
tracked here. They are development records rather than part of the submission.

### The pipeline: `sepsis/project/`

| File | Role |
|---|---|
| `00_preregistration.md` | The pre-registration, including the G0 analysis gate and Protocol Amendments 1–8, each dated and disclosed as post-hoc |
| `config.R` | **Sole source of truth** for every constant: label-variant parameters, the covariate vector, plausibility ranges, seeds, bootstrap sizes, multiplicity families, event floors. `check_model_features()` turns a stored model whose columns disagree with it into an error rather than a wrong number |
| `utils.R` | Shared helpers, including `require_features()` (errors rather than silently dropping a declared predictor) and `check_multinom_fit()` |
| `clinical_scores.R` | SOFA, NEWS2, qSOFA, SIRS |
| `01_setup.Rmd` … `12_inference.Rmd` | The twelve pipeline stages, in execution order |
| `run_pipeline.sh` / `run_pipeline.R` | Orchestration; runs all stages or a named subset |
| `thesis_constants.R` | Reads the result tables and emits every number in the thesis as a LaTeX macro |
| `utility_score.py` | Reference implementation of the PhysioNet Utility Score, maintained as a mirror of the R scoring rule |
| `check_consistency.R` | Cross-file assertions over the generated result tables. A failure means two reported quantities disagree |
| `check_thesis_numbers.R` | Literal-number linter for the thesis sources. Fails on any result-shaped number typed without recorded provenance |
| `check_thesis_margins.R` | Measures the built PDF for anything running past the text block, which LaTeX does not warn about for tables |

| # | Stage | Phase |
|---|---|---|
| 01 | Setup: verify source tables | 1 |
| 02 | Cohort and labels, six variants (A--F) | 2 |
| 03 | Person-hour panel (streams ~6 GB) | 2 |
| 04 | Sample size (Riley et al.) | 3 |
| 05 | Primary model: multinomial discrete-time competing risks | 4 |
| 06 | Comparators: GBT, Cox, NEWS2/qSOFA/SIRS | 4 |
| 07 | Metrics suite, including the utility threshold sweep | 5 |
| 08 | External validation on eICU-CRD | 6 |
| 09 | Variance decomposition and label-anchor attribution | 7 |
| 10 | Equity analysis | 7 |
| 11 | Clinical metrics: calibration, DCA, operating points, lead time | 8 |
| 12 | Inference: cluster bootstrap, Holm + BH, analysis register | 9 |

---

## Running it

### Prerequisites

- **R 4.5+** with the packages listed in `sepsis/project/requirements.txt`,
  which pins the version each dependency was at when the reported results were
  produced. Check or install them with:

  ```bash
  cd sepsis/project
  Rscript install_requirements.R --check   # report only
  Rscript install_requirements.R           # install what is missing
  ```
- **Python 3.14** with `pandas` 3.0.4 (for the Utility Score mirror only),
  pinned in `sepsis/project/requirements-python.txt`. pandas 3.x is required:
  the script depends on its CSV datetime behaviour
- **TeX** providing `xelatex` and `pdflatex` + `biber` (to build the thesis)
- **Both databases**, obtained independently through PhysioNet credentialing:
  - MIMIC-IV v3.1 → `data/mimic-iv-3.1/{hosp,icu}/*.csv.gz`
  - eICU-CRD v2.0 → `data/eicu-collaborative-research-database-2.0/`

`config.R` walks up the tree to locate `data/`; override with the
`MIMIC_RESEARCH_ROOT` environment variable if it lives elsewhere.

### Full run

```bash
cd sepsis/project
./run_pipeline.sh
```

Runs stages 01–12 in order and, on success, regenerates the thesis constants
and figures. **About 2 h 30 m end to end** on a 2023 MacBook Pro; stage 05
(~73 min, nine model fits) and stage 12 (~19 min, the bootstrap) dominate, and
stage 03 streams about 6 GB. Per-stage wall-clock, measured from the run that
produced the reported results:

| Stage | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| min | <1 | 3 | 16 | <1 | 73 | 9 | 2 | 16 | <1 | <1 | 15 | 19 |

### Partial runs

```bash
./run_pipeline.sh 10 11 12          # named stages only
Rscript run_pipeline.R --phase 4    # a whole phase
V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07   # restrict the variant loop
V2_ARMS=ablated ./run_pipeline.sh 05 06            # restrict the fitting arm
```

One caution, learned the hard way: stages 05/06 should be restricted with
`V2_VARIANTS` when adding a variant, because gradient-boosted tree fitting is
not bit-stable and an incidental refit moves every GBT number. Stage 07's
alternative-label table used to be overwritten from whatever ran, so a partial
pass silently deleted the other variants' rows; it now merges, carrying forward
any variant not in the current run and logging that it did so.

### Building the thesis

```bash
cd sepsis/project && Rscript thesis_constants.R
cd ../thesis && ./build.sh
```

`build.sh` refuses to produce a PDF in which any macro a chapter references is
unresolved, because such a macro typesets as a conspicuous red marker on the
page.

### Checking it

Three read-only checks, none of which runs the pipeline. **All three are
wired in**: `run_pipeline.sh` runs the first two after regenerating the thesis
constants, and `build.sh` runs the third on the PDF it has just produced. Run
them by hand only after editing the thesis without re-running anything:

```bash
cd sepsis/project
Rscript check_consistency.R       # cross-file arithmetic + claim predicates
Rscript check_thesis_numbers.R    # literal provenance over the thesis sources
Rscript check_thesis_margins.R    # does anything pass the text block
```

The first asserts identities that must hold between tables written by different
stages: a printed rate against its own numerator and denominator, a
decomposition row against the hypothesis estimate it duplicates, the external
labelled event count against the scored one, the cohort ladder's arithmetic. It
also holds the **claim predicates**: sentences the thesis states in words,
written as assertions on the result tables, so that a re-run which makes one of
them false says so.

The second sorts every result-shaped number typed in the thesis into *cited*
(quoting prior work), *allow-listed* (a design constant or a fact about the
source data, each with its reason recorded) or *unaccounted for*, and fails on
the third.

The third measures the built PDF, because LaTeX cannot: a table is set at its
natural width, so it has no target width to be overfull against and runs past
the right margin without a warning.

Together they cover the gap the generator cannot reach. It guarantees that a
number in the thesis is the number the pipeline produced; it cannot check that
two numbers which must agree do, that a number was not typed beside a macro
instead of as one, or that what was typeset fits on the page.

`run_pipeline.sh` exit codes: **1** a stage failed, **2** a macro or generated
table body is unresolved, **3** a consistency check failed, **4** the thesis
types a result-shaped number with no recorded provenance.

---

## Reproducibility

Every seed is fixed in `config.R`, and the train/test partition is defined by
admission year rather than by sampling, so it is invariant. A repeated run
reproduces the reported estimates exactly, with one documented exception:
gradient-boosted tree fitting is not bit-reproducible across differing library
builds, so the GBT rows serve as an explicit consistency check on any re-run.

**No quantity this study estimates is typed by hand into the thesis.** The
exceptions are figures quoted from prior work, thresholds fixed by the
pre-registration, and prose roundings of a macro stated exactly in the adjacent
table. `thesis_constants.R` reads
the result tables and writes every reported quantity into
`sepsis/thesis/generated/pipeline_constants.tex` as a LaTeX macro, which the document
includes; larger tables are generated whole. A quantity the pipeline did not
produce typesets as a conspicuous marker rather than as a stale value, so a
partial run cannot silently leave an outdated number in the text.

---

## Findings in brief

- **Model class dominates discrimination, not the label.** The model-class
  spread is an order of magnitude larger than the label spread, and the interval on the
  difference excludes zero. That is the reverse of the pre-registered
  hypothesis.
- **An interpretable hazard model is not outperformed by gradient-boosted
  trees.** The trees are not better by more than the pre-registered 0.02
  margin, and the interval on the difference lies wholly below zero, so the
  interpretable model is ahead rather than merely not behind. This is
  non-inferiority rather than two-sided equivalence, because the interval
  extends past the margin on the side that favours the interpretable model. It
  is the strongest positive result in the study, and the lead is small enough
  that the Utility Score orders the two models the other way round.
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
agreement. Its terms, including the prohibition on redistribution and on
attempted re-identification, were observed throughout, and `.gitignore` is
configured so that no patient-derived file can be committed.

## Licence

The pipeline source code written for this study is released under the
**Apache License 2.0**. See [`LICENSE`](LICENSE).

The grant is scoped, and [`NOTICE`](NOTICE) states the boundary in full. In
short:

- **Covered**: everything under `sepsis/project/`, plus the repository
  documentation. All of it was written for this study.
- **Not covered**: the ATU thesis template and brand assets in
  `sepsis/thesis/` (reproduced only so the thesis will typeset; ATU's
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
