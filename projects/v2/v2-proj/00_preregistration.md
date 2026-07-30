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

---

# Amendment 1 — Inference, Multiplicity, and Analysis Status

**Date:** 2026-07-30
**Status:** **POST-HOC.** Written after the analyses in notebooks 02–11 had been
run and inspected. This amendment is *not* pre-specified and must not be
described as such anywhere in the thesis.

**Scope of the amendment.** It adds nothing to §§1–12: no hypothesis, estimand,
threshold, direction, subgroup, or model is changed, added, or removed. It only
(a) attaches uncertainty to contrasts that were already pre-specified, and
(b) imposes the multiplicity control that the original protocol omitted. Where
the correction changes a verdict recorded in §7, the corrected verdict is the
one reported.

## 13. Uncertainty Quantification

**13.1 Resampling unit.** Person-hours are nested within ICU stays. All
intervals come from a **stay-level (cluster) bootstrap**: whole stays are
resampled with replacement and every person-hour of a drawn stay is carried
with it. Row-level resampling is prohibited — it would treat ~45 correlated
hours per stay as independent and produce intervals several times too narrow.

**13.2 Interval type and replicates.** Percentile intervals at the 95% level.
B = 2,000 replicates for internal contrasts and subgroup analyses; B = 1,000
for eICU-CRD (7.9M person-hours). Seed fixed at 42; each contrast draws from
its own seed offset so streams are reproducible independently.

**13.3 Pairing.** Variants A, B and C are built on the same test stays, and all
model classes are scored on the same person-hours. Contrasts within these sets
(H1, H6) are therefore evaluated **within replicate**, so the interval reflects
the correlation between the quantities being differenced. Contrasts across
different evaluation sets (H4 temporal vs. random split; H5 MIMIC-IV vs.
eICU-CRD) use independent streams and propagate both variances.

**13.4 Stratification for subgroups.** Subgroup analyses resample stays
*within* subgroup, holding the observed subgroup sizes fixed. The subgroups are
the estimand, not a random draw.

**13.5 P-values.** Obtained by recentring the bootstrap distribution on the
null boundary and reading off the tail area, with the (1 + count)/(B + 1)
convention so no p-value is reported as exactly zero. The smallest reportable
p-value is therefore 1/(B+1).

**13.6 Degenerate cases.** Where a hypothesis has no variance estimate, no
p-value is invented:
- **H2** (coefficient instability) is a stability criterion, not a contrast.
  The stored multinomial fit carries no Hessian and refitting under a bootstrap
  is not tractable at 2.3M training rows, so H2 is reported as a **descriptive
  count** with no test.
- **H3** (treatment leakage) is degenerate: the outcome is entirely absent from
  the pre-treatment window, so AUROC is undefined and the pre-registered ≥0.03
  contrast cannot be formed. An **exact one-sided upper bound** on the
  per-hour onset rate is reported instead.

## 14. Multiplicity Control

**14.1 Confirmatory family (FWER).** The six pre-registered hypotheses H1–H6
form one confirmatory family, corrected by **Holm–Bonferroni at α = 0.05**.

The family size is fixed at **m = 6**, the number of hypotheses pre-registered,
*not* the number that turned out to be testable. H2 and H3 each reserve a slot
without contributing a p-value. This is deliberately conservative: a hypothesis
becoming untestable after unblinding must not make the correction on the
remaining hypotheses less strict.

**14.2 Exploratory families (FDR).** Subgroup analyses were pre-registered in
*scope* (§9) but not in specific contrasts: neither the subgroup levels, the
reference level, nor the direction of any comparison was fixed in advance. They
are therefore **exploratory** and corrected by **Benjamini–Hochberg at
q = 0.05** within two families:

| Family | Contents |
|--------|----------|
| E1 | Subgroup AUROC vs. reference level, over all equity variables (race, language, insurance) × both models |
| E2 | Subgroup label-sensitivity (A–C range) vs. reference level, over all equity variables |

The correction denominator is the number of contrasts **actually computed**,
not the number reported in the thesis. Selecting a subset for presentation does
not shrink the family.

**14.3 Reference level.** Each subgroup is contrasted against the largest level
of its own variable. The reference is chosen by sample size only, never by
outcome, and is recorded in the output tables.

**14.4 Eligibility.** A subgroup is reported only with ≥50 person-hours and
≥5 sepsis onsets. Subgroups below the event floor are listed as
non-estimable rather than shown with an uninterpretable point estimate.

**14.5 Why the two procedures differ.** A confirmatory claim must survive
family-wise control, because a single false confirmation invalidates the claim.
An exploratory scan exists to generate hypotheses, and only needs its
false-discovery proportion bounded. Applying FWER to the exploratory families
would be over-strict; applying FDR to the confirmatory family would be too
weak. Both are reported so a reader may substitute their own preference —
Bonferroni-adjusted p-values are also emitted for every exploratory contrast.

## 15. Confirmatory vs. Exploratory Status

Every analysis reported in the thesis carries an explicit status tag, held in a
machine-readable **analysis register** (`12_analysis_register.parquet`) and
reproduced in the thesis:

| Tag | Meaning |
|-----|---------|
| **Confirmatory** | Estimand, threshold, and direction fixed in §§1–12 before any modelling |
| **Exploratory** | Pre-registered in scope but not in specific contrasts; generates hypotheses, does not test them |
| **Descriptive** | No inferential claim attached |

The general statement in §12 ("any analysis not specified here is exploratory")
is retained but is no longer the only mechanism: the tag now travels with each
individual result rather than sitting once in the methodology chapter.

**Deliverables:** `12_inference.Rmd` (Phase 9 of `run_pipeline.R`), producing
`12_confirmatory_tests`, `12_subgroup_auroc_ci`,
`12_subgroup_auroc_contrasts`, `12_subgroup_labelsens_ci`,
`12_subgroup_labelsens_contrasts`, `12_internal_ci`,
`12_h2_coefficient_stability`, and `12_analysis_register`.
