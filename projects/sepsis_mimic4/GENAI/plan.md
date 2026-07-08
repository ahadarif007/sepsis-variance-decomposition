# Phase-One Statistical Plan — Aligning with Real-Time Sepsis Prediction

> **STATUS 2026-07-01: EXECUTED.** Phases 1a–1c are built and rendered. MRSA
> surveillance exclusion applied (03→05 re-run, Sepsis-3 37.1%); `06` hardened
> (CV/calibration/PR-AUC/GAM/VIF/MICE); `07` hourly panel (3.10M stay-hours),
> `08` onset labelling + landmark exports, and `09` longitudinal report
> (KM/Cox/time-varying Cox/Fine–Gray/ACF/HMM/AUC(t) vs qSOFA/SIRS/SOFA) all
> produced. Phase 2 (the real-time sequence model) is the remaining work.
> Detail of what shipped is in `HANDOFF.md` (2026-07-01 update).


> Companion to `HANDOFF.md`. Written 2026-07-01 for **Abdul Ahad**.
> Purpose: (1) state the project's *real* goal, (2) judge whether the current
> phase-one statistical analysis is aligned with it, (3) enumerate the
> statistical strategies/techniques that are **missing**, and (4) propose a
> concrete, phased plan. Read `HANDOFF.md` first for pipeline mechanics.

---

## 0. The real goal (as stated by the user)

**Predict sepsis (yes/no) in ICU patients from real-time time-series data —
an online early-warning system.** At each point in time, using only data
observed *up to now*, output the risk that the patient is/becomes septic within
a near-future window. This is the same problem shape as the **PhysioNet/CinC
2019 Early Sepsis Prediction Challenge**.

Phase one = the statistical-analysis stage of this research project. The
question the user is asking: *what statistical strategy/technique did I miss?*

---

## 1. Alignment verdict

| | Real-time goal needs | What phase one currently does | Aligned? |
|---|---|---|---|
| **Unit of analysis** | patient × time (hourly panel) | one row per ICU stay | ❌ |
| **Outcome** | onset-timed event; risk at each t | single stay-level `sepsis3` flag | ❌ |
| **Features** | only-past, windowed, updated over time | first-24h min/max/mean (uses the *whole* window) | ❌ |
| **Temporal structure** | autocorrelation, trajectories, transitions | collapsed away; HMM run on stay *order* (disclaimed) | ❌ |
| **Validation** | leakage-safe, patient-grouped, time-respecting, out-of-sample | in-sample AUC, complete-case, no split | ❌ |
| **Association discovery** | which physiology tracks sepsis | EDA + tests + GLM + effect sizes | ✅ (keep) |
| **Distributional insight** | shape of key markers | MLE, KDE, Gaussian mixture, MCMC | ✅ (keep) |

**Bottom line.** The current report is a solid *cross-sectional inferential
study* — keep it as the "understand the data" layer. But it is **not** a
foundation for a real-time model, because it has (a) no time axis, (b) no sepsis
**onset time**, (c) future-leaking features, and (d) no leakage-safe evaluation.
Phase one must be extended with the *temporal statistical* work that bridges to
phase two.

---

## 2. The single most important structural gap

There is **no sepsis onset time (`t_sepsis`) in the pipeline**. `sepsis3` is a
static stay label derived from first-24h SOFA. Without an onset time you cannot:

- define a prediction horizon (e.g. "predict 6 h before onset"),
- separate past from future for causal features,
- do survival / time-to-event analysis,
- evaluate *early* warning (the entire point).

**Everything else depends on fixing this first.** Onset should be defined per
the Sepsis-3 operationalization used in the PhysioNet challenge / Seymour 2016:
`t_suspicion` (already computed in `03`) combined with the *time SOFA first rises
≥ 2*, computed on an **hourly** SOFA rather than a single day-1 SOFA.

---

## 3. Missing statistical techniques

### 3A. Rigor gaps *within* the current cross-sectional analysis
These are fixable in `06_*.Rmd` and matter regardless of the temporal pivot.

1. **Out-of-sample validation is absent.** The AUC (~) is computed **in-sample**
   on the same data the GLM was fit to — optimistic by construction. Add:
   train/validation/test split (patient-grouped), **k-fold cross-validation**,
   and **optimism-corrected** performance (bootstrap .632+ or repeated CV).
2. **No calibration.** For a clinical risk model, calibration ≈ as important as
   discrimination. Add a **calibration curve**, **Brier score**, and
   intercept/slope (calibration-in-the-large). AUC alone is insufficient.
3. **Discrimination metric is wrong for imbalance.** Sepsis is imbalanced with
   asymmetric costs. Report **PR-AUC (average precision)** and a
   **decision-curve / net-benefit** analysis, not just ROC-AUC. The report
   currently *dismisses* imbalance instead of measuring its consequences.
4. **Missingness is only handled by complete-casing.** Dropping stays without
   lactate enriches for severity (acknowledged but not addressed). Add:
   **missingness-as-information** (measurement/no-measurement is predictive),
   a **missingness-indicator** analysis, and/or **multiple imputation (MICE)**
   with a stated MAR/MNAR argument. This is a *statistical* gap, not a nuisance.
5. **Linearity assumed on the log-odds scale.** Lactate's effect is almost
   certainly non-linear. Add **restricted cubic splines / GAM** and test
   non-linearity; check **interactions** (e.g. lactate × age).
6. **Collinearity checked on only 3 of 6 predictors.** Add full **VIF**.
7. **No bootstrap for model stability / feature-selection stability.** Only MCMC
   (one parameter) uses resampling; extend bootstrap CIs to the GLM ORs and AUC.
8. **Multiple-comparison control** across the three hypothesis tests (minor at
   this n, but state it).
9. **"Huge-n makes p meaningless" is noted but not formalized.** Consider
   **equivalence / minimum-effect testing** (e.g. TOST) to make the
   effect-size-first stance rigorous.

### 3B. Temporal / time-series techniques missing (the real alignment work)
This is the block that actually moves the project toward its goal.

1. **Longitudinal panel construction.** Resample each stay to a regular grid
   (hourly is standard) → patient × hour matrix of vitals/labs with
   forward-fill + "time since last measured" columns. *This is the new data
   substrate; the current `analysis_matrix.csv` is a byproduct, not the base.*
2. **Sepsis onset labeling + prediction-horizon framing.** Compute `t_sepsis`
   (§2). Define the target at each hour t: sepsis within `[t + h_min, t + h_max]`
   (PhysioNet used a 6–12 h early window). Include an **alignment/gap** so the
   model isn't rewarded for detecting sepsis that has already happened.
3. **Survival / time-to-event analysis** — *the key missing inferential bridge.*
   - **Kaplan–Meier** for time-to-sepsis-onset from ICU admission, stratified by
     baseline physiology.
   - **Cox proportional-hazards** and, better, **time-varying-covariate Cox**
     (vitals as they evolve) → which trajectories raise the hazard.
   - **Competing risks** (death/discharge compete with sepsis onset;
     Fine–Gray or cause-specific hazards).
   - **Landmark analysis** to preview dynamic-prediction validity.
4. **Repeated-measures regression.** With longitudinal data, replace the single
   GLM with a **GLMM (random intercept per patient)** or **GEE** — the correct
   way to model correlated within-patient observations.
5. **Time-series characterization of vitals.** ACF/PACF, stationarity, and
   **trajectory features**: slope/trend, rolling variance, EWMA, deltas,
   range-in-window. Quantify **irregular sampling** (sampling rate itself is a
   severity signal). These become the model's features and are worth a
   descriptive statistical section.
6. **Dynamic latent-state models done on the right axis.** Re-run the **HMM (and
   state-space / change-point detection) on true within-patient vital
   sequences**, not stay order — this is where an HMM is actually meaningful and
   directly supports "detecting a state change toward sepsis."
7. **Time-dependent evaluation.** **AUC(t) / time-dependent ROC**,
   **early-prediction score** (utility-weighted, PhysioNet-style), and
   **patient-grouped, time-respecting splits** (no patient and no future in
   both train and test). Consider **temporal external validation** (train on
   earlier admissions, test on later).
8. **Baselines to beat, tested properly.** Compute **qSOFA, SIRS, (hourly) SOFA,
   MEWS/NEWS** as streaming scores and compare AUCs with **DeLong's test**. A
   new model is only interesting relative to these.

---

## 4. Proposed plan (phased)

### Phase 1a — Finish the cross-sectional report (small, high value)
Keep `06_*.Rmd`'s narrative; harden it:
- Add patient-grouped train/test + k-fold CV; report **out-of-sample** AUC.
- Add **calibration curve + Brier + PR-AUC + decision curve**.
- Add **splines/GAM** for lactate; full **VIF**; bootstrap ORs.
- Add a **missingness** subsection (indicator analysis + MICE sensitivity).
- Reframe the HMM section honestly as a preview of the temporal work in 1c.
- **No heavy recompute needed** — runs on existing `analysis_matrix.csv`.

### Phase 1b — Build the temporal substrate (new scripts)
- `07_hourly_panel.py`: resample every cohort stay to an **hourly grid** of
  vitals/labs (reuse `04`'s streaming + itemids), forward-fill + time-since-last.
  Output `hourly_panel.parquet` (+ CSV sample). *This is the heavy step.*
- `08_onset_label.py`: compute **hourly SOFA**, derive `t_sepsis` (first ≥2 rise
  paired with `t_suspicion`), and emit per-hour target with the prediction
  horizon. Output `hourly_labeled.parquet`.
- Resolve the **MRSA-SCREEN surveillance-swab** decision from `HANDOFF.md §7`
  *before* onset labeling bakes in — it shifts prevalence and onset counts.

### Phase 1c — Temporal statistical report (new `09_*.Rmd`)
The phase-one deliverable that actually aligns with the goal:
- Cohort/onset **descriptives**; time-to-onset **Kaplan–Meier**.
- **Cox / time-varying Cox** + **competing risks**; hazard interpretation.
- **Trajectory & ACF** characterization; irregular-sampling analysis.
- **Within-patient HMM / change-point** on vital sequences.
- **AUC(t)** and **streaming-baseline (qSOFA/SIRS/SOFA/MEWS)** comparison with
  DeLong tests — establishes the bar the phase-2 model must clear.

### Phase 2 — Real-time model (out of scope here, but this plan feeds it)
Leakage-safe windowed features → sequence model (start simple: penalized
logistic / gradient boosting on windowed features as a strong baseline; then
temporal models) evaluated with the **utility score + AUC(t)** protocol above.
Everything phase-1c establishes (onset labels, baselines, splits) is reused
directly.

---

## 5. Sequencing & dependencies

```
[decide MRSA-screen filter]  ── gate ──┐
                                       v
1a (harden 06 on existing matrix) ─────┼──► phase-1 report v1 (cross-sectional)
                                       │
07 hourly_panel  ──► 08 onset_label ───┴──► 09 temporal report ──► Phase 2 model
      (heavy)          (fast)                (Cox/KM/HMM/AUC(t))
```

- 1a can start **now** (no recompute).
- 07 is the only expensive stage; run once, iterate 08/09 cheaply.
- 09 depends on 08; Phase 2 depends on 08 (labels) + 07 (features).

---

## 6. What to keep unchanged
- The cross-sectional report's structure, seed (`486649`), dynamic-prose style,
  and **non-circular predictor** discipline — extend the same discipline to the
  temporal features (only-past, no SOFA components predicting a SOFA label).
- CSV-default / parquet-opt-in convention, `config.py` as single source of truth,
  and the memory-safe streaming pattern from `utils.stream_windowed_agg`
  (reused by `07`).

---

## 7. One-line summary
Phase one is a good **static** study but **structurally misaligned** with a
**real-time** goal: it has no onset time, no time axis, future-leaking features,
and in-sample-only evaluation. The missing statistics are the **temporal**
ones — hourly panel + onset labeling, **survival/Cox/competing-risks**,
trajectory/ACF characterization, within-patient HMM, and **leakage-safe,
time-dependent, baseline-benchmarked** evaluation — plus tightening the existing
report with **out-of-sample validation, calibration, PR-AUC/net-benefit, and
principled missingness handling.**
```
