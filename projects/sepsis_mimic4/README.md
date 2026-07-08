# Real-Time Sepsis-3 Onset Prediction on MIMIC-IV: A Statistical Pipeline

A reproducible research pipeline that builds toward a **real-time, hourly
early-warning system for sepsis** in the ICU, using classical statistical
methods on **MIMIC-IV v3.1**. The work is deliberately statistical rather than
deep-learning-based: every stage is interpretable, every design choice is
justified, and the evaluation is held to a stricter standard than most published
sepsis-prediction studies.

---

## Abstract

Sepsis is life-threatening organ dysfunction caused by a dysregulated host
response to infection. The **Sepsis-3** consensus defines it operationally as a
suspected infection together with an acute rise of at least two points in the
Sequential Organ Failure Assessment (SOFA) score. This project constructs an
adult ICU cohort from MIMIC-IV, labels sepsis at the level of the individual
hour, and asks the clinically useful question: given only the data observed so
far, will a patient who is not yet septic develop sepsis in the near future.
We report a cross-sectional statistical analysis (for understanding) and a
longitudinal analysis (for prediction), and we benchmark the result against the
recent literature. The headline figure, a cross-validated AUROC of about 0.755
for predicting incident onset within 12 hours, is discussed in context: it is
lower than some published numbers, yet it answers a harder and more honest
question, and it out-discriminates every standard clinical score on the same
task. We then build the real-time model itself (Phase 2, Section 9) **without
leaving classical statistics** — a full-feature nomogram (AUROC 0.775) and a
dynamic **landmark supermodel** that emits an hourly-updating risk — and evaluate
it as a streaming alarm with the PhysioNet utility score and an alarm-burden
analysis. The ceiling on this task is set by the label's dependence on clinician
recognition, not by model class, which is why a purely statistical model is
competitive and no neural network is required.

---

## 1. Background and Objective

**The long-term objective** is an online model that emits, at each hour of an
ICU stay, the probability that the patient will become septic within a short
horizon. This is the same problem shape as the PhysioNet/CinC 2019 Early Sepsis
Prediction Challenge.

**Phase 1** is the statistical foundation for that objective. It has two layers:

1. A **cross-sectional** analysis that establishes which physiology is
   associated with sepsis and characterises the data.
2. A **longitudinal** analysis that reframes the problem on a true time axis,
   defines a sepsis onset time, and quantifies how well the signal can be
   predicted ahead of time, together with the baselines any future model must
   beat.

**Phase 2 (also in this repository, executed)** is the real-time model itself —
built, by design, with **classical statistics only** (no machine learning or deep
learning). It reaches hourly, real-time prediction through **dynamic landmarking**
(a landmark supermodel), consuming exactly what Phase 1 produced (the hourly
panel, the onset labels, the landmark design, the baselines). See Section 9 for
the results. The one piece still outstanding is external validation on a second
database (eICU), which is deferred because no eICU data is present locally.

---

## 2. Data

- **Source.** MIMIC-IV v3.1, a de-identified critical-care database from the
  Beth Israel Deaconess Medical Center, in `data/mimic-iv-3.1/{hosp,icu}` as
  gzipped CSVs.
- **Scale.** The event tables are large: `chartevents` about 3.3 GB,
  `labevents` about 2.4 GB. These are never loaded whole; they are streamed in
  chunks (see Section 5.10).
- **Cohort.** Adults (age at least 18), first ICU stay only, ICU length of stay
  at least 4 hours. This yields **65,241 stays / 65,241 patients**.

---

## 3. Pipeline Overview

The pipeline is a linear sequence of small, single-purpose scripts. Each writes
an intermediate that the next consumes. The split into a static branch (04 to
06) and a temporal branch (07 to 09) is the core of the design.

```
                         data/mimic-iv-3.1  (raw, read-only)
                                   |
                                   v
                        01_explore_data.py        profiles data, confirms itemids
                                   |
                                   v
                        02_extract_cohort.py      65,241 adult first ICU stays
                                   |
                                   v
                     03_suspected_infection.py    antibiotics x cultures -> t_suspicion
                                   |                (surveillance swabs excluded)
                 __________________|__________________
                |                                     |
     STATIC branch (understanding)        TEMPORAL branch (prediction)
                |                                     |
                v                                     v
     04_extract_measurements.py            07_hourly_panel.py
     one row per stay, first 24 h          one row per stay-HOUR (3.1M rows)
                |                           hourly grid + forward-fill + time-since-last
                v                                     |
     05_sofa_sepsis3.py                               v
     SOFA organs + Sepsis-3 label          08_onset_label.py
     -> analysis_matrix.csv                hourly SOFA -> onset hour -> per-hour label
                |                           + hour-6 landmark cohort + baselines
                v                                     |
     06_statistical_report.Rmd                        v
     cross-sectional report (PDF)          09_temporal_report.Rmd
     EDA, tests, MLE, GLM, KDE,            KM, Cox, time-varying Cox, Fine-Gray,
     mixture, MCMC, HMM,                   autocorrelation, within-patient HMM,
     validation + calibration             time-dependent AUC vs clinical scores
                                                      |
                                                      v
                        Phase 2 (10-17): dynamic landmark supermodel
                        + full-feature nomogram + utility/alarm eval
                        (purely statistical; see Section 9)
```

Text-only reading of the flow: raw tables feed a cohort; the cohort feeds an
infection-suspicion detector; from there the data splits. The static branch
compresses each stay to a single row for an interpretive report. The temporal
branch expands each stay to one row per hour, defines when sepsis begins, and
supports a longitudinal analysis that is the true blueprint for real-time
prediction.

---

## 4. Stage-by-Stage Description

| Script | Output | Purpose |
|---|---|---|
| `01_explore_data.py` | `exploration_report.txt` | Profile tables, confirm candidate itemids exist, preview cohort. |
| `02_extract_cohort.py` | `cohort.csv` | Adult first-stay ICU cohort with mortality flags. |
| `03_suspected_infection.py` | `suspected_infection.csv` | Pair antibiotic orders with cultures inside the Sepsis-3 windows to get the earliest suspicion time per stay. |
| `04_extract_measurements.py` | `stay_measurements.csv` | Stream the big tables to one row per stay of first-24h physiology (heavy stage). |
| `05_sofa_sepsis3.py` | `analysis_matrix.csv` | Score the six SOFA organs, total them, apply the Sepsis-3 and septic-shock labels. |
| `06_statistical_report.Rmd` | `06_statistical_report.pdf` | Cross-sectional statistical report plus out-of-sample validation. |
| `07_hourly_panel.py` | `hourly_panel.parquet` | Resample every stay to an hourly grid with forward-fill and time-since-last (heavy stage). |
| `08_onset_label.py` | `hourly_labeled.parquet`, `onset_summary.csv`, `landmark_h6.csv`, `traj_means.csv`, `panel_sample_long.csv` | Hourly SOFA, sepsis onset hour, per-hour early-warning label, landmark cohort, streaming baselines. |
| `09_temporal_report.Rmd` | `09_temporal_report.pdf` | Longitudinal report: survival analysis, competing risks, time-series structure, time-dependent discrimination. |
| `10_landmark_nomogram.R` | `phase2_tier1_*.csv`, nomogram/calibration PNGs | **Phase 2 T1:** full-feature elastic-net nomogram at h6 with informative-missingness design. |
| `11_landmark_stack.py` | `landmark_stack.csv` | **Phase 2 T2:** stacked multi-landmark dataset (s in {6..48}h). |
| `12_supermodel.R` | `phase2_tier2_*.csv`, `auc_by_landmark.png` | **Phase 2 T2:** dynamic landmark supermodel; hourly-updating risk and AUC(s). |
| `13_repeated_measures.R` | `phase2_tier3_*.csv` | **Phase 2 T3:** GEE (within-patient correlation) + ridge time-varying Cox. |
| `14_realtime_holdout.py` | `realtime_holdout_*.csv` | **Phase 2 T4:** all-hours feature stream for a 6,000-stay holdout. |
| `15_realtime_eval.R` | `phase2_tier4_*.csv`, `alarm_tradeoff.png` | **Phase 2 T4:** PhysioNet utility score + alarm-burden analysis. |
| `16_subgroup_fairness.R` | `phase2_tier5_subgroups.csv` | **Phase 2 T5:** subgroup calibration by sex/age (eICU external validation deferred). |
| `17_phase2_report.Rmd` | `17_phase2_report.pdf` | **Phase 2 report:** narrates Tiers 1–5. |

---

## 5. Methodology and Design Rationale

Every decision below was made for a stated reason. This section is the heart of
the project.

### 5.1 Cohort: adults, first stay, minimum length of stay

We keep adults only (clinical relevance), the first ICU stay per patient (so
observations are independent and one patient cannot dominate), and stays of at
least 4 hours (ultra-short stays are usually incomplete or administrative). The
first-stay rule has a useful side effect: it makes the cohort patient-disjoint,
so an ordinary random split is already free of patient-level leakage.

### 5.2 Suspected infection and the surveillance-swab exclusion

Sepsis-3 requires suspected infection, operationalised (following Seymour et
al. 2016) as an antibiotic order paired with a body-fluid culture within defined
time windows. A subtle but important decision concerns **MRSA SCREEN** and
similar admission swabs. These are colonization or resistance surveillance
tests, not diagnostic cultures of an active infection. Including them inflated
suspected infection to 51.5 percent of the cohort. We therefore exclude
surveillance screens by default (`config.EXCLUDE_SURVEILLANCE_CULTURES`,
`SURVEILLANCE_SPEC_TYPES`), which is standard practice in sepsis phenotyping.
After exclusion, suspected infection falls to a clinically sensible **40.5
percent**, with the leading cultures being blood, urine and sputum rather than a
nasal surveillance swab. We deliberately keep generic wound swabs and the
respiratory viral panel, which are genuine diagnostic tests.

### 5.3 SOFA operationalisation

- **Assumed-zero baseline.** Per Sepsis-3, the pre-morbid SOFA is assumed to be
  zero, so an acute rise of at least two points reduces to a total SOFA of at
  least two.
- **Day-1 SOFA in the static branch.** Script 05 scores SOFA over each stay's
  first 24 hours (labs from minus 6 hours to plus 24 hours). This gives every
  stay an identical, non-circular window and is justified because suspicion of
  infection lands a median of about 1 hour from ICU admission.
- **Hourly SOFA in the temporal branch.** Script 08 scores SOFA every hour from
  the forward-filled panel, which is what a real-time system needs and what lets
  us locate an onset time.
- **Documented simplifications.** Respiration ignores the strict ventilation
  requirement on the highest scores; phenylephrine or vasopressin presence maps
  to a cardiovascular score of 3; a component with no data scores 0. These are
  stated in the `05_sofa_sepsis3.py` header so nothing is hidden.

### 5.4 Non-circular predictors in the cross-sectional report

The Sepsis-3 label is built from SOFA. If we then predicted that label using
SOFA components, the model would be partly re-deriving its own target. To avoid
this circularity, the cross-sectional GLM predicts sepsis from physiology that
is not part of SOFA (lactate, white-cell count, heart rate, respiratory rate,
temperature, age). This is an honesty constraint that lowers the apparent AUROC
but makes the result meaningful. It is revisited in Section 7.

### 5.5 From static to temporal: the hourly panel

A single-row-per-stay summary cannot answer a real-time question, because it has
already looked at the whole 24 hours. Script 07 rebuilds the data as one row per
stay-hour (3.1 million rows). For each core variable it stores three things:

- the value measured in that hour (missing where nothing was charted),
- a forward-filled version (`_ff`, the value a bedside clinician would currently
  know), and
- the hours since the variable was last actually measured (`_tsl`).

The `_tsl` column matters because sampling is irregular and the sampling rate
itself is a severity signal: sicker patients are measured more often.

### 5.6 Prevalent versus incident sepsis, and the landmark design

The onset-hour distribution reveals that about **34 percent of septic stays are
already septic at ICU admission** (onset hour 0). These prevalent cases are not
predictable in any real sense. The clinically useful target is **incident**
sepsis: onset among patients who are not yet septic. We isolate it with a
**landmark at hour 6**, conditioning on the first six hours and predicting onset
after that. This is exactly how a deployed model is used, and it removes the
prevalent cases that would otherwise flatter the metrics. At the hour-6
landmark, 48,829 stays remain at risk, of whom 9.7 percent later develop sepsis
and 6.8 percent within the next 12 hours.

### 5.7 Leakage-safe, patient-grouped, time-dependent evaluation

- **Patient-grouped splits.** Because the cohort is first-stay-only, no patient
  appears in both training and test folds.
- **Only-past information.** Features at the landmark use forward-filled values
  up to hour 6; nothing from the future enters the prediction.
- **Competing risks.** Death and discharge compete with sepsis onset. Treating
  a death as ordinary censoring overstates incidence, so a Fine-Gray model is
  used for the cumulative incidence.
- **Time-dependent discrimination.** We report AUROC as a function of the
  prediction horizon, not a single static number.

### 5.8 Statistical methods used, and why each

| Method | Where | Why it is there |
|---|---|---|
| EDA, effect sizes | 06 | Describe the data; with a large sample, effect size matters more than a p-value. |
| Welch t-test, Wilcoxon, chi-squared | 06 | Match the test to the distribution (unequal variance, skew, categorical). |
| Maximum likelihood estimation | 06 | Estimate the typical septic lactate under a log-normal model. |
| Logistic GLM | 06, 09 | The natural model for a binary outcome; interpretable odds ratios. |
| KDE and Gaussian mixture | 06 | Ask whether a single biomarker splits the groups without labels. |
| Metropolis-Hastings MCMC | 06 | Demonstrate Bayesian inference and show it agrees with MLE (see Section 5.9). |
| Hidden Markov model | 06, 09 | In 06 as a negative control on stay order; in 09 on real within-patient sequences. |
| Cross-validation, calibration, PR-AUC, decision curve | 06 | Out-of-sample honesty and clinical usefulness, not just ranking. |
| Splines / GAM, VIF | 06 | Test non-linearity of lactate; check collinearity. |
| Multiple imputation (MICE) | 06 | Address informative missingness rather than dropping incomplete cases. |
| Kaplan-Meier, log-rank | 09 | Time-to-onset accounting for censoring. |
| Cox and time-varying Cox | 09 | Hazard of onset from fixed and from hour-updated physiology. |
| Fine-Gray competing risks | 09 | Cumulative incidence with death as a competing event. |
| Autocorrelation, trajectories | 09 | Quantify within-patient temporal dependence. |
| Time-dependent ROC | 09 | Discrimination across horizons; the bar for Phase 2. |

### 5.9 Why we do not use Bayesian inference for the predictive model

Bayesian inference is used once, illustratively, in the cross-sectional report
(a Metropolis-Hastings sampler for the mean log-lactate). We deliberately do not
adopt it for the predictive and temporal modelling, for concrete reasons:

1. **The data dominate the prior.** With tens of thousands of observations, the
   likelihood overwhelms any reasonable prior. We showed this empirically in
   report 06: the Bayesian posterior mean and the maximum-likelihood estimate
   were almost identical. Paying the computational cost of MCMC to reproduce the
   MLE is not justified here.
2. **The objective is discrimination and calibration, not parameter
   uncertainty.** The quantities we care about (AUROC, PR-AUC, calibration,
   net benefit) are naturally produced by frequentist GLM, Cox and
   cross-validation. A full posterior over coefficients does not change the
   ranking of patients.
3. **Scale.** The hourly panel has 3.1 million rows. Full Bayesian sampling over
   a hierarchical model at this scale is expensive and slow to iterate, without
   a corresponding gain for the prediction task.
4. **Reproducibility and transparency.** Penalized logistic regression, Cox
   models and cross-validation are standard, fast, and easy for a reviewer to
   reproduce exactly with a fixed seed.

This is not a rejection of Bayesian methods in principle. They are the right
tool when samples are small, when strong external priors exist, or when
hierarchical partial pooling is needed (for example, sharing information across
ICUs or across patients). Two natural Phase-2 extensions are explicitly
Bayesian: a hierarchical model that partially pools across care units, and
Bayesian sequential updating of a patient's risk as each new hour arrives. We
keep the door open; we simply do not pay for it where it adds no value.

### 5.10 Engineering: memory-safe streaming and reproducibility

The multi-gigabyte tables are processed in chunks (`utils.stream_windowed_agg`
and the hourly aggregator in 07), accumulating partial statistics so the full
table is never in memory at once. Intermediates default to CSV for easy
inspection, with a parquet option for the large panels. Every random operation
uses the fixed seed 486649.

---

## 6. Results

**Labels (script 05).** Suspected infection 40.5 percent. Sepsis-3 at the stay
level 37.1 percent. Septic shock 9.2 percent. In-hospital mortality is 18.7
percent among septic stays versus 6.1 percent among non-septic stays, a threefold
separation that validates the label.

**Cross-sectional report (script 06).** Using only non-circular predictors, the
six-predictor logistic model reaches a cross-validated AUROC of about 0.66. It
is well calibrated (calibration slope near 1.0). Lactate has a clearly
non-linear effect (spline effective degrees of freedom about 4.5). Missingness
is informative: sepsis prevalence is 62.6 percent among stays with a measured
lactate versus 23.8 percent among those without.

**Temporal report (script 09).** At the hour-6 landmark, predicting incident
onset within 12 hours:

| Model or score | AUROC |
|---|---|
| SOFA at hour 6 | 0.36 (inverse) |
| qSOFA at hour 6 | 0.49 |
| SIRS at hour 6 | 0.59 |
| Multivariable logistic (static, 6 h) | 0.749 |
| Multivariable logistic + 6 h trajectory slopes | 0.755 |

The trajectory slopes add a small but statistically significant amount
(DeLong p about 3e-7). Within-patient heart-rate autocorrelation at lag one is
about 0.57, confirming real temporal structure, and a within-patient hidden
Markov model shows persistent physiologic states. At a sensible operating point
the 0.755 model gives roughly 71 percent sensitivity and 67 percent specificity;
raising sensitivity to 90 percent (screening mode) drops specificity to about 43
percent. Plain accuracy is not reported as a headline because the event rate is
only 6.8 percent, so a model that predicts "no sepsis" for everyone would score
about 93 percent accuracy while being useless.

---

## 7. Benchmarking: Why a Lower AUROC Is Still a Better Result

Published statistical AUROCs of about 0.75 to 0.85 look higher than our 0.755,
but they mostly solve an easier problem than ours.

- Most predict **mortality** or **diagnose already-present sepsis** in emergency
  department or general populations, where a high SOFA strongly flags the sick
  patient.
- Our task is genuinely harder: **incident onset among ICU patients who are not
  yet septic**, at a fixed landmark, with no future leakage. In that setting
  organ dysfunction is already widespread, so it barely discriminates.

The proof is in our own numbers on the same task: SOFA 0.36 (inverse), qSOFA
0.49, SIRS 0.59. The standard scores are near-useless for true early prediction,
far below their textbook 0.74 to 0.82. Our multivariable logistic at 0.755 beats
every single clinical score on that identical task, which is exactly the pattern
the nomogram papers report (multivariable regression beats single scores).

**Fair verdict.**

- On like-for-like early-onset prediction, our statistical model is competitive
  and clearly out-discriminates qSOFA, SIRS and SOFA, the expected and desired
  result for a nomogram-style approach.
- Versus the best published nomograms (0.82 to 0.85), ours is lower, but partly
  because (a) those target easier prevalent or mortality endpoints, and (b) our
  06 model was deliberately handicapped by excluding SOFA components to avoid
  circularity. A full-feature nomogram on our data (including all labs and organ
  markers) would likely reach about 0.80 or more.
- Methodologically, ours is more rigorous than most of these papers:
  patient-grouped cross-validation, a leakage-safe landmark, competing-risk and
  time-dependent evaluation, steps the typical cross-sectional nomogram skips.

So, as a statistical effort, this work is solidly in range, arguably ahead of
the pack on evaluation honesty, and only behind on headline AUROC because it
picked the harder, more realistic question. To close that gap while staying
purely statistical, the next move is a LASSO-penalized logistic nomogram using
the full feature set (all labs, organ markers and trajectory slopes) at the
landmark. We expect about 0.80 to 0.83, directly comparable to the published
nomograms.

Selected references for these numbers are listed in Section 11.

---

## 8. Limitations

1. **Label depends on clinician behaviour.** Onset is defined partly by when
   cultures and antibiotics are ordered, so incident onset reflects recognition
   timing as well as physiology. This caps the achievable performance of any
   model on this label.
2. **Single database, internal validation only.** All evaluation is internal
   cross-validation on MIMIC-IV. External validation on another database (for
   example eICU) is not yet done.
3. **Assumed-zero SOFA baseline** and the documented SOFA simplifications
   slightly overcount organ dysfunction.
4. **qSOFA uses mean arterial pressure as a proxy** for systolic pressure,
   because the panel carries MAP.
5. **The time-varying Cox and the HMM use sampled subsets** for tractability, so
   those hourly hazards are directional rather than precise.

---

## 9. Phase 2 (EXECUTED): a purely statistical real-time model

Phase 2 is now built, and — by design — **entirely with classical statistics**
(no gradient boosting, no neural sequence models). It reaches real-time
prediction through **dynamic landmarking** (van Houwelingen 2007). Scripts
`10`–`16` produce the intermediates; `17_phase2_report.Rmd` narrates them
(`17_phase2_report.pdf`). Full design in `GENAI/plan_phase2_statistical.md`.

| Tier | Script(s) | What it does | Headline result |
|---|---|---|---|
| 1 | `10_landmark_nomogram.R` | Full-feature elastic-net nomogram at h6 with informative-missingness design | AUROC **0.775** (vs Phase 1's 0.755; DeLong p≈0); measurement indicators dominate |
| 2 | `11_landmark_stack.py`, `12_supermodel.R` | Dynamic landmark **supermodel** across s∈{6..48}h → hourly-updating risk | AUC(s) 0.65–0.77, matching per-landmark models with one deployable model |
| 3 | `13_repeated_measures.R` | GEE (within-patient correlation) + ridge time-varying Cox | within-patient corr **0.68**; cluster-robust SEs up to **4.5×** naive |
| 4 | `14_realtime_holdout.py`, `15_realtime_eval.R` | PhysioNet utility score + **alarm-burden** on an hourly risk stream | utility (norm.) **0.29**; 90% sens ⇒ 6.5 false alarms/patient-day |
| 5 | `16_subgroup_fairness.R` | Subgroup calibration/AUROC by sex + age | well calibrated (ratio 0.94–1.06) across subgroups |

**Key finding.** The ceiling on this incident-onset task is set by the label's
dependence on *clinician recognition* (when cultures/antibiotics are ordered),
not by model class — which is why the largest predictors are missingness
indicators and why a purely statistical model is competitive. No neural network
was required to reach the real-time goal.

**Remaining honest gap.** External validation on a second database (eICU) is
**deferred** — no eICU database is present locally. The within-MIMIC fairness
check (Tier 5) stands in until it is available.

---

## 10. Reproducibility: Environment and Run Order

**Python.** Use the framework Python that has pandas (pandas 3.x). Do not use the
system `/usr/bin/python3`, which lacks pandas. Install dependencies:

```bash
pip3 install -r requirements.txt
```

**Paths** are auto-detected by walking up to find `data/mimic-iv-3.1`. Override
with `export MIMIC_RESEARCH_ROOT=/path/to/RESEARCH` if needed.

**Run order** (from `projects/sepsis_mimic4/`):

```bash
python3 01_explore_data.py --count-small
python3 02_extract_cohort.py
python3 03_suspected_infection.py            # surveillance swabs excluded by default
python3 04_extract_measurements.py           # heavy: streams about 6 GB
python3 05_sofa_sepsis3.py
Rscript -e 'rmarkdown::render("06_statistical_report.Rmd")'
python3 07_hourly_panel.py                   # heavy: builds 3.1M stay-hours
python3 08_onset_label.py
Rscript -e 'rmarkdown::render("09_temporal_report.Rmd")'

# Phase 2 (purely statistical; fast — reuses the 08 outputs, no heavy recompute)
Rscript 10_landmark_nomogram.R               # Tier 1: full-feature nomogram
python3 11_landmark_stack.py                 # Tier 2: stacked landmark dataset
Rscript 12_supermodel.R                      # Tier 2: dynamic supermodel (~3 min)
Rscript 13_repeated_measures.R               # Tier 3: GEE + time-varying Cox
python3 14_realtime_holdout.py               # Tier 4: holdout hourly stream
Rscript 15_realtime_eval.R                   # Tier 4: utility + alarm burden
Rscript 16_subgroup_fairness.R               # Tier 5: subgroup calibration
Rscript -e 'rmarkdown::render("17_phase2_report.Rmd")'
```

**R packages.** Report 06 needs `rmarkdown, bookdown, tidyverse, knitr,
kableExtra, MASS, mclust, coda, depmixS4, effectsize, broom, patchwork, pROC,
PRROC, mgcv, car, mice`. Report 09 additionally needs `survival, cmprsk,
timeROC`. **Phase 2 additionally needs `glmnet, rms, geepack, sandwich`.** A
LaTeX engine (TinyTeX or MacTeX) is required for PDF output.

---

## 11. Repository Map and References

```
projects/sepsis_mimic4/
  config.py                    paths, itemids, thresholds, surveillance-swab list
  utils.py                     streaming reads, IO, dictionary mining
  01_explore_data.py .. 05_sofa_sepsis3.py     static branch
  06_statistical_report.Rmd    cross-sectional report
  07_hourly_panel.py           hourly panel (temporal substrate)
  08_onset_label.py            hourly SOFA, onset labels, landmark, baselines
  09_temporal_report.Rmd       longitudinal report
  10_landmark_nomogram.R       PHASE 2 T1: full-feature elastic-net nomogram @ h6
  11_landmark_stack.py         PHASE 2 T2: stacked multi-landmark dataset
  12_supermodel.R              PHASE 2 T2: dynamic landmark supermodel, AUC(s)
  13_repeated_measures.R       PHASE 2 T3: GEE + ridge time-varying Cox
  14_realtime_holdout.py       PHASE 2 T4: all-hours holdout feature stream
  15_realtime_eval.R           PHASE 2 T4: PhysioNet utility + alarm burden
  16_subgroup_fairness.R       PHASE 2 T5: subgroup calibration (eICU deferred)
  17_phase2_report.Rmd         PHASE 2 report (PDF)
  GENAI/
    HANDOFF.md                 cold-start context for the whole project
    plan.md                    the Phase 1 plan (executed)
    plan_phase2_statistical.md the Phase 2 plan (executed, purely statistical)
    README.md                  this document
```

**Primary references.**

1. Singer M, et al. (2016). The Third International Consensus Definitions for
   Sepsis and Septic Shock (Sepsis-3). JAMA 315(8).
2. Seymour CW, et al. (2016). Assessment of Clinical Criteria for Sepsis. JAMA
   315(8).
3. Vincent JL, et al. (1996). The SOFA score. Intensive Care Medicine 22(7).
4. Reyna MA, et al. (2020). Early Prediction of Sepsis from Clinical Data: the
   PhysioNet/CinC Challenge 2019. Critical Care Medicine 48(2).
5. Fine JP, Gray RJ (1999). A Proportional Hazards Model for the Subdistribution
   of a Competing Risk. JASA 94(446).
6. Blanche P, et al. (2013). Estimating and comparing time-dependent areas under
   ROC curves. Statistics in Medicine 32(30).
7. van Houwelingen HC (2007). Dynamic prediction by landmarking. Scandinavian
   Journal of Statistics 34(1).

**Benchmark sources (comparative AUROCs in Section 7).**

- SIRS, SOFA, qSOFA, NEWS systematic review and meta-analysis (2023),
  Expert Review of Anti-infective Therapy 21(8).
- NEWS, SIRS and qSOFA with logistic models on CETAT and MIMIC-IV (2024).
- MIMIC nomograms (LASSO plus logistic) outperforming the SOFA score.
- qSOFA, SIRS and NEWS mortality meta-analysis (2022).
```
