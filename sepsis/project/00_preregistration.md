# Pre-registered Protocol: Sepsis Prediction Study

*Quantifying Model, Label, and Methodological Contributions to Variance in
Real-Time Sepsis Onset Prediction*

**Version:** 2.0
**Date:** 2026-07-13
**Status:** Sections 1–12 pre-registered: written as the first deliverable of
the project and locked before any of the modelling reported in this study.
Sections 13–24 are dated post-hoc amendments.

---

## How to read this document

Sections 1–12 are the protocol proper. They were locked on the date above,
before any of the modelling reported in the thesis, and their content has not
been altered since. Their wording is therefore left as written, including
phrasing that a later edit would change.

Everything after §12 is an **amendment**, each one dated and explicitly marked
POST-HOC. Amendments never edit §§1–12; they are appended. An amendment can
still change what was analysed. Depending on the amendment, it may add an
estimand, substitute one that could not be formed, correct a defective
implementation, or change how a family is corrected for multiplicity. Each
amendment states which of these it does. Where an amendment changes the
inferential classification that §7 anticipated, it says so, and the thesis
reports the amended classification.

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
| 10 | Intervals on Three Point-Estimate Claims, and H6's Second Limb | 2026-08-31 | §24 | Adds intervals for the ablation, cross-label calibration and Variant D transport; computes both boundaries of H6's interval null |

The pipeline notebooks and the thesis cite these section numbers, so the
numbering is kept fixed.

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

**Scope of the amendment.** With one exception, it changes no hypothesis,
estimand, threshold, direction, subgroup or model in §§1–12. The exception is
H5, whose pre-registered estimand cannot be formed. §13.6 records the
substitute that takes its place. Otherwise the amendment (a) attaches
uncertainty to contrasts that were already pre-specified, and (b) imposes the
multiplicity control that the original protocol omitted. Both change how the
results are read. Where they change the inferential classification
anticipated in §7, the amended classification is the one reported.

## 13. Uncertainty Quantification

**13.1 Resampling unit.** Person-hours are nested within ICU stays. All
intervals come from a **stay-level (cluster) bootstrap**: whole stays are
resampled with replacement, and every person-hour of a drawn stay is included
in that replicate. Row-level resampling is prohibited. It would treat about 45
correlated hours per stay as independent and so understate the uncertainty.

**13.2 Interval type and replicates.** Percentile intervals at the 95% level.
B = 2,000 replicates for internal contrasts and subgroup analyses; B = 1,000
for eICU-CRD (7.9M person-hours). Seed fixed at 42; each contrast draws from
its own seed offset so streams are reproducible independently.

**13.3 Pairing.** Variants A, B and C are built on the same test stays, and all
model classes are scored on the same person-hours. Contrasts within these sets
(H1, H6) are therefore evaluated **within replicate**, so the interval reflects
the correlation between the quantities being differenced. Contrasts across
different evaluation sets (H4 temporal vs. random split; H5 MIMIC-IV vs.
eICU-CRD) use independent streams, so the interval combines both variances but
models no covariance between the two estimates. For H5 the two sets are
independent. For H4 the temporal and random test sets share some stays, and
that covariance is omitted.

**13.4 Stratification for subgroups.** Subgroup analyses resample stays
*within* subgroup, holding the observed subgroup sizes fixed. The intervals
therefore describe uncertainty within the recorded subgroups, conditional on
their observed sizes.

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
  2. The direction of the substitute, external AUROC below internal, is the
     one §4 already fixed for external validation. Its null is θ₀ = 0, so the
     test asks only whether any degradation is detectable. §4's expected
     degradation of ≈ 0.085 (Moor et al.) is the reference magnitude against
     which the estimate is read, not the null of the test.
  3. The Utility limb is reported **descriptively and internally**, as the
     swept ceiling under the primary label, rather than as part of an external
     comparison. That is a finding about the internal cohort, not a test of
     H5.

  The substituted estimand produces the family's smallest raw p-value. It is
  reported as a non-confirmation, because its interval is too wide to support
  a conclusion about external AUROC degradation, and nothing in the thesis's
  conclusions rests on it.

## 14. Multiplicity Control

**14.1 Confirmatory family (FWER).** The six pre-registered hypotheses H1–H6
form one confirmatory family, corrected by **Holm–Bonferroni at α = 0.05**.

The family size is fixed at **m = 6**, the number of hypotheses pre-registered,
*not* the number that turned out to be testable. H2 and H3 contribute no
p-value. Holm's step-down is applied to the four available p-values with
multipliers 6, 5, 4 and 3, which is equivalent to ranking H2 and H3 last with
p = 1. This convention is conservative. A hypothesis that becomes untestable
after the outcomes have been constructed and analysed does not make the
correction on the remaining hypotheses less strict.

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

**14.5 Why the two procedures differ.** Family-wise control is used for the
confirmatory family, because a single false confirmation would undermine a
confirmatory claim. The exploratory families generate hypotheses rather than
confirm them, so they control the expected false-discovery rate instead.
Applying FWER control to the exploratory families would be over-strict, and
applying FDR control to the confirmatory family would be too weak.
Bonferroni-adjusted p-values are also emitted for every exploratory contrast,
as a stricter sensitivity analysis.

## 15. Confirmatory vs. Exploratory Status

Every analysis reported in the thesis carries an explicit status tag, held in a
machine-readable **analysis register** (`12_analysis_register.parquet`) and
reproduced in the thesis:

| Tag | Meaning |
|-----|---------|
| **Confirmatory** | Estimand, threshold, and direction fixed in §§1–12 before any modelling |
| **Exploratory** | Pre-registered in scope but not in specific contrasts; may carry a test, but its results generate hypotheses rather than confirm them |
| **Descriptive** | No inferential claim attached |

§§1–12 contain no general rule for analyses they do not specify. The register
supplies one: every result carries its status in the register itself, rather
than relying on a single statement in the methodology chapter.

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

**Motivation.** §2 locks three label variants. All three are Sepsis-3
operationalisations built on the same culture-plus-antibiotic anchor, and that
anchor records a clinician's decision to treat. The label-variant result
therefore mixes two things, which the original protocol cannot separate:

- **Definitional.** Under these variants, onset is a function of treatment
  timing, so changing the antibiotic–culture windows changes onset assignment
  by construction. Part of the H1 label spread arises from the definitions and
  would appear even if the physiology were identical across patients.
- **Empirical.** Whether a label that does not use treatment timing selects
  different stays, at different hours, with different predictability.

Only the second is an empirical question. It cannot be answered inside a family
of labels that all share the anchor, so a label outside that family is added.

**Scope.** The amendment changes nothing in §§1–15. No pre-registered
hypothesis, estimand, threshold, direction, subgroup or model is changed or
removed. H1–H6, the variance decomposition table and the equity families E1/E2
are computed from exactly the same inputs as before. What it adds are separate
post-hoc variants and estimands (§§16–17). The new variants are held outside
`LABEL_VARIANTS` in `config.R` for this reason. Their metrics are written to
separate files (`07_metric_results_altlabel`, `05_coef_alt_variants`), which
keeps them from being pooled with A–C by accident.

## 16. Alternative Label Variants

Sepsis-3 is a conjunction: *suspected infection* **and** *acute organ
dysfunction*. Each of the two components, called limbs below, is used as a
label on its own.

| Variant | Name | Suspicion anchor | Organ dysfunction | Uses treatment timing? |
|---------|------|------------------|-------------------|------------------------|
| B | Seymour-Standard | required | required | yes |
| E | Anchor-Only | required (B's windows) | not required | yes |
| D | Deterioration | not required | required | **no** |

**16.1 Variant E (Anchor-Only).** Onset is the suspicion-of-infection time
itself, computed with Variant B's windows (ABX→culture 72 h, culture→ABX 24 h),
with the SOFA criterion removed. The label records the timing of treatment
decisions, which reflect the patient's condition as well as clinical workflow.
Predicting it means predicting which stays receive a qualifying culture and
antibiotic. E is *not* a sepsis definition, and its AUROC is not a sepsis
result.

**16.2 Variant D (Deterioration).** Onset is the first hour after hour 1 at
which a **physiology-only** SOFA score rises ≥ 2 points above the stay's
admission baseline (component means over hours 0–3, mirroring the "admission"
baseline of variants A and B). Physiology-only means the vasopressor and
catecholamine terms are withheld from the SOFA computation, so the
cardiovascular component is scored from MAP alone. The score is therefore a
modified SOFA rather than the standard one. A missing component is scored as
normal. No antibiotic order, culture draw or drug administration enters the
definition. The laboratory components can still depend on which tests were
ordered, so the label is independent of treatment timing but not of care
processes altogether. Onsets are derived in `03_person_hours.Rmd`, where the
hourly panel exists.

**16.3 Why not PhysioNet/CinC 2019, SEP-1, or CDC Adult Sepsis Event.** All
three were considered and rejected for this specific purpose. CinC 2019 sets
onset to min(t_suspicion, t_SOFA) using the same culture-plus-antibiotic
trigger. The CDC Adult Sepsis Event requires a blood culture and qualifying
antimicrobial days, and SEP-1 requires clinician-documented suspicion of
infection. Each depends on a clinical action or decision, so none removes the
dependence on treatment that motivates this amendment. They remain valid *alternative Sepsis-adjacent*
definitions and are discussed as such, but they cannot serve as the
treatment-independent comparator.

**16.4 Fitting.** D and E are fitted with the same model specification,
feature set, temporal split and seed as A–C. The fitting procedure is
therefore the same, and the differences between fits follow from the label:
it determines the at-risk person-hours, the onset count and, through the
training hours, the spline knots.

**16.5 Interpretive limits, stated in advance of reading the results.**

- Variant E's discrimination is discrimination about treatment behaviour, not
  about sepsis.
- Variant D's label is a threshold function of recorded physiology, and five of
  its six SOFA components (all but PaO₂/FiO₂) are model inputs. The outcome
  thus overlaps with the predictors by construction, so its AUROC is partly
  self-fulfilling. Its *level* can be reported but should not be read as
  performance on the same outcome as Variant B. The informative comparison is
  whether D selects **different stays or different onset times**. This is
  reported as onset agreement (Cohen's κ, sensitivity to B) and median onset
  shift.

## 17. Estimands and Multiplicity for Amendment 2

**17.1 Anchor-attributable fraction.** The share of Variant B's above-chance
discrimination reproduced by the treatment anchor alone:

    φ_anchor = (AUROC_E − 0.5) / (AUROC_B − 0.5)

Bootstrapped end to end on the stay-level cluster bootstrap of §13, reported as
a point estimate with a 95% percentile interval. Its natural reference value is
1, at which the anchor alone reproduces all of B's above-chance
discrimination, and the interval is read against that value. **No p-value is
computed for it**, and it sits outside the corrected family. The ratio would be
unstable if Variant B's AUROC were close to 0.5. B and E also have different
outcome targets, so the ratio compares two labels, not two models of one
label.

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
**Status:** **POST-HOC.** A defect correction.

Three defects were found while responding to supervisory review. Each affected
the fitted models and every result derived from them:

1. No physiological plausibility filter existed anywhere in the pipeline.
2. The primary multinomial specification was completely separated and was
   fitted without a penalty. With complete separation, some combination of
   covariates predicts the outcome categories perfectly, so the likelihood has
   no finite maximum and the maximum-likelihood estimate does not exist.
   `nnet::multinom`'s `convergence = 0` was therefore uninformative.
3. A naming mismatch between `heart_rate` and `hr` caused heart rate to be
   omitted from every fitted model, through `intersect()`.

The fixes are as follows:

- `PLAUSIBLE_RANGES` and `apply_plausibility()` are applied in stages 03 and 08
  before forward-filling.
- A ridge penalty, `PRIMARY_MODEL_DECAY = 1e-4`, makes the penalised likelihood
  strictly concave, so its maximum is unique. `check_multinom_fit()` warns when
  any coefficient exceeds 20 in absolute value.
- `require_features()` raises an error on any declared feature that is absent.

The penalty is a fixed stabilisation value, not a tuned hyperparameter. A
20-point ridge path, examined after the defect was found, moved test AUROC by
less than 0.02 for every variant. That post-hoc sensitivity check is the
justification for the value, and the value should not be presented as
optimised. Every fitted model and every downstream stage was re-run after the
fixes.

---

# Amendment 4: Standard Sepsis-3 Onset Timing (Variant F)

**Date:** 2026-08-05
**Status:** **POST-HOC.** Written in response to supervisory review of the H3
result. Like Amendments 1–3, it is *not* pre-specified and must not be described
as such anywhere in the thesis.

**Motivation.** The implementation of §2 assigns onset as `t_susp` for variants
A–C whenever the SOFA criterion is met somewhere in the evaluation window. The
SOFA criterion determines *membership* and contributes no timing information.
Because `t_susp` is by construction the later element of a qualifying
antibiotic–culture pair, no onset under this implementation can precede the
first antibiotic or culture. **H3's zero is therefore entailed by the
implementation, not measured**, and the thesis's claim that "no patient
develops sepsis before doctors begin treatment" was an over-reading of it.
External evidence contradicts the absolute claim directly. The Epic Sepsis
Model v2 reports median lead times of 1.4–7.1 h ahead of clinician
recognition, at encounter-level AUROC 0.80–0.90 (Wong et al., 2026).

The standard operationalisation, Seymour et al. (2016) and the PhysioNet/CinC
2019 Challenge, assigns `t_onset = min(t_susp, t_SOFA)`, which permits an onset
to precede treatment whenever the SOFA rise is detected first. Amendment 2
considered and rejected that operationalisation as a *treatment-independent*
comparator, correctly (its membership is still anchored). That was not a reason
to omit it as a *timing* comparator, and this amendment adds it.

**Scope.** Changes nothing in §§1–17. No pre-registered hypothesis, estimand,
threshold, direction, subgroup or model is changed. H1, the variance
decomposition and families E1/E2 are computed from exactly the same inputs.
The amendment adds Variant F and its estimands (§18). Variant F is held
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
administration is a treatment. An F onset is therefore not assigned directly
from the antibiotic–culture time, but it is not independent of treatment in
general. Variant D is the label that uses neither treatment timing nor
medication exposure in its definition. (b) `t_SOFA` is searched only inside the
72 h modelled panel, so a rise occurring earlier in the admission is not
detected.

**18.2 Estimands.** Descriptive: number and percentage of onsets moved earlier,
median and extreme shift, and the count of onsets falling before
`min(first_abx_hour, first_culture_hour)`, the number the conjunction rule
fixes at zero. Exploratory: F's AUROC and its ΔAUROC against B join family
**E3**. Every Benjamini–Hochberg adjustment in that family is then recomputed
over the enlarged family.

**18.3 Agreement.** F and B label the same stays septic over the whole
admission, so their stay-level membership is identical and the informative
agreement statistic for F is the onset *shift*. κ(F, B) is nonetheless < 1 on the modelled horizon: moving an
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

**Motivation.** The study argues that the Sepsis-3 label is partly
operationalised through treatment-related records, not merely correlated with
them. The same concern applies to part of the **feature** set. §§1–18 examine
it for the outcome but not for the predictors. Two kinds of covariate in the
pre-registered feature list record clinical actions rather than patient
physiology:

- **Vasopressor exposure** (`vaso_any`, `norepi_epi_any`) is a treatment
  exposure, not a physiological measurement.
- **The per-test order indicators** (`lactate_measured`, `creatinine_measured`,
  `bilirubin_total_measured`, `platelets_measured`, `wbc_measured`,
  `pf_ratio_measured`) record that a test was ordered. The value carries
  physiology, while the indicator reflects clinical attention.

That makes eight covariates of the 22. Without an ablation, the features cannot
be examined for this concern: any discrimination the models achieve could
partly reflect the same clinical suspicion that defines the outcome.

**Scope.** Changes nothing in §§1–18. No pre-registered hypothesis, estimand,
threshold, direction, subgroup or model is changed or removed. H1–H6, the
variance decomposition and families E1/E2/E3 are computed from exactly the same
inputs as before this amendment. What it adds is an exploratory ablated model
specification, called the ablated arm, with its own estimands (§19). The arm
enters no hypothesis, no confirmatory family and no decomposition row.

## 19. The Ablated Fitting Arm

`ACTION_DERIVED_FEATURES` in `config.R` names exactly the 8 of 22 covariates
listed above. The primary model and the gradient-boosted comparator are
refitted on the same training rows, the same temporal split, the same seed and
the same hyperparameters, with those 8 removed and every physiological
measurement retained.

**19.1 Definition of the ablated feature set.** The boundary is deliberately
conservative, which keeps the contrast interpretable. Forward-filled
laboratory *values* are **retained**,
even though a value exists only because somebody ordered the test. Dropping
them as well would remove most of the laboratory signal and confound the
ablation with a loss of physiological information. What is removed is the set
of features that encode *only* clinician behaviour. The ablation therefore
measures the effect of removing the **explicit** traces of clinical attention,
not of removing all of them. Routinely collected ICU data cannot fully separate
physiology from measurement and treatment processes, and the thesis states
this explicitly as a limitation.

**19.2 Nothing is re-tuned.** The gradient-boosted arm keeps the
hyperparameters of the full fit. Re-tuning would confound the feature set with
the search budget. The trade-off is that the ablated model may sit slightly
below the performance a re-tuned model would reach.

**19.3 Estimands.** These are descriptive and exploratory, with no test
attached:

1. ΔAUROC and ΔUtility, each defined as ablated minus full, per variant and
   model. Both arms are scored by the same metric code on the same test rows.
2. The cross-label coefficient-instability count (the H2 criterion),
   recomputed on the ablated arm as an exploratory quantity.
3. The instability rate in the full fit, split by feature kind
   (action-derived vs. physiological).

**19.4 Execution isolation.** `V2_ARMS=ablated` restricts stages 05 and 06 to
the ablated arm, so adding or refreshing the ablation cannot re-execute a fit
that any H1, H4 or H6 input depends on. Ablated output is written to
`*_ablated_*` files; the main files are never overwritten. This matters because
repeated gradient-boosted tree fits do not reproduce identical predictions.

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
is precise enough for substantive interpretation, and at 5 events it is not.
The stay-level cluster-bootstrap interval on such a stratum spans most of the
unit interval and reaches the 0.5 chance line. Family E1 as originally
constituted therefore corrected over 30 contrasts, most of which offered too
little precision for subgroup comparison. That diluted the Benjamini–Hochberg
procedure and invited interpretation of estimates the design cannot support.

## 20. Two Thresholds, and the Distinction Between Them

**20.1 The two floors.** `MIN_SUBGROUP_EVENTS = 5` (unchanged from §14.4)
decides whether a subgroup AUROC is **computed**.
`MIN_SUBGROUP_EVENTS_INTERPRET = 100` decides whether it is **interpreted**.
The second is defined in `config.R` as `MIN_EXTERNAL_EVENTS`, not as a literal,
so the internal and external interpretability floors cannot drift apart. The
100-event value comes from the guidance on external validation (Riley et al.,
2021; Collins et al., 2024). It is applied here to subgroups on the view that
the question is similar: whether an event count supports a sufficiently
precise AUROC. The two settings differ in prevalence and structure, so the
threshold is a convention adopted for both rather than one derived
specifically for subgroup contrasts.

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
prohibits. It is recorded here as an amendment so that the discrepancy is
stated rather than left to be found. Four reasons are given below for why the
floor is nonetheless admissible. The result under the original m = 30 family is
also reported, so a reader who does not accept these reasons can use it
instead:

1. **The rule's target is a different manoeuvre.** §14.2 forbids computing many
   contrasts, reporting the favourable ones, and correcting only over what was
   reported. The floor is not a presentation choice: below-floor contrasts are
   still estimated and still shown; they are removed from the *inferential*
   family, and the removal is disclosed with its effect on the result.
2. **The criterion uses no result of the comparison.** Eligibility depends on
   the stratum's event count alone. The count is an outcome quantity, so the
   rule is not blind to the outcome, but no p-value, effect size, direction or
   subgroup identity enters it. The same constant governs the external
   analysis, where it was fixed before the eICU event counts were known.
3. **The reduction removed a discovery rather than creating one.** It removed
   the family's only surviving discovery, a language contrast estimated on 12
   events. This lessens the concern that the family was narrowed to produce
   significance, although it does not remove every concern about selection
   after inspection.
4. **The retained contrasts do not depend on the choice.** None of the six
   retained contrasts survives Benjamini–Hochberg under either denominator; at
   m = 6 the smallest adjusted value is q = 0.066. The two families differ only
   in the 12-event contrast of point 3, which survives at m = 30 and lies below
   the interpretation floor at m = 6.

**20.5 What must be reported.** Both floors, the count of strata clearing the
interpretation floor, and the fact that only two racial strata clear it, one
of which (`UNKNOWN`) is a missingness category, so the study contains no
sufficiently powered comparison between two racial strata that both record a
demographic category rather than a missingness category. That sentence is the
finding, and it must be reported in full.

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
multinomial carried no variance estimate. That ground no longer holds. The
`sandwich` package has no score (`estfun`) method for `nnet::multinom`, but the
fitted object stores what such a method needs. Supplying it yields a
covariance clustered on stay, so standard errors for the primary model's
coefficients now exist.

They expose a limitation of H2 that could not previously be examined. H2's
criterion is a **threshold rule on point estimates**: a sign reversal, or a
magnitude ratio of at least two, across variants A, B and C. The rule does not
account for coefficient uncertainty, so it cannot distinguish two situations:

- a difference that is large relative to its estimation uncertainty;
- a coefficient estimated so imprecisely that a doubling is within its noise.

For a covariate whose standard error is comparable to its estimate, a doubling
is quite likely by chance alone and says little about label sensitivity. The
count of flagged covariates may therefore overstate the instability that is
substantively present, by an amount that was not measured.

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

This ratio is reported per covariate, alongside the three coefficients and the
pooled standard error. The column `exceeds_noise` marks a ratio of at least
1.96, used as a descriptive benchmark of about two standard errors rather than
as a test.

**21.2 It is not a hypothesis test, and no p-value is emitted.** Two reasons,
both of which would have to be resolved before any inferential reading:

1. **The estimates are correlated.** Variants A, B and C are fitted on
   overlapping stays, so the two coefficients being differenced are not
   independent. The pooled standard error assumes they are. Fits that share
   most of their stays are expected to give positively correlated estimates,
   and in that case the pooled standard error overstates the true one and the
   ratio is conservative. The sign and size of the covariance are not
   estimated in this design, however.
2. **The covariance is that of the penalised estimator.** `PRIMARY_MODEL_DECAY`
   is a precondition for identification (Amendment 3), not a tuning choice, so
   the sandwich is ridge-regularised and its bread is the inverse *penalised*
   Hessian. The usual asymptotic interpretation of a Wald ratio is therefore
   approximate here.

The quantity shows whether a difference is of the order of the estimation
noise or well above it. The count of flagged covariates needs that question
answered. The quantity is reported as a ratio and is not interpreted as a
formal inferential test.

**21.3 What must be reported, and in what order.** The pre-registered count
first, unmodified and identified as the pre-registered answer; the diagnostic
second, identified as post-hoc and exploratory. **The count must not be
restated as the number of covariates surviving the diagnostic.** That would
replace a pre-registered estimand with a post-hoc one. The protocol avoids such
substitutions elsewhere, and the replacement would be no more acceptable here
merely because it would suit the study's argument.

**21.4 The direction of the result is recorded before it is interpreted.** A
result consistent with the study's proposed interpretation calls for
particular care. Should the covariates surviving the diagnostic prove to be
disproportionately action-derived, that would be a *convergence* with the
Amendment 5 ablation, not an independent confirmation of it. Both quantities
are computed from the same three fits, and the ablation's instability split by
feature kind and this diagnostic share the flagged set. The two analyses are
statistically dependent and must not be described as independent
corroboration.

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
That element was the temporal test set. The number of boosting rounds, a
model-selection choice, was therefore made on the final temporal test set
later used to evaluate the model. No other hyperparameter was selected on it.
The same pattern was present in all three arms: the main fit, the Amendment 5
ablated arm and the H4 random-split arm.

§8 of this protocol specifies the comparator as "in-house, identical
conditions" and fixes no hyperparameters, so this was not a departure from the
protocol. It was an implementation defect that leaked test-set information
into model selection. It also contradicted what the thesis described, and it
was found by audit rather than by any check in the pipeline.

**The fix.** `gbt_valid_split()` in `utils.R` selects an early-stopping subset
from the **training** stays. Three properties are fixed here rather than chosen
after seeing the result:

**22.1 The split is on the stay, not the row.** Person-hours are roughly 45
correlated observations per stay. A row-level split would put hours from the
same stay on both sides and would not keep the early-stopping subset separate
from the fitting data. The stay is also the unit used by the cluster bootstrap
(§13) and by the sample-size check in `04_sample_size.Rmd`, for the same
reason.

**22.2 Nothing is tuned.** `GBT_VALID_FRACTION = 0.15` and
`GBT_VALID_SEED = 42L` are constants in `config.R`. Neither is searched over,
and no hyperparameter is re-tuned alongside the fix. The fraction is a common
choice, fixed without reference to any result. The comparator is a reference
point, not the object of study, and tuning it would confound the model-class
contrast with a search budget. §19.2 records the same objection for the ablated
arm. The trade-off is that the comparator may sit below its best attainable
performance.

**22.3 The same held-out stays serve the full and ablated arms**, since both
call the helper with the same seed and fraction. The Amendment 5 contrast
therefore remains a contrast in the feature set alone.

**22.4 Expected direction of the correction, recorded before the re-run.**
Removing an optimistic bias from the comparator is expected to lower GBT's
discrimination slightly. The expected effects on reported results are recorded
now, so that none of them can be presented as a discovery afterwards:

- **H6** contrasts GBT against the primary model. A weaker GBT widens the gap
  in the interpretable model's favour, which is the direction this thesis
  argues for. The verdict must therefore be read with that in mind: the
  pre-correction fits already supported non-inferiority, so the correction
  strengthens an existing finding rather than creating one.
- **The utility ceiling** under Variants B and C was held by GBT. If the
  correction moves the ceiling to the primary model, the model attaining the
  highest Utility Score changes while the substantive claim (the ceiling sits a
  few per cent above the no-alert strategy) does not. The claim predicates in
  `check_consistency.R` assert which model holds the ceiling, so a change is
  detected programmatically.
- **H1's model-class range** is bounded by the primary model above and qSOFA
  below. GBT sits at neither extreme, so the range is expected to be
  essentially unchanged.

**22.5 Check.** `gbt_valid_split()` raises an error if either side of the
split carries no positive case. It does not fall back to monitoring another
set, which could silently reintroduce the defect. This follows the principle
adopted after the `intersect()` and NEWS2 defects: an interface raises an
explicit error rather than applying a silent fallback.

**Deliverables:** no new output files. Every `06_*` fit, and every downstream
quantity that reads a GBT prediction, is re-estimated: `07_*`, `08_*`
(GBT external rows), `09_*`, `11_*`, `12_*`.

---

# Amendment 9: External Validation of the Treatment-Independent Label

**Date:** 2026-08-18
**Status:** **POST-HOC.** Like Amendments 1–8, not pre-specified. It was decided
after the results of the preceding amendments were in hand and after the
external coverage constraint had been measured, so it is exploratory by
construction. It is recorded here before the arm was run.

**23.1 What it adds and why.** Every external estimate in the study so far is
confined to the microbiology-covered sub-cohort — 2,824 of 181,589 eICU stays,
1.555 % — because the Sepsis-3 anchor requires a culture record. Variant D
(Amendment 2) carries no treatment timestamp of any kind: its onset is the
first hour at which a physiology-only SOFA score stands ≥ 2 points above the
stay's admission baseline. It therefore needs no microbiology and can be
constructed on the entire cohort. This amendment adds one external arm applying
the frozen Variant D models to the **full** eICU cohort. It is the only
external estimate in the study whose denominator is the complete eligible
eICU-CRD cohort.

**23.2 Estimand and status.** The arm reports external AUROC and AUPRC for the
primary model, the gradient-boosted comparator and NEWS2 under Variant D, with
the stay, person-hour and event counts beside them. It is **descriptive**: no
p-value is computed, it joins **no** corrected family, and it is neither a
confirmatory nor an exploratory test in the sense of §14.

**23.3 Exclusions, and why they are asserted rather than assumed.** Variant D is
excluded from H1 and from the variance decomposition by Amendment 2. This arm is
excluded from **H5** on identical terms, and for the same reason: a post-hoc
label kept out of the internal analyses must not enter a pre-registered family
through the external analysis. The arm writes to
`08_external_validation_results_altlabel`; H5 and stage 09 read
`08_external_validation_results`. Stage 08 checks at run time that neither file
contains the other's variants, and raises an error if either does.

**23.4 The two cohorts do not score SOFA from the same components.** eICU's
`vitalPeriodic` carries no Glasgow Coma Scale. The neurological component is
therefore scored from `score_sofa()`'s assumed-normal substitution in both the
hourly score and the baseline. It contributes no change to the difference, so
neurological deterioration is not captured. eICU's deterioration delta rests
on five SOFA components and MIMIC-IV's on six. The external label is
consequently a slightly coarser construct than the internal one. The two
labels share a definition but are computed from different available SOFA
components.

**23.5 The ceiling on what this arm can establish, recorded before the run.**
Variant D's onset is a deterministic function of physiological variables that
are themselves model inputs. The outcome thus overlaps with the predictors by
construction: a model with access to the panel is partly predicting a
transformation of its own covariates. This is why Variant D's internal AUROC
(primary 0.8498, GBT 0.9360 on the unrestricted temporal window, at the time
of writing) sits so far above every Sepsis-3 variant's. **A high external
AUROC in this arm is therefore not evidence that sepsis prediction transports
well.** It would be evidence that a physiological deterioration rule, computed
from a given set of vital signs and laboratory values, reproduces itself in a
second dataset. That is a weaker and different claim. The arm's value lies in
its cohort coverage and event count, not in the magnitude of its AUROC, and the
thesis must say so wherever it quotes the arm. Two outcomes are anticipated,
neither of which is a finding about sepsis, and other factors could also
contribute:

- discrimination substantially above the Sepsis-3 arm's, consistent with the
  partial overlap just described;
- a fall toward the Sepsis-3 arm's, which would point to cross-cohort
  measurement rather than the label as the source of the degradation.

**23.6 Timebox.** One implementation pass and one stage-08 run are allowed. The
change is reverted, and the experiment reported in Future Work as an untested
question, in either of two cases:

- the run does not produce a scoreable arm on the first clean attempt;
- the integrity check on `08_external_validation_results` and
  `08_h5_internal_external`, which requires both to be unchanged, fails.

The experiment is not to be modified repeatedly until it runs. This is
recorded so that a negative outcome cannot be re-described afterwards as a
decision not to pursue.

**Deliverables:** `08_external_validation_results_altlabel` (Parquet and CSV),
additional `anchor = "deterioration"` rows in `08_eicu_label_summary`. No
existing output file changes in content: the primary and sensitivity arms are
recomputed with identical values, and this is checked rather than asserted
(value by value; see §24.5 on why file hashes cannot be used). Per-hour external
predictions were not persisted for this arm in the original pass, matching the
antibiotic-only sensitivity arm. **Amendment 10 reverses that decision**: they
are now written to `08_eicu_predictions_D`, because an arm important enough to
carry a conclusion is important enough to carry an interval.

---

# Amendment 10: Intervals on Three Point-Estimate Claims, and H6's Second Limb

**Date:** 2026-08-31
**Status:** **POST-HOC.** Like Amendments 1–9, not pre-specified. It changes no
estimand, no threshold, no direction and no hypothesis. It attaches uncertainty
to three quantities that were reported without it, and it completes a test that
was implemented against one boundary of a two-boundary null.

**24.1 Why.** An examiner-style audit of the compiled thesis found four places
where an inferential statement rested on a point estimate without an interval.
The pipeline's inference plan (Amendment 1) attaches intervals to every
*contrast entering a corrected family*. By construction, that excludes the
post-hoc arms, and the post-hoc arms are where three of this study's
conclusions now live. The original inference plan did not cover analyses
outside the corrected families, so the gap is closed once, here, rather than
case by case.

**24.2 What is added.**

1. **Ablation contrast intervals** (`12_ablation_ci`). The paired
   ablated-minus-full AUROC difference for the primary model and the
   gradient-boosted comparator under each of Variants A, B and C, with a
   stay-level cluster-bootstrap interval. Both arms are fitted on the same
   training stays and scored on the same test stays, so the difference is paired
   within replicate. This interval supports or fails to support the thesis's
   statement that discrimination is "essentially unaffected" by removing the
   action-derived features.

2. **Cross-label calibration intervals** (`12_calibration_ci`,
   `12_calibration_contrasts`). The primary model's calibration slope and
   calibration intercept under each variant, and the paired contrast of each
   against Variant B. These intervals support or fail to support the statement
   that the label definition makes no practical difference to calibration. The
   calibration fits are refitted inside each replicate. `utils.R` carries a
   warm-started IRLS for the two small models (one and two parameters),
   verified against `glm()` to within its own convergence tolerance. `glm()`
   itself was about two orders of magnitude too slow to be practical at this
   replicate count.

3. **Variant D transport interval** (`12_altlabel_transport_ci`). The
   internal-minus-external AUROC difference for the Amendment 9 arm, drawn as
   two independent bootstrap streams and differenced, exactly as H5 is. This is
   the only external estimate in the study that clears the 100-event
   interpretability floor and it was the only one carrying no interval. It
   remains **excluded from H5** and from every corrected family, on Amendment
   9's terms and for Amendment 9's reason.

4. **H6's second limb.** H6's null is the interval −0.02 ≤ θ ≤ 0.02. An
   interval null has two boundaries, and rejecting it means clearing one of
   them. The implementation tested the upper boundary only, which asks whether
   the boosted trees beat the hazard model by more than the margin. That is the
   pre-registered concern and remains the limb the thesis's conclusion is about
   — but with θ̂ on the negative side of zero it is also the limb the data
   cannot speak to, and it returns p ≈ 1 for arithmetic reasons rather than
   evidential ones. Both limbs are now computed, and both are persisted in
   `12_confirmatory_tests` as `p_limb_upper` and `p_limb_lower`. The reported
   `p_raw` is their minimum. Under any θ inside the interval, at most one limb
   can be small, because a θ near one boundary is two margins (0.04) away from
   the other. The minimum is therefore approximately valid for the interval
   null. Its rejection rate under the null exceeds the nominal level only by
   the probability that the far limb also rejects, which is negligible at this
   study's precision. It is not strictly conservative; twice the minimum (a
   Bonferroni bound) would be. Rejecting this null would show that the two
   models differ by more than the margin. Failing to reject it does not by
   itself establish that they lie within the margin. Any claim of
   non-inferiority or equivalence rests on where the confidence interval for θ
   lies relative to ±0.02.

**24.2a A consequence not anticipated when this amendment was written.** The
per-variant calibration intervals were added to support the *cross-label*
comparison, but they are also the first intervals this study has placed around
the absolute calibration targets, intercept = 0 and slope = 1. At 548,827
person-hours they resolve departures the point estimates hide: the slope covers
one under Variants A and B but not under C, and the intercept covers zero under
C but not under A or B. Under each variant, therefore, one of the two 95%
intervals excludes its ideal value. With more than half a million person-hours,
such an exclusion does not by itself imply practically important
miscalibration. This does not change any hypothesis or verdict. As an
approximate illustration of size, an intercept of −0.106 on the logit scale
lowers a 0.00189 hourly risk by about a tenth of itself. It does mean the thesis can no longer say the primary model
is calibrated under every variant without qualification, and §5.3.1 has been
rewritten to state the measured position instead. Recorded here because it is a
claim the amendment weakened, not one it was designed to test.

**24.3 What does not change, and why that is checkable.** The verdict for every
hypothesis is unchanged, and so is every Holm-adjusted p-value. H6's reported
`p_raw` moves off 1.000 onto the lower limb's value, but Holm's step-down is
driven by the *ordering* of the raw p-values, and H6 remains the largest or
second-largest in the family either way; H5's adjusted value of 0.551 is
determined by its own raw value of 0.092 and the family size of six, neither of
which this amendment touches. This prediction is recorded before the re-run so
that it can be compared with the regenerated outputs. Nothing in H1–H5 is
recomputed at all: the ablation, calibration and transport blocks read stored
predictions and write new files.

**24.4 The direction of the risk.** Each of the first three changes attaches an
interval to a claim that was previously stated on a point estimate. The
interval can leave such a claim standing or weaken it, but it cannot make the
claim stronger than its original wording. The fourth change replaces an
uninformative p-value with an informative one. This is recorded so that the
amendment log shows which amendments worked in the study's favour. Amendment 7
did, and is flagged as such in the limitations; this one cannot.

**24.5 Timebox.** One stage-08 run to persist the Variant D external
predictions and one stage-12 run. Stage 08's existing outputs must be
*value*-identical afterwards, checked field by field rather than by file hash:
Parquet embeds writer metadata, so a re-run moves every file's bytes while its
contents are unchanged, and a hash comparison would report a change that is not
one.

*Outcome, appended after execution.* Verified on the run of 2026-08-31: all
nine of stage 08's result tables
match the frozen run exactly, including the external AUROCs (A 0.6913 /
B 0.6960 / C 0.7370), the coverage ladder (2,824 of 181,589 = 1.555 %; 232 both
limbs), the event-rate ratios (0.094 anchored, 0.7458 under Variant D) and the
Variant D arm's 52,535 events over 5,866,697 person-hours.

**Deliverables:** `08_eicu_predictions_D`, `12_ablation_ci`,
`12_calibration_ci`, `12_calibration_contrasts`, `12_altlabel_transport_ci`,
two new columns in `12_confirmatory_tests`, and four new rows in
`12_analysis_register`.
