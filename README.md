# Quantifying Model, Label, and Methodological Contributions to Variance in Real-Time Sepsis Onset Prediction

Analysis pipeline and thesis source for a pre-registered variance-decomposition
study of real-time sepsis onset prediction.

**Abdul Ahad** · M.Sc. in Computing · Atlantic Technological University (ATU), Galway
Student ID: G00486649

This repository holds the final analysis reported in the submitted M.Sc. thesis.

---

## Overview

This repository contains the code for a pre-registered variance-decomposition
study of real-time sepsis onset prediction on MIMIC-IV v3.1, with external
validation on eICU-CRD v2.0.

Comparative studies in this area usually hold the sepsis definition and the
train/test split fixed, evaluate discrimination by AUROC (area under the ROC
curve), and attribute differences in performance to the choice of model. This
study treats the label definition, the split, the prediction-time anchor and the
evaluation metric as analytical factors, and estimates how much of the
variation in reported performance each accounts for relative to model class.

**Research question.** In real-time sepsis onset prediction on MIMIC-IV, how much
of the variation in reported performance is attributable to model class, and how
much to label operationalisation, temporal versus random split, prediction-time
anchoring and evaluation metric?

Six hypotheses (H1–H6) were pre-registered before the reported models were
fitted. The primary analysis uses three Sepsis-3 label variants: A (Narrow),
B (Seymour-Standard) and C (Liberal). Variants D–F were added through dated
protocol amendments, recorded in `00_preregistration.md`, to separate
definitional from empirical variation in the label. They are analysed
separately from A–C.

> [!IMPORTANT]
> This repository contains code only. No MIMIC-IV or eICU-CRD records, derived
> tables or fitted models are included, and the underlying data cannot be
> redistributed under the PhysioNet data use agreement.

---

## Repository layout

```
sepsis-variance-decomposition/
├── sepsis/
│   ├── project/        ← analysis pipeline (R, plus one Python script)
│   └── thesis/         ← thesis source (LaTeX)
└── data/               ← not tracked; populate after obtaining access (see below)
```

Internal development notes and review records are not included.

### Pipeline files: `sepsis/project/`

| File | Role |
|---|---|
| `00_preregistration.md` | Pre-registration, including the G0 analysis gate and the dated, post-hoc Protocol Amendments 1–10 |
| `config.R` | Central configuration: label parameters, predictors, plausibility ranges, seeds, bootstrap settings, multiplicity families and event floors |
| `utils.R` | Shared validation and utility functions |
| `clinical_scores.R` | SOFA, NEWS2, qSOFA and SIRS |
| `01_setup.Rmd` … `12_inference.Rmd` | The twelve pipeline stages, in execution order |
| `run_pipeline.sh` / `run_pipeline.R` | Runs all stages or a named subset |
| `thesis_constants.R` | Writes every reported result into the thesis as a LaTeX macro |
| `utility_score.py` | Independent Python implementation of the PhysioNet Utility Score, cross-checked against the R implementation in stage 07 |
| `check_consistency.R` | Cross-checks the generated result tables against each other |
| `check_thesis_numbers.R` | Checks the provenance of numbers written in the thesis source |
| `check_thesis_margins.R` | Checks the built PDF for content extending past the text area |

| # | Stage | Phase |
|---|---|---|
| 01 | Setup: verify source tables | 1 |
| 02 | Cohort and labels, six variants (A–F) | 2 |
| 03 | Person-hour panel, built from about 6 GB of source tables | 2 |
| 04 | Sample size (Riley et al.) | 3 |
| 05 | Primary model: multinomial discrete-time competing-risks model | 4 |
| 06 | Comparators: gradient-boosted trees (GBT), Cox, NEWS2, qSOFA, SIRS | 4 |
| 07 | Performance metrics and utility-threshold sweep | 5 |
| 08 | External validation on eICU-CRD | 6 |
| 09 | Variance decomposition and label-anchor attribution | 7 |
| 10 | Equity analysis | 7 |
| 11 | Clinical metrics: calibration, decision-curve analysis, operating points, lead time | 8 |
| 12 | Inference: cluster bootstrap, Holm and Benjamini–Hochberg correction, and the analysis register (one row per reported test with its family and adjusted p-value) | 9 |

---

## Running the analysis

### Requirements

- **R 4.5+** with the packages in `sepsis/project/requirements.txt`, an R
  package-version manifest that records the versions used to produce the
  reported results. The installer adds missing packages at the current CRAN
  version and reports any installed package whose version differs from the
  manifest:

  ```bash
  cd sepsis/project
  Rscript install_requirements.R --check   # report only
  Rscript install_requirements.R           # install missing packages
  ```

- **Python 3.14** with pandas 3.0.4 (`sepsis/project/requirements-python.txt`),
  used only by `utility_score.py`. pandas 2.x is not supported.
- **TeX** with `xelatex`, `pdflatex` and `biber`, to build the thesis.
- **Credentialed PhysioNet access** to both databases, placed as follows:
  - MIMIC-IV v3.1: `data/mimic-iv-3.1/{hosp,icu}/*.csv.gz`
  - eICU-CRD v2.0: `data/eicu-collaborative-research-database-2.0/`

`config.R` searches parent directories for `data/`. Set `MIMIC_RESEARCH_ROOT`
to use a different location.

### Full run

```bash
cd sepsis/project
./run_pipeline.sh
```

This runs stages 01–12 in order and, if all of them succeed, regenerates the
thesis constants and figures. The run that produced the reported results took
about 2 hours 30 minutes on a 2023 MacBook Pro. Stage 05 (nine model fits) and
stage 12 (the bootstrap) account for most of it. Timings will vary with
hardware and library builds.

| Stage | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Minutes | <1 | 3 | 16 | <1 | 73 | 9 | 2 | 16 | <1 | <1 | 15 | 26 |

### Partial runs

```bash
./run_pipeline.sh 10 11 12                         # named stages only
Rscript run_pipeline.R --phase 4                   # one phase
V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07   # restrict to some label variants
V2_ARMS=ablated ./run_pipeline.sh 05 06            # restrict to one fitting arm
```

> [!NOTE]
> When adding a label variant, restrict stages 05 and 06 with `V2_VARIANTS`.
> GBT fitting is not bit-reproducible across library builds, so refitting the
> existing variants may change the reported GBT estimates. Stage 07 merges new
> alternative-label results with the existing rows, so a partial run keeps the
> results for variants it did not include.

### Building the thesis

```bash
cd sepsis/project && Rscript thesis_constants.R
cd ../thesis && ./build.sh
```

`build.sh` exits before compiling if a chapter references a macro the pipeline
did not produce. Set `V2_ALLOW_MISSING=1` for a draft build.

### Validation checks

Three read-only checks run automatically: `run_pipeline.sh` runs the first two
after regenerating the thesis constants, and `build.sh` runs the third on the
PDF it produces. They can also be run by hand after editing the thesis:

```bash
cd sepsis/project
Rscript check_consistency.R
Rscript check_thesis_numbers.R
Rscript check_thesis_margins.R
```

- `check_consistency.R` checks relationships that must hold between outputs of
  different stages, such as a rate against its numerator and denominator, or the
  cohort-flow arithmetic. It also evaluates claim predicates: executable checks
  of empirical statements made in the thesis text, which fail if a rerun no
  longer supports the statement.
- `check_thesis_numbers.R` classifies each result-like number in the thesis
  source as cited, as an allow-listed design constant or source-data fact, or as
  unaccounted for. It fails on any unaccounted number.
- `check_thesis_margins.R` checks the built PDF for tables or other content
  extending past the text area, which LaTeX does not report for tables.

`run_pipeline.sh` exit codes:

- `1`: a pipeline stage failed
- `2`: a macro or generated table is unresolved
- `3`: a consistency check failed
- `4`: the thesis source contains a result-like number without recorded provenance
- `5`: the cohort-flow figure could not be regenerated and still shows counts
  from an earlier run

---

## Reproducibility

Seeds are fixed in `config.R`. The train/test split is defined by admission year
rather than by random sampling, so it does not depend on the seed. With the
package versions in `requirements.txt`, a rerun is expected to reproduce the
reported estimates, with one documented exception: GBT fitting is not
bit-reproducible across library builds. On a rerun the GBT rows are therefore
the first place to look for drift, and `install_requirements.R --check` lists
any package version that differs.

Estimated quantities reach the thesis through generated code, not manual
transcription. `thesis_constants.R` reads the result tables and writes each
reported quantity to `sepsis/thesis/generated/pipeline_constants.tex` as a LaTeX
macro, and generates the larger tables whole. Three kinds of number are typed
directly: values quoted from prior studies, thresholds fixed by the
pre-registration, and rounded values in the prose whose exact value appears in
an adjacent generated table. A quantity the pipeline did not produce prints as a
visible placeholder rather than an earlier value, and `build.sh` blocks it.

---

## Findings in brief

AUROC differences are on the Variant B temporal test set unless stated
otherwise. All intervals are 95% cluster-bootstrap confidence intervals.

- **Model class accounted for more of the AUROC spread than label choice.** The
  AUROC range across model specifications was 0.1499, against 0.0123 across the
  three Sepsis-3 labels. The difference (label − model) was −0.1375
  (−0.162 to −0.108). H1 predicted the opposite.
- **The primary model met the non-inferiority criterion against GBT.** GBT minus
  primary AUROC was −0.0165 (−0.031 to −0.001). GBT did not exceed the primary
  model by the pre-registered 0.02 margin. Because the lower limit passes −0.02,
  this is non-inferiority, not equivalence. The two models' best utility values
  were similar (0.031 for GBT, 0.025 for the primary model).
- **Label choice mainly changed cohort membership.** Variants A and B had
  stay-level prevalences of 8.8% and 9.2% but agreed on which stays were septic
  at Cohen's κ = 0.267.
- **The pre-treatment onset count of zero follows from the onset rule.** Variants
  A–C time onset at suspicion of infection, so no onset can precede treatment.
  Variant F, which keeps Variant B's membership and re-times onset to the
  earlier of suspicion and SOFA increase, gives 71 pre-treatment onsets.
- **The external event-rate gap tracks the label's data requirements.** Events per
  1,000 person-hours in eICU-CRD were 0.094 times the MIMIC-IV rate under
  Variant B. The ratio rose to 0.425 when the microbiology-culture requirement
  was dropped (culture data cover 1.55% of eICU-CRD stays), and to 0.746 under
  Variant D, a post-hoc deterioration label with no treatment anchor. Variant D
  is not pooled with the Sepsis-3 results. Its AUROC is not a measure of sepsis
  prediction, because the label is defined from physiology that the models also
  use as input.
- **No operating point approached the alert-burden benchmark.** Under Variant B
  the highest Utility Score was 0.031 (GBT), within a few per cent of the
  no-alert strategy, at 51.8 false alerts per true alert against a benchmark
  of 1.4.

The six pre-registered hypotheses resolved as follows. H1 and H4 were not
confirmed. H2 was met descriptively. H3 and H5 could not be evaluated as
pre-registered: H3's count is fixed at zero by the onset rule, and H5's internal
Utility Score was too close to zero to define a proportional decline. H6
supported non-inferiority. The thesis reports all estimates, confidence
intervals and multiplicity-adjusted results.

---

## Thesis and screencast

- **Thesis:** [`sepsis/thesis/index.pdf`](sepsis/thesis/index.pdf), built from
  `sepsis/thesis/` by `build.sh`.
- **Screencast:** [`sepsis/Screencast/`](sepsis/Screencast/).

---

## Ethics and data access

Both databases are de-identified and available to credentialed researchers
through PhysioNet, under the PhysioNet Credentialed Health Data Use Agreement.
They are distributed under the institutional approvals obtained by their
custodians. This study is a retrospective secondary analysis with no patient
contact or intervention. The terms of the data use agreement were followed
throughout, including its prohibitions on redistribution and on attempted
re-identification. The thesis (Section 3, Ethical Considerations) gives the
details.

`.gitignore` excludes `data/` and the pipeline's output directory from version
control. Anyone running the pipeline is responsible for storing the source data
as their own data use agreement requires.

---

## Citation

```bibtex
@mastersthesis{ahad2026sepsis,
  author  = {Ahad, Abdul},
  title   = {Quantifying Model, Label, and Methodological Contributions to
             Variance in Real-Time Sepsis Onset Prediction},
  school  = {Atlantic Technological University (ATU), Galway},
  type    = {M.Sc. thesis},
  year    = {2026},
  url     = {https://github.com/ahadarif007/sepsis-variance-decomposition}
}
```

---

## Licence

The pipeline source code is released under the
[Apache License 2.0](LICENSE). The licence covers only the parts of the
repository listed in [`NOTICE`](NOTICE), which sets out the full boundary:

- **Covered:** everything under `sepsis/project/`, and the repository
  documentation.
- **Not covered:** the ATU thesis template and brand assets in `sepsis/thesis/`,
  which are included only so the thesis compiles and remain subject to ATU's
  terms; and the MIMIC-IV and eICU-CRD databases, which are not in this
  repository.
- **Thesis text and figures** are not licensed under Apache 2.0. They may be
  read and cited in line with normal academic practice. Reproducing them
  requires permission.
- **Published methods** (SOFA, Sepsis-3, NEWS2, qSOFA, SIRS, the PhysioNet
  Utility Score, Riley's sample-size criteria, pooled logistic regression,
  decision-curve analysis) were implemented for this project from their
  published descriptions. The methods are credited to their authors in
  `NOTICE` and in the thesis.

## Clinical use

This is research software. It is not a medical device, has not been validated
for clinical use, and must not be used to guide patient care.
