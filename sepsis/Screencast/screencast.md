# Screencast script

Each `>` line is a screen cue and is not spoken. Each bullet is said in one go, then a short breath before the next.

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

- Hi, I'm Abdul Ahad, and this is the screencast for my M.Sc. in Computing project at Atlantic Technological
  University.
- My thesis is about predicting sepsis onset in real time.
- When papers in this area compare models, they usually read any difference in performance as a difference between
  the models.
- But that number also depends on decisions made along the way. How sepsis is defined, how the data is split, which
  metric gets reported.
- So my main question was this: how much of the variation in reported performance really comes from the model, and how
  much comes from those choices?
- I built everything on MIMIC-IV and used eICU for external validation. And I pre-registered six hypotheses before
  fitting any of the models I report.
- I'll start with a tour of the repository, then go through what I found, and finish by following one number from the
  pipeline all the way into the thesis.

---

## 2. Repository tour (5:00)

### README

> **Screen:** GitHub repository, README

- So this is the GitHub repository, and the README is where I'd start.
- It covers the research question and how the repository is laid out. Then the practical side: installing the
  dependencies, running the pipeline and building the thesis.

### Data access

- Before going further, I should be clear that there's no patient data in this repository.
- MIMIC-IV and eICU are credentialed PhysioNet datasets, so I can't share patient records, anything derived from them,
  or the fitted models.
- Running it requires separate PhysioNet access. The README says where to put the data once access is granted.

### Folder structure

> **Screen:** the `sepsis` folder on the local machine

- Let me switch over to my local copy. Everything lives in the `sepsis` folder.
- It has two main parts. `project` is the analysis pipeline, and `thesis` has the LaTeX source along with the compiled
  PDF.

### Pre-registration

> **Screen:** `project/00_preregistration.md`

- The first file in `project` is `00_preregistration.md`, the pre-registration.
- It lists the six hypotheses, and every protocol amendment I made later is added there with its date. That keeps the
  original plan clearly separate from what changed afterwards.

### Pipeline stages

> **Screen:** the numbered `.Rmd` files in `project`

- The analysis itself is a staged R pipeline, twelve numbered R Markdown files from 01 to 12.
- Each stage can be run and checked on its own, and each one renders its own report. I'll pick out the ones that
  matter most.
- Stage 02 builds the cohort and the sepsis labels. The pre-registered analysis uses three Sepsis-3 variants, Narrow,
  Seymour-Standard and Liberal, and variant B, Seymour-Standard, is the primary one.
- I added three more variants later, D to F, through dated amendments. Those are analysed separately.
- Stage 03 breaks each ICU stay into hourly rows, so the model is estimating the risk of sepsis onset hour by hour.
- Stage 05 fits the primary model, which is a discrete-time competing-risks model.
- Stage 06 fits everything I compare it against: gradient boosting, a Cox model, and the clinical scores NEWS2, qSOFA
  and SIRS.
- Stage 08 takes the frozen models and applies them to eICU. Nothing gets retrained.
- Stage 09 compares how far AUROC moves when changing the model class, the label definition or the split method, or
  move to external data. These are ranges. They aren't variance shares.
- And Stage 12 does the formal inference, using a stay-level cluster bootstrap with a correction for multiple
  comparisons.

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

- The pipeline is driven by configuration. Shared settings sit in one place, `config.R`: the label parameters, the
  predictors, the random seeds and the bootstrap settings.
- Environment variables can also limit a run to particular label variants or fitting arms, without touching
  the code.
- Functions that get reused are kept out of the stages. `utils.R` handles data loading, Parquet storage, metrics, the
  bootstrap and the model checks, and `clinical_scores.R` computes SOFA, NEWS2, qSOFA and SIRS.
- I also wrote the utility score a second time, independently, in Python. That gives me a check on the R version from
  a different language.

### Environment setup

> **Screen:** `install_requirements.R` and `requirements.txt`

- Setting up the environment is automated too. `install_requirements.R` installs whatever packages are missing, and
  flags any version that differs from what's recorded in `requirements.txt`.
- With `--check`, it only reports. It won't change anything.

### Running the pipeline

> **Screen:** `run_pipeline.sh`

- Running everything comes down to one shell script, `run_pipeline.sh`. A single command runs all twelve stages in
  order, or stage numbers can be passed to run just some of them.
- If every stage succeeds, the same script writes the results into the thesis as LaTeX macros and runs the consistency
  checks. If something fails, it records it, and the exit code shows which kind of failure it was.
- A full run takes about two and a half hours, mostly model fitting and the bootstrap.
- So I won't run it live. Here are the outputs from the final run instead.

### Outputs

> **Screen:** the `output` folder on the local machine. Show file names only; do not open processed data files.

- Pipeline execution fills up the local `output` folder. 
- It contains the processed data, figures, one rendered pdf report for each stage,
  and the run logs.
- Intermediate data is saved as Parquet, which is a compact columnar format, and the next stage reads it back in.
- There's one log per stage plus one for the full run, showing each stage finishing with how long it took.
- The intermediate processed data is git-ignored, so it never reaches the staging area. The figures, stage reports and logs are committed.

### Checker scripts

> **Screen:** `check_consistency.R`, `check_thesis_numbers.R`, `check_thesis_margins.R`

- Last stop on the tour is three checker scripts. The first two run automatically at the end of every successful
  pipeline run.
- `check_consistency.R` makes sure related results agree with each other.
- `check_thesis_numbers.R` looks for any result-like number that was typed into the thesis by hand instead of being
  generated.
- And `check_thesis_margins.R` goes through the built PDF for anything running past the page margins.
- I'll come back to these in the reproducibility part.

### Thesis build and freeze

> **Screen:** `thesis/build.sh`, then `project/freeze.sh`

- The thesis build is reproducible as well. If any result the thesis needs is missing, `build.sh` simply won't build
  the PDF.
- And `freeze.sh` runs the final pipeline from a clean, committed state, then stamps that commit into Appendix A of
  the thesis.

---

## 3. Results (3:15)

All screens are in `thesis/index.pdf`. Each cue gives the printed page number first and the PDF viewer page in
brackets.

### Overview (0:10)

> **Screen:** Section 5.10.2, Table 5.29 "The confirmatory family", p. 85 [PDF 106]. Zoom until the six rows and the
> Verdict column fill the screen. Do not read the table aloud.

Speaker reference only. This block is not shown.

```
 H   Question                                        Result                       Verdict
 --  ----------------------------------------------  ---------------------------  ----------------
 H1  Label moves AUROC more than model?              model 0.150 vs label 0.012   Not confirmed
 H2  Coefficients change across labels?              6 of 22 (3 beyond noise)     Descriptive
 H3  AUROC falls before treatment?                   0 onsets in that window      Not evaluable
 H4  Random split more optimistic than temporal?     -0.017, CI includes 0        Not confirmed
 H5  AUROC falls on external data? (substitute)      0.063, 29 events, CI incl 0  Inconclusive
 H6  GBT beats primary by more than 0.02?            0.742 vs 0.759               Not rejected
```

- The analysis cohort contains 65,078 ICU stays.
- This table lists the six pre-registered hypotheses and their verdicts.
- I will take them in order.

### H1: label definition versus model class (0:30)

> **Screen:** figures `09_model_class_auroc.png` and `09_label_variance_auroc.png`

- H1 was my main question: would the sepsis definition move AUROC more than the model? It didn't.
- Changing the model moved AUROC by about 0.15. Changing the definition moved it by only about 0.01.
- The definitions still pick out quite different patients. They just matter less for AUROC.

### H2: coefficient stability (0:20)

> **Screen:** Section 5.10.4, Table 5.30 "Features with sign reversal or magnitude instability across label
> variants", p. 87 [PDF 108]. Then scroll down to Table 5.31 on the same page. Highlight the three rows with a ratio
> above 2.

- H2 looked at whether coefficients changed across definitions. Six of 22 predictors met my pre-registered instability
  rule, but that's a descriptive count with no formal test.
> **Screen:** scroll to the next table, "H2 instability against estimation noise"

### H3: performance before treatment (0:30)

> **Screen:** Section 5.6.3, Table 5.18 "Events in the treatment-anchored (pre-treatment) evaluation window",
> p. 73 [PDF 94]. Highlight row B in the Onsets column, which shows 0. Then highlight row F, which shows 71.

- H3 asked whether performance dropped in the hours before treatment. It couldn't be tested.
- My pre-registered rule put onset at the later of the antibiotic and culture times, so no onset could fall before
  treatment.
- *[Pause.]*
- That's down to the label rule. It says nothing about the patients.

### H4: random versus temporal split (0:15)

> **Screen:** Section 5.10.6, Table 5.33 "Temporal vs. random split comparison", p. 90 [PDF 111]. Highlight the
> Primary row. Then run down the last column, where all four values are negative.

- H4 asked whether a random split looked more optimistic than a temporal split. The difference was small and the
  interval included zero, so it wasn't confirmed.

### H5: external validation (0:30)

> **Screen:** Section 5.5.2, Table 5.13 "External validation on eICU-CRD", p. 67 [PDF 88]. Highlight row B, Primary:
> N events (29), AUROC (eICU) 0.6960 and AUROC (MIMIC) 0.7590.

- H5 was meant to compare the drop in utility and AUROC on external data. Utility couldn't be estimated, so as a
  substitute I tested AUROC alone.
- AUROC fell from 0.759 on MIMIC-IV to 0.696 on eICU, a drop of about 0.06.
- But eICU had only 29 sepsis events, below my 100-event interpretability floor, and the interval included zero. So
  H5 remains inconclusive.

### H6: primary model versus gradient boosting (0:20)

> **Screen:** Section 5.10.8, Figure 5.10 "AUROC by model class", p. 92 [PDF 113]. Point at the primary-model and GBT
> bars. Then point at the four lower bars.

- H6 asked whether gradient boosting would beat the primary model by more than 0.02 AUROC. It didn't: 0.742 against 0.759.
- That doesn't make them equivalent. Gradient boosting just didn't clear the margin I set in advance.

### Overall pattern (0:20)

> **Screen:** Section 5.10.1, Table 5.28 "Variance decomposition", p. 83 [PDF 104]. Run down the ΔAUROC column from
> top to bottom. Then point at the interval for External transport.

Speaker reference only. This block is not shown.

```
 AUROC range by factor (others held fixed)

 Model class          0.1499   ###############
 External transport   0.0630   ######            widest interval, includes zero
 Label definition     0.0123   #
 Split method        -0.0165   ~0

 Ranges, not variance shares: they cannot be added up.
```

- Overall, model class produced the largest AUROC range. External transport came next, but its estimate is too
  uncertain to confirm a difference.
- Label and split moved AUROC less, though the label did change who counted as septic.

### Alert burden (0:20)

> **Screen:** Section 5.3.1, Figure 5.1 "Normalised Utility Score against alert rate", p. 53 [PDF 74], for a few
> seconds. Then Table 5.5 "Maximum achievable Utility Score", p. 54 [PDF 75]. Highlight the Variant B rows for Primary
> and GBT in the Alert burden column (47.3 and 51.8).

Speaker reference only. This block is not shown.

```
 False alerts per true alert (Variant B, best threshold)

 Primary model         47.3   ###############################################
 Gradient boosting     51.8   ####################################################
 Published benchmark    1.4   #
```

- AUROC isn't the whole story, though. On the primary label, even the best utility score came with about 52 false
  alerts for every true one. The published benchmark is 1.4.
- And even that's optimistic, because the threshold was chosen on the test set. Nothing came close to the benchmark.

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

- Finally, I'll trace one reported number from the pipeline into the thesis.
- Estimated results reach the thesis through generated code, not by being copied in by hand.

> **Screen:** window 1

- It starts in `thesis_constants.R`, which reads the result tables...

> **Screen:** window 2

- ...and writes each value out as a LaTeX macro in `pipeline_constants.tex`. That file holds almost 1,500 generated values.
- This one is the primary model's AUROC, 0.759.

> **Screen:** window 3

- In the Results chapter, the source uses that macro. The number itself is never typed in.

> **Screen:** window 4

- And the compiled PDF shows the same value.
- Three checks back this up. If a value the thesis uses is missing, the build script won't produce the PDF.
- A second checker flags any result-like number typed straight into the thesis.
- And when I re-ran the full pipeline on the same machine, every reported analysis value came out exactly the same.

---

## 5. Close (0:30)

> **Screen:** thesis title page or GitHub README

- So, back to my main question: for AUROC, the model mattered most.
- The sepsis definition moved AUROC much less, but it changed which patients counted as septic.
- External validation was inconclusive, and my pre-registered onset rule made the pre-treatment test impossible.
- Even the best setup on the primary label still gave about 52 false alerts for every true one.
- The thesis, the code and this screencast are all in the repository. Thanks for watching.
