# Phase-2 Plan — A Purely Statistical Real-Time Sepsis Early-Warning Model

> Written 2026-07-02 for **Abdul Ahad**. Companion to `plan.md` (Phase 1, executed)
> and `HANDOFF.md` (pipeline mechanics). Scope decision (2026-07-02): keep the
> modelling PURELY STATISTICAL — no gradient boosting, no neural sequence models.
>
> **STATUS 2026-07-08: EXECUTED (Tiers 1–5).** Scripts `10`–`16` built and run;
> `17_phase2_report.Rmd` rendered to PDF. Results: Tier 1 nomogram AUROC **0.775**
> (vs Phase 1 0.755, DeLong p≈0); Tier 2 supermodel AUC(s) 0.65–0.77 matching
> per-landmark fits; Tier 3 within-patient corr **0.68** with cluster-robust SEs
> up to **4.5×** naive; Tier 4 PhysioNet utility (norm.) **0.29**, 90% sens ⇒ 6.5
> false alarms/patient-day; Tier 5 well-calibrated across sex/age. **Tier 5
> external eICU validation DEFERRED** — no eICU database present locally. See the
> per-tier outputs `processed_data/phase2_tier*.csv` and README §9.

---

## 0. Where Phase 1 left us

- `hourly_labeled.parquet` — 3.10M stay-hours × 64 cols; forward-filled (`_ff`),
  time-since-last (`_tsl`), hourly SOFA components, per-hour `label`.
- `landmark_h6.csv` — 48,829 at-risk stays at the hour-6 landmark, static + 6h
  slope features, `onset_within_h` target.
- Best Phase-1 result: multivariable logistic + trajectory slopes = **AUROC 0.755**
  (12h incident onset, h6 landmark), out-discriminating SOFA/qSOFA/SIRS.

The remaining gap is the project's true goal: **an online model that emits, at
each hour, the risk of sepsis in a near-future window.** The insight of this plan
is that this can be done *without leaving the statistics domain*, via **dynamic
prediction by landmarking**. Everything below reuses existing outputs; the only
potential heavy recompute is external validation (Tier 4).

---

## 1. The core idea: a landmark SUPERMODEL, not a single landmark

Phase 1 fit **one** landmark (hour 6). A real-time system must produce a risk at
**every** hour. The classical-statistics answer (van Houwelingen 2007, already
README ref 7) is a **landmark supermodel**:

1. Choose a grid of landmark times `s ∈ {6, 12, 18, 24, ...}` h.
2. At each `s`, take the still-at-risk patients, build only-past features, and
   label onset within `[s, s+w]` (w = 12h horizon, matching Phase 1).
3. Stack all landmark datasets into one long "super" dataset with `s` as a
   covariate; fit **one penalized logistic (or Cox) supermodel** with smooth
   `s`-interactions (`s`, `s²`, feature×`s`).
4. At deployment, plug in the current hour as `s` → an hourly-updating risk.

This is a genuine real-time model, fully interpretable, no ML. It is the
statistical spine of Phase 2.

---

## 2. Tiered plan (all purely statistical)

### Tier 1 — Full-feature LASSO nomogram at the h6 landmark  *(fast, no recompute)*
The honest "how far can pure statistics go" number, dropping Phase 1's
deliberate non-circular handicap.
- Input: `landmark_h6.csv` (ready).
- Method: **LASSO / elastic-net penalized logistic** over the full feature set
  (labs, organ markers, `_tsl` missingness signals, 6h slopes).
- Evaluation: patient-grouped CV, calibration curve + Brier, PR-AUC, DeLong vs
  the 0.755 model. Publish as a **nomogram** (matches the benchmark papers).
- Expected: **AUROC ≈ 0.80–0.83** (README §7 prediction). Closes the
  benchmarking gap.
- Deliverable: `10_landmark_nomogram.Rmd`.

### Tier 2 — The landmark supermodel (§1) — the real-time model  *(the centrepiece)*
- Build the stacked multi-landmark dataset from `hourly_labeled.parquet`
  (new `10_landmark_stack.py` or R prep from the parquet).
- Fit a **penalized logistic supermodel** with smooth `s`-effects; optionally a
  **landmark Cox supermodel** for time-to-onset within the window.
- Report **AUC(s)** — discrimination as a function of the hour the prediction is
  made — this is the real-time analogue of Phase 1's single AUROC.
- Deliverable: extends into `11_dynamic_landmark_report.Rmd`.

### Tier 3 — Correct-for-correlation inferential models  *(supporting evidence)*
Not for the headline risk, but to characterise the data rigorously and support
the supermodel's feature choices — all classical:
- **GLMM (random intercept per patient)** or **GEE** on the hourly panel — the
  statistically correct treatment of repeated within-patient measurements
  (flagged as missing in `plan.md §3B.4`).
- **Penalized time-varying-covariate Cox** on the full hourly panel (Phase 1 ran
  it on a subset only; upgrade to the full cohort with ridge penalty).
- Optional: a **joint longitudinal-survival model** for the star markers
  (lactate, MAP) if tractable — the most sophisticated statistical option.

### Tier 4 — Real-time evaluation protocol  *(method-agnostic, decisive)*
- **PhysioNet 2019 utility score** — early-detection-weighted, penalizes late
  and false alarms. This is *the* field-standard metric and is currently absent.
- **AUC(t) / time-dependent ROC** across horizons (Phase 1 has the scaffolding).
- **Alarm-burden analysis** — false alarms per true early catch at each operating
  point. Clinically decisive and currently missing entirely.
- **Dynamic calibration** — calibration of the supermodel at each landmark `s`.

### Tier 5 — Generalization & fairness  *(what makes it defensible)*
- **External validation on eICU** — retrain/apply the nomogram + supermodel on a
  second database (the one thing that upgrades this from "internal study" to a
  credible clinical claim; README Limitation §8.2).
- **Subgroup calibration** by age band and sex — check the model isn't
  miscalibrated for a subpopulation.

---

## 3. Recommended sequence & dependencies

```
Tier 1 (LASSO nomogram @ h6)  ── fast, no recompute ──► statistical ceiling
        │
        ▼
Tier 2 (landmark supermodel)  ── build stacked dataset from parquet ──► real-time risk
        │                                                         │
        ├──► Tier 3 (GLMM/GEE, penalized tv-Cox) — supporting     │
        │                                                         ▼
        └──────────────────────────────────────────► Tier 4 (utility score, AUC(t), alarms)
                                                                  │
                                                                  ▼
                                                        Tier 5 (eICU external, fairness)
```

- **Start with Tier 1** — cheapest, highest-certainty, closes the README §7 gap.
- **Tier 2 is the deliverable** that actually meets the real-time goal.
- Tiers 4–5 apply to whatever Tier 1/2 produce; Tier 5 (eICU) is the only stage
  needing a new data source + heavy recompute.

## 4. What stays fixed (carry over from Phase 1)
- Seed `486649`; patient-grouped, time-respecting splits; only-past features.
- CSV-default / parquet-opt-in; `config.py` as single source of truth; memory-safe
  streaming for any new heavy stage.
- Non-circular discipline is **relaxed on purpose** only for the full-feature
  nomogram (Tier 1) — state this explicitly in the report, as README §7 anticipates.

## 5. One-line summary
Phase 2 can reach the real-time goal **without leaving statistics**: a
**full-feature LASSO nomogram** for the ceiling, a **landmark supermodel** for the
hourly-updating risk, **GLMM/penalized time-varying Cox** for rigorous inference,
and a **utility-score + alarm-burden + eICU** evaluation to make it defensible.
