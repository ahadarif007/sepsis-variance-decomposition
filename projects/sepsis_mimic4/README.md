# Time-Varying Statistical Modeling for Real-Time Sepsis Onset Prediction

A reproducible, purely statistical pipeline for **real-time sepsis onset
prediction** on **MIMIC-IV v3.1**, **externally validated on eICU-CRD**
(200+ US ICUs). No machine learning or deep learning. Every model is
interpretable and benchmarked against established clinical scores.

> **Research question:** Can a time-varying Cox / landmark statistical model,
> using routinely available ICU vitals and labs, predict impending Sepsis-3
> onset ahead of clinical recognition, outperforming SIRS, qSOFA, and NEWS?

---

## 1. Data

| Item | Detail |
|---|---|
| **Primary dataset** | MIMIC-IV v3.1 (`data/mimic-iv-3.1/{hosp,icu}/*.csv`) |
| **External validation** | eICU-CRD v2.0 (`data/eicu-collaborative-research-database-2.0/`), 136,864 stays across 200+ ICUs |
| **Cohort** | Adults >= 18, first ICU stay only, LOS >= 4h, yields **65,241 stays** |
| **Heavy tables** | `chartevents` ~3.3 GB, `labevents` ~2.4 GB (streamed in chunks, never loaded whole) |

---

## 2. Pipeline Overview

```
                        data/mimic-iv-3.1  (raw, read-only)
                                  |
                                  v
                       01  explore and profile data
                                  |
                                  v
                       02  extract adult ICU cohort (65,241 stays)
                                  |
                                  v
                       03  detect suspected infection (antibiotics x cultures)
                                  |
                   _______________|________________
                  |                                |
       STATIC (understanding)            TEMPORAL (prediction)
                  |                                |
                  v                                v
       04  first-24h measurements        07  hourly panel (3.1M rows)
                  |                                |
                  v                                v
       05  SOFA scoring + labels         08  onset labelling + landmark cohort
                  |                                |
                  v                                v
       06  cross-sectional report        09  longitudinal report
                 (PDF)                           (PDF)
                                                   |
                    _______________________________|
                    |
                    v
       10  full-feature nomogram at hour 6         (Tier 1)
                    |
                    v
       11  stack multiple landmark time points      (Tier 2a)
                    |
                    v
       12  fit landmark supermodel                  (Tier 2b)
                    |
                    v
       13  GEE + time-varying Cox                   (Tier 3)
                    |
                    v
       14  prepare holdout feature stream            (Tier 4a)
                    |
                    v
       15  evaluate as streaming alarm               (Tier 4b)
                    |
                    v
       16  subgroup fairness check                   (Tier 5)
                    |
                    v
       18  trajectory class discovery (GBTM)         (Tier 6)
                    |
                    v
       19  causal analysis (PSM / IPW)               (Tier 7)
                    |
                    v
       20  final combined report (PDF)
                    |
                    v
       21  eICU external panel  ->  landmark_h6_eicu.csv
       22  external validation (frozen transport + recalibration + eICU ceiling)
```

Scripts 21-22 externally validate the frozen Tier-1 nomogram on eICU-CRD v2.0
(see §9, "External validation").

---

## 3. Running the Pipeline

All commands run from `projects/sepsis_mimic4/`. Paths are auto-detected by `config.py`.
Override with `export MIMIC_RESEARCH_ROOT=/path/to/RESEARCH` if needed.

### Prerequisites

```bash
pip3 install -r requirements.txt
```

Python 3.x with pandas, R 4.x, and a LaTeX engine (TinyTeX or MacTeX) are required.

R packages: `rmarkdown, bookdown, tidyverse, knitr, kableExtra, MASS,
mclust, coda, depmixS4, effectsize, broom, patchwork, pROC, PRROC, mgcv, car,
mice, survival, cmprsk, timeROC, glmnet, rms, geepack, sandwich, flexmix,
MatchIt, WeightIt, cobalt`.

---

### Data preparation

**01. Explore data** (Python)
Profiles every MIMIC table, confirms that the expected itemids exist, and gives an overview of data quality.

```bash
python3 01_explore_data.py --count-small
```

**02. Extract cohort** (Python)
Selects adult patients (>= 18), keeps only their first ICU stay, applies a minimum 4-hour length-of-stay filter, and adds mortality flags.

```bash
python3 02_extract_cohort.py
```

**03. Suspected infection** (Python)
Pairs antibiotic orders with microbiology cultures inside the Sepsis-3 time windows to find the earliest moment each patient was suspected of having an infection. Surveillance swabs (e.g. MRSA screens) are excluded by default.

```bash
python3 03_suspected_infection.py
```

---

### Static branch (understanding)

**04. Extract measurements** (Python, heavy)
Streams the large chartevents and labevents tables in chunks and extracts first-24-hour vitals and labs for every stay. This is one of the two slow stages because it reads ~6 GB of raw data.

```bash
python3 04_extract_measurements.py
```

**05. SOFA and Sepsis-3 labels** (Python)
Scores each of the six SOFA organ systems, computes total SOFA, and applies the Sepsis-3 label (suspected infection + SOFA >= 2) and the septic-shock label.

```bash
python3 05_sofa_sepsis3.py
```

**06. Cross-sectional statistical report** (R Markdown, produces PDF)
A comprehensive statistical analysis of the cohort at a single time point: EDA, hypothesis tests, logistic regression, kernel density estimation, Bayesian MCMC demo, hidden Markov model, cross-validation with calibration, multiple imputation (MICE).

```bash
Rscript -e 'rmarkdown::render("06_statistical_report.Rmd")'
```

---

### Temporal branch (prediction)

**07. Hourly panel** (Python, heavy)
Resamples every stay into an hourly grid (one row per stay-hour, ~3.1 million rows). For each variable it stores the raw value, a forward-filled version (what the clinician currently knows), and a time-since-last-measured counter.

```bash
python3 07_hourly_panel.py
```

**08. Onset labelling** (Python)
Computes hourly SOFA scores, locates the exact hour each patient first meets Sepsis-3, builds a binary "will develop sepsis within 12h" label at each hour, creates the hour-6 landmark cohort, and computes clinical score baselines (SIRS, qSOFA, NEWS).

```bash
python3 08_onset_label.py
```

**09. Longitudinal statistical report** (R Markdown, produces PDF)
Survival analysis on the time axis: Kaplan-Meier curves, Cox proportional hazards, time-varying Cox, Fine-Gray competing risks (death vs sepsis), autocorrelation structure, within-patient HMM, and time-dependent AUC benchmarked against clinical scores.

```bash
Rscript -e 'rmarkdown::render("09_temporal_report.Rmd")'
```

---

### Real-time model (Tiers 1 to 7)

All scripts below reuse the outputs from script 08. They are fast and do not need to re-read the raw data.

**10. Nomogram (Tier 1)** (R Markdown, produces PDF)
Builds a full-feature elastic-net penalized logistic model at the hour-6 landmark. Uses an informative-missingness design: median-impute each lab, then add a binary "was it measured" indicator. Produces a clinician-facing nomogram and calibration plot.

```bash
Rscript -e 'rmarkdown::render("10_landmark_nomogram.Rmd")'
```

**11. Landmark stack (Tier 2a)** (Python)
Creates a single stacked dataset by repeating the modelling at multiple landmark times (6h, 12h, 18h, 24h, 36h, 48h). This is the input to the dynamic supermodel.

```bash
python3 11_landmark_stack.py
```

**12. Supermodel (Tier 2b)** (R Markdown, produces PDF)
Fits one "supermodel" across all the stacked landmarks so that a single model can emit an hourly-updating risk score at any point during the stay.

```bash
Rscript -e 'rmarkdown::render("12_supermodel.Rmd")'
```

**13. Repeated measures (Tier 3)** (R Markdown, produces PDF)
Fits GEE (Generalized Estimating Equations) to properly account for within-patient correlation in hourly data, and a ridge-penalized time-varying Cox model. Reports how much the standard errors inflate when correlation is handled correctly.

```bash
Rscript -e 'rmarkdown::render("13_repeated_measures.Rmd")'
```

**14. Holdout feature stream (Tier 4a)** (Python)
Builds an all-hours feature table for a random 6,000-stay holdout set. This is the test bed for simulating a real-time alarm system.

```bash
python3 14_realtime_holdout.py
```

**15. Real-time evaluation (Tier 4b)** (R Markdown, produces PDF)
Runs the supermodel on the holdout hour-by-hour, computes the PhysioNet/CinC 2019 utility score, and reports alarm burden (false alarms per patient-day at various sensitivity thresholds).

```bash
Rscript -e 'rmarkdown::render("15_realtime_eval.Rmd")'
```

**16. Subgroup fairness (Tier 5)** (R Markdown, produces PDF)
Checks whether the model is equally well-calibrated and discriminating across sex and age subgroups.

```bash
Rscript -e 'rmarkdown::render("16_subgroup_fairness.Rmd")'
```

**18. GBTM trajectories (Tier 6)** (R Markdown, produces PDF)
Group-Based Trajectory Modelling: discovers latent classes of SOFA-score trajectories over the first 24 hours (e.g. "stable-low", "moderate-rising", "steep-worsening"), then links each class to mortality (Cox) and incident sepsis (logistic regression).

```bash
Rscript -e 'rmarkdown::render("18_gbtm_trajectories.Rmd")'
```

**19. Confounder adjustment (Tier 7)** (R Markdown, produces PDF)
Uses LASSO to select confounders, then estimates the causal effect of early antibiotics (<= 3h) on mortality using four methods: propensity-score matching (PSM), inverse probability weighting (IPW), augmented IPW, and doubly-robust estimation.

```bash
Rscript -e 'rmarkdown::render("19_confounder_adjustment.Rmd")'
```

**20. Final report** (R Markdown, produces PDF)
Narrates Tiers 1 through 7 into a single PDF report with all tables and figures.

```bash
Rscript -e 'rmarkdown::render("20_realtime_model_report.Rmd")'
```

**21. eICU external panel** (Python)
Rebuilds the hour-6 landmark table on eICU-CRD v2.0 using the identical cohort,
hourly-panel, SOFA, onset, and feature definitions as the MIMIC pipeline
(`02/03/07/08`). Emits `landmark_h6_eicu.csv`. Heavy: streams `vitalPeriodic`
(1.7 GB), `nurseCharting` (1.6 GB), and `lab` (0.5 GB) in chunks.

```bash
python 21_eicu_external_panel.py
```

**22. External validation** (R Markdown, produces PDF)
Applies the **frozen** Tier-1 nomogram (`tier1_coefs.csv`) to eICU without
refitting, reporting: frozen-transport AUROC + DeLong CI, calibration
slope/intercept, one-line recalibration, and an internal eICU elastic-net
ceiling that separates loss of discrimination from miscalibration.

```bash
Rscript -e 'rmarkdown::render("22_external_validation.Rmd")'
```

---

## 4. Shared Modules

| File | Purpose |
|---|---|
| `config.py` | Single source of truth for all file paths, MIMIC itemids, clinical thresholds, and surveillance-swab filters. |
| `utils.py` | Streaming I/O helpers, memory-safe chunked aggregation, and dictionary mining utilities. |

---

## 5. Key Design Decisions

**Cohort.** Adults only, first ICU stay per patient (ensures statistical independence), minimum 4-hour stay (ultra-short stays are usually administrative).

**Suspected infection.** Follows Seymour et al. (2016): antibiotics paired with cultures. Surveillance swabs (MRSA screens) are excluded to avoid inflating the suspected-infection rate from 51.5% to a clinically implausible level.

**SOFA scoring.** Assumed-zero baseline per Sepsis-3. In the static branch (script 05) SOFA uses the first 24 hours. In the temporal branch (script 08) SOFA is scored every hour from the forward-filled panel.

**Non-circular predictors.** The cross-sectional model (script 06) deliberately excludes SOFA components from the predictor set to avoid the model partly re-deriving its own target. The Tier 1 nomogram (script 10) lifts this restriction and uses all features.

**Incident vs prevalent sepsis.** About 34% of septic stays are already septic at admission. The pipeline isolates incident (new-onset) sepsis using a landmark at hour 6, which is the clinically useful prediction target.

**Memory-safe streaming.** The multi-gigabyte tables are processed in chunks (via `utils.stream_windowed_agg` and chunked readers in scripts 04 and 07). The full table is never held in memory.

**Reproducibility.** Every random operation uses the fixed seed 486649.

**Temporal resolution: why hourly, not per-second.** ICU data in MIMIC-IV is
irregularly sampled, not a uniform per-second stream. Vitals (heart rate, blood
pressure, SpO2, respiratory rate) are charted every 1–5 minutes by nurses or
monitor snapshots. Temperature and GCS are recorded every 1–4 hours. Labs
(lactate, creatinine, WBC) arrive every 4–12 hours, ordered on clinical
suspicion. SOFA components are only meaningful at hourly granularity or coarser.
Hourly aggregation (script 07) is the natural resolution that balances signal
density against computational tractability and matches the PhysioNet/CinC 2019
Challenge benchmark.

**Prediction mechanism: expanding window with dynamic landmarking.** The
supermodel (script 12) uses an *expanding window*, not a fixed-width sliding
window. At each hour h (starting from h = 6), the model sees all available data
from admission up to hour h and predicts onset within the next 12 hours:

```
Hour  6:  features from [0, 6]   →  P(onset in 6–18h)
Hour  7:  features from [0, 7]   →  P(onset in 7–19h)
Hour  8:  features from [0, 8]   →  P(onset in 8–20h)
  ...
Hour 48:  features from [0, 48]  →  P(onset in 48–60h)
```

Within this expanding window, slope features (e.g. heart-rate trend over the
last 6 hours) act as a *local sliding window* that captures recent deterioration.
The supermodel includes interaction terms between features and landmark time
(s, s²) so that the coefficient surface adapts as the stay progresses. This
means the model recalibrates its predictions at every hour — a patient whose
vitals were stable at hour 6 but deteriorate at hour 12 will see a rising risk
score without any manual threshold adjustment.

**Why not per-second prediction?** Treatment decisions in the ICU (antibiotics,
fluids, vasopressors) operate on 30-minute to multi-hour timescales. Per-second
prediction would require continuous waveform data (e.g. MIMIC-III Waveform
Database or live bedside monitors), a streaming model architecture (RNN or
streaming transformer), and edge deployment — a fundamentally different system
from the interpretable statistical early-warning tool built here. The hourly
resolution is standard in the sepsis prediction literature and is the granularity
at which clinical action can realistically occur.

---

## 6. Key Results

### Benchmarking clinical scores (hour-6 landmark, incident onset within 12h)

| Model / Score | AUROC |
|---|---|
| SOFA at hour 6 | 0.36 (inverse) |
| qSOFA at hour 6 | 0.49 |
| SIRS at hour 6 | 0.59 |
| Multivariable logistic + trajectory slopes | 0.755 |
| Full-feature elastic-net nomogram (Tier 1) | **0.775** |

Standard clinical scores are near-useless for true early prediction of incident
onset in ICU patients. Our multivariable model beats every clinical score on the
same task, consistent with the pattern seen in the nomogram literature.

### Real-time model summary

| Tier | Headline |
|---|---|
| 1. Nomogram | AUROC 0.775; missingness indicators are the strongest predictors |
| 2. Supermodel | AUC(s) 0.65 to 0.77 across landmark hours; one deployable model |
| 3. GEE / TV-Cox | Within-patient correlation 0.68; cluster-robust SEs up to 4.5x naive |
| 4. Utility | PhysioNet utility (norm.) 0.29; 90% sensitivity gives 6.5 false alarms/patient-day |
| 5. Fairness | Well calibrated across sex and age subgroups (ratio 0.94 to 1.06) |
| 6. GBTM | 3 latent trajectory classes; steepest-worsening has ~5x mortality HR |
| 7. Causal | Early antibiotics (<= 3h) associated with lower mortality across all four estimators |

### External validation on eICU-CRD (frozen Tier-1 nomogram, no refitting)

Applied as-is to 113,597 at-risk eICU stays across 200+ US ICUs (4,782 incident
onsets within 12h of the hour-6 landmark):

| Metric | eICU | MIMIC (development) |
|---|---|---|
| AUROC (frozen transport) | **0.686** (95% CI 0.678–0.694) | 0.775 |
| AUROC (internal eICU refit ceiling) | 0.712 | — |
| Calibration slope | 0.537 | 1.0 |
| Mean predicted vs observed risk | 0.121 vs 0.042 | — |
| Brier (frozen → recalibrated) | 0.052 → 0.040 | 0.059 |

Discrimination transports with modest degradation — the frozen model (0.686)
sits close to what an eICU-native refit could achieve at all (0.712), so most of
the drop from MIMIC's 0.775 reflects a harder, more heterogeneous multi-centre
population and the antibiotic-only suspicion label, not model failure. The model
is **miscalibrated** on eICU (over-predicts ~3×, slope 0.54, from the lower
onset base rate), which a one-line intercept/slope recalibration corrects
(Brier 0.052 → 0.040; see `figure/calibration_eicu.png`).

### Key finding

The ceiling on the incident-onset prediction task is set by the label's
dependence on clinician recognition (when cultures and antibiotics are ordered),
not by model class. This is why the strongest predictors are missingness
indicators, and why a purely statistical model is competitive. No neural
network was required.

### Limitations

1. Sepsis onset label depends on clinician recognition timing, capping any model's performance.
2. eICU external validation triggers suspected infection on antibiotics alone
   (culture refines timing when present): eICU captures microbiology for only
   ~1.5% of stays vs ~83% for antibiotics, so a culture requirement would make
   the *label*, not the model, untransportable.
3. Assumed-zero SOFA baseline slightly overcounts organ dysfunction.
4. qSOFA uses mean arterial pressure as a proxy for systolic pressure.
5. Time-varying Cox and HMM use sampled subsets for tractability.

---

## 7. Repository Map

```
RESEARCH/
├── data/mimic-iv-3.1/{hosp,icu}/*.csv       raw MIMIC-IV (read-only)
├── processed_data/                          all pipeline outputs (CSV, Parquet)
└── projects/sepsis_mimic4/
    ├── config.py                            paths, itemids, thresholds
    ├── utils.py                             streaming I/O and helpers
    ├── 01_explore_data.py                   data profiling
    ├── 02_extract_cohort.py                 cohort extraction
    ├── 03_suspected_infection.py            infection suspicion detection
    ├── 04_extract_measurements.py           first-24h feature extraction
    ├── 05_sofa_sepsis3.py                   SOFA scoring and Sepsis-3 labels
    ├── 06_statistical_report.Rmd (.pdf)     cross-sectional analysis report
    ├── 07_hourly_panel.py                   hourly time-series panel
    ├── 08_onset_label.py                    onset labelling and landmark cohort
    ├── 09_temporal_report.Rmd (.pdf)        longitudinal analysis report
    ├── 10_landmark_nomogram.Rmd             Tier 1: elastic-net nomogram
    ├── 11_landmark_stack.py                 Tier 2: stacked landmark dataset
    ├── 12_supermodel.Rmd                    Tier 2: dynamic supermodel
    ├── 13_repeated_measures.Rmd             Tier 3: GEE + time-varying Cox
    ├── 14_realtime_holdout.py               Tier 4: holdout feature stream
    ├── 15_realtime_eval.Rmd                 Tier 4: utility + alarm evaluation
    ├── 16_subgroup_fairness.Rmd             Tier 5: subgroup calibration
    ├── 18_gbtm_trajectories.Rmd             Tier 6: GBTM trajectory classes
    ├── 19_confounder_adjustment.Rmd         Tier 7: PSM / IPW / doubly-robust
    ├── 20_realtime_model_report.Rmd (.pdf)  final combined report
    ├── 21_eicu_external_panel.py            eICU hour-6 landmark rebuild
    ├── 22_external_validation.Rmd (.pdf)    eICU external validation
    ├── figure/                              all generated plots
    └── GENAI/
        ├── HANDOFF.md                       cold-start context document
        ├── sepsis_mimic4_literature_review.md   literature review (18 studies)
        └── sepsis_mimic4_project_plan.md    MSc project proposal
```

---

## 8. References

1. Singer M, et al. (2016). Sepsis-3. *JAMA* 315(8). `10.1001/jama.2016.0287`
2. Seymour CW, et al. (2016). Clinical Criteria for Sepsis. *JAMA* 315(8). `10.1001/jama.2016.0288`
3. Vincent JL, et al. (1996). The SOFA score. *Intensive Care Med* 22(7).
4. Reyna MA, et al. (2020). PhysioNet/CinC 2019 Challenge. *Crit Care Med* 48(2). `10.1097/CCM.0000000000004145`
5. van Houwelingen HC (2007). Dynamic prediction by landmarking. *Scand J Stat* 34(1).
6. Fine JP, Gray RJ (1999). Competing risks. *JASA* 94(446).
7. Yang R, et al. (2022). GBTM of SOFA trajectories. *J Intensive Med*. `10.1016/j.jointm.2021.11.001`
8. Guo P, et al. (2025). PSM / IPW / doubly-robust in MIMIC-IV sepsis. *Front Med*. `10.3389/fmed.2025.1555103`
9. Zou ZY, et al. (2022). Cox + PSM in MIMIC-IV. *Burns Trauma*. `10.1093/burnst/tkac029`
