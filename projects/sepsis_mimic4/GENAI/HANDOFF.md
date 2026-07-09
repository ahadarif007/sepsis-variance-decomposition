# GENAI Handoff — MIMIC-IV Sepsis-3 Pipeline & Statistical Report

> Purpose of this file: let another AI assistant (or a human) **continue this
> project cold**, with full context on what was built, why, the current state,
> and the exact next steps. Read this top to bottom before touching anything.

Last updated: 2026-07-09. Author of work: Claude (Anthropic), working with the
user **Abdul Ahad** (email ahadarif.1998@gmail.com; PyCharm on macOS).

> **2026-07-09 UPDATE — single-study framing; Tiers 6-7 added.** The user
> asked to stop framing this as two research efforts ("Phase 1" / "Phase 2")
> since it is **one research programme** — the whole pipeline `01`→`20` is
> now described that way throughout code, reports, and README. Concretely:
> - **Renamed** every `phase2_tier*.csv` artifact to `tier*.csv` (also fixed
>   `tier3_glmm.csv` → `tier3_gee.csv`, since the script fits GEE, not a GLMM —
>   a pre-existing naming/doc mismatch). Scripts `10,12,13,15,16` updated to
>   match; all five re-run and verified to reproduce the original numbers.
> - **Renamed** `17_phase2_report.Rmd` → `20_realtime_model_report.Rmd`
>   (renumbered so the final report sits after the new Tiers 6-7 below).
> - **Two new tiers**, closing gaps the literature review flagged against
>   comparable MIMIC-IV statistical studies: **Tier 6** (`18_gbtm_trajectories.R`)
>   fits group-based trajectory modelling (flexmix latent-class growth model,
>   since `lcmm`/`traj` aren't installed) on first-24h SOFA trajectories,
>   linking class membership to mortality (Cox) and incident Sepsis-3
>   (logistic) — following Yang et al. 2022. **Tier 7**
>   (`19_confounder_adjustment.R`) uses LASSO-selected confounders, then PSM /
>   IPW / doubly-robust (augmented-IPW) estimation of the effect of early
>   (≤3h) antibiotics on mortality — following Guo et al. 2025 and Zou et al.
>   2022. New R packages: `flexmix, MatchIt, WeightIt, cobalt` (installed this
>   session). Both ran cleanly end-to-end; see README §9 for headline numbers.
> - **Dead code removed:** `utils.read_filtered` and `utils.load_dict_items`
>   (both unused), unused `numpy` imports in `02`/`04`, and the stale
>   `cohort.parquet` / `suspected_infection.parquet` leftovers (pre-CSV-switch
>   artifacts; `02`/`03` docstrings corrected to say CSV, not parquet).
> - **Two new files appeared in this folder mid-session**
>   (`sepsis_mimic4_literature_review (2).md`, `sepsis_mimic4_project_plan.md`)
>   — a more rigorous, dissertation-style companion review (18 studies) and
>   project plan, not authored by this session. Cross-checked against the
>   pipeline: its two live methodological asks — formally test the
>   proportional-hazards assumption (Kasal et al. 2004) and respond if it
>   fails — are **already satisfied**: `09_temporal_report.Rmd` runs
>   `cox.zph`, finds the global test fails, and fits a time-varying Cox model
>   in response (see `09_temporal_report.Rmd:193-206`). External validation on
>   eICU remains the one open item in both documents and here.
>
> **CURRENT STATUS IN ONE LINE (2026-07-09):** the whole pipeline `01`→`20` is
> built and run, covering Tiers 1-7. The only outstanding work is **external
> validation on eICU** (deferred — no eICU database is present locally). Read
> the dated update banners below (newest first), then the section detail.
> Where a section body still says "[NOT RUN]" it has been corrected inline;
> trust the banners + §3/§5 status markers as of this date. Some body text
> below still says "Phase 1" / "Phase 2" as a historical record of how the
> work was originally sequenced — the pipeline and its docs no longer use
> that framing going forward.

> **2026-07-08 UPDATE — PHASE 2 EXECUTED (purely statistical).** The real-time
> model is now built with classical statistics only (no ML/DL), reaching
> real-time prediction via **dynamic landmarking**. New scripts `10`–`16` +
> report `17_phase2_report.Rmd` (rendered). Plan & results in
> `GENAI/plan_phase2_statistical.md`; summary table in README §9. Outputs:
> `processed_data/phase2_tier{1..5}*.csv`, figures in `figure/`. Headlines:
> Tier 1 nomogram **0.775** AUROC (informative-missingness indicators dominate);
> Tier 2 landmark **supermodel** gives hourly-updating risk, AUC(s) 0.65–0.77;
> Tier 3 GEE within-patient corr 0.68, cluster-robust SEs up to 4.5× naive
> (a per-patient random-intercept GLMM is DEGENERATE here — quasi-complete
> separation — so GEE + sandwich SEs were used instead); Tier 4 PhysioNet
> utility 0.29 + alarm-burden curve; Tier 5 subgroup fairness OK, **eICU external
> validation deferred (no eICU data locally)**. New R pkgs used: `glmnet, rms,
> geepack, sandwich` (geepack was installed this session). Everything reuses the
> Phase-1 substrate (`hourly_labeled.parquet`, `landmark_h6.csv`); no heavy
> recompute (04/07) was needed.

> **2026-07-01 UPDATE — the real goal & plan.md execution.** The user clarified
> the project's true objective: a **real-time, hourly sepsis-onset early-warning
> system** from ICU time series. The cross-sectional work (01–06) is only the
> descriptive/inferential first layer. See `GENAI/plan.md` for the full gap
> analysis and phased plan; it has now been **executed**:
> - **MRSA-SCREEN resolved** (was the long-standing open question). Surveillance
>   swabs are now excluded by default (`config.EXCLUDE_SURVEILLANCE_CULTURES`,
>   `SURVEILLANCE_SPEC_TYPES`). `03` re-run: suspected infection 51.5% → **40.5%**;
>   `05` re-run: Sepsis-3 **37.1%** (septic mortality 18.7% vs 6.1% — label validates).
> - **`06` hardened & re-rendered on real data**: added out-of-sample 10-fold CV
>   AUC, calibration (Brier + curve), PR-AUC + decision curve, GAM/spline
>   non-linearity, VIF, and a missingness section (informative missingness +
>   MICE). Needs pkgs `pROC, PRROC, mgcv, car, mice` (installed).
> - **`07_hourly_panel.py`** (NEW, heavy): resamples every stay to an hourly grid
>   → `hourly_panel.parquet` (3.10M stay-hours; `_ff`/`_tsl` companions).
> - **`08_onset_label.py`** (NEW): hourly SOFA + **sepsis onset hour** + per-hour
>   early-warning label; emits `hourly_labeled.parquet`, `onset_summary.csv`, and
>   R-friendly `landmark_h6.csv` / `traj_means.csv` / `panel_sample_long.csv`.
> - **`09_temporal_report.Rmd`** (NEW): the longitudinal report — KM, Cox +
>   **time-varying Cox**, **Fine–Gray competing risks**, ACF/trajectories,
>   **within-patient HMM**, and time-dependent AUC vs qSOFA/SIRS/SOFA baselines.
>   Needs pkgs `survival, cmprsk, timeROC, depmixS4` (installed). Rendered PDF.
> Key finding: incident (post-6h) Sepsis-3 is gated by *new infection
> recognition*, so single severity scores are weak/inverse (SOFA AUC 0.36); a
> multivariable hourly model hits CV AUC ~0.75 and **trajectory slopes add
> significant signal** (DeLong p≈3e-7) — the empirical case for Phase 2.
> Sections below describe the ORIGINAL 01–06 pipeline; treat 07–09 as the
> temporal layer added on top.

---

## 1. Mission

Build a reproducible pipeline on **MIMIC-IV v3.1** that:

1. Constructs an adult ICU cohort.
2. Labels each ICU stay as **Sepsis-3** (suspected infection **AND** an acute
   SOFA rise ≥ 2) vs. not.
3. Produces an **R Markdown statistical report** analysing **Sepsis-3 vs no
   sepsis**, deliberately modelled on a prior student report the user wrote
   ("Statistical Analysis of Breast Tumour Cell Malignancy"). Same skeleton:
   EDA → hypothesis tests (with effect sizes) → MLE → GLM → KDE + Gaussian
   mixture → Metropolis-Hastings MCMC → Hidden Markov Model → conclusion.

The report's binary outcome was an explicit user choice: **Sepsis-3 vs no
sepsis** (they were offered mortality or suspected-infection instead). This is
why the heavy SOFA-labeling stages had to be built before the report.

---

## 2. CRITICAL environment facts (read first — these caused real bugs)

| Fact | Detail |
|---|---|
| **Python with pandas** | `/Library/Frameworks/Python.framework/Versions/3.14/bin/python3` — pandas **3.0.4**. This is what the shell's `python3` resolves to. |
| **System python (AVOID)** | `/usr/bin/python3` has **no pandas**. PyCharm defaulted to this and threw `ModuleNotFoundError: No module named 'pandas'`. Fix: point PyCharm's interpreter at the framework build above, or run from the terminal. |
| **pandas 3.0 Arrow strings** | pandas 3.0 stores text columns as Arrow `large_string`. **CSV datetime columns load back as `str`**, and `str - Timedelta` raises `ArrowNotImplementedError`. **Always `parse_dates=[...]` when loading CSV datetimes.** This bit us in `03` (now fixed via `U.load(..., parse_dates=...)`). |
| **R** | `/usr/local/bin/Rscript` — R **4.5.2**. Report 06 pkgs: `rmarkdown, bookdown, tidyverse, knitr, kableExtra, MASS, mclust, coda, depmixS4, effectsize, broom, patchwork, pROC, PRROC, mgcv, car, mice`. Report 09 adds `survival, cmprsk, timeROC`. **Phase 2 adds `glmnet, rms, geepack, sandwich`** (all installed; `geepack` was installed 2026-07-08). `pdflatex` present at `/Library/TeX/texbin/`. `pdftoppm`/`pdftools` NOT installed (can't rasterize PDF for inspection). |
| **Data root** | `/Users/arif/Desktop/RESEARCH/data/mimic-iv-3.1/` with `hosp/` and `icu/` subdirs, all `*.csv.gz`. |
| **Outputs** | `/Users/arif/Desktop/RESEARCH/processed_data/` |
| **Project code** | `/Users/arif/Desktop/RESEARCH/projects/sepsis_mimic4/` (this pipeline lives in a subfolder because the wider `RESEARCH/` project "will be tremendously big in future"). |
| **Path auto-detection** | `config.py` walks up parents until it finds `data/mimic-iv-3.1`, so scripts run correctly from the project subfolder and write to `RESEARCH/processed_data/`. Override with env var `MIMIC_RESEARCH_ROOT`. |

---

## 3. Repository layout & per-file status

All stages `01`→`17` have been **run** (2026-07-08). Full listing:

```
RESEARCH/
├── data/mimic-iv-3.1/{hosp,icu}/*.csv.gz      # raw data (do not modify)
│                                                 # NB: NO eICU database present
├── processed_data/                             # all outputs (all EXIST)
│   ├── exploration_report.txt        from 01
│   ├── cohort.csv                    from 02  (65,241 stays)
│   ├── suspected_infection.csv       from 03  (26,432 stays / 40.5%, swabs excluded)
│   ├── stay_measurements.csv         from 04  (one row/stay, first-24h physiology)
│   ├── analysis_matrix.csv           from 05  (SOFA + Sepsis-3 label; feeds 06)
│   ├── hourly_panel.parquet          from 07  (3.10M stay-hours)
│   ├── hourly_labeled.parquet        from 08  (+ hourly SOFA, onset, per-hour label)
│   ├── onset_summary.csv             from 08  (stay-level time-to-event)
│   ├── landmark_h6.csv               from 08  (48,829 at-risk @ h6; feeds 09 + Phase 2)
│   ├── traj_means.csv, panel_sample_long.csv   from 08 (report inputs)
│   ├── landmark_stack.csv            from 11  (207,010 rows, 6 landmarks — Phase 2 T2)
│   ├── realtime_holdout_features.csv from 14  (152,910 hourly rows — Phase 2 T4)
│   ├── realtime_holdout_ids.csv      from 14  (6,000 held-out stays)
│   └── phase2_tier{1..5}*.csv        from 10/12/13/15/16  (Phase 2 results)
│      (cohort.parquet / suspected_infection.parquet are harmless STALE leftovers)
└── projects/sepsis_mimic4/
    ├── config.py                 single source of truth (paths, itemids, thresholds)
    ├── utils.py                  IO + streaming aggregation helpers
    ├── 01_explore_data.py        [RUN] → exploration_report.txt
    ├── 02_extract_cohort.py      [RUN] → cohort.csv
    ├── 03_suspected_infection.py [RUN] → suspected_infection.csv (swabs excluded)
    ├── 04_extract_measurements.py[RUN] heavy scan → stay_measurements.csv
    ├── 05_sofa_sepsis3.py        [RUN] SOFA + labels → analysis_matrix.csv
    ├── 06_statistical_report.Rmd [RENDERED on real data] → 06_statistical_report.pdf
    ├── 07_hourly_panel.py        [RUN] heavy → hourly_panel.parquet
    ├── 08_onset_label.py         [RUN] → hourly_labeled.parquet + landmark/onset exports
    ├── 09_temporal_report.Rmd    [RENDERED] → 09_temporal_report.pdf
    ├── 10_landmark_nomogram.R    [RUN] Phase 2 T1  → phase2_tier1_*.csv, nomogram/calib png
    ├── 11_landmark_stack.py      [RUN] Phase 2 T2  → landmark_stack.csv
    ├── 12_supermodel.R           [RUN] Phase 2 T2  → phase2_tier2_*.csv, auc_by_landmark.png
    ├── 13_repeated_measures.R    [RUN] Phase 2 T3  → phase2_tier3_*.csv (GEE + tv-Cox)
    ├── 14_realtime_holdout.py    [RUN] Phase 2 T4  → realtime_holdout_*.csv
    ├── 15_realtime_eval.R        [RUN] Phase 2 T4  → phase2_tier4_*.csv, alarm_tradeoff.png
    ├── 16_subgroup_fairness.R    [RUN] Phase 2 T5  → phase2_tier5_subgroups.csv
    ├── 17_phase2_report.Rmd      [RENDERED] → 17_phase2_report.pdf
    ├── figure/                   report figures (Phase 1 + Phase 2 PNGs)
    ├── README.md                 human-facing docs (see §9 for the Phase 2 table)
    ├── requirements.txt          pandas>=2.0, numpy, pyarrow, tqdm
    └── GENAI/{HANDOFF.md, plan.md, plan_phase2_statistical.md, README.md}
```

Everything defaults to **CSV** (user opens intermediates in the IDE); every
Python script accepts `--parquet` for a typed copy. The two large panels
(`07`/`08`) are parquet-only by necessity (3.1M rows).

---

## 4. The dataset (from `exploration_report.txt`)

- **All candidate itemids in `config.py` were confirmed present** (section 5 of
  the report) — nothing missing, no corrections needed.
- Cohort preview: 94,458 ICU stays → after adults + LOS ≥ 4h + first-stay-only →
  **65,241 stays / 65,241 patients** (cohort.csv). Median age 66, 43.8% female,
  in-hospital mortality 10.8%, ICU mortality 7.3%.
- Big tables: `chartevents` 3.3 GB, `labevents` 2.4 GB, `prescriptions` 578 MB,
  `inputevents` 382 MB, `outputevents` 47 MB, `microbiologyevents` 112 MB.
- Verified units (peeked directly, drives the extraction code):
  - FiO2 (223835) stored as **percent** (median 40) → ÷100, clip [0.21, 1.0].
  - GCS components clean numerics (eye 220739 1–4, verbal 223900 1–5, motor 223901 1–6).
  - Temp in both °F (223761) and °C (223762) → convert F→C.
  - MAP has garbage outliers (max 117120) → clip [10, 250].
  - Labs in SOFA-ready units: lactate mmol/L (50813), creatinine mg/dL (50912),
    bilirubin mg/dL (50885), platelets K/uL (51265), WBC K/uL (51301/51300),
    PaO2 mmHg (50821).
  - Vasopressors mostly `mcg/kg/min` (norepi 221906, epi 221289, dopamine 221662,
    dobutamine 221653); phenylephrine 221749 / vasopressin 222315 in non-weight
    units. `patientweight` median 80 kg available in inputevents.
  - Urine (outputevents, itemids in `config.URINE_OUTPUT_ITEMIDS`) in mL.

---

## 5. Pipeline stages in detail

### 01_explore_data.py  [RUN]
Profiles the data, mines `d_items`/`d_labitems`, verifies candidate itemids,
lists sepsis ICD codes, previews cohort. Output: `exploration_report.txt`.
Run with `--count-small`.

### 02_extract_cohort.py  [RUN]
Small-table join (icustays + patients + admissions). Applies MIN_AGE=18,
MIN_ICU_LOS_HOURS=4, FIRST_ICU_STAY_ONLY=True. Adds mortality flags + approx age.
Output: `cohort.csv` (65,241 stays). **Now saves CSV by default** (`--parquet` opt-in).

### 03_suspected_infection.py  [RUN, surveillance swabs EXCLUDED]
Streams `prescriptions` (matches `config.ANTIBIOTICS` substrings) × dedup'd
`microbiologyevents` cultures, pairs them within the Sepsis-3 windows
(abx→culture ≤72h; culture→abx ≤24h), earliest qualifying `t_suspicion` per stay.
**MRSA-SCREEN / surveillance swabs are now excluded by default**
(`config.EXCLUDE_SURVEILLANCE_CULTURES`, `SURVEILLANCE_SPEC_TYPES`). Output:
`suspected_infection.csv` (**26,432 / 65,241 = 40.5%**; was 51.5% with swabs).
Suspicion lands median **+1.1h** from ICU intime — this justified the day-1 SOFA window.

### 04_extract_measurements.py  [RUN — the one heavy stage]
THE expensive step. Streams `chartevents` (3.3 GB) + `labevents` (2.4 GB) +
`inputevents` + `outputevents` using `utils.stream_windowed_agg` (chunked,
memory-safe, per-`(stay, itemid)` min/max/mean over a per-stay window).
- Window: chart/output/input `[intime, intime+24h]`; labs `[intime−6h, intime+24h]`
  (labs key on `hadm_id`; everything else on `stay_id`).
- Emits one row/stay: `hr_*, resp_rate_*, temp_max_c, spo2_min, map_min, gcs_min,
  fio2_max, pao2_min, pf_ratio_min, lactate_max, creatinine_max, bilirubin_max,
  platelets_min, wbc_max, wbc_min, urine_24h_ml`, plus vasopressor flags/rates
  (`norepi_epi_any, dopamine_any, dobutamine_any, other_vaso_any, vaso_any,
  norepi_epi_max_rate, dopamine_max_rate`), joined onto all cohort columns.
- Output: `stay_measurements.csv`. Prints progress + coverage to stderr.
- Handles FiO2 %→fraction, temp F→C, MAP/GCS clipping, count-weighted means.

### 05_sofa_sepsis3.py  [RUN — Sepsis-3 prevalence 37.1%, septic shock 9.2%]
Pure compute on `stay_measurements.csv` + `suspected_infection.csv` (no big files).
Scores the 6 SOFA organs (functions `score_respiration/coagulation/liver/cardio/
cns/renal`, each unit-tested), sums to `sofa_total`, then:
- `suspected_infection` = stay_id ∈ suspected_infection.csv
- `sepsis3` = suspected_infection AND `sofa_total >= SOFA_INCREASE_THRESHOLD` (=2)
- `septic_shock` = sepsis3 AND vaso_any AND `lactate_max > SEPTIC_SHOCK_LACTATE_MMOL` (2.0)
- Output: **`analysis_matrix.csv`** — demographics + first-24h features + SOFA
  components + labels. This is the file the report reads.

### 06_statistical_report.Rmd  [RENDERED on real data → 06_statistical_report.pdf]
Knit with `Rscript -e 'rmarkdown::render("06_statistical_report.Rmd")'` → PDF.
Reads `../../processed_data/analysis_matrix.csv` (has a `find_data()` fallback).
Predicts **sepsis3** from **non-circular** predictors (NOT SOFA components):
`lactate_max, wbc_max, hr_max, resp_rate_max, temp_max_c, age`. Star feature =
**lactate**. CV AUROC ~0.66 (deliberately handicapped — see README §5.4). Seed
`set.seed(486649)` (the user's student ID, matching their breast-cancer report).

### 07–09  [RUN / RENDERED — the temporal layer]
See the **2026-07-01 update banner** at the top. `07_hourly_panel.py` (heavy) →
`hourly_panel.parquet`; `08_onset_label.py` → `hourly_labeled.parquet` + landmark
& onset exports; `09_temporal_report.Rmd` → rendered PDF (KM, Cox, time-varying
Cox, Fine–Gray, ACF, within-patient HMM, AUC(t) vs baselines). Best Phase-1
number: multivariable hourly logistic **0.755** AUROC for 12h incident onset @ h6.

### 10–17  [RUN / RENDERED — Phase 2, purely statistical]
See the **2026-07-08 update banner** at the top and **README §9** (per-tier table)
and **`GENAI/plan_phase2_statistical.md`** (design + results). Reuses the Phase-1
substrate; no heavy recompute. Real-time prediction via **dynamic landmarking**
(a landmark supermodel), not ML. Headline: Tier-1 full-feature nomogram **0.775**
AUROC; Tier-2 supermodel AUC(s) 0.65–0.77 (hourly-updating risk).

---

## 6. Key design decisions & rationale

1. **CSV by default, parquet opt-in.** User can't open parquet in the IDE.
   `utils.save(..., fmt="csv")` default; `utils.load()` tries CSV then parquet
   and takes `parse_dates=`. Every script has a `--parquet` flag.

2. **Outcome = Sepsis-3** (user chose it over mortality/suspected-infection).
   Forced building SOFA before the report.

3. **Non-circular predictors in the report.** The GLM/tests predict sepsis from
   SIRS-type vitals + lactate + age — none of which are SOFA components — so the
   model isn't just re-deriving the label. SOFA inputs (platelets, bilirubin,
   creatinine, MAP/pressors, GCS, PaO2/FiO2) are deliberately excluded from the
   predictors.

4. **Day-1 SOFA operationalization.** SOFA computed over first 24h of ICU
   (labs −6h..+24h) rather than a suspicion-centred window. Justified because
   suspicion ≈ ICU admission (median +1.1h), chartevents is ICU-only (no pre-ICU
   data), and it gives every stay an identical, non-circular window. `config`'s
   `SOFA_WINDOW_BEFORE/AFTER_HOURS` are retained for a future hourly-SOFA refinement.

5. **Assumed-zero SOFA baseline** (per Sepsis-3) → "rise ≥ 2" reduces to
   `sofa_total >= 2`.

6. **Documented SOFA simplifications** (in `05` header): respiration ignores the
   strict ventilation requirement on scores 3–4; phenylephrine/vasopressin
   presence → cardiovascular score 3; a component with no data scores 0.

7. **Memory-safe streaming** (`utils.stream_windowed_agg`) instead of persisting
   multi-GB long tables — accumulates partial min/max/sum/count per chunk and
   combines. Unit-tested.

8. **Honest expected finding:** unlike tumour radius (which nearly separates
   malignancy at ~91%), lactate alone only **partially** separates sepsis
   (~65–75% unsupervised). The report frames this as the reason Sepsis-3 needs a
   multi-organ score, not one biomarker. Report prose is dynamic (inline `r`),
   so it stays correct whatever the real numbers are.

---

## 7. OPEN QUESTIONS / decisions pending

The four original open items are all **RESOLVED**: MRSA-SCREEN swabs are now
excluded by default (§3/§5); `04` and `05` have been run; `06` (and `09`, `17`)
are rendered on real data. The remaining work is:

1. **External validation on eICU — DEFERRED (blocking a clinical claim).** No
   eICU database is present under `data/`. The Phase-2 Tier-5 script
   (`16_subgroup_fairness.R`) delivers within-MIMIC subgroup calibration as a
   stand-in, but true external validation needs a second database. To do it:
   obtain eICU, build the same cohort/onset/landmark features, then apply the
   Tier-1 nomogram and the Tier-2 supermodel (both purely statistical, so
   transportable) and report AUROC + calibration on eICU. **Ask the user to
   point at an eICU path before starting.**

2. **Tier-1 landed at 0.775, below the 0.80–0.83 README projection** — honestly
   so: at a 6h landmark the labs that would lift discrimination are mostly not
   yet drawn, so their imputed values add little beyond the fact of absence
   (which the missingness indicators already capture). Not a bug; documented in
   `17_phase2_report.Rmd` and README §9.

3. **A per-patient random-intercept GLMM is degenerate on this outcome**
   (quasi-complete separation — most patients never have an event). Phase-2
   Tier-3 therefore uses **GEE + cluster-robust SEs** instead. Don't "fix" the
   GLMM; the GEE route is deliberate.

4. **Deliberately NOT pursued** (out of scope by the user's purely-statistical
   decision): gradient boosting / neural sequence models. If the user ever lifts
   that constraint, the Phase-2 substrate (`landmark_stack.csv`, the holdout
   stream) feeds them directly.

---

## 8. Exact run order (from the project dir)

All of the below has already been run; re-run a stage only if its inputs/config
change. `python3` = the framework build with pandas, NOT `/usr/bin/python3`.

```bash
cd /Users/arif/Desktop/RESEARCH/projects/sepsis_mimic4

# --- Phase 1: static branch ---
python3 04_extract_measurements.py     # SLOW: streams ~6 GB, memory-safe
python3 05_sofa_sepsis3.py             # fast: SOFA + labels
Rscript -e 'rmarkdown::render("06_statistical_report.Rmd")'

# --- Phase 1: temporal branch ---
python3 07_hourly_panel.py             # SLOW: builds 3.1M stay-hours
python3 08_onset_label.py              # hourly SOFA, onset, landmark, baselines
Rscript -e 'rmarkdown::render("09_temporal_report.Rmd")'

# --- Phase 2: purely statistical real-time model (fast; reuses 08 outputs) ---
Rscript 10_landmark_nomogram.R         # T1 nomogram
python3 11_landmark_stack.py           # T2 stacked landmark dataset
Rscript 12_supermodel.R                # T2 supermodel + AUC(s)   (~3 min)
Rscript 13_repeated_measures.R         # T3 GEE + time-varying Cox
python3 14_realtime_holdout.py         # T4 holdout hourly stream
Rscript 15_realtime_eval.R             # T4 utility + alarm burden
Rscript 16_subgroup_fairness.R         # T5 subgroup calibration
Rscript -e 'rmarkdown::render("17_phase2_report.Rmd")'
```

---

## 9. Validation already performed

- `utils.stream_windowed_agg`: unit-tested on a synthetic gzip (window filtering,
  min/max/mean/count, multi-chunk combine). ✓
- All 6 SOFA scorers in `05`: unit-tested against hand-computed expectations,
  incl. NaN→0 and vasopressor dose logic. ✓
- `06_*.Rmd`: `knitr::purl` parse ✓; every chunk executed against a synthetic
  `analysis_matrix.csv` ✓; **full PDF render** via pdflatex ✓ (454 KB);
  knit-to-markdown showed inline values substitute with **no NA/error leakage** ✓;
  all 12 R packages present ✓.
- `03` datetime bug fixed and **re-run on real data** — reproduces the cohort. ✓
- All Python scripts `py_compile` clean (incl. `11`, `14`). ✓
- **Phase 2 (2026-07-08):** every tier script runs to exit 0; `17_phase2_report`
  renders to PDF with **no NA/error leakage** in inline values (knit-to-md
  checked). `11_landmark_stack.py` reproduces the h6 landmark exactly (48,829
  at-risk / 3,330 onset-in-12h, matching `landmark_h6.csv`). Supermodel CV is
  patient-grouped on `stay_id` (each stay recurs across landmarks). Tier-4
  holdout is trained on the complement of the 6,000 held-out stays (leakage-safe).

---

## 10. Chronological conversation log (what happened, in order)

1. User dropped `files.zip` → it contained the initial pipeline skeleton
   (`config.py`, `utils.py`, `01_explore_data.py`, `02_extract_cohort.py`,
   `requirements.txt`, `README.md`). I summarized it.
2. User: copy files into `RESEARCH/`, but into a **subdirectory** because the
   project "will be tremendously big." → created `projects/sepsis_mimic4/`.
3. User hit `command not found: pip/python` → told them to use `python3`/`pip3`;
   the working interpreter is the 3.14 framework build.
4. User ran `01` → I read `exploration_report.txt`: all itemids confirmed,
   65,366 first-stay cohort preview.
5. User ran `02` → cohort.csv/parquet, 65,241 stays. I summarized demographics.
6. I wrote `03_suspected_infection.py`; user ran it → 33,592 stays (51.5%). I
   flagged the **MRSA SCREEN surveillance-swab** issue (still unresolved).
7. User: "why you making file .parquet? i can't explore those by IDE." → switched
   **all scripts to CSV-default**, added `--parquet` opt-in, converted existing
   outputs, made `utils.load` try CSV first.
8. User switched model to **Opus 4.8** and shared their prior **breast-cancer
   statistical report** (`.Rmd`), asking for a "similar one for sepsis data."
9. I asked (AskUserQuestion) which binary outcome to use. User chose **Sepsis-3
   vs no sepsis** → committed to building SOFA labeling first.
10. I peeked the raw data to confirm units (FiO2 %, GCS, temp F/C, MAP outliers,
    vaso rate units), then built: `utils.stream_windowed_agg`,
    `04_extract_measurements.py`, `05_sofa_sepsis3.py`, `06_statistical_report.Rmd`;
    unit-tested helpers & scorers; validated the Rmd via a full synthetic render;
    updated the README. Tracked via the task list.
11. User ran `03` again (fresh) and hit `str - Timedelta` (pandas 3.0 Arrow
    strings, because cohort now loads from CSV). → **fixed**: added `parse_dates`
    to `U.load`, used it in `03`; re-ran `03` and verified (33,592 stays).
12. User: create `GENAI/` folder + this handoff file.
13. **(2026-07-01)** User clarified the real goal (real-time early warning).
    Executed `plan.md`: excluded MRSA swabs, hardened `06`, built `07`/`08`
    temporal substrate + `09` longitudinal report. See the 2026-07-01 banner.
14. **(2026-07-02)** User asked "what else can we do"; decided Phase 2 should be
    **purely statistical** and, at that point, **plan-only**. Wrote
    `GENAI/plan_phase2_statistical.md`.
15. **(2026-07-08)** User: "execute phase 2." Built and ran Tiers 1–5
    (scripts `10`–`16`) + report `17`; installed `geepack`; switched Tier-3 from
    a degenerate GLMM to GEE; deferred eICU. Then updated README + this HANDOFF.

---

## 11. Gotchas / lessons for whoever continues

- **Never assume CSV round-trips dtypes.** After the parquet→CSV switch, always
  `parse_dates=` datetime columns (pandas 3.0 makes the failure loud). Currently
  only `03` (cohort intime/outtime) and `04` (intime) need dates; `05` and the
  Rmd use numeric/bool only.
- **Interpreter drift:** if you see `ModuleNotFoundError: pandas`, it's the
  system python. Use the framework `python3`.
- **Don't re-run the heavy `04` unless needed** — it streams ~6 GB. `05` and the
  report are cheap to iterate.
- **Report prose is deliberately dynamic** — don't hardcode numbers into the
  `.Rmd`; keep using inline `r ...` so it stays truthful to the data.
- **Keep predictors non-circular** if you extend the report's models — don't add
  SOFA-component variables as predictors of the SOFA-derived label.
- The user is a student; the report mirrors an academic format (bookdown PDF,
  effect-size-first interpretation, PAIR-framework acknowledgment, references).
  Preserve that tone and structure.
```
