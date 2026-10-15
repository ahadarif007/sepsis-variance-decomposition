# Screencast script

Each `>` line is a screen cue and is not spoken. Each bullet is one spoken line.

## Run sheet

| # | Section               | Time      | On screen                               |
|---|-----------------------|-----------|-----------------------------------------|
| 1 | Introduction          | 1:00      | Thesis title page                       |
| 2 | Repository tour       | 5:00      | GitHub README, then the `sepsis` folder |
| 3 | Results               | 3:15      | Thesis, Results chapter                 |
| 4 | Reproducibility chain | 1:15      | Four windows, in order                  |
| 5 | Close                 | 0:30      | Thesis title page or GitHub README      |
|   | **Total**             | **11:00** |                                         |

---

## 1. Introduction (1:00)

> **Screen:** thesis title page

- Hello, my name is Abdul Ahad. This screencast presents my M.Sc. in Computing project at Atlantic Technological
  University.
- My thesis examines real-time sepsis onset prediction.
- Most studies compare models and interpret performance differences as model effects.
- But those results also depend on analytical choices: how sepsis is defined, how the data are split, and which metric
  is reported.
- This led to my main question: how much of the reported performance variation comes from the model, and how much from
  these choices?
- I used MIMIC-IV for development and eICU for external validation.
- Six hypotheses were pre-registered before the reported models were fitted.
- I'll first show how the repository implements the analysis, then the main findings, and then trace one reported value
  from the pipeline into the thesis.

---

## 2. Repository tour (5:00)

### README

> **Screen:** GitHub repository, README

- This is the GitHub repository. The README is the starting point.
- It explains the research question, the layout, how to install everything, how to run the pipeline, and how to build
  the thesis.

### Data access

- One important note before we start. This repository contains no patient data.
- MIMIC-IV and eICU are credentialed datasets from PhysioNet, so I can't share any patient records, derived tables or
  fitted models.
- Anyone who wants to run this needs their own PhysioNet access. The README explains where to place the data.

### Folder structure

> **Screen:** the `sepsis` folder on your machine

- Let me open the project on my machine. The project lives inside the `sepsis` folder.
- There are two main parts:
    - `project`, which is the analysis pipeline;
    - and `thesis`, which holds the LaTeX source and the compiled thesis PDF.

### Pre-registration

> **Screen:** `project/00_preregistration.md`

- Inside `project`, the first file is `00_preregistration.md`. This is the pre-registration.
- It records the six hypotheses and each later protocol amendment, with dates, so the original plan can be told apart
  from later changes.

### Pipeline stages

> **Screen:** the numbered `.Rmd` files in `project`

- The analysis is a staged R pipeline: twelve numbered R Markdown stages, from 01 to 12.
- Each stage is a separate step that can be run and inspected on its own, and each one renders its own report.
- **Stage 02** builds the cohort and the sepsis labels.
    - The pre-registered analysis uses three Sepsis-3 variants: Narrow, Seymour-Standard and Liberal.
    - Variant B, Seymour-Standard, is the primary analysis.
    - Three more variants, D to F, were added later through dated amendments and are analysed separately.
- **Stage 03** turns each ICU stay into hourly rows, so the model can estimate the risk of sepsis onset in each hour.
- **Stage 05** fits the primary model, a discrete-time competing-risks model.
- **Stage 06** fits the comparators: gradient boosting, a Cox model, and the clinical scores NEWS2, qSOFA and SIRS.
- **Stage 08** applies the frozen models to eICU, without retraining.
- **Stage 09** compares the AUROC ranges for model class, label definition, split method and external validation. These
  are ranges, not variance shares.
- **Stage 12** runs the formal inference, with a stay-level cluster bootstrap and multiplicity correction.

```
 01 setup ─► 02 cohort + labels ─► 03 hourly rows ─► 04 sample size
                                                          │
 08 eICU validation ◄─ 07 metrics ◄─ 06 comparators ◄─ 05 primary model
        │
        ▼
 09 decomposition ─► 10 equity ─► 11 clinical metrics ─► 12 inference
```

### Shared files

> **Screen:** `config.R`, `utils.R`, `clinical_scores.R`, `utility_score.py`

- The pipeline is configuration-driven. Shared settings are centralised in `config.R`: label parameters, predictors, random seeds and bootstrap settings.
  - Environment variables can restrict a run to chosen label variants or fitting arms, without editing code.
- Reusable functions are kept out of the stages:
  - `utils.R` handles data loading, Parquet storage, metrics, the bootstrap and model checks;
  - `clinical_scores.R` computes SOFA, NEWS2, qSOFA and SIRS.
- The utility score is also implemented independently in Python. That gives a cross-language check of the R version.

### Environment setup

> **Screen:** `install_requirements.R` and `requirements.txt`

- Dependency checking is automated. `install_requirements.R` installs any missing packages and reports any version
  that differs from those recorded in `requirements.txt`.
- With the `--check` option, it only reports and changes nothing.

### Running the pipeline

> **Screen:** `run_pipeline.sh`

- The pipeline is orchestrated by a shell script, `run_pipeline.sh`. One command runs all twelve stages in order. You
  can also run a subset by passing stage numbers.
- When every stage succeeds, the same script writes the results into the thesis as LaTeX macros and runs the
  consistency checks. It records any failure and ends with a separate exit code for each kind of failure.
- A full run takes about two and a half hours, mostly the model fitting and the bootstrap.
- So I'm not re-running it live here. Instead I'll show the outputs from the final run.

### Outputs

> **Screen:** the `output` folder on your machine. Show file names only; do not open processed data files.

- When the pipeline runs, it fills the local `output` folder:
    - the processed data. Intermediate data is stored as Parquet, a compact columnar format, and read back by the
      next stage;
    - the figures;
    - the rendered reports for each stage;
    - and the run logs: one log per stage, plus one for the full run.
- The processed data stays on my machine and is not on GitHub. The figures, stage reports and logs are.
- The logs show each stage completing, with its time.

### Checker scripts

> **Screen:** `check_consistency.R`, `check_thesis_numbers.R`, `check_thesis_margins.R`

- Finally, there are three checker scripts. The first two run automatically at the end of every successful pipeline run.
    - `check_consistency.R` checks that related results agree with each other.
    - `check_thesis_numbers.R` flags any result-like number typed by hand into the thesis instead of generated.
    - `check_thesis_margins.R` checks the built PDF for content running past the page margins.
- I'll come back to that in the reproducibility part.

### Thesis build and freeze

> **Screen:** `thesis/build.sh`, then `project/freeze.sh`

- The thesis has a reproducible build. `build.sh` refuses to build the PDF if any result it uses is missing.
- `freeze.sh` runs the final pipeline from a clean, committed state and stamps that commit into the thesis, in
  Appendix A.

> **Note to self:** say the `freeze.sh` line only after the Appendix A tag and commit exist on GitHub. Today they do
> not.

---

## 3. Results (3:15)

> **Screen:** Results chapter, section "Variance Decomposition and Hypothesis Verdicts", the hypothesis table. Let the
> table speak; don't read it out.

```
 H   Question                                        Result                     Verdict
 --  ----------------------------------------------  -------------------------  ----------------
 H1  Label changes AUROC more than model?            model 0.15 vs label 0.01   Not confirmed
 H2  Coefficients change across labels?              6 of 22 (3 beyond noise)   Descriptive
 H3  AUROC falls before treatment?                   no onsets in that window   Structural
 H4  Random split more optimistic than temporal?     about -0.02, CI spans 0    Not confirmed
 H5  AUROC falls on external data? (substitute)      about 0.06, 29 events      Inconclusive
 H6  GBT beats primary by more than 0.02?            0.742 vs 0.759             Not rejected
```

- My cohort has 65,078 ICU stays. I'll summarise the six pre-registered hypotheses, then show what they mean together.

### H1: label vs model (main question)

> **Screen:** figures `09_model_class_auroc.png` and `09_label_variance_auroc.png`

- H1 asked whether the sepsis definition changes AUROC more than the choice of model. The hypothesis was not confirmed.
    - Across models, AUROC ranged by about 0.15.
    - Across the three definitions, it ranged by only about 0.01.
- This doesn't mean the definitions are equivalent. They select quite different patients. Their effect on AUROC was
  simply smaller.

### H2: coefficient stability (brief)

- H2 looked at whether the model's coefficients change across the definitions.
- Six of the 22 predictors met the pre-registered instability rule. This is reported as a count, without a formal test.
- After allowing for estimation uncertainty, three remained unstable, and all three indicated whether a test had been
  ordered.

### H3: before treatment

- H3 asked whether performance falls if we evaluate only the hours before treatment begins. It could not be evaluated.
    - My pre-registered rule placed onset at the later of the antibiotic and culture times, so onset could never come
      before treatment.
    - The pre-treatment window contained no onsets.
- *[Pause.]*
- That is a consequence of the label rule, not a finding about patients.

### H4: random vs temporal split (brief)

- H4 asked whether a random split gives a more optimistic AUROC than a split by time.
- The difference was small, and the confidence interval included zero, so it was not confirmed.

### H5: external validation

- As pre-registered, H5 compared how much the utility score and AUROC fall on external data. The utility part could not
  be estimated, so I tested the fall in AUROC instead.
- AUROC fell from 0.759 on MIMIC-IV to 0.696 on eICU, an observed decrease of about 0.06.
    - But the external test had only 29 sepsis events, below the thesis's 100-event interpretability floor.
    - And the confidence interval included zero.
- So this result is inconclusive.

### H6: primary model vs gradient boosting (brief)

- H6 asked whether gradient boosting beats the primary model by more than 0.02 AUROC. It did not: 0.759 for the primary
  model, 0.742 for gradient boosting.
- This doesn't prove the two are equivalent. Gradient boosting simply did not exceed the margin I set in advance.

### Overall result

> **Screen:** "The Decomposition Table" in the same section

```
 AUROC range by factor (others held fixed)

 Model class          0.1499   ###############
 External transport   0.0630   ######            widest interval, covers zero
 Label definition     0.0123   #
 Split method        -0.0165   ~0

 Ranges, not variance shares: they cannot be added up.
```

- Taken together: for AUROC, model class produced the largest difference.
- The internal-to-external gap came next, but it is too uncertain to confirm.
- Label definition and split method produced smaller AUROC differences, although the label did change which patients
  counted as septic.

### Alert burden

> **Screen:** section "Utility and Alert Burden Across Thresholds", figure `07_utility_threshold_sweep.png`

```
 False alerts for every true alert

 Best result, primary label   51.8   ####################################################
 Published benchmark           1.4   #
```

- But AUROC is only one view.
- Under the primary label, the best utility score still needed about 52 false alerts for every true alert. The published
  benchmark is 1.4.
- Because the threshold was chosen on the test set, even that figure is optimistic.
- No model and threshold came close to the benchmark.

---

## 4. Reproducibility chain (1:15)

> **Screen:** these four windows in order. Zoom in on the relevant line before speaking, and leave each one on screen
> for a few seconds.

```
 1  project/thesis_constants.R               lines 285-291: reads 07_metric_results,
                                             writes the AUROC macro
            │
            ▼
 2  thesis/generated/pipeline_constants.tex  \pcAurocPrimaryB = 0.7590
            │
            ▼
 3  thesis/chapters/ch5-results/             line 27: table cell uses \pcAurocPrimaryB
      s03-internal-performance.tex
            │
            ▼
 4  index.pdf                                Results table shows 0.7590
```

- Now I'll trace one reported value from the pipeline into the thesis.
- Estimated results reach the thesis through generated code, not by copying.

> **Screen:** window 1

- First, `thesis_constants.R` reads the result tables...

> **Screen:** window 2

- ...and writes each value as a LaTeX macro into `pipeline_constants.tex`. That file holds almost 1,500 values.
- Here is the primary model's AUROC, 0.759.

> **Screen:** window 3

- In the Results chapter, the source uses this macro, not a copied number.

> **Screen:** window 4

- And the compiled PDF shows the same value.
- Safeguards:
    - If a value the thesis uses is missing, the build script refuses to build the PDF.
    - A checker flags any result-like number typed by hand into the thesis.
    - Re-running the full pipeline on the same machine reproduced every reported analysis value exactly.

---

## 5. Close (0:30)

> **Screen:** thesis title page or GitHub README

- This project asked how much reported sepsis-model performance depends on the model, and how much on analytical
  choices.
- For AUROC, model class produced the largest difference. Label definition had a smaller effect on AUROC, but it changed
  which patients were labelled septic.
- External validation remained inconclusive, and the pre-registered onset rule made the planned pre-treatment analysis
  impossible.
- And even the best result under the primary label needed about 52 false alerts for every true one.
- The thesis, the source code and this screencast are in the repository. Thank you for watching.
