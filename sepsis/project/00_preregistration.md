# Pre-registered Protocol: V2 Sepsis Prediction Study

**Quantifying Model, Label, and Methodological Contributions to Variance in Real-Time Sepsis Onset Prediction**

**Version:** 2.0  
**Date:** 2026-07-13  
**Status:** Pre-registered (Phase 0 deliverable; locked before any of the modelling reported in this study)

---

## 1. Primary Research Question

In real-time sepsis onset prediction on MIMIC-IV, how does predictive performance split between two things:

- **(a) Model choice** — comparing an interpretable discrete-time survival model against gradient-boosted trees
- **(b) Analyst decisions** — specifically: how sepsis is defined, whether the data is split by time or randomly, when the prediction is anchored relative to clinical action, and which metric is reported

---

## 2. Label Variants (Pre-specified; locked before cohort extraction)

Three defensible readings of Sepsis-3 are tested. All share the same base definition (suspected infection plus acute SOFA increase ≥ 2) but differ in how strictly they define the time windows for antibiotic and culture draws.

| Variant | Name | Antibiotic to Culture (h) | Culture to Antibiotic (h) | SOFA window before (h) | SOFA window after (h) | SOFA baseline |
|---------|------|---|---|---|---|---|
| A | Narrow | 24 | 24 | 24 | 12 | ICU admission SOFA |
| B | Seymour-Standard | 72 | 24 | 48 | 24 | ICU admission SOFA |
| C | Liberal | 72 | 72 | 48 | 24 | Rolling 24h min SOFA |

The label-variance result is only considered reliable if at least two variants work (gate G2).

---

## 3. Prediction Framing (Lauritsen et al., 2021)

How the prediction is set up matters. These are the details:

- **Observation window:** expands from ICU admission — all data up to the current hour
- **Prediction horizon:** what happens in the next 6 hours
- **Window shift:** each hour generates one prediction
- **Prediction trigger:** every person-hour at risk, starting from MIN_OBS_HOURS
- **Minimum observation before prediction:** 1 hour after ICU admission

This matches the setup used in the PhysioNet/CinC 2019 Challenge (Reyna et al., 2020).

---

## 4. Validation Architecture

Four different ways to split the data are tested. Each one answers a different question about generalization.

| Split | Design | Purpose |
|-------|--------|---------|
| Internal (primary) | Temporal: training on 2008–2016, testing on 2017–2019 | Tests honest internal performance; follows time rather than randomly mixing years (Guo et al., 2022) |
| Internal (secondary) | Random patient-level 75/25 split | Measures how much better models look when future data leaks into training |
| Treatment-anchored | Restricted to hours before first culture or antibiotic | Removes what clinician suspicion alone predicts (Kamran et al., 2024) |
| External (primary) | eICU-CRD database | Does the model generalize beyond MIMIC-IV? |
| External (fallback) | Within-MIMIC-IV temporal split if eICU doesn't work | Alternative if harmonisation between databases fails |

Expected external degradation based on prior work: roughly 0.085 AUROC (Moor et al., 2023). If the drop is much smaller, the external dataset is probably too similar to be a real test.

---

## 5. Primary Evaluation Metrics

The field usually reports AUROC. This study does not lead with AUROC. Here's why and what's reported instead.

1. **PhysioNet Utility Score** (Reyna et al., 2020): balances rewarding early prediction against penalising late alerts, missed cases, and false alarms. It can go negative—and that's the key. Wang et al. (2025) found the Utility Score collapsed from +0.381 to −0.164 across ninety-one models while AUROC barely moved. AUROC is blind to that collapse.

2. **Calibration** (intercept, slope, flexible curve): the thing predictive analytics usually gets wrong (Van Calster et al., 2019). For the competing-risks model, cause-specific calibration is reported via multinomial recalibration (Heyard et al., 2020).

**AUROC is designated DESCRIPTIVE ONLY.** It's reported for completeness, not as the primary claim.

---

## 6. Secondary Metrics

- **AUPRC:** essential when events are rare (one positive per hour)
- **Discrete-time cause-specific AUC and concordance index** (Heyard et al., 2020)
- **Decision-curve net benefit** (Vickers & Elkin, 2006)
- **Alert burden:** false alerts per true alert (benchmark is 1.4 from published data)
- **Lead time:** how many hours ahead of clinical recognition the model alerts

---

## 7. Pre-registered Hypotheses

Six hypotheses, locked before any modelling. Each tests one aspect of whether analyst choices matter as much as model choice.

| ID | Hypothesis | Threshold | Source |
|----|-----------|-----------|--------|
| H1 | Label dominance: do label changes affect AUROC as much as model changes? | Label swing 0–6% should be ≥ model gain 1–5% | Cohen et al. (2024) |
| H2 | Coefficient instability: does at least one covariate change sign or swing by 2× across labels? | n/a — yes/no criterion | Lauritsen et al. (2021) |
| H3 | Treatment leakage: does restricting to pre-treatment hours drop AUROC by ≥ 0.03? | Δ ≥ 0.03 | Kamran et al. (2024) |
| H4 | Split optimism: is temporal-split AUROC at least 0.02 lower than random-split? | Δ ≥ 0.02 | Guo et al. (2022) |
| H5 | Metric divergence: does Utility Score decline more than AUROC from internal to external validation? | Utility may cross zero | Wang et al. (2025) |
| H6 | Model-class null: is the hazard model within 0.02 AUROC of gradient-boosted trees? | \|Δ\| ≤ 0.02 | Christodoulou et al. (2019) vs. Fagerström et al. (2019) |

H1 and H6 push against each other by design. If the label dominates (H1), then model class doesn't matter much (H6 is true). If the model matters (H6 is false), then label doesn't dominate (H1 is false). Both outcomes are informative.

---

## 8. Comparators

Which other models and rules are tested alongside the primary model?

| Comparator | Role | Why |
|-----------|------|-----|
| NEWS2 | Rule-based baseline everyone knows | Evans et al. (2021) recommend NEWS2 over qSOFA for screening |
| SIRS, qSOFA | Reference only — shown for context | No formal testing |
| Static Cox PH | Deliberately weak baseline | Tests the cost of the field's standard approach |
| Gradient-boosted trees | Required ML comparator | Reyna et al. (2020): published comparisons don't transfer, so fitting in-house on identical conditions is essential |
| Dynamic deep survival | Optional, if time permits | Would answer whether temporal models beat static ones |

---

## 9. Equity Analysis

The study examines whether results hold across different patient groups.

**Subgroups:** race, ethnicity, primary language, insurance status (based on Wang, Li, Naidech, & Luo, 2022).

**Two separate analyses:**

1. **Subgroup performance:** Utility Score, calibration, AUPRC, and alert burden within each subgroup
2. **Subgroup label-sensitivity:** how many patients each label variant identifies as septic within each subgroup — this combination hasn't been reported for any sepsis model

---

## 10. Sample Size (Riley et al., 2019)

Formal power calculation per label variant:

- **Anticipated AUC:** 0.846 (from Moor et al., 2023 internal AUROC)
- **Targets:** shrinkage ≥ 0.9; gap between apparent and adjusted R² ≤ 0.05
- **Tool:** `pmsampsize::pmsampsize()` (binary outcome, person-hour level)
- **Effective information:** governed by onset events, not total person-hours

If a variant turns out to be underpowered, that's a finding, not a failure.

---

## 11. Go/No-Go Gates

Checkpoints at which the study might stop if key milestones fail.

| Gate | Week | Question | If it fails |
|------|------|----------|-----------|
| G0 | 2 | Is the protocol registered? | Stop — do not model |
| G1 | 3 | Is data access confirmed? | Continue on demo data; not blocking |
| G2 | 7 | Are ≥ 2 label-variant datasets built? | Minimum two variants required |
| G3 | 15 | Is internal validation complete? | Drop the optional deep-survival comparator |
| G4 | 18 | Is eICU harmonisation working? | Fall back to within-MIMIC temporal split |

---

## 12. Reporting Standards

- TRIPOD+AI (Collins et al., 2024) guidelines followed
- PROBAST+AI self-appraisal completed at design time (Moons et al., 2025)
- Code released openly under permissive licence

---

# Amendment 1: Inference, Multiplicity, and Analysis Status

**Date:** 2026-07-30  
**Status:** POST-HOC. Written after the first pass of analyses. Not pre-specified.

**What changes:** This amendment adds uncertainty (confidence intervals) to claims that were already locked in §1–12. No hypothesis, estimand, threshold, direction, subgroup, or model is changed. The amendment only:
- Attaches uncertainty to pre-specified contrasts
- Adds multiplicity control (which the original protocol should have specified)

## 13. Uncertainty Quantification

**13.1 Resampling unit:** Person-hours cluster within stays. If person-hours were resampled independently, standard errors would shrink several times over (they're ~45 correlated hours per stay). Instead, whole stays are resampled with replacement—carry all person-hours of a drawn stay with it.

**13.2 Interval type and replicates:** 95% percentile intervals. B = 2,000 replicates for internal contrasts; B = 1,000 for external validation (7.9M person-hours in eICU). Seed fixed at 42; each contrast draws from its own seed offset.

**13.3 Pairing:** Variants A, B, C are built on the same test stays. All model classes are scored on the same person-hours. So contrasts within these sets (H1, H6) use paired resampling—the interval captures the correlation between what's being compared. Contrasts across different test sets (H4, H5) use independent streams.

**13.4 Stratification for subgroups:** Subgroup bootstrap resamples stays within subgroup, holding observed subgroup sizes fixed. The subgroups are the estimand, not random draws.

**13.5 P-values:** Recentre the bootstrap distribution on the null boundary and read off tail area. Use the (1 + count)/(B + 1) convention so no p-value reports as exactly zero.

**13.6 Degenerate cases — what to do when standard inference breaks:**

- **H2 (coefficient instability):** a stability criterion, not a contrast. The multinomial fit carries no Hessian; refitting 2.3M training rows under bootstrap is intractable. Report as a **descriptive count with no test**.
- **H3 (treatment leakage):** the outcome doesn't exist in the pre-treatment window (completely separated). AUROC is undefined. Report an **exact one-sided upper bound on the per-hour onset rate** instead.
- **H5 (metric divergence):** partially degenerate. The estimand actually tested is a substitute for §7's specification. This is recorded here rather than left to infer from results.

  §7 specifies H5 as a comparison of proportional declines (Utility Score falls proportionally more than AUROC from internal to external). That comparison requires a non-negligible baseline Utility Score. Under the primary label it's 0.000 at default threshold, 0.025 at best threshold. Dividing by near-zero yields a ratio with no usable sampling distribution. External validation has only 29 observable events—not enough to estimate external Utility Score at all.

  **What gets tested instead:** AUROC alone (internal minus external for the primary model, Variant B), tested against null. This substituted contrast occupies H5's slot in the Holm family. Three constraints:

  1. This is NOT an alternative route to H5's original claim. Metric divergence is not established by this and must not be reported as established.
  2. The direction and threshold were already fixed in §4 (expected 0.085 degradation), so no new degree of freedom is taken.
  3. The Utility limb is reported **descriptively and internally only** — the swept ceiling under the primary label.

  The substituted contrast happens to produce the family's smallest raw p-value. It's reported as a non-confirmation based on interval width; nothing in conclusions rests on it.

## 14. Multiplicity Control

**14.1 Confirmatory family (FWER):** The six hypotheses H1–H6 form one family. Controlled by **Holm–Bonferroni at α = 0.05**. Family size is fixed at **m = 6** (the number pre-registered), not the number that turned out testable. H2 and H3 reserve slots without p-values—deliberately conservative.

**14.2 Exploratory families (FDR):** Subgroup analyses were pre-registered in scope (§9) but not in specifics (which subgroup levels, which reference, which direction). They're exploratory and corrected by **Benjamini–Hochberg at q = 0.05** within two families:

| Family | Contents |
|--------|----------|
| E1 | Subgroup AUROC contrasts: each subgroup level vs. reference, across race, language, insurance × both models |
| E2 | Subgroup label-sensitivity (A–C range) contrasts: each subgroup level vs. reference, across all equity variables |

Correction denominator is the number of contrasts actually computed, not just those in the thesis. Selecting a subset for presentation doesn't shrink the family.

**14.3 Reference level:** Each subgroup is contrasted against its largest level (by sample size only, never by outcome). Recorded in output tables.

**14.4 Eligibility:** A subgroup is reported only with ≥ 50 person-hours and ≥ 5 sepsis onsets. Below that floor, listed as non-estimable rather than shown with uninterpretable point estimates.

**14.5 Why the two corrections differ:** A confirmatory claim must survive family-wise control—one false positive invalidates the claim. Exploratory scans exist to generate hypotheses; only the false-discovery proportion needs bounding. FWER is over-strict for exploration; FDR is too weak for confirmation. Both are reported.

## 15. Confirmatory vs. Exploratory Status

Every analysis carries an explicit tag, held in `12_analysis_register.parquet` and reproduced in the thesis:

| Tag | Meaning |
|-----|---------|
| **Confirmatory** | Estimand, threshold, direction fixed in §1–12 before modelling |
| **Exploratory** | Pre-registered in scope, not in specifics; generates hypotheses |
| **Descriptive** | No inferential claim |

---

# Amendment 2: A Label That Does Not Depend on Treatment Timing

**Date:** 2026-08-02  
**Status:** POST-HOC. Written after initial analyses.

**Why this amendment:** §2 locks three Sepsis-3 readings, all anchored to treatment (antibiotic + culture). Two things therefore follow from H1's result—and the protocol can't separate them:

- **Definitional:** Sepsis-3 makes onset depend on treatment timing. Changing the windows *must* move onsets. Part of H1's label spread is guaranteed by construction.
- **Empirical:** Whether a label owing nothing to treatment timing selects different patients at different hours.

Only the second is a claim about the world. It can't be tested inside a family that all share the same anchor, so a label without the anchor is added.

## 16. Alternative Label Variants

Sepsis-3 is a conjunction (*suspected infection* AND *acute organ dysfunction*). Split it and label each limb separately.

| Variant | Name | Suspicion anchor | Organ dysfunction | Uses treatment timing? |
|---------|------|---|---|---|
| B | Seymour-Standard | required | required | yes |
| E | Anchor-Only | required (B's windows) | not required | yes |
| D | Deterioration | not required | required | **no** |

**Variant E (Anchor-Only):** Onset is suspicion-of-infection time alone (B's windows: antibiotic–culture 72h, culture–antibiotic 24h). SOFA criterion removed. This is purely clinician behaviour—predicting it means predicting who gets cultured and started on antibiotics. Not a sepsis definition; AUROC is not a sepsis result.

**Variant D (Deterioration):** Onset is the first hour after hour 1 where physiology-only SOFA rises ≥ 2 above admission baseline (vasopressor and catecholamine terms withheld; cardiovascular scored from MAP alone). No antibiotic order, culture draw, or drug administration enters the definition.

**Why not PhysioNet/CinC 2019, SEP-1, or CDC Adult Sepsis Event?** All three are anchored to treatment by construction. They're valid alternative definitions, discussed as such, but can't serve as the treatment-independent comparator.

**Fitting:** D and E use identical model specification, feature set, temporal split, and seed as A–C. Label is the only difference.

**Interpretive limits, stated upfront:**
- Variant E's discrimination is discrimination about *treatment behaviour*, not sepsis
- Variant D's label is a threshold function of recorded physiology; five of six SOFA components are model inputs. Its AUROC is partly self-fulfilling. The informative comparison is not the level but whether D selects different patients at different hours.

## 17. Estimands and Multiplicity for Amendment 2

**17.1 Anchor-attributable fraction:** Share of Variant B's discrimination reproduced by the treatment anchor alone:

    φ_anchor = (AUROC_E − 0.5) / (AUROC_B − 0.5)

Bootstrapped end-to-end, reported with 95% interval. No p-value (it's a ratio with no meaningful null). Outside the corrected family.

**17.2 Exploratory family E3:** AUROC differences {D, E} vs. B × {primary, GBT}, corrected by **Benjamini–Hochberg at q = 0.05**. Contrasts paired within replicate.

**17.3 Label agreement:** Onset agreement between each variant and B (percent, κ, sensitivity to B's positives, median shift) is **descriptive—no test**.

---

# Amendment 3: Fit Identification and Data Plausibility

**Date:** 2026-08-03  
**Status:** POST-HOC.

Three defects found during review, all affecting every result:

1. No physiological plausibility filter existed in the pipeline
2. The primary multinomial is completely separated and was fitted unpenalised—its MLE doesn't exist; `convergence = 0` was uninformative
3. `heart_rate`/`hr` naming mismatch silently dropped heart rate from every fit via `intersect()`

**Fixes:** 
- `PLAUSIBLE_RANGES` + `apply_plausibility()` applied before forward-fill (stages 03, 08)
- `PRIMARY_MODEL_DECAY = 1e-4` with `check_multinom_fit()` guards
- `require_features()` errors on any declared-but-absent feature

The penalty is not tuned: test AUROC moves < 0.02 across a 20-point ridge path. That insensitivity is the justification—never present it as optimised.

---

# Amendment 4: Standard Sepsis-3 Onset Timing (Variant F)

**Date:** 2026-08-05  
**Status:** POST-HOC.

**Why:** §2 assigns onset as `t_susp` for variants A–C. SOFA gates *membership* but contributes no timing. Because `t_susp` is by construction the later element of a qualifying antibiotic–culture pair, no onset can precede first antibiotic or culture. H3's zero is therefore entailed by implementation, not measured. The thesis's claim "no patient develops sepsis before doctors begin treatment" was an over-reading.

External evidence contradicts that absolute claim (Epic Sepsis Model v2: median lead times 1.4–7.1 hours ahead of clinician recognition).

The standard operationalisation (Seymour et al., 2016; PhysioNet/CinC 2019) assigns `t_onset = min(t_susp, t_SOFA)`. Amendment 2 rejected this as a treatment-independent comparator (membership still anchored). But it's valid as a timing comparator.

## 18. Variant F: Sepsis-3 Early-Onset

| Variant | Membership | Onset time | Uses treatment timing? |
|---------|-----------|------------|---|
| B | Sepsis-3 conjunction, B's windows | `t_susp` | membership AND timing |
| F | **identical to B** | `min(t_susp, t_SOFA)` | membership only |

`t_SOFA` is the first hour in `[t_susp - 48h, t_susp + 24h]`, after MIN_OBS_HOURS, where SOFA is already ≥ SOFA_INCREASE_THRESHOLD above admission baseline.

**Two stated limits:**
- (a) The full SOFA score including vasopressor terms (Seymour et al. specify this). F onset is free of the antibiotic-culture anchor but not treatment in general; Variant D remains fully treatment-independent.
- (b) `t_SOFA` is searched only in the 72h modelled panel.

**Estimands:** Descriptive—onset count, percentage moved earlier, median shift, count falling before first antibiotic/culture (the conjunction rule fixes at zero). Exploratory—F's AUROC and ΔAUROC vs. B join family E3.

**Agreement:** F and B label the same stays septic (stay-level membership identical). Informative agreement is onset shift. κ(F, B) < 1 on modelled horizon: moving an onset earlier can move it into the 72h window.

---

# Amendment 5: Action-Derived Feature Ablation

**Date:** 2026-08-06  
**Status:** POST-HOC.

**Why:** The study argues the Sepsis-3 label is constituted by clinician action. The same objection applies to part of the **feature set**. Two kinds of covariate record clinician behaviour, not patient physiology:

- **Vasopressor exposure** — treatment, not measurement
- **Per-test order indicators** — record a decision to look; the value carries physiology; the indicator carries clinician attention

Without ablation, "the label is constituted by clinician action" is unfalsifiable on the feature side.

## 19. The Ablated Fitting Arm

`ACTION_DERIVED_FEATURES` in `config.R` names exactly 8 of 22 covariates. Primary model and gradient-boosted comparator are refitted on the same training rows, temporal split, seed, and hyperparameters, with those 8 removed and all physiological measurements retained.

**19.1 Conservative boundary:** Forward-filled laboratory *values* are retained (even though they exist only because somebody ordered the test). Dropping them would remove most laboratory signal. What's removed is features encoding *only* clinician behaviour. Ablation measures explicit traces of clinical attention; a predictor set with no trace is unconstructible from routine ICU data.

**19.2 Nothing is re-tuned:** Gradient-boosted arm keeps hyperparameters of the full fit. Re-tuning would confound feature set with search budget.

**19.3 Estimands:** Descriptive and exploratory, no test:
- ΔAUROC and ΔUtility between full and ablated arms, per variant and model
- Cross-label coefficient-instability count (H2 criterion) recomputed on ablated arm
- Instability rate split by feature kind (action-derived vs. physiological)

**19.4 Execution isolation:** `V2_ARMS=ablated` restricts stages 05 and 06 to the ablated arm. Gradient-boosted tree fitting is not bit-stable across runs, so this isolation matters.

---

# Amendment 6: Subgroup Interpretability Floor

**Date:** 2026-08-06  
**Status:** POST-HOC.

**Why:** §14.4 sets one rule: a subgroup is reported only with ≥ 50 person-hours and ≥ 5 sepsis onsets. That decides whether AUROC can be *computed*. It doesn't decide whether the estimate can be *read*. At 5 events, the bootstrap interval spans most of the unit interval and hits the 0.5 chance line. Family E1 as originally constituted corrected over 30 contrasts, most carrying no information, which diluted Benjamini–Hochberg and invited interpretation the design can't support.

## 20. Two Thresholds, and the Distinction Between Them

**20.1 The two floors:**
- `MIN_SUBGROUP_EVENTS = 5` decides whether a subgroup AUROC is **computed**
- `MIN_SUBGROUP_EVENTS_INTERPRET = 100` decides whether it is **interpreted**

The second is defined as `MIN_EXTERNAL_EVENTS` in `config.R`, so internal and external floors can't drift apart.

**20.2 Below-floor strata are still estimated and tabulated,** flagged `†`. Suppressing them hides cohort composition. The figure showing their intervals hitting chance is the argument for the floor. They're excluded from spread statements, interpretive claims, and **family E1**.

**20.3 Consequence for the family:** E1 falls from 30 contrasts to 6. All six carry ≥ 100 events. E2 and E3 unaffected (E2's estimand is a stay-level proportion, so event floor doesn't apply).

**20.4 The tension with §14.2:** §14.2 says "the number of contrasts actually computed, not reported," and "selecting a subset doesn't shrink the family." Reducing E1 from 30 to 6 is on its face the move that rule prohibits. Four reasons why it's nonetheless admissible:

1. **Different manoeuvre:** §14.2 forbids computing many, reporting favourables, correcting only over reported. The floor is not a presentation choice; below-floor contrasts are still estimated and shown, removed from *inferential* family with disclosure.
2. **Outcome-blind:** Eligibility depends on event count alone. No p-value, effect size, direction, or subgroup identity enters it.
3. **Exculpatory direction:** The reduction *removed* the family's only surviving discovery rather than creating one.
4. **Verdict invariant:** Nothing in E1 survives Benjamini–Hochberg under either denominator (m = 6: smallest q = 0.066).

**20.5 What must be reported:** Both floors, count clearing interpretation floor, fact that only two racial strata clear it—one of which is missingness. The study contains no sufficiently powered racial comparison between two actual demographic answers. That sentence is the finding; don't soften it.

---

# Amendment 7: Uncertainty Diagnostic for H2

**Date:** 2026-08-10  
**Status:** POST-HOC.

**Why:** §13.6 recorded H2 as untestable because the multinomial carried no variance estimate. That's been resolved. `sandwich` lacks `estfun` for `nnet::multinom`, but the missing piece is a score matrix the fit already stores.

H2's criterion is a **threshold rule on point estimates** (sign reversal or 2× magnitude swap). It can't distinguish:
- A coefficient genuinely taking different values under different labels
- A coefficient estimated so imprecisely that doubling is within its noise

For covariates with SE comparable to estimate, the second is near-certain and carries no label-sensitivity information. The count of flagged covariates is an **upper bound** on instability present, and its looseness was unmeasured.

## 21. The Diagnostic

**21.1 Definition:** For each covariate flagged by H2, take the two variants at range extremes, form the difference of coefficients, refer it to pooled SE:

    z = |β_hi − β_lo| / sqrt(SE_hi² + SE_lo²)

Reported per covariate alongside three coefficients and pooled SE, with `exceeds_noise` set at 1.96.

**21.2 Not a hypothesis test; no p-value emitted.** Two reasons:
1. **Estimates are correlated:** Variants A, B, C fit on overlapping stays
2. **Covariance is penalised estimator's:** The sandwich is ridge-regularised

The quantity answers "is this difference estimation noise, or an order of magnitude above it?" That's what the H2 count needs answered, reported as ratio rather than inference.

**21.3 Reporting order:** Pre-registered count first (unmodified); diagnostic second (post-hoc, exploratory). Don't restate count as covariates surviving the diagnostic—that's the manoeuvre this protocol criticises.

**21.4 Direction recorded in advance:** Favourable to the thesis, so requires most scepticism. Covariates surviving the diagnostic disproportionately action-derived would be *convergence* with Amendment 5 ablation, not independent confirmation—both computed from the same three fits.

---

# Amendment 8: Comparator Fit Isolation

**Date:** 2026-08-11  
**Status:** POST-HOC.

**The defect:** Stage 06 fitted gradient-boosted comparator with test set as the final element of `evals`. `xgb.train` selects `best_iteration` against the last element. That element was the temporal test set—model-selection choice was made on the rows the model was scored on. Leakage.

**The fix:** `gbt_valid_split()` in `utils.R` carves an early-stopping set out of *training* rows.

## 22. Properties Fixed Here

**22.1 Split on stay, not row:** Person-hours are ~45 correlated observations per stay. Row-level split leaves same patient on both sides. This is the unit the cluster bootstrap and Riley's criterion use.

**22.2 Nothing is re-tuned:** `GBT_VALID_FRACTION = 0.15` and `GBT_VALID_SEED = 42` are constants. Neither is searched. Comparator is reference point, not object of study.

**22.3 Same held-out stays serve full and ablated arms** — both call helper with same seed and fraction. Amendment 5 contrast remains contrast in feature set alone.

**22.4 Direction of correction, recorded before re-run:** Removing optimistic bias from comparator lowers GBT discrimination slightly. Runs against thesis argument in one place, with it in another:

- **H6:** Weaker GBT widens gap in interpretable model's favour. Pre-correction fits already supported non-inferiority; correction strengthens existing finding.
- **Utility ceiling:** Held by GBT under variants B and C. If correction moves it to primary model, holder changes while substantive claim (ceiling sits few per cent above no-alert) doesn't. Claim predicates in `check_consistency.R` assert holder.
- **H1's model-class range:** GBT sits at neither extreme, so range essentially unchanged.

**22.5 Guard:** `gbt_valid_split()` stops if either side carries no positive case, rather than falling back to watchlist. An interface fails loudly or not at all.
