# Response to Supervisory Feedback — Summary of Changes

**Abdul Ahad** · G00486649 · M.Sc. Computing, ATU Galway
*Model, Label, or Analyst? A Variance Decomposition of Real-Time Sepsis Onset Prediction on MIMIC-IV*

Three supervisory feedback rounds and one full examiner-style audit, all
closed. This is the one-page-per-section summary; `v1.md`, `v2.md`, `v3.md` and
`v4.md` in this directory hold the full record with file locations and
diagnostics.

---

## 1. Headline: six findings reversed

Every reversal came from fixing a defect or adding uncertainty quantification —
none from changing a modelling choice to obtain a better number.

| # | Originally reported | Now | Cause of the change |
|---|---|---|---|
| **H1** Label dominance | Confirmed; label 0.153 > model 0.142 | **Not confirmed, reversed.** Label **0.0123** vs model **0.1499**; Δ = −0.1375 [−0.162, −0.109] | Confidence intervals, then the Variant B fit repair |
| **H3** Treatment leakage | "0 pre-treatment onsets" — presented as the strongest finding | **Definitional, not empirical.** The zero is a *theorem* given the onset rule. Standard timing recovers **71** pre-treatment onsets at 0.8081 AUROC | Recognised as circular; Variant F added |
| **H4** Split optimism | Confirmed, +0.123 | **Not confirmed, reversed.** −0.0165 [−0.037, +0.004] | Fit repair |
| **H5** Metric divergence | Confirmed, +0.170 | **Not confirmed.** +0.0630 [−0.022, +0.156]; direction established, magnitude not | eICU label bug fixed |
| **H6** Model-class null | **Rejected** (0.135) | **Not rejected — non-inferiority established.** −0.0129 [−0.027, +0.002]. The upper limit is inside the 0.02 margin, so the boosted trees are not better by more than it; the lower limit is not, so this is *not* two-sided equivalence. *Now the strongest positive result* | Fit repair; wording corrected in round 10 |
| φ_anchor | 2.40 [2.06–2.89] — "Sepsis-3 is harder than either limb" | **1.041 [0.990, 1.097]** — interval includes 1; claim withdrawn | Fit repair |

**All four testable hypotheses are non-confirmations.** The thesis is built around
that as a result, not repaired around it.

---

## 2. Fourteen defects found and fixed

Grouped by what they invalidated. Each was found while addressing a feedback
point, not by the point itself.

| # | Defect | Consequence |
|---|---|---|
| 1 | Predictors selected by `intersect()`; column named `heart_rate`, feature list asked for `hr` | **Heart rate was absent from every fitted model.** NEWS2's HR component constant 0; SIRS capped at 3/4 |
| 2 | No physiological plausibility filter existed (documentation claimed one) | HR to 5,113,280; MAP −9,806 to 8,999,090 — infinite-leverage rows in training |
| 3 | Unpenalised multinomial likelihood completely separated | Variant B's fit arbitrary; `convergence = 0` reported regardless. **AUROC 0.607 → 0.7590** once penalised |
| 4 | `sandwich::vcovHC()` undefined for `multinom`; call failed silently | Cluster-robust SEs claimed but never computed |
| 5 | Utility Score normalised against one reference strategy, not two | A model issuing no alerts scored **−1.000** instead of 0 |
| 6 | Utility reward paid as `1 − lead/6` | Alerting *at* onset scored best in a timeliness metric |
| 7 | eICU: one label built from Variant B, reused across all three variants | Three "variants" were one label wearing three names |
| 8 | eICU: inner-joined antibiotics and cultures while docs said antibiotics alone | Documentation and implementation disagreed for the whole project |
| 9 | eICU: negative culture offsets → whole stays silently deleted | Denominator shrank invisibly |
| 10 | eICU: only `medication.csv` read, not `infusionDrug.csv` | Vancomycin, pip-tazo, all vasopressors missed |
| 11 | eICU: absolute `SOFA ≥ 2` instead of MIMIC's delta-vs-baseline | Rejected on *missingness*, in the sparser database |
| 12 | `avpu_alert`: unmeasured GCS → `FALSE` → charged 3 NEWS2 points | Every external person-hour carried a spurious +3 |
| 13 | eICU GBT booster returned empty `feature_names` | GBT comparator silently absent from external results for the whole project |
| 14 | Chapter 4 claimed cluster-robust SEs; Chapter 3 correctly denied them | Two chapters contradicted each other |

**Pattern worth noting:** items 7, 8 and 14 are all *documentation contradicting
code*, and all three ran in the direction that flattered the study. The pipeline
now fails loudly rather than silently — `require_features()` errors on an absent
predictor, and three run-time invariants halt the run rather than warn.

---

## 3. What changed in code and methodology

Seven pre-registration amendments, all disclosed as post-hoc.

| Amendment | What was built | Why |
|---|---|---|
| **1** Inference layer | New stage `12_inference.Rmd`: stay-level cluster bootstrap (B = 2,000), Holm–Bonferroni (m = 6), Benjamini–Hochberg on three exploratory families, machine-generated analysis register | Point estimates alone could not support the claims being made |
| **2** Label limbs | Variants **D** (physiology only, no treatment timestamp) and **E** (suspicion anchor only) | Sepsis-3 is a conjunction; splitting it separates definitional from empirical label variance |
| **3** Model identification | Plausibility filter (19 variables), `hr` naming fix, ridge penalty (λ = 1e−4), fit guards | Defects 1–3 above |
| **4** Standard onset timing | Variant **F** — Variant B's membership exactly, onset re-timed to `min(t_susp, t_SOFA)` | Isolates *timing* from *membership*; supplies the empirical counterpart to H3 |
| **5** Feature ablation | Refit without the 8 action-derived covariates (vasopressors + 6 order flags) | Makes "the label is constituted by clinician action" falsifiable |
| **6** Subgroup interpretability floor | 100-event floor for *interpreting* a subgroup AUROC; family E1 falls from 30 contrasts to 6 | 5 events is enough to compute an AUROC and not enough to read one |
| **7** H2 uncertainty diagnostic | Cluster-robust SEs on the primary model's coefficients; each H2-flagged covariate's cross-label movement referred to its own pooled SE | A threshold rule on point estimates cannot tell a coefficient that moved from one never estimated precisely enough for a doubling to mean anything |

**Also built:** new stage `11_clinical_metrics.Rmd` (calibration curves, decision
curves, PPV/NNE, false alarms per patient-day, lead time, per-patient
detection); a complete rewrite of stage `08` (per-variant external labels, two
anchor arms, variant-invariance guard); a 60-point Utility Score threshold
sweep; Riley's sample-size criterion re-parameterised on the **stay** rather than
the person-hour; a 100-event interpretability floor for subgroup discrimination.

**Reproducibility.** `thesis_constants.R` now writes every number in the thesis
from the result tables as a LaTeX macro. **No result value in the document is
typed by hand**, and a quantity the pipeline did not produce typesets as a
visible marker rather than a stale number. Nine miscited references were
corrected — including one paper that does not exist — and every DOI in the
bibliography now resolves.

---

## 4. What changed in the results

| Quantity | Was | Now |
|---|---|---|
| Primary AUROC (Variant B, temporal test) | 0.607 | **0.7590** |
| Calibration slope (Variant B) | 0.209 (degenerate) | **1.055** |
| Coefficient instability (H2) | 10/20 sign reversals | **6/22 unstable, 2 by sign**; of the 6, only **3** exceed their own cluster-robust SE, and all 3 are order indicators (Amendment 7) |
| Utility Score, primary model | −1.000 at cut-off | **0.000** at cut-off; ceiling **+0.025**; best overall **+0.039** (GBT) |
| Alert burden at that ceiling | — | **44 false alerts per true alert** (29–49 across variants; benchmark: 1.4) |
| eICU events (A/B/C) | 63 / 63 / 63 | **27 / 29 / 73** |
| eICU AUROC (Variant B) | 0.7623 | **0.6960** |
| eICU event rate vs MIMIC | ratio ≈ 0.004 | **0.094** (strict) / **0.425** (relaxed) |
| Sample size adequacy | min-N vs 2.3 M person-hours | min-N **1,437 stays** vs **52,946** available (**36.8×**) |
| Subgroup contrast family E1 | 30 contrasts, 1 survivor | **6 contrasts, 0 survivors** |
| Feature ablation | not performed | ΔAUROC **−0.0076**; instability **6/22 → 1/14** |

**Three results that survived unchanged** and now carry the argument:
κ(A,B) = 0.267 between the two narrowest label readings despite near-identical
prevalence; κ(D,B) = 0.057 for a treatment-independent label; and the 65,078-stay
cohort with all three variants on identical patients.

---

## 5. The analogy

**Predicting sepsis from Sepsis-3 labels is like predicting building fires when
your only record of a fire is *the moment someone pulled the alarm*.**

| In the analogy | In the study |
|---|---|
| The alarm-pull timestamp is your ground truth | Sepsis onset = when a culture was drawn *and* an antibiotic ordered |
| **No fire can be detected before the alarm** — not because fires don't smoulder, but because your definition of "fire" *is* the alarm | H3's zero pre-treatment onsets is a **theorem**, not a discovery |
| Different buildings have different alarm policies — some pull at first smell, some wait for flames | Label variants A/B/C: different antibiotic–culture windows |
| Two policies with similar *fire counts* still flag largely **different fires** | κ(A,B) = 0.267 at near-identical prevalence |
| Install independent smoke detectors — they *do* fire before the alarms, 1,362 times | Variant D (physiology only, no treatment timestamp) |
| Keep the alarm definition but timestamp it when smoke was first detected rather than when the handle was pulled | Variant F: 71 pre-treatment onsets at 0.8081 AUROC |
| A better camera barely helps once you have any decent camera; a *smoke detector* vs a *camera* is the real difference | H6: hazard model ≈ gradient-boosted trees; both ≫ bedside scores |
| Whichever policy you use, the system cries wolf ~44 times per real fire | The utility ceiling: no deployable operating point exists |
| Buildings with poor record-keeping have the least reliable alarm records | The only significant equity strata are the two *missingness* categories |

**The conclusion the analogy makes obvious:** you cannot fix this with a better
camera. The problem is that the fire was defined by the alarm. That is why the
thesis's central finding is about the label rather than the model — and why four
failed hypotheses are the finding rather than a failure.

---

## 6. Where the thesis is still exposed

Stated so it is not discovered at viva.

1. **External validation is bounded by label transport, not cohort size.** eICU
   documents microbiology for 1.55 % of stays, so only 29 events are observable
   under the primary label — below the 100-event interpretability floor. The
   study establishes that discrimination *degrades* and explicitly declines to
   say by how much.
2. **The subgroup analysis cannot speak about race.** Only two racial strata
   clear the event floor, and one of them is "Unknown". The study contains no
   sufficiently powered comparison between two strata that both record an actual
   demographic answer — an absence of measurement, not a null result.
3. **All seven amendments are post-hoc**, disclosed as such. Amendment 1
   overturned the study's most attractive finding, which is the strongest
   available argument that the disclosure is honest. Two need their own defence
   and get it in the pre-registration: Amendment 6 *reduces* an exploratory
   family, which the inference plan's own rule prohibits (§20.4 gives four
   reasons it is admissible, the decisive one being that the reduction removed
   the family's only surviving discovery rather than creating one); and
   Amendment 7 returns a result favourable to the thesis, so §21.4 records in
   advance that it is not a test and not independent corroboration of
   Amendment 5.
4. **The literature review is narrative, not systematic** — no de-duplicated
   screening pass, no second reviewer. Novelty claims are hedged and bounded.
5. **Variant D is unvalidated and partly self-fulfilling** (5 of 6 SOFA
   components are model inputs). Only its *disagreement* with Sepsis-3 carries
   weight, never its AUROC level.
6. **No deep survival comparator**, so H6's non-inferiority holds against
   gradient-boosted trees, not against every flexible estimator. It is also
   one-sided: the boosted trees are excluded from outperforming the hazard
   model, but the two have not been shown to be interchangeable.
7. **H5 is tested on a substituted estimand.** The pre-registered contrast
   compares proportional declines and cannot be formed against an internal
   Utility Score of 0.025, so the AUROC limb alone occupies H5's slot. Declared
   in §13.6 of the pre-registration and flagged wherever H5's verdict is
   reported.

---

## 7. Current state

Pipeline: 12 stages, 12/12 succeeding, seed-fixed, ~60 min end to end.
Thesis: 162 pages, 0 errors, 0 undefined references, 0 undefined citations,
1,337 generated constants.
Code: Apache-2.0, no patient data, 70 tracked files —
`https://github.com/ahadarif007/RESEARCH`. **The repository must be made public
(or shared with the panel) before submission**: two sentences in the thesis
assert that it is.

Outstanding: read and amend the Declaration (blocking); make the repository
public; record the screencast; rebuild the presentation in October against the
generated constants. The decks were **untracked in round 10** — they predate
these results and invert the H6 verdict, and an examiner following the
repository URL in the thesis would have found them.
