# Pre-registered Protocol: V2 Sepsis Prediction Study
# "Quantifying Model, Label, and Methodological Contributions to Variance in Real-Time Sepsis Onset Prediction"

**Version:** 2.0
**Date:** 2026-07-13
**Status:** Pre-registered (Phase 0 deliverable; locked before any of the modelling reported in this study)

---

## How to read this document

Sections 1–12 are the protocol proper. They were locked on the date above,
before any of the modelling reported in the thesis, and their content has not
been altered since.

Everything after §12 is an **amendment**, each one dated, each one explicitly
marked POST-HOC. An amendment never edits §§1–12; it appends. Where an
amendment changes a verdict that §7 anticipated, the amendment says so and the
corrected verdict is the one the thesis reports.

| # | Amendment | Date | Adds | What it does |
|---|-----------|------|------|--------------|
| 1 | Inference, Multiplicity, and Analysis Status | 2026-07-30 | §§13–15 | Attaches intervals and multiplicity control to contrasts already pre-specified |
| 2 | A Label That Does Not Depend on Treatment Timing | 2026-08-02 | §§16–17 | Adds variants D and E, splitting the Sepsis-3 conjunction into its limbs |
| 3 | Fit Identification and Data Plausibility | 2026-08-03 | — | Defect correction: plausibility filter, ridge penalty, feature guard |
| 4 | Standard Sepsis-3 Onset Timing (Variant F) | 2026-08-05 | §18 | Adds variant F, re-timing B's stays by `min(t_susp, t_SOFA)` |
| 5 | Action-Derived Feature Ablation | 2026-08-06 | §19 | Adds an ablated fitting arm dropping 8 clinician-behaviour covariates |
| 6 | Subgroup Interpretability Floor | 2026-08-06 | §20 | Separates the floor for computing a subgroup AUROC from the floor for reading one |
| 7 | Uncertainty Diagnostic for H2 | 2026-08-10 | §21 | Adds a noise-scale diagnostic beside H2's pre-registered count |
| 8 | Comparator Fit Isolation | 2026-08-11 | §22 | Defect correction: early stopping was selected on the test set |
| 9 | External Validation of the Treatment-Independent Label | 2026-08-18 | §23 | Adds a full-cohort eICU arm for variant D, outside every corrected family |

Section numbers are cited from the pipeline notebooks and from the thesis, so
they are stable identifiers rather than presentation choices.

---

## 1. Primary Research Question

In real-time sepsis onset prediction on MIMIC-IV, how are predictive performance and
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
   missed, and false alerts. **Can go negative**, and it is the metric that reveals the collapse
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
| H2 | Coefficient instability: ≥1 covariate changes sign OR magnitude ≥ 2× across label variants | n/a | Lauritsen et al. (2021) |
| H3 | Leakage: restricting to pre-treatment hours reduces AUROC by ≥ 0.03 | Δ ≥ 0.03 | Kamran et al. (2024) |
| H4 | Split optimism: temporal-split AUROC < random-split AUROC by ≥ 0.02 | Δ ≥ 0.02 | Guo et al. (2022) |
| H5 | Metric divergence: proportional decline internal→external substantially larger for Utility Score than AUROC; Utility Score may cross zero | n/a | Wang et al. (2025) |
| H6 | Model-class null: discrete-time hazard model not inferior to gradient-boosted trees by more than 0.02 AUROC (under fixed label, fixed temporal split) | \|Δ\| ≤ 0.02 | Christodoulou et al. (2019) vs. Fagerström et al. (2019) |

H1 and H6 are in productive tension: both outcomes are informative.

---

## 8. Comparators

| Comparator | Role | Warrant |
|-----------|------|---------|
| NEWS2 | **Headline rule-based comparator** | Evans et al. (2021): qSOFA not recommended as sole screener |
| SIRS, qSOFA | Descriptive reference only | n/a |
| Static Cox PH | Deliberately weak baseline (Schoenfeld residual testing required) | Quantify cost of field's default choice |
| Gradient-boosted trees | **Mandatory ML comparator** (in-house, identical conditions) | Reyna et al. (2020): published comparisons do not transfer |
| Dynamic deep survival (stretch, optional) | n/a | Only if time permits |

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
- If a variant is underpowered, this is a finding, not a failure.

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

# Amendment 1: Inference, Multiplicity, and Analysis Status

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
with it. Row-level resampling is prohibited: it would treat ~45 correlated
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
- **H5** (metric divergence) is **partially degenerate, and the estimand
  actually tested is a substitute for the one §7 specifies.** This is the one
  place in the protocol where that happens and it is recorded here rather than
  left to be inferred from the results chapter.

  §7 states H5 as a comparison of *proportional* declines: the Utility Score
  should fall proportionally more than AUROC from internal to external
  validation. That contrast cannot be formed. A proportional decline needs a
  non-negligible baseline to be proportional to, and the internal Utility Score
  under the primary label is 0.000 at the default cut-off and 0.025 at its best
  threshold; dividing by a quantity indistinguishable from zero yields a ratio
  with no usable sampling distribution. The external arm compounds this: at 29
  observable external events no external Utility Score can be estimated
  reliably in any case.

  **What is tested in its place** is the AUROC limb alone, internal minus
  external AUROC for the primary model under Variant B, against θ₀ = 0, and it
  is this substituted contrast that occupies H5's slot in the Holm family and
  carries the adjusted p-value reported for H5. Three constraints apply to it,
  fixed here rather than after the fact:

  1. The substitution is **not** an alternative route to the pre-registered
     claim. Metric divergence is not established by it and must not be reported
     as established; the AUROC limb is one of the two quantities the original
     contrast would have compared, not the comparison itself.
  2. The direction and threshold of the substitute are the ones §4 already
     fixed for external validation (an expected degradation of ≈ 0.085 from
     Moor et al.), so no new degree of freedom is taken in choosing them.
  3. The Utility limb is reported **descriptively and internally**, where it
     needs no external arm: the swept ceiling under the primary label. That is
     a finding about the internal cohort, not a test of H5.

  The reader should note that the substituted estimand happens to produce the
  family's smallest raw p-value. It is reported as a non-confirmation on the
  width of its interval, and nothing in the thesis's conclusions rests on it.

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
weak. Both are reported so a reader may substitute their own preference:
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

---

# Amendment 2: A Label That Does Not Depend on Treatment Timing

**Date:** 2026-08-02
**Status:** **POST-HOC.** Written after the analyses in notebooks 02–12 had been
run. Like Amendment 1, it is *not* pre-specified and must not be described as
such anywhere in the thesis.

**Motivation.** §2 locks three label variants, and all three are Sepsis-3
readings firing on the same culture-plus-antibiotic anchor. That anchor records
a clinician's decision to treat. Two things therefore follow from the
label-variant result, and the original protocol cannot separate them:

- **Definitional.** Sepsis-3 makes onset a function of treatment timing, so
  changing the antibiotic–culture windows *must* move the onsets. Part of the
  H1 label spread is guaranteed by construction and would appear even if the
  physiology were identical across patients.
- **Empirical.** Whether a label owing nothing to treatment timing selects
  different patients, at different hours, with different predictability.

Only the second is a claim about the world. It cannot be tested inside a family
of labels that all share the anchor, so a label outside that family is added.

**Scope.** The amendment adds nothing to §§1–15. No hypothesis, estimand,
threshold, direction, subgroup, or model is changed, added, or removed. H1–H6,
the variance decomposition table, and the equity families E1/E2 are computed
from exactly the same inputs as before. The new variants are held outside
`LABEL_VARIANTS` in `config.R` for this reason, and their metrics are written
to separate files (`07_metric_results_altlabel`, `05_coef_alt_variants`) so
they cannot be pooled with A–C by accident.

## 16. Alternative Label Variants

Sepsis-3 is a conjunction: *suspected infection* **and** *acute organ
dysfunction*. The conjunction is split and each limb is labelled on its own.

| Variant | Name | Suspicion anchor | Organ dysfunction | Uses treatment timing? |
|---------|------|------------------|-------------------|------------------------|
| B | Seymour-Standard | required | required | yes |
| E | Anchor-Only | required (B's windows) | not required | yes |
| D | Deterioration | not required | required | **no** |

**16.1 Variant E (Anchor-Only).** Onset is the suspicion-of-infection time
itself, computed with Variant B's windows (ABX→culture 72 h, culture→ABX 24 h),
with the SOFA criterion removed. The label is purely a record of clinician
behaviour: predicting it means predicting who gets cultured and started on
antibiotics. E is *not* a sepsis definition and its AUROC is not a sepsis
result.

**16.2 Variant D (Deterioration).** Onset is the first hour after hour 1 at
which a **physiology-only** SOFA score rises ≥ 2 points above the stay's
admission baseline (component means over hours 0–3, mirroring the "admission"
baseline of variants A and B). Physiology-only means the vasopressor and
catecholamine terms are withheld from the SOFA computation, so the
cardiovascular component is scored from MAP alone. No antibiotic order, culture
draw, or drug administration enters the definition. Onsets are derived in
`03_person_hours.Rmd`, where the hourly panel exists.

**16.3 Why not PhysioNet/CinC 2019, SEP-1, or CDC Adult Sepsis Event.** All
three were considered and rejected for this specific purpose. CinC 2019 sets
onset to min(t_suspicion, t_SOFA) using the same culture-plus-antibiotic
trigger; SEP-1 and CDC ASE are defined on antibiotic days. Each is anchored to
treatment timing by construction, so none of them breaks the circularity that
motivates this amendment. They remain valid *alternative Sepsis-adjacent*
definitions and are discussed as such, but they cannot serve as the
treatment-independent comparator.

**16.4 Fitting.** D and E are fitted with the identical model specification,
feature set, temporal split, and seed as A–C, so the label is the only thing
that differs.

**16.5 Interpretive limits, stated in advance of reading the results.**

- Variant E's discrimination is discrimination about treatment behaviour, not
  about sepsis.
- Variant D's label is a threshold function of recorded physiology, and five of
  its six SOFA components (all but PaO₂/FiO₂) are model inputs. Its AUROC is
  therefore partly self-fulfilling and its *level* is not comparable with
  Variant B's. The informative comparison is not the level but whether D
  selects **different patients at different hours**, reported as onset
  agreement (Cohen's κ, sensitivity to B) and median onset shift.

## 17. Estimands and Multiplicity for Amendment 2

**17.1 Anchor-attributable fraction.** The share of Variant B's above-chance
discrimination reproduced by the treatment anchor alone:

    φ_anchor = (AUROC_E − 0.5) / (AUROC_B − 0.5)

Bootstrapped end to end on the stay-level cluster bootstrap of §13, reported as
a point estimate with a 95% percentile interval. It is a ratio with no
meaningful null at zero, so **no p-value is computed for it** and it sits
outside the corrected family.

**17.2 Exploratory family E3.** The AUROC differences against Variant B,
{D, E} × {primary, GBT}, form a new exploratory family corrected by
**Benjamini–Hochberg at q = 0.05**, on the same terms as E1 and E2 (§14.2).
Contrasts are paired within replicate: all variants are labelled on the same
test stays, so one replicate draw applies to all of them.

**17.3 Label agreement.** Onset agreement between each variant and B (percent
agreement, Cohen's κ, sensitivity to B's positives, median onset shift among
stays positive under both) is **descriptive**. No test is attached. Onsets
beyond the 72 h modelling horizon count as negative so that D, whose onsets
exist only inside the panel, is comparable with variants labelled on the full
stay.

**Deliverables:** `02_alt_label_variance_table`, `05_coef_alt_variants`,
`07_metric_results_altlabel`, `09_label_anchor_attribution`,
`09_label_agreement`, `12_altlabel_auroc_ci`, `12_altlabel_contrasts`,
`12_anchor_attribution_ci`, and figure `09_label_anchor_attribution.png`.

---

# Amendment 3: Fit Identification and Data Plausibility

**Date:** 2026-08-03
**Status:** **POST-HOC.** See `../feedback/v2.md` for the full diagnosis.

Three defects found while responding to supervisory review, all affecting every
result: (i) no physiological plausibility filter existed anywhere in the
pipeline, (ii) the primary multinomial specification is completely separated and
was fitted unpenalised, so its MLE does not exist and `nnet::multinom`'s
`convergence = 0` was uninformative, (iii) `heart_rate`/`hr` naming mismatch
silently dropped heart rate from every fitted model via `intersect()`.

Fixes: `PLAUSIBLE_RANGES` + `apply_plausibility()` applied in stages 03 and 08
before forward-fill; `PRIMARY_MODEL_DECAY = 1e-4` with `check_multinom_fit()`
guards; `require_features()` errors on any declared-but-absent feature. The
penalty value is **not tuned**: test AUROC moves < 0.02 across a 20-point ridge
path for every variant, and that insensitivity is the justification. It must
never be presented as optimised.

---

# Amendment 4: Standard Sepsis-3 Onset Timing (Variant F)

**Date:** 2026-08-05
**Status:** **POST-HOC.** Written in response to supervisory review of the H3
result. Like Amendments 1–3, it is *not* pre-specified and must not be described
as such anywhere in the thesis.

**Motivation.** §2 assigns onset as `t_susp` for variants A–C whenever the SOFA
criterion is met somewhere in the evaluation window; the SOFA criterion gates
*membership* and contributes no timing information. Because `t_susp` is by
construction the later element of a qualifying antibiotic–culture pair, it
follows analytically that no onset can precede the first antibiotic or culture.
**H3's zero is therefore entailed by the implementation, not measured**, and the
thesis's claim that "no patient develops sepsis before doctors begin treatment"
was an over-reading of it. External evidence contradicts the absolute claim
directly (Epic Sepsis Model v2: median lead times 1.4–7.1 h ahead of clinician
recognition at encounter AUROC 0.80–0.90).

The standard operationalisation, Seymour et al. (2016) and the PhysioNet/CinC
2019 Challenge, assigns `t_onset = min(t_susp, t_SOFA)`, which permits an onset
to precede treatment whenever the SOFA rise is detected first. Amendment 2
considered and rejected that operationalisation as a *treatment-independent*
comparator, correctly (its membership is still anchored). That was not a reason
to omit it as a *timing* comparator, and this amendment adds it.

**Scope.** Adds nothing to §§1–17. No hypothesis, estimand, threshold,
direction, subgroup or model is changed. H1, the variance decomposition and
families E1/E2 are computed from exactly the same inputs. Variant F is held
outside `LABEL_VARIANTS` in `config.R` and its metrics go to the alternative-label
files.

## 18. Variant F: Sepsis-3 Early-Onset

| Variant | Membership | Onset time | Uses treatment timing? |
|---------|-----------|------------|------------------------|
| B | Sepsis-3 conjunction, B's windows | `t_susp` | membership **and** timing |
| F | **identical to B** | `min(t_susp, t_SOFA)` | membership only |

`t_SOFA` is the first hour in the evaluation window
`[t_susp - 48 h, t_susp + 24 h]`, after `MIN_OBS_HOURS`, at which the full SOFA
score is already ≥ `SOFA_INCREASE_THRESHOLD` points above the admission baseline
(component means over hours 0–`DETERIORATION_BASELINE_H`, with vasopressor
exposure taken as *any* during that window). Derived in `03_person_hours.Rmd`
because it needs the hourly panel.

**18.1 Two stated limits.** (a) The SOFA score used is the *full* score,
vasopressor terms included, as Seymour et al. specify. Vasopressor
administration is a treatment, so an F onset is free of the
antibiotic-and-culture anchor but not of treatment in general; Variant D remains
the fully treatment-independent label. (b) `t_SOFA` is searched only inside the
72 h modelled panel, so a rise occurring earlier in the admission is not
detected.

**18.2 Estimands.** Descriptive: number and percentage of onsets moved earlier,
median and extreme shift, and the count of onsets falling before
`min(first_abx_hour, first_culture_hour)`, the number the conjunction rule
fixes at zero. Exploratory: F's AUROC and its ΔAUROC against B join family
**E3**, which is thereby enlarged, making every Benjamini–Hochberg adjustment in
that family stricter than before this amendment.

**18.3 Agreement.** F and B label the same stays septic, so stay-level
membership is identical and the informative agreement statistic for F is the
onset *shift*. κ(F, B) is nonetheless < 1 on the modelled horizon: moving an
onset earlier can move it *into* the 72 h window, so F ⊇ B there and the
difference is the count of stays whose `t_susp` fell past hour 72 but whose
`t_SOFA` did not. Report that count; it is a property of the onset rule.

**Deliverables:** `03_early_onset_shift`, `09_pretreatment_onsets`, F rows in
`07_metric_results_altlabel`, `09_label_agreement`, `12_altlabel_auroc_ci`,
`12_altlabel_contrasts`.

---

# Amendment 5: Action-Derived Feature Ablation

**Date:** 2026-08-06
**Status:** **POST-HOC.** Written after the analyses in notebooks 02–12 had been
run and inspected. Like Amendments 1–4, it is *not* pre-specified and must not
be described as such anywhere in the thesis.

**Motivation.** The study's central argument is that the Sepsis-3 label is
constituted by clinician action rather than merely correlated with it. The same
objection applies to part of the **feature** set, and §§1–18 press it against
the outcome while leaving the predictors unexamined. Two kinds of covariate in
the pre-registered feature list record clinician behaviour rather than patient
physiology:

- **Vasopressor exposure** (`vaso_any`, `norepi_epi_any`) is a treatment: it is
  something done to the patient, not something measured in them.
- **The per-test order indicators** (`lactate_measured`, `creatinine_measured`,
  `bilirubin_total_measured`, `platelets_measured`, `wbc_measured`,
  `pf_ratio_measured`) record a decision to look. The value carries physiology;
  the indicator carries the clinician's attention.

Without an ablation, "the label is constituted by clinician action" is not
falsifiable on the feature side: any discrimination the models achieve could be
a rediscovery of the same clinical suspicion that defines the outcome.

**Scope.** Adds nothing to §§1–18. No hypothesis, estimand, threshold,
direction, subgroup or model is changed, added or removed. H1–H6, the variance
decomposition and families E1/E2/E3 are computed from exactly the same inputs
as before this amendment. The ablated arm is **exploratory**: it enters no
hypothesis, no confirmatory family and no decomposition row.

## 19. The Ablated Fitting Arm

`ACTION_DERIVED_FEATURES` in `config.R` names exactly the 8 of 22 covariates
listed above. The primary model and the gradient-boosted comparator are
re-fitted on the same training rows, the same temporal split, the same seed and
the same hyperparameters, with those 8 removed and every physiological
measurement retained.

**19.1 The boundary is deliberately conservative, and that is what makes the
contrast interpretable.** Forward-filled laboratory *values* are **retained**,
even though a value exists only because somebody ordered the test. Dropping
them as well would remove most of the laboratory signal and confound the
ablation with a loss of physiological information. What is removed is the set
of features that encode *only* clinician behaviour. The ablation therefore
measures the effect of removing the **explicit** traces of clinical attention,
not of removing all of them; a predictor set carrying no such trace is not
constructible from routinely collected ICU data, and that limitation is stated
in the thesis rather than papered over.

**19.2 Nothing is re-tuned.** The gradient-boosted arm keeps the
hyperparameters of the full fit. Re-tuning would confound the feature set with
the search budget.

**19.3 Estimands.** Descriptive and exploratory, with no test attached:
(i) ΔAUROC and ΔUtility between the full and ablated arms, per variant and
model, both scored by the same metric code on the same test rows; and (ii) the
cross-label coefficient-instability count (the H2 criterion) recomputed on the
ablated arm, plus the instability rate split by feature kind (action-derived
vs. physiological) in the full fit.

**19.4 Execution isolation.** `V2_ARMS=ablated` restricts stages 05 and 06 to
the ablated arm, so adding or refreshing the ablation cannot re-execute a fit
that any H1, H4 or H6 input depends on. Ablated output is written to
`*_ablated_*` files; the main files are never overwritten. This matters because
gradient-boosted tree fitting is not bit-stable across runs.

**Deliverables:** `07_ablation_metrics`, `05_h2_stability_ablated`,
`05_coef_all_variants_ablated`, `12_h2_stability_by_kind`.

---

# Amendment 6: Subgroup Interpretability Floor

**Date:** 2026-08-06
**Status:** **POST-HOC.** Written after the subgroup analyses of §9 and family
E1 had been run and inspected. Like Amendments 1–5, it is *not* pre-specified.

**Motivation.** §14.4 sets a single eligibility rule: a subgroup is reported
only with ≥ 50 person-hours and ≥ 5 sepsis onsets. That floor decides whether
an AUROC can be *computed*. It does not decide whether the resulting estimate
can be *read*, and at 5 events it cannot: the stay-level cluster-bootstrap
interval on such a stratum spans most of the unit interval and reaches the 0.5
chance line. Family E1 as originally constituted therefore corrected over 30
contrasts of which the majority carried no information, which both diluted the
Benjamini–Hochberg procedure and invited interpretation of estimates the design
cannot support.

## 20. Two Thresholds, and the Distinction Between Them

**20.1 The two floors.** `MIN_SUBGROUP_EVENTS = 5` (unchanged from §14.4)
decides whether a subgroup AUROC is **computed**.
`MIN_SUBGROUP_EVENTS_INTERPRET = 100` decides whether it is **interpreted**.
The second is defined in `config.R` as `MIN_EXTERNAL_EVENTS`, not as a literal,
so the internal and external interpretability floors cannot drift apart: they
answer the same question, which is whether an event count can carry a reading.

**20.2 Below-floor strata are still estimated and still tabulated,** flagged
`†`. Suppressing them would hide the cohort's composition, which is the thing
the equity section is about, and the figure showing their intervals reaching
the chance line *is* the argument for the floor. What they are excluded from is
every spread statement, every interpretive claim, and **family E1**.

**20.3 Consequence for the family.** E1 falls from **30 contrasts to 6**. All
six carry ≥ 100 events. The reference level is unchanged (§14.3: largest level
of each variable, chosen by sample size, never by outcome). Families E2 and E3
are unaffected: E2's estimand is a stay-level proportion rather than a
discrimination metric, so the event floor does not apply to it.

**20.4 The tension with §14.2, stated plainly.** §14.2 says the correction
denominator is "the number of contrasts **actually computed**, not the number
reported in the thesis", and that "selecting a subset for presentation does not
shrink the family". Reducing E1 from 30 to 6 is on its face the move that rule
prohibits, and it is recorded here as an amendment precisely so that a reader
does not have to discover the discrepancy for themselves. Four reasons are
offered for why the floor is nonetheless admissible, and the reader is free to
reject them and read the m = 30 correction instead:

1. **The rule's target is a different manoeuvre.** §14.2 forbids computing many
   contrasts, reporting the favourable ones, and correcting only over what was
   reported. The floor is not a presentation choice: below-floor contrasts are
   still estimated and still shown; they are removed from the *inferential*
   family, and the removal is disclosed with its effect on the result.
2. **The criterion is outcome-blind.** Eligibility depends on the stratum's
   event count alone. No p-value, effect size, direction or subgroup identity
   enters it, and the same constant governs the external analysis, where it was
   fixed before the eICU event counts were known.
3. **The direction is exculpatory.** The reduction *removed* the family's only
   surviving discovery (a language contrast estimated on 12 events) rather
   than creating one. A family narrowed to manufacture significance narrows
   around its significant results; this one discarded its own.
4. **The verdict is invariant to the choice.** Nothing in E1 survives
   Benjamini–Hochberg under either denominator. At m = 6 the smallest adjusted
   value is q = 0.066. The amendment changes which contrasts are read, not what
   is concluded from them.

**20.5 What must be reported.** Both floors, the count of strata clearing the
interpretation floor, and the fact that only two racial strata clear it, one
of which (`UNKNOWN`) is a missingness category, so the study contains no
sufficiently powered comparison between two racial strata that both record an
actual demographic answer. That sentence is the finding; it must not be
softened.

**Deliverables:** `interpretable` and `min_events_interpret` columns in
`12_subgroup_auroc_ci`; the reduced `12_subgroup_auroc_contrasts`;
`table_equityperformance` and `table_equitycontrasts` generated whole (the row
count is no longer fixed, so a one-macro-per-cell grid would either leave
unresolved cells or silently drop a stratum).

---

# Amendment 7: Uncertainty Diagnostic for H2

**Date:** 2026-08-10
**Status:** **POST-HOC.** Written after H1–H6 had been run, reported and
inspected. Like Amendments 1–6, it is *not* pre-specified.

**Motivation.** §13.6 recorded H2 as untestable on the ground that the fitted
multinomial carried no variance estimate. That ground has since been removed:
`sandwich` lacks an `estfun` method for `nnet::multinom`, but the missing piece
is a single score matrix the fitted object already stores, and supplying it
yields a cluster-robust covariance clustered on stay. Standard errors for the
primary model's coefficients now exist.

Their availability exposes a weakness in H2 that was previously unfalsifiable.
H2's criterion is a **threshold rule on point estimates**: a sign reversal, or
a magnitude ratio of at least two, across variants A, B and C. Such a rule
cannot distinguish the two situations it conflates:

- a coefficient that genuinely takes different values under different labels;
- a coefficient estimated so imprecisely that a doubling is within its noise.

For a covariate whose standard error is comparable to its estimate, the second
is near-certain and carries no information about label sensitivity at all. The
count of flagged covariates is therefore an **upper bound** on the instability
present, and its looseness was unmeasured.

**Scope.** Adds nothing to §§1–20 and **changes no estimand.** H2's
pre-registered criterion, its threshold, its family slot and its reported count
are all unaltered, and the reported count remains the pre-registered answer.
The diagnostic is an additional, separately labelled quantity. It is
exploratory, enters no confirmatory family, and receives no multiplicity
correction.

## 21. The Diagnostic

**21.1 Definition.** For each covariate flagged by H2, take the two variants at
the extremes of its estimated range, form the difference of the two
coefficients, and refer that difference to the pooled standard error of the
same two estimates:

    z = |β_hi − β_lo| / sqrt(SE_hi² + SE_lo²)

Reported per covariate alongside the three coefficients and the pooled standard
error, with `exceeds_noise` set at the conventional 1.96.

**21.2 It is not a hypothesis test, and no p-value is emitted.** Two reasons,
both of which would have to be resolved before any inferential reading:

1. **The estimates are correlated.** Variants A, B and C are fitted on
   overlapping stays, so the two coefficients being differenced are not
   independent. The pooled standard error assumes they are, which makes it
   conservative, but by an amount this design does not quantify.
2. **The covariance is that of the penalised estimator.** `PRIMARY_MODEL_DECAY`
   is a precondition for identification (Amendment 3), not a tuning choice, so
   the sandwich is ridge-regularised and its bread is the inverse *penalised*
   Hessian. The usual asymptotic interpretation of a Wald ratio is therefore
   approximate here.

The quantity answers "is this difference of the order of the estimation noise,
or an order of magnitude above it". That is the question the count of flagged
covariates needs answered, and it is reported as a ratio rather than dressed up
as inference.

**21.3 What must be reported, and in what order.** The pre-registered count
first, unmodified and identified as the pre-registered answer; the diagnostic
second, identified as post-hoc and exploratory. **The count must not be
restated as the number of covariates surviving the diagnostic.** Replacing a
pre-registered estimand with a post-hoc one is the manoeuvre this protocol
criticises elsewhere, and the fact that the substitution would be convenient
here is not a reason to make it.

**21.4 The direction of the result is recorded in advance of interpreting it,**
because it is favourable to the study's thesis and therefore requires the most
scepticism. Should the covariates surviving the diagnostic prove to be
disproportionately action-derived, that is a *convergence* with the Amendment 5
ablation and not an independent confirmation of it: both quantities are
computed from the same three fits, and the ablation's instability split by
feature kind and this diagnostic share the flagged set. They are two readings
of one body of evidence and must be described as such.

**Deliverables:** `se_cluster` column in `05_coef_table_primary_*` and
`05_coef_all_variants`; `12_h2_stability_uncertainty`; the generated table
`table_htwouncertainty`.

---

# Amendment 8: Comparator Fit Isolation

**Date:** 2026-08-11
**Status:** **POST-HOC.** Like Amendments 1–7, not pre-specified. It is a defect
correction of the same class as Amendment 3, and is recorded here for the same
reason: the fix changes reported numbers, so it must be traceable.

**The defect.** Stage 06 fitted the gradient-boosted comparator with

```r
evals = list(train = dtrain, test = dtest), early_stopping_rounds = 30
```

`xgb.train` selects `best_iteration` against the **last** element of `evals`.
That element was the temporal test set, so the number of boosting rounds, a
model-selection choice, was made on the rows the model was then scored on. The
same pattern was present in all three arms: the main fit, the Amendment 5
ablated arm, and the H4 random-split arm.

§8 of this protocol specifies the comparator as "in-house, identical
conditions" and fixes no hyperparameters, so this is an implementation defect
rather than a departure from the protocol. It is nonetheless leakage, it is not
what the thesis described, and it was found by audit rather than by any guard in
the pipeline.

**The fix.** `gbt_valid_split()` in `utils.R` carves an early-stopping set out of
the **training** rows. Three properties are fixed here rather than chosen after
seeing the result:

**22.1 The split is on the stay, not the row.** Person-hours are roughly 45
correlated observations per stay, so a row-level split would leave the same
patient on both sides and would not break the dependence it exists to break.
This is the same unit the cluster bootstrap (§13) and Riley's criterion (§10,
Amendment 6 note) use, and for the same reason.

**22.2 Nothing is tuned.** `GBT_VALID_FRACTION = 0.15` and
`GBT_VALID_SEED = 42L` are constants in `config.R`. Neither is searched over,
no hyperparameter is re-tuned alongside the fix, and the fraction is the
conventional one. The comparator is a reference point, not the object of study;
tuning it would confound the model-class contrast with a search budget, which is
the objection §19.2 already records for the ablated arm.

**22.3 The same held-out stays serve the full and ablated arms**, since both
call the helper with the same seed and fraction. The Amendment 5 contrast
therefore remains a contrast in the feature set alone.

**22.4 Direction of the correction, recorded before the re-run.** Removing an
optimistic bias from the comparator is expected to lower GBT's discrimination
slightly. That runs *against* the study's own argument in one place and *with*
it in another, and both are recorded now so neither can be presented as a
discovery afterwards:

- **H6** contrasts GBT against the primary model. A weaker GBT widens the gap
  in the interpretable model's favour, which is the direction this thesis
  argues for. The verdict must therefore be read with that in mind: the
  pre-correction fits already supported non-inferiority, so the correction
  strengthens an existing finding rather than creating one.
- **The utility ceiling** under Variants B and C was held by GBT. If the
  correction moves the ceiling to the primary model, the *holder* changes while
  the substantive claim (the ceiling sits a few per cent above the no-alert
  strategy) does not. The claim predicates in `check_consistency.R` assert the
  holder, so a change is reported by the pipeline rather than left to a read.
- **H1's model-class range** is bounded by the primary model above and qSOFA
  below. GBT sits at neither extreme, so the range is expected to be
  essentially unchanged.

**22.5 Guard.** `gbt_valid_split()` `stop()`s if either side of the split
carries no positive case, rather than falling back to a watchlist that would
reintroduce the defect silently. This follows the architectural principle the
`intersect()` and NEWS2 defects established: an interface fails loudly or not
at all.

**Deliverables:** no new output files. Every `06_*` fit, and every downstream
quantity that reads a GBT prediction, is re-estimated: `07_*`, `08_*`
(GBT external rows), `09_*`, `11_*`, `12_*`.

---

# Amendment 9: External Validation of the Treatment-Independent Label

**Date:** 2026-08-18
**Status:** **POST-HOC.** Like Amendments 1–8, not pre-specified. It was decided
after the eight-round results were in hand and after the external coverage
constraint had been measured, so it is exploratory by construction and is
recorded here before the arm was run.

**23.1 What it adds and why.** Every external estimate in the study so far is
confined to the microbiology-covered sub-cohort — 2,824 of 181,589 eICU stays,
1.555 % — because the Sepsis-3 anchor requires a culture record. Variant D
(Amendment 2) carries no treatment timestamp of any kind: its onset is the
first hour at which a physiology-only SOFA score stands ≥ 2 points above the
stay's admission baseline. It therefore needs no microbiology and can be
constructed on the entire cohort. This amendment adds one external arm applying
the frozen Variant D models to the **full** eICU cohort. It is the only
external estimate in the study whose denominator is the whole of eICU-CRD.

**23.2 Estimand and status.** The arm reports external AUROC and AUPRC for the
primary model, the gradient-boosted comparator and NEWS2 under Variant D, with
the stay, person-hour and event counts beside them. It is **descriptive**: no
p-value is computed, it joins **no** corrected family, and it is neither a
confirmatory nor an exploratory test in the sense of §14.

**23.3 Exclusions, and why they are asserted rather than assumed.** Variant D is
excluded from H1 and from the variance decomposition by Amendment 2. This arm is
excluded from **H5** on identical terms, and for the same reason: a post-hoc
label must not enter a pre-registered family through the external door after
being kept out of the internal one. The arm writes to
`08_external_validation_results_altlabel`; H5 and stage 09 read
`08_external_validation_results`. Stage 08 asserts at run time that neither file
contains the other's variants, and stops if either does.

**23.4 The two cohorts do not score SOFA from the same components.** eICU's
`vitalPeriodic` carries no Glasgow Coma Scale. The neurological component is
therefore scored from `score_sofa()`'s assumed-normal substitution in both the
hourly score and the baseline, where it cancels from the difference. eICU's
deterioration delta rests on five SOFA components and MIMIC-IV's on six. The
external label is consequently a slightly coarser construct than the internal
one, and the comparison is between two labels that are the same in definition
but not identical in the data available to compute them.

**23.5 The ceiling on what this arm can establish, recorded before the run.**
Variant D's onset is a deterministic function of physiological variables that
are themselves model inputs. A model with access to the panel is therefore
predicting a transformation of its own covariates, which is why Variant D's
internal AUROC (primary 0.8498, GBT 0.9360 on the unrestricted temporal window)
sits so far above every Sepsis-3 variant's. **A high external AUROC in this arm
is therefore not evidence that sepsis prediction transports well.** It would be
evidence that a physiological deterioration rule computed from a given set of
vital signs and laboratory values reproduces itself in a second dataset, which
is a weaker and different claim. The arm's value lies in the event count and
the denominator, not in the height of the number, and the thesis must say so
wherever it quotes it. Two outcomes are anticipated and neither is a finding
about sepsis: discrimination substantially above the Sepsis-3 arm's (consistent
with the partial circularity just described), or a fall toward it (which would
locate the degradation in cross-cohort measurement rather than in the label).

**23.6 Timebox.** One implementation pass and one stage-08 run. If the run does
not produce a scoreable arm on the first clean attempt, or if the canary on
`08_external_validation_results` and `08_h5_internal_external` fails, the change
is reverted and the experiment is reported in Future Work as an untested
question rather than debugged into existence. This is recorded so that a
negative outcome cannot be re-described afterwards as a decision not to pursue.

**Deliverables:** `08_external_validation_results_altlabel` (Parquet and CSV),
additional `anchor = "deterioration"` rows in `08_eicu_label_summary`. No
existing output file changes: the primary and sensitivity arms are recomputed
byte-identically and this is checked rather than asserted. Per-hour external
predictions are not persisted for this arm, matching the antibiotic-only
sensitivity arm.
