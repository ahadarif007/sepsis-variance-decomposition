# Pre-registered Protocol — V2 Sepsis Prediction Study
# "Model, Label, or Analyst? A Variance Decomposition of Real-Time Sepsis Onset Prediction on MIMIC-IV"

**Version:** 2.0  
**Date:** 2026-07-13  
**Status:** Pre-registered (Phase 0 deliverable — must be locked before any modelling)

---

## 1. Primary Research Question

In real-time sepsis onset prediction on MIMIC-IV, how is predictive performance and
inferential validity partitioned between:
- (a) the choice of model class (interpretable dynamic discrete-time survival model vs.
  gradient-boosted trees), and
- (b) the analyst's discretionary methodological choices: label operationalisation,
  temporal vs. random validation split, prediction-time anchoring relative to clinical
  action, and choice of evaluation metric?

---

## 2. Label Variants (Pre-specified; to be locked before cohort extraction)

| Variant | Name | ABX→Culture (h) | Culture→ABX (h) | SOFA window before (h) | SOFA window after (h) | SOFA baseline |
|---------|------|-----------------|-----------------|------------------------|----------------------|---------------|
| A | Narrow | 24 | 24 | 24 | 12 | ICU admission SOFA |
| B | Seymour-Standard | 72 | 24 | 48 | 24 | ICU admission SOFA |
| C | Liberal | 72 | 72 | 48 | 24 | Rolling 24h min SOFA |

All three variants define Sepsis-3 onset as: suspected infection + acute SOFA increase ≥ 2.

**Floor:** the label-variance result survives with two variants (gate G2).

---

## 3. Prediction Framing (Lauritsen et al., 2021)

- **Observation window:** expanding from ICU admission (all data up to current hour)
- **Prediction horizon:** onset within the next 6 hours
- **Window shift:** hourly
- **Prediction trigger:** every at-risk person-hour from hour MIN_OBS_HOURS
- **Minimum observation before prediction:** 1 hour post-admission

This framing matches the PhysioNet/CinC 2019 Challenge (Reyna et al., 2020).

---

## 4. Validation Architecture

| Split | Design | Purpose |
|-------|--------|---------|
| Internal (primary) | Temporal: anchor_year_group train=[2008–2016], test=[2017–2019] | Honest internal estimate (Guo et al., 2022) |
| Internal (secondary) | Random patient-level 75/25 | Quantify optimism only |
| Treatment-anchored | Restricted to hours before first culture/antibiotic | Remove clinician-suspicion leakage (Kamran et al., 2024) |
| External (primary) | eICU-CRD | Generalisation test |
| External (fallback) | Within-MIMIC-IV temporal: earliest → latest year-group | If eICU harmonisation fails |

**Pre-registered expected external degradation:** ≈ 0.085 AUC (Moor et al., 2023).
A materially smaller observed drop = evidence external data is insufficiently distant.

---

## 5. Primary Evaluation Metrics

1. **PhysioNet Utility Score** (Reyna et al., 2020): rewards early prediction; penalises late,
   missed, and false alerts. **Can go negative** — this is the metric that reveals the collapse
   documented by Wang et al. (2025).
2. **Calibration** (intercept, slope, flexible curve): Achilles heel of predictive analytics
   (Van Calster et al., 2019). Cause-specific calibration for the competing-risks model
   via multinomial recalibration (Heyard et al., 2020).

**AUROC is designated DESCRIPTIVE ONLY** (Wang et al., 2025: AUROC 0.811→0.783 while
Utility Score +0.381→−0.164 across 91 models).

---

## 6. Secondary Metrics

- AUPRC (mandatory: low per-hour prevalence makes AUROC misleading in isolation)
- Discrete-time cause-specific AUC and concordance index (Heyard et al., 2020)
- Decision-curve net benefit (Vickers & Elkin, 2006)
- Alert burden = false alerts per true alert (benchmark: 1.4, Moor et al., 2023)
- Lead time relative to clinical recognition (benchmark: 3.7h, Moor et al., 2023)

---

## 7. Pre-registered Hypotheses

| ID | Hypothesis | Threshold | Source |
|----|-----------|-----------|--------|
| H1 | Label dominance: spread in AUROC across label variants ≥ spread across model classes | Label swing 0–6% ≥ model gain 1–5% | Cohen et al. (2024) |
| H2 | Coefficient instability: ≥1 covariate changes sign OR magnitude ≥ 2× across label variants | — | Lauritsen et al. (2021) |
| H3 | Leakage: restricting to pre-treatment hours reduces AUROC by ≥ 0.03 | Δ ≥ 0.03 | Kamran et al. (2024) |
| H4 | Split optimism: temporal-split AUROC < random-split AUROC by ≥ 0.02 | Δ ≥ 0.02 | Guo et al. (2022) |
| H5 | Metric divergence: proportional decline internal→external substantially larger for Utility Score than AUROC; Utility Score may cross zero | — | Wang et al. (2025) |
| H6 | Model-class null: discrete-time hazard model not inferior to gradient-boosted trees by more than 0.02 AUROC (under fixed label, fixed temporal split) | |Δ| ≤ 0.02 | Christodoulou et al. (2019) vs. Fagerström et al. (2019) |

H1 and H6 are in productive tension: both outcomes are informative.

---

## 8. Comparators

| Comparator | Role | Warrant |
|-----------|------|---------|
| NEWS2 | **Headline rule-based comparator** | Evans et al. (2021): qSOFA not recommended as sole screener |
| SIRS, qSOFA | Descriptive reference only | — |
| Static Cox PH | Deliberately weak baseline (Schoenfeld residual testing required) | Quantify cost of field's default choice |
| Gradient-boosted trees | **Mandatory ML comparator** (in-house, identical conditions) | Reyna et al. (2020): published comparisons do not transfer |
| Dynamic deep survival (stretch, optional) | — | Only if time permits |

---

## 9. Equity Analysis

Subgroups: race, ethnicity, primary language, insurance status (Wang, Li, Naidech, & Luo, 2022).

Two analyses:
1. **Subgroup performance**: Utility Score, calibration, AUPRC, alert burden within each subgroup.
2. **Subgroup label-sensitivity**: variation in who is identified as septic across the 3 label variants,
   stratified by subgroup. This conjunction has not been reported for any sepsis model.

---

## 10. Sample Size (Riley et al., 2019)

Formal calculation per label variant:
- Anticipated AUC = 0.846 (Moor et al., 2023 internal AUC)
- Targets: shrinkage factor ≥ 0.9; |apparent − adjusted Nagelkerke R²| ≤ 0.05
- Calculated using `pmsampsize::pmsampsize()` (binary outcome, person-hour level)
- Note: effective information governed by onset events (not person-hours)
- If a variant is underpowered, this is a finding — not a failure.

---

## 11. Go/No-Go Gates

| Gate | Week | Decision | Action if not met |
|------|------|---------|------------------|
| G0 | 2 | Protocol registered? | Blocking. Do not model. |
| G1 | 3 | Data access confirmed? | Non-blocking; continue on demo data |
| G2 | 7 | ≥ 2 label-variant person-hour tables built? | Floor = 2 variants |
| G3 | 15 | Internal validation complete? | Drop optional deep-survival comparator |
| G4 | 18 | eICU harmonisation working? | Fall back to within-MIMIC temporal split |

---

## 12. Reporting

- TRIPOD+AI (Collins et al., 2024) conformant
- PROBAST+AI self-appraisal completed at design time (Moons et al., 2025)
- Open pipeline release under permissive licence
