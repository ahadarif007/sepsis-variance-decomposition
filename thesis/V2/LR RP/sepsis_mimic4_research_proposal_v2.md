# Model, Label, or Analyst? A Variance Decomposition of Real-Time Sepsis Onset Prediction on MIMIC-IV

### Revised MSc Research Proposal (Version 2.0)

**Supersedes:** *Time-Varying Statistical Modeling for Real-Time Sepsis Onset Prediction: A Survival Analysis Approach Using MIMIC-IV* (Version 1.0)
**Basis for revision:** *Statistical and Machine-Learning Approaches to Real-Time Sepsis Onset Prediction on MIMIC-IV: An Extended Critical Literature Review* (50 sources)
**Date:** 13 July 2026
**Citation style:** APA (7th ed.)

---

## Abstract

Version 1.0 of this proposal sought to develop a time-varying Cox proportional-hazards model for real-time sepsis onset prediction on MIMIC-IV, to test the proportional-hazards assumption, to benchmark against SIRS, qSOFA, and NEWS, and to validate externally on eICU-CRD. The extended literature review conducted since that proposal was written establishes that this design, though internally coherent, rests on four premises that the evidence does not support.

First, the design is **not novel**: Fagerström, Bång, Wilhelms, and Chew (2019) fitted a Cox proportional-hazards model for septic-shock onset on MIMIC-III using Henry et al.'s (2015) exact feature set and target definition, and an LSTM detected onset up to twenty hours earlier at comparable sensitivity and specificity. Ninety-one real-time sepsis prediction models already exist (Wang et al., 2025).

Second, the design's **interpretability premise is conditional on a stable label, and the label is not stable**. Cohen et al. (2024) show that on MIMIC-III the identified sepsis cohort ranges from 867 to 2,178 admissions depending solely on how Sepsis-3 onset is operationalised, and that predictive performance is more sensitive to that reading than to the choice of model. Dutta et al. (2026) reproduce this prospectively across 198,494 encounters. Lauritsen et al. (2021) show that problem framing can reverse the *sign* of an estimated covariate effect. Kamran et al. (2024) show that the Sepsis-3 label is partly constituted by clinician actions, so that models predicting it partly learn to predict clinician suspicion.

Third, the design's **validation architecture is optimistically biased**: Guo et al. (2022) find that among four prediction tasks benchmarked on MIMIC-IV, sepsis is the *worst* degraded by temporal dataset shift, and that no domain-generalisation method repairs it. A random train/test split therefore overstates performance for this outcome specifically.

Fourth, the design's **evaluation metrics cannot detect the characteristic failure mode**. Wang et al. (2025) report that across ninety-one models, median AUROC falls only from 0.811 to 0.783 from internal to external validation — not a statistically significant difference — while the median clinical Utility Score collapses from +0.381 to **−0.164**, that is, from useful to worse than issuing no alert. Discrimination does not merely fail to reveal the collapse; it conceals it.

This revision inverts the design accordingly. The label, the validation split, and the evaluation metric are promoted from nuisance parameters to **objects of study**, and the contribution becomes a variance decomposition: *how much of the apparent performance and inferential content of a real-time sepsis model is attributable to the model, and how much to the analyst's discretionary choices?* The primary model is changed from a static or time-varying Cox model to a **dynamic discrete-time competing-risks hazard model** (a multinomial pooled logistic regression over person-hour records), which D'Agostino et al. (1990) prove to be asymptotically equivalent to time-dependent-covariate Cox regression for short intervals and small per-interval event probabilities — precisely the hourly, low-prevalence regime of ICU sepsis. This is therefore not an abandonment of the survival framework but its implementation in the form the data actually takes. It requires no proportional-hazards assumption, accommodates the informative competing risk of discharge (Resche-Rigon et al., 2006), answers Schoenfeld's (2006) objection to survival methods in ICU outcome studies by construction, and emits exactly the hourly risk score that the PhysioNet Utility Score consumes. A validated architectural precedent exists: Heyard, Timsit, Essaied, Held, and the COMBACTE-MAGNET Consortium (2019) built dynamic discrete-time competing-risks prediction models on daily ICU records, and Heyard, Timsit, Held, and the COMBACTE-MAGNET Consortium (2020) supply the corresponding discrimination, calibration, and prediction-error estimators.

The revised study is *less* computationally demanding than Version 1.0, carries *lower* delivery risk, and — critically — **produces a publishable result whichever way the findings fall**, because its contribution does not depend on the model achieving a performance target. Three components of Version 1.0 are removed as category errors (propensity-score matching, inverse-probability weighting, and E-value analysis are causal-inference instruments with no role in a prediction study; group-based trajectory modelling produces no real-time score). Two of Version 1.0's largest risks are substantially eliminated by the `ricu` package (Bennett, Plečko, Ukor, Meinshausen, & Bühlmann, 2023), which supplies a peer-reviewed MIMIC-IV/eICU harmonisation layer and demo datasets requiring no credentialed access. The plan remains deliverable within a 22-week MSc timeline.

**Keywords:** sepsis; MIMIC-IV; discrete-time survival analysis; competing risks; label definition; temporal dataset shift; clinical utility; variance decomposition; TRIPOD+AI

---

## 1. Introduction: Why Version 1.0 Requires Revision

### 1.1 What Version 1.0 got right

Version 1.0 correctly identified that the MIMIC-IV statistical literature is dominated by post-diagnosis prognostic modelling rather than pre-onset detection; that the proportional-hazards assumption is not reported as tested in that literature despite Kasal et al.'s (2004) demonstration that it frequently fails in sepsis cohorts; and that external validation is scarce precisely where it matters most. A currency scan of the 2025–2026 MIMIC-IV literature conducted for the extended review confirms the first of these claims: every located study published in that window predicts an outcome *after* sepsis has been diagnosed. The diagnosis was sound.

Version 1.0 was also right to insist on interpretability, on assumption-testing, and on external validation as non-negotiable design commitments. Those commitments are retained here in full. What changes is the *object* to which they are applied.

### 1.2 What Version 1.0 got wrong

The proposal's prescription does not follow from its diagnosis. Its central move — build a time-varying Cox model for sepsis onset on MIMIC-IV, and benchmark it against rule-based scores — encounters four independent difficulties, each documented in the extended review and each sufficient on its own to compromise the contribution.

**(i) The gap is narrower than claimed.** Version 1.0 asserts that statistical onset modelling "has not been substantially revisited on MIMIC-IV specifically" since Henry et al.'s (2015) work on MIMIC-II. Fagerström et al. (2019) fitted a Cox proportional-hazards model on MIMIC-III, using Henry et al.'s exact input variables and exact septic-shock target, as a head-to-head baseline — and an LSTM beat it by up to twenty hours of lead time. The gap that remains is not "nobody has fitted this model" but "nobody has fitted a properly specified, label-sensitivity-analysed, temporally validated survival model for onset on MIMIC-IV." That is still a real gap. It is simply a more demanding one, and it is not closed by fitting the model Fagerström et al. already fitted and lost with.

**(ii) The benchmark is weak.** Version 1.0's Objective O4 proposes to benchmark against SIRS, qSOFA, and NEWS. But the Surviving Sepsis Campaign guidelines (Evans et al., 2021) issue a **strong recommendation against using qSOFA as a sole screening tool**, on grounds of poor sensitivity. Demonstrating superiority over an instrument that the governing clinical guideline has already told practitioners not to use for screening is not a persuasive result. Furthermore, Mellhammar et al. (2020) already constructed a LASSO-derived statistical score and **failed to beat NEWS2** — a direct precedent for Version 1.0's plan that Version 1.0 cites without registering its implication.

**(iii) The validation design is optimistically biased for this outcome specifically.** Version 1.0 proposes internal validation via a train/test split within MIMIC-IV. Guo et al. (2022) partitioned MIMIC-IV by admission-year group and evaluated four prediction tasks — mortality, long length of stay, sepsis, and invasive ventilation — under temporal shift. Sepsis was the **worst-affected task**, and domain-generalisation and domain-adaptation algorithms failed to outperform plain empirical risk minimisation. A random split on MIMIC-IV therefore inflates apparent performance more for sepsis than for any neighbouring outcome a reader might use to calibrate their scepticism.

**(iv) The evaluation metrics cannot see the failure.** Version 1.0's Objective O4 nominates AUC-ROC, sensitivity, specificity, and lead time. Wang et al. (2025), reviewing ninety-one real-time sepsis prediction models, report that these are precisely the quantities that survive the internal-to-external transition while clinical value inverts: median AUROC 0.811 → 0.783 (not statistically significant), median Utility Score **+0.381 → −0.164**. A study reporting Version 1.0's metric set and concluding that its model generalises would have failed to measure the thing that fails. The same pattern appears in deployment: Wong et al. (2026) report AUROC between 0.82 and 0.92 for the Epic Sepsis Model version 2 across 227,091 encounters, *alongside* low positive predictive value and high alert burden.

### 1.3 The core inversion

Version 1.0 treats the label, the split, and the metric as **nuisance parameters** — matters of convention to be fixed so that the model can be evaluated. The literature says the opposite. Cohen et al. (2024) show that the label moves performance at least as much as the model does. Guo et al. (2022) show that the split determines whether the performance estimate is honest. Wang et al. (2025) show that the metric determines whether a collapse is visible at all.

**The variance lives in the analyst's choices, not in the model.** That inversion is the contribution of Version 2.0. It converts the project from a ninety-second entrant into a crowded field — where the ninety-first entrant's rank on a leaderboard carries, per Reyna et al. (2020), a Spearman correlation of approximately −0.03 to 0.01 with its performance at an unseen hospital — into a methodological study that the field measurably needs and that has not been performed for a survival model on MIMIC-IV.

### 1.4 What is unchanged

The database (MIMIC-IV), the external cohort (eICU-CRD), the clinical target (Sepsis-3 onset in adult ICU patients), the commitment to interpretable statistical modelling, the non-interventional design, the open-source release, and the 22-week MSc timeline are all retained. Machine learning is no longer deferred wholesale to "future work" — a gradient-boosted comparator is now **required**, because Cohen et al. (2024) establish that cross-paper comparison under differing labels is uninterpretable, so the only informative comparison is one the student runs themselves under identical conditions. This is not a scope expansion; it is a scope *correction*, and the marginal cost is small.
---

## 2. Summary by Source: The Evidential Warrant for Each Design Decision

Every design decision in Section 5 is traceable to a specific source. This section states the mapping. It is organised by *design component*, and within each, by the source that constrains it.

### 2.1 Sources governing the estimand and the label

**Singer, M., Deutschman, C. S., Seymour, C. W., et al. (2016).** *The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3).* JAMA, 315(8), 801–810.
Fixes the clinical target: life-threatening organ dysfunction from a dysregulated host response to infection, operationalised as an acute rise of ≥2 SOFA points in a patient with suspected infection. Note what this definition contains: a *composite of two clocks*, one of which (suspicion of infection) is inferred from clinician behaviour.
→ **Design consequence:** the estimand must be stated as a rule for reading both clocks, not merely as "sepsis."

**Johnson, A. E. W., Aboab, J., Raffa, J. D., Pollard, T. J., Deliberato, R. O., Celi, L. A., & Stone, D. J. (2018).** *A comparative analysis of sepsis identification methods in an electronic database.* Critical Care Medicine, 46(4), 494–499.
Five retrospective sepsis identification algorithms, applied to 11,791 qualifying ICU admissions drawn from 23,620, agreed only acceptably: Cronbach's alpha 0.40–0.62.
→ **Design consequence:** "the MIMIC sepsis cohort" is not one object. The extraction must be **parameterised by identification rule**, not hard-coded to one.

**Cohen, S. N., Foster, J., Foster, P., Lou, H., Lyons, T., Morley, S., Morrill, J., Ni, H., Palmer, E., Wang, B., Wu, Y., Yang, L., & Yang, W. (2024).** *Subtle variation in sepsis-III definitions markedly influences predictive performance within and across methods.* Scientific Reports, 14(1), 1920.
Holding MIMIC-III fixed and varying only the reading of Sepsis-3 onset across three defensible interpretations, the identified cohort ranged from **867 to 2,178 admissions**. Across tree-based, deep-learning, and survival-analysis models: holding the definition fixed, the best method gained 1–5% AUROC; holding the method fixed and varying the definition swung performance by 0–6% AUROC.
→ **Design consequence:** this is the single most load-bearing source in the proposal. It mandates **≥3 pre-specified label variants**, and it mandates that cross-label variance be reported as a **primary result**, not a sensitivity analysis. It is also the source of hypotheses H1 and H2.

**Dutta, S., McMurry, R., Tasi, M. C., et al. (2026).** *Performance of a sepsis prediction model across different sepsis definitions.* JAMA Network Open, 9(4), e265599.
A locally trained gradient-boosted model, predicting every fifteen minutes across nine acute-care hospitals, evaluated on 198,494 encounters against Sepsis-3, SEP-1, and the CDC Adult Sepsis Event definitions. Performance varied substantially by definition; expected calibration error differed (0.05 Sepsis-3, 0.06 Adult Sepsis Event, 0.07 SEP-1); decision-curve net benefit differed.
→ **Design consequence:** the label-sensitivity finding is **not a MIMIC artefact, not a small-sample artefact, and not a research-model artefact**. It reproduces prospectively, at n ≈ 200,000, with a commercial model. It is a property of the problem. This retires any objection that the label analysis is over-engineered.

**Lauritsen, S. M., Thiesson, B., Jørgensen, M. J., Riis, A. H., Espelund, U. S., Weile, J. B., & Lange, J. (2021).** *The framing of machine learning risk prediction models illustrated by evaluation of sepsis in general wards.* npj Digital Medicine, 4(1), 158.
Formalises *framing* — observation window, prediction window, window shift, event trigger — and shows that framing determines discrimination and calibration, and can produce **opposing interpretations of the same physiological variable** (their example: SpO₂). They further conclude that a model with strong discrimination *and* calibration may still be clinically unusable.
→ **Design consequence:** framing must be **pre-specified**, and coefficient stability across framings must be reported. This is the source of hypothesis H2. It is also the direct threat to Version 1.0's interpretability premise: a hazard ratio whose sign is an artefact of framing is not an interpretable quantity.

**Kamran, F., Tjandra, D., Heiler, A., Virzi, J., Singh, K., King, J. E., Valley, T. S., & Wiens, J. (2024).** *Evaluation of sepsis prediction models before onset of treatment.* NEJM AI, 1(3).
Clinicians frequently recognise and begin treating sepsis *before* the formal Sepsis-3 criteria are met. Because the criteria are partly defined by clinician actions (blood culture, antibiotic administration), a model trained to predict the moment the criteria are met partly learns to predict *when the clinician will act*. Re-evaluating performance restricted to alerts arriving before clinical action showed that apparent accuracy is substantially inflated without that restriction; the model had learned to encode clinician suspicion rather than independent physiological signal.
→ **Design consequence:** evaluation must be **treatment-anchored** — restricted to predictions issued before the first culture order or antibiotic administration — and lead time must be measured against *clinical recognition*, not against the label. This is the source of hypothesis H3, and it is the deepest threat to any causal reading of the fitted coefficients.

### 2.2 Sources governing the model class

**D'Agostino, R. B., Lee, M.-L., Belanger, A. J., Cupples, L. A., Anderson, K., & Kannel, W. B. (1990).** *Relation of pooled logistic regression to time dependent Cox regression analysis: The Framingham Heart Study.* Statistics in Medicine, 9(12), 1501–1515.
Observations over multiple intervals are pooled and a logistic regression relates risk factors to event occurrence. The authors prove — with the formal proof and necessary conditions given in their appendix, and with numerical examples across a range of sample sizes and event proportions — that this **pooled logistic regression is close to time-dependent-covariate Cox regression**.
→ **Design consequence:** this is the source that licenses the change of model class *without abandoning the survival framework*. The equivalence holds for short intervals and small per-interval event probabilities. Hourly ICU bins with a low per-hour probability of sepsis onset is exactly that regime. **The proposed model is the Cox model, in the form the data actually takes.** This point should be made explicitly to the examiner, because it pre-empts the natural objection that the student has abandoned Version 1.0's methodological commitment.

**Ngwa, J. S., Cabral, H. J., Cheng, D. M., Pencina, M. J., Gagnon, D. R., LaValley, M. P., & Cupples, L. A. (2016).** *A comparison of time dependent Cox regression, pooled logistic regression and cross sectional pooling with simulations and an application to the Framingham Heart Study.* BMC Medical Research Methodology, 16(1), 148.
Simulation comparison of the three approaches, concluding that models which explicitly account for the times at which time-dependent covariates are measured yield more reliable estimates than unadjusted analyses.
→ **Design consequence:** the measurement times must be modelled, not ignored. This motivates the inclusion of informative-missingness indicators and the explicit baseline-hazard term.

**Heyard, R., Timsit, J.-F., Essaied, W., Held, L., & COMBACTE-MAGNET Consortium. (2019).** *Dynamic clinical prediction models for discrete time-to-event data with competing risks — a case study on the OUTCOMEREA database.* Biometrical Journal, 61(3), 514–534.
**The architectural precedent.** Dynamic (landmarked) prediction models for discrete time-to-event data with competing risks, built on daily ICU records, predicting ventilator-associated pneumonia attributable to *Pseudomonas aeruginosa*, with competing events of extubation, death, and VAP from other organisms. Cause-specific variable selection accounts for variables that affect the target only indirectly, through a competing event.
→ **Design consequence:** the proposed architecture is not novel machinery invented for this project; it is a **published, peer-reviewed ICU prediction architecture** transposed to a new outcome (sepsis), a new database (MIMIC-IV), and a finer time grid (hourly rather than daily). This materially reduces methodological risk and is a strong answer to any charge of over-ambition.

**Heyard, R., Timsit, J.-F., Held, L., & COMBACTE-MAGNET Consortium. (2020).** *Validation of discrete time-to-event prediction models in the presence of competing risks.* Biometrical Journal, 62(3), 643–657.
Supplies the missing validation methodology for exactly this model class: estimators for **cause-specific discrete time-dependent AUC**, a **discrete-time concordance index** (with a method for linearly combining cause-specific indices into a global measure), **cause-specific calibration** (assessed via a multinomial logistic recalibration model and a likelihood-ratio test), and **cause-specific prediction error**.
→ **Design consequence:** the evaluation suite for the primary model is not something the student must invent. It exists, it is published, and it is ICU-validated.

**Tutz, G., & Schmid, M. (2016).** *Modeling discrete time-to-event data.* Springer.
**Schmid, M., & Berger, M. (2021).** *Competing risks analysis for discrete time-to-event data.* WIREs Computational Statistics, 13, e1529.
The textbook and the review. Schmid and Berger set out the discrete cause-specific hazards model and the discrete subdistribution hazard model, nonparametric estimation, and model validation. The multinomial-logit specification of the discrete-time cause-specific hazard (with conditional survival as the reference category) is given in Tutz and Schmid, Chapter 8.
→ **Design consequence:** the model specification in §5.5 follows these directly.

**Kasal, J., Jovanovic, Z., Clermont, G., et al. (2004).** *Comparison of Cox and Gray's survival models in severe sepsis.* Critical Care Medicine.
Hazards for death after sepsis are frequently **non-proportional**.
→ **Design consequence:** Version 1.0 proposed to *test* proportional hazards and fall back if it failed. Version 2.0 **dissolves the assumption**: a discrete-time model with a spline baseline hazard and optional time-varying coefficients imposes no proportionality. The static Cox model is retained *only* as a deliberately weak comparator, to quantify what the field's default choice costs.

**Resche-Rigon, M., Azoulay, E., & Chevret, S. (2006).** *Evaluating mortality in intensive care units: contribution of competing risks analyses.* Critical Care, 10(1), R5.
**Fine, J. P., & Gray, R. J. (1999).** *A proportional hazards model for the subdistribution of a competing risk.* Journal of the American Statistical Association, 94(446), 496–509.
**Schoenfeld, D. (2006).** *Survival methods, including those using competing risk analysis, are not appropriate for intensive care unit outcome studies.* Critical Care, 10(1), 103.
In ICU cohorts, discharge alive is an **informative competing event**: the independent-censoring assumption underlying Kaplan–Meier estimation is violated (Resche-Rigon et al.). The standard remedy is the Fine–Gray subdistribution hazard model. But Schoenfeld disputes the entire enterprise, arguing that survival methods — explicitly including competing-risks methods — are inappropriate for ICU outcome studies, and that logistic regression is preferable.
→ **Design consequence:** Version 1.0 does not engage this dispute at all. Version 2.0 must, and the discrete-time formulation is the resolution: it is a **cause-specific competing-risks model** (satisfying Resche-Rigon et al.) that is *also* **a logistic regression** (satisfying Schoenfeld), while retaining the time-to-event structure Schoenfeld would discard. The dispute is answered by construction rather than by choosing a side.

**van Houwelingen, H. C. (2007).** *Dynamic prediction by landmarking in event history analysis.* Scandinavian Journal of Statistics, 34(1), 70–85.
**van Houwelingen, H., & Putter, H. (2011).** *Dynamic prediction in clinical survival analysis.* Chapman & Hall/CRC.
The landmarking approach, and the caution — the landmark model does not in general satisfy the proportional-hazards assumption.
→ **Design consequence:** landmarking is *not* an escape from Version 1.0's proportional-hazards problem; it is a different model with its own approximation error. The discrete-time formulation is preferred, with landmarking retained as the mechanism for allowing coefficients to vary with time-in-ICU.

**Christodoulou, E., Ma, J., Collins, G. S., Steyerberg, E. W., Verbakel, J. Y., & Van Calster, B. (2019).** *A systematic review shows no performance benefit of machine learning over logistic regression for clinical prediction models.* Journal of Clinical Epidemiology, 110, 12–22.
Across 71 studies drawn from 927 screened, no performance benefit of machine learning over logistic regression; potential bias in the validation procedures of 68% of studies.
→ **Design consequence:** this is the strongest available *warrant* for retaining an interpretable regression as the primary model — a warrant Version 1.0 asserts but does not cite. It is also the source of hypothesis H6. Its boundary must be stated honestly: Christodoulou et al. examined *binary outcomes on tabular data*, and Fagerström et al. (2019) show that on the *temporal lead-time* axis the deep model won substantially. The defensible claim is narrower than "statistics matches ML," and the study is designed to test where the boundary actually falls.

### 2.3 Sources governing the validation architecture

**Guo, L. L., Pfohl, S. R., Fries, J., Johnson, A. E. W., Posada, J., Aftandilian, C., Shah, N., & Sung, L. (2022).** *Evaluation of domain generalization and adaptation on improving model robustness to temporal dataset shift in clinical medicine.* Scientific Reports, 12(1), 2726.
MIMIC-IV patients partitioned by admission-year group (2008–2010, 2011–2013, 2014–2016, 2017–2019); four tasks evaluated (mortality, long length of stay, **sepsis**, invasive ventilation). Impact of temporal shift was heterogeneous, and **worst for sepsis**. Domain-generalisation and unsupervised domain-adaptation methods failed to outperform empirical risk minimisation.
→ **Design consequence:** the **temporal split is primary**; the random split is reported alongside solely to quantify the optimism. This single change is the highest-value, lowest-cost correction in the entire revision — it costs one filter on `anchor_year_group` and it removes a bias that Version 1.0 would have carried into every reported number. It is the source of hypothesis H4. It also supplies the **fallback external-validation strategy** (§6.4, R2): if eICU harmonisation fails, a within-MIMIC-IV temporal external validation is an *evidence-backed* substitute, not a consolation prize, precisely because Guo et al. established the magnitude of that shift for this outcome.

**Moor, M., Bennett, N., Plečko, D., Horn, M., Rieck, B., Meinshausen, N., Bühlmann, P., & Borgwardt, K. (2023).** *Predicting sepsis using deep learning across international sites: a retrospective development and validation study.* eClinicalMedicine, 62, 102124.
Across 136,478 ICU admissions in four databases (United States, Netherlands, Switzerland): internal AUC 0.846 (95% CI 0.841–0.852), external AUC **0.761** (0.746–0.770), recovering to 0.807 (0.801–0.813) with a 10% fine-tuning sample from the target site. The deployed system raised **1.4 false alerts per true alert** and detected 80% of septic patients a median of **3.7 hours** (3.0–4.3) before onset.
→ **Design consequence:** three benchmarks to pre-register. The expected external penalty is ≈ **0.085 AUC**; a *smaller* observed drop should be treated as evidence that the external data is insufficiently distant, not as evidence of an unusually robust model. The alert-burden benchmark is **1.4**. And the honest lead time of a strong modern system is **under four hours** — not the 28 hours of the original TREWScore headline, which Version 1.0 implicitly treats as the target.

**Reyna, M. A., Josef, C. S., Jeter, R., Shashikumar, S. P., Westover, M. B., Nemati, S., Clifford, G. D., & Sharma, A. (2020).** *Early prediction of sepsis from clinical data: The PhysioNet/Computing in Cardiology Challenge 2019.* Critical Care Medicine, 48(2), 210–217.
40,336 records released, 22,761 sequestered; 104 teams; 853 entries; task defined as prediction six hours before clinical recognition; scored on a purpose-built clinical **Utility Score** rewarding early prediction and penalising late predictions, missed detections, and false alarms. Utility scores were strongly rank-correlated between the two hospital systems participants had trained on (Spearman ρ = 0.949) but **essentially uncorrelated with the unseen third system (ρ = −0.033 and ρ = 0.013)**.
→ **Design consequence:** two. First, it supplies the primary evaluation metric (§5.8). Second, its rank-correlation result establishes that **selecting a modelling approach by consulting published competitor performance is uninformative out of distribution.** The only comparison that carries evidential weight is one run in-house, on the same cohort, label, split, and metric. This is why the gradient-boosted comparator is mandatory rather than optional.

**Wang, Z., Wang, W., Sun, C., Li, J., Xie, S., Xu, J., Zou, K., Jin, Y., Yan, S., Liao, X., Kang, Y., Coopersmith, C. M., & Sun, X. (2025).** *A methodological systematic review of validation and performance of sepsis real-time prediction models.* npj Digital Medicine, 8(1), 190.
Ninety-one models. Only 54.9% applied full-window validation with both metric types. Under full-window evaluation, median internal AUROC 0.811 (IQR 0.760–0.842) and median external AUROC 0.783 (IQR 0.755–0.865) — **not a statistically significant difference**. Median Utility Score, internal → external: **+0.381 → −0.164**.
→ **Design consequence:** the source of hypothesis H5, and the reason AUROC is demoted to a *descriptive* metric in §5.8. A negative Utility Score means the model does net harm relative to issuing no alerts. That AUROC barely moved across the same transition is the central methodological fact of this field.

**Pollard, T. J., Johnson, A. E. W., Raffa, J. D., Celi, L. A., Mark, R. G., & Badawi, O. (2018).** *The eICU Collaborative Research Database, a freely available multi-center database for critical care research.* Scientific Data, 5, 180178.
Over 200,000 ICU admissions across 208 United States hospitals.
→ **Design consequence:** retained from Version 1.0 as the external cohort. Correct choice, unchanged.

**Moor, M., Rieck, B., Horn, M., Jutzeler, C. R., & Borgwardt, K. (2021).** *Early prediction of sepsis in the ICU using machine learning: a systematic review.* Frontiers in Medicine, 8, 607952.
Principal finding: low comparability and reproducibility. Particular attention to **case–control matching** — specifically how the pseudo-onset time of a non-septic control is chosen, since a control aligned near discharge is trivially separable from a case aligned near onset, inflating apparent performance.
→ **Design consequence:** the **control-alignment rule must be pre-specified**. Version 1.0 proposes "matched non-septic ICU patients serve as controls" without stating the alignment rule — an unguarded exposure to precisely this trap. The person-hour design largely dissolves the problem (every patient contributes all at-risk hours; there is no case–control matching step), which is a further argument for it.

### 2.4 Sources governing the evaluation metrics

**Van Calster, B., McLernon, D. J., van Smeden, M., Wynants, L., & Steyerberg, E. W. (2019).** *Calibration: the Achilles heel of predictive analytics.* BMC Medicine, 17(1), 230.
Calibration — the agreement between predicted probability and observed event frequency — is systematically under-reported, and poorly calibrated models are actively misleading for clinical decision-making.
→ **Design consequence:** any model driving a threshold-based alert is a calibration-dependent instrument. Calibration intercept, calibration slope, and a flexible calibration curve become **primary** endpoints, not appendices.

**Vickers, A. J., & Elkin, E. B. (2006).** *Decision curve analysis: a novel method for evaluating prediction models.* Medical Decision Making, 26(6), 565–574.
Net benefit plotted against threshold probability, comparing "treat all," "treat none," and "use the model." Requires only the test dataset; no external utility elicitation.
→ **Design consequence:** supplies the net-benefit analysis. Retained from Version 1.0, now correctly positioned as a primary rather than supplementary analysis.

**Wong, A., et al. (2026).** *Multicenter prospective validation of an updated proprietary sepsis prediction model.* JAMA Network Open.
Epic Sepsis Model version 2 — a gradient-boosted tree ensemble that can be locally retrained, superseding version 1's logistic regression — across 227,091 inpatient encounters at four US health systems: AUROC **0.82–0.92**, but with high institutional variability, low PPV, and high alert burden.
→ **Design consequence:** the AUROC illusion, observed at the field's largest deployment scale. Note also the honest tension this creates with Christodoulou et al. (2019): the model class changed from logistic regression to gradient boosting and discrimination improved enormously (0.63 → 0.82–0.92). But version 2 *also* changed from globally trained to locally trainable, and Moor et al. (2023) show local fine-tuning alone recovers roughly half the external penalty. The improvement is confounded between model class and localisation, and the published evidence cannot separate them. **The proposed study can**, because it holds the label, cohort, and split fixed while varying only the model class.

**Wong, A., Otles, E., Donnelly, J. P., et al. (2021).** *External validation of a widely implemented proprietary sepsis prediction model in hospitalized patients.* JAMA Internal Medicine, 181(8), 1065–1070.
**Ostermayer, D. G., Braunheim, B., Mehta, A. M., Ward, J., Andrabi, S., & Sirajuddin, A. M. (2024).** *External validation of the Epic sepsis predictive model in 2 county emergency departments.* JAMIA Open, 7(4), ooae133.
Epic Sepsis Model version 1: AUC 0.63, sensitivity 33%, PPV 12% (Wong et al.); sensitivity 14.7%, PPV 7.6% in two county emergency departments (Ostermayer et al.).
→ **Design consequence:** deployed performance sits *outside the distribution* of published research AUROCs. This is a publication-bias signature, and it justifies pre-registering the expected external degradation rather than discovering it.

### 2.5 Sources governing the comparators

**Evans, L., Rhodes, A., Alhazzani, W., et al. (2021).** *Surviving Sepsis Campaign: International guidelines for management of sepsis and septic shock 2021.* Critical Care Medicine, 49(11), e1063–e1143.
Strong recommendation **against qSOFA as a sole screening tool**.
→ **Design consequence:** **NEWS2 replaces qSOFA as the headline rule-based comparator.** qSOFA and SIRS are retained only as descriptive reference points, since the literature reports them, not as the bar to be cleared.

**Mellhammar, L., Linder, A., Tverring, J., et al. (2020).** *Scores for sepsis detection and risk stratification — construction of a novel score using a statistical approach and validation of RETTS.* PLoS ONE, 15(2), e0229210.
A LASSO-derived statistical score (SHEWS) that **failed to outperform NEWS2**.
→ **Design consequence:** a direct precedent for Version 1.0's plan, and a negative one. Beating NEWS2 is *not* assumed to be achievable, and the study is not designed such that failing to beat it constitutes failure.

**Fagerström, J., Bång, M., Wilhelms, D., & Chew, M. S. (2019).** *LiSep LSTM: A machine learning algorithm for early detection of septic shock.* Scientific Reports, 9, 15132.
An LSTM trained on MIMIC-III with Henry et al.'s (2015) exact features and target, against a **Cox proportional-hazards model fitted on the same data**; the LSTM detected septic shock up to **twenty hours earlier** at comparable sensitivity and specificity.
→ **Design consequence:** this sets the performance bar and supplies the benchmark for hypothesis H6. It is also one of the very few internally valid statistics-versus-machine-learning comparisons in this literature, precisely because it was run under a *single fixed label*.

**Nemati, S., Holder, A., Razmi, F., Stanley, M. D., Clifford, G. D., & Buchman, T. G. (2018).** *An interpretable machine learning model for accurate prediction of sepsis in the ICU.* Critical Care Medicine, 46(4), 547–553.
The Artificial Intelligence Sepsis Expert: AUROC 0.83–0.85 for prediction 4–12 hours ahead; developed on ~31,000 Emory admissions, validated on >52,000 MIMIC-III patients.
→ **Design consequence:** supplies the performance reference range. Note that AISE is itself a **modified Weibull–Cox** formulation — the leading "machine-learning" sepsis model of its generation has a survival-analytic backbone, which further dissolves the statistics-versus-ML dichotomy Version 1.0 relies on.

### 2.6 Sources governing the equity analysis

**Wang, H., Li, Y., Naidech, A., & Luo, Y. (2022).** *Comparison between machine learning methods for mortality prediction for sepsis patients with different social determinants.* BMC Medical Informatics and Decision Making, 22(Suppl 2), 156.
Among 11,791 MIMIC-III critical-care patients (5,783 meeting Sepsis-3): the competing sepsis identification criteria selected **systematically different sub-populations** by race, marital status, insurance type, and language; and prediction performance degraded significantly for Asian, Hispanic, and Spanish-speaking patients.
→ **Design consequence:** the conjunction is what matters. The label is demographically non-neutral *and* performance is inequitable **for the same subgroups**. Subgroup analysis is therefore not a robustness garnish; it is a **validity requirement**, and it is entangled with the label analysis. The study must report **subgroup label-sensitivity** as well as subgroup performance — a combination that, to this author's knowledge, has not been reported for any sepsis model.

### 2.7 Sources governing sample size, reporting, and tooling

**Riley, R. D., Snell, K. I. E., Ensor, J., Burke, D. L., Harrell, F. E., Jr., Moons, K. G. M., & Collins, G. S. (2019).** *Minimum sample size for developing a multivariable prediction model: PART II — binary and time-to-event outcomes.* Statistics in Medicine, 38(7), 1276–1296.
**Riley, R. D., Ensor, J., Snell, K. I. E., et al. (2020).** *Calculating the sample size required for developing a clinical prediction model.* BMJ, 368, m441.
**Riley, R. D., Van Calster, B., & Collins, G. S. (2021).** *A note on estimating the Cox-Snell R² from a reported C statistic (AUROC) to inform sample size calculations for developing a prediction model with a binary outcome.* Statistics in Medicine, 40(4), 859–864.
The minimum sample size must satisfy three criteria: global shrinkage factor ≥ 0.9; absolute difference ≤ 0.05 between apparent and adjusted Nagelkerke R²; and precise estimation of the overall risk. Riley, Van Calster, and Collins (2021) further supply a method for back-deriving the anticipated Cox–Snell R² **from a published C-statistic**.
→ **Design consequence:** Version 1.0 contains **no sample-size justification at all**. Version 2.0 performs a formal calculation *per label variant* (§5.9), using Moor et al.'s (2023) internal AUC of 0.846 as the anticipated discrimination to derive the anticipated R². Note also that van Smeden et al. have shown there is no rationale for the traditional "ten events per variable" heuristic, so the Riley approach is the correct one.

**Collins, G. S., Moons, K. G. M., Dhiman, P., Riley, R. D., Beam, A. L., Van Calster, B., et al. (2024).** *TRIPOD+AI statement.* BMJ, 385, e078378.
**Moons, K. G. M., Damen, J. A. A., Kaul, T., et al. (2025).** *PROBAST+AI.* BMJ, 388, e082505.
The governing reporting and risk-of-bias standards, explicitly covering **both regression and machine-learning** prediction models under a single checklist.
→ **Design consequence:** the reporting standard has already abandoned the statistics-versus-ML dichotomy on which Version 1.0's scoping rests. A Cox or discrete-time model reported in 2026 is a TRIPOD+AI study. PROBAST+AI self-appraisal must be conducted at **design time**, because its participant-selection, outcome-definition, and analysis domains are precisely where the label problem does its damage — and they cannot be repaired retrospectively.

**Bennett, N., Plečko, D., Ukor, I.-F., Meinshausen, N., & Bühlmann, P. (2023).** *ricu: R's interface to intensive care data.* GigaScience, 12, giad041.
An R package providing a **unified, dataset-agnostic interface** to five public ICU databases out of the box — MIMIC-III, MIMIC-IV, eICU-CRD, HiRID, and AmsterdamUMCdb — supporting roughly 100 clinical concepts across 319,402 ICU admissions from four data sources in Europe and the United States. It explicitly handles the timestamp heterogeneity between databases (MIMIC uses shifted absolute times; eICU uses times relative to admission). **Demo subsets of MIMIC and eICU are distributed as `mimic.demo` and `eicu.demo` and do not require credentialed PhysioNet access.** It is the harmonisation layer used by Moor et al. (2023).
→ **Design consequence:** this single source retires Version 1.0's two largest risks. **R1 (credentialing delay, rated Medium/High)** becomes low-impact, because the entire pipeline can be built and unit-tested on demo data from Week 1. **R6 (MIMIC-IV/eICU schema mismatch, rated Medium/High)** becomes low-likelihood, because the harmonisation layer already exists, is peer-reviewed, and has been used for precisely this task. It also makes a **non-US external cohort (AmsterdamUMCdb or HiRID) a realistic stretch goal** — which matters, because Moor et al. (2023) show the magnitude of the external penalty scales with the distance of the shift.

### 2.8 Design Decision Register

| # | Design decision | Warrant |
|---|---|---|
| D1 | ≥3 pre-specified Sepsis-3 onset label variants; cross-label variance is a **primary result** | Cohen et al. (2024); Johnson et al. (2018); Dutta et al. (2026) |
| D2 | Pre-specified framing (observation/prediction window, shift, trigger); coefficient-stability reporting | Lauritsen et al. (2021) |
| D3 | Treatment-anchored evaluation window; lead time measured against clinical recognition | Kamran et al. (2024) |
| D4 | Primary model = dynamic discrete-time competing-risks hazard model (multinomial pooled logistic over person-hours) | D'Agostino et al. (1990); Heyard et al. (2019, 2020); Tutz & Schmid (2016) |
| D5 | No proportional-hazards assumption imposed; static Cox retained only as weak comparator | Kasal et al. (2004); van Houwelingen (2007) |
| D6 | Cause-specific competing risks (discharge alive; death without sepsis) | Resche-Rigon et al. (2006); Fine & Gray (1999); Schoenfeld (2006) |
| D7 | **Temporal split primary**; random split reported only to quantify optimism | Guo et al. (2022) |
| D8 | Primary metrics = Utility Score + calibration; AUROC demoted to descriptive | Wang et al. (2025); Van Calster et al. (2019); Reyna et al. (2020) |
| D9 | AUPRC and alert burden (false alerts per true alert) reported; benchmark 1.4 | Moor et al. (2023); Wong et al. (2026) |
| D10 | Decision-curve net benefit | Vickers & Elkin (2006) |
| D11 | NEWS2 as headline rule-based comparator, not qSOFA | Evans et al. (2021); Mellhammar et al. (2020) |
| D12 | Gradient-boosted comparator **mandatory**, run in-house under identical conditions | Reyna et al. (2020) (rank non-transfer); Cohen et al. (2024) |
| D13 | Subgroup performance **and** subgroup label-sensitivity | Wang, Li, Naidech, & Luo (2022) |
| D14 | Formal sample-size calculation per label variant | Riley et al. (2019, 2020, 2021) |
| D15 | Pre-registration before any modelling | The study's own thesis (analyst degrees of freedom) |
| D16 | TRIPOD+AI reporting; PROBAST+AI design-time self-appraisal | Collins et al. (2024); Moons et al. (2025) |
| D17 | `ricu` for extraction and harmonisation; demo data for Week-1 prototyping | Bennett et al. (2023) |
| D18 | Expected external penalty of ≈0.085 AUC **pre-registered**; a smaller drop treated as suspicious | Moor et al. (2023) |
---

## 3. Comparative Analysis: Version 1.0 versus Version 2.0

### 3.1 Head-to-head design comparison

| Design element | Version 1.0 | Version 2.0 | Warrant for the change |
|---|---|---|---|
| **Contribution** | A model | A **variance decomposition** | Cohen et al. (2024); Guo et al. (2022); Wang et al. (2025) |
| **Primary model** | Time-varying Cox PH | Dynamic discrete-time competing-risks hazard model (multinomial pooled logistic) | D'Agostino et al. (1990); Heyard et al. (2019) |
| **PH assumption** | Test it; fall back if it fails | **Dissolve it** — not required by the model class | Kasal et al. (2004); van Houwelingen (2007) |
| **Competing risks** | Not addressed | Cause-specific: discharge alive; death without sepsis | Resche-Rigon et al. (2006); Schoenfeld (2006) |
| **Label** | Single Sepsis-3 definition, treated as given | **≥3 pre-specified variants; variance reported as a primary result** | Cohen et al. (2024); Dutta et al. (2026) |
| **Controls** | "Matched non-septic ICU patients" (alignment rule unstated) | No case–control matching; **all at-risk person-hours** contribute | Moor et al. (2021) |
| **Leakage** | Not addressed | **Treatment-anchored evaluation** | Kamran et al. (2024) |
| **Internal split** | Random train/test | **Temporal**; random reported only to quantify optimism | Guo et al. (2022) |
| **External validation** | eICU-CRD | eICU-CRD via `ricu`; **fallback = within-MIMIC-IV temporal**; stretch = non-US cohort | Bennett et al. (2023); Guo et al. (2022); Moor et al. (2023) |
| **Primary metrics** | AUC-ROC, sensitivity, specificity, lead time | **Utility Score + calibration**; AUROC descriptive only | Wang et al. (2025); Van Calster et al. (2019) |
| **Secondary metrics** | KM curves, log-rank, DCA | AUPRC, alert burden (benchmark 1.4), DCA, discrete-time cause-specific AUC and C-index | Moor et al. (2023); Heyard et al. (2020); Vickers & Elkin (2006) |
| **Rule-based comparator** | SIRS, qSOFA, NEWS | **NEWS2** headline; SIRS/qSOFA descriptive only | Evans et al. (2021) |
| **ML comparator** | None (deferred to "future work") | **Gradient-boosted trees, mandatory**, in-house, identical conditions | Reyna et al. (2020); Cohen et al. (2024) |
| **Equity** | Not addressed | Subgroup performance **and** subgroup label-sensitivity | Wang, Li, Naidech, & Luo (2022) |
| **Sample size** | **Absent** | Formal calculation per label variant | Riley et al. (2019, 2020, 2021) |
| **Reporting standard** | Not specified | TRIPOD+AI; PROBAST+AI at design time | Collins et al. (2024); Moons et al. (2025) |
| **Pre-registration** | Absent | **Phase 0, non-optional** | The study's own thesis |
| **Causal-adjustment tools** | PSM, IPW, doubly robust, E-values | **Removed** (category error — see §3.2) | — |
| **GBTM** | Exploratory extension | **Removed** (produces no real-time score) | — |
| **Failure mode if model underperforms** | Project risk R3 (Med/Med), requiring mitigation | **Pre-registered hypothesis H6** — equally publishable either way | Structural |

### 3.2 What is removed, and why

Three components of Version 1.0 are removed. Two of these are removals of *category errors*, and stating them plainly is more useful than politely retaining them.

**(a) Propensity score matching, inverse probability weighting, doubly robust estimation, and E-value sensitivity analysis. Removed.**
These are **causal-inference instruments**, designed to estimate the effect of an exposure or treatment on an outcome in the presence of confounding. They have no role in a *prediction* study. A prediction model does not need to be unconfounded; it needs to be **calibrated and validated**. A predictor that is a pure confounder — one with no causal relationship to sepsis whatsoever — is a perfectly legitimate and useful feature in a prediction model, provided it is available at prediction time and its association is stable. Conversely, adjusting a prediction model for confounding will typically *degrade* its predictive performance, because it removes precisely the associational signal the model exists to exploit.

Version 1.0 inherits these tools from the base literature review's Theme 4 (Guo et al., 2025; Zou et al., 2022) — a body of work that uses them entirely appropriately, because those studies are asking **aetiological questions** ("does heparin reduce sepsis mortality?"). The import into a prediction proposal is a straightforward confusion of estimands. Removing them is not a scope reduction; it is a correction, and it frees Weeks 13–14 of Version 1.0's schedule.

**(b) Group-based trajectory modelling. Removed (may be reinstated as a purely descriptive appendix if time permits).**
GBTM is a **latent-class clustering method**. It partitions patients into trajectory groups *post hoc*, using the full observed trajectory — including data from after the prediction time. It does not produce a real-time risk score, it cannot be evaluated on the Utility Score, and its groups cannot be assigned prospectively without a separate classifier. Version 1.0 lists it as an exploratory extension and simultaneously (correctly) flags in risk R7 that it may consume disproportionate time. The resolution is to remove it. Sepsis heterogeneity is real and important (Seymour et al., 2019), but it is addressed here through **subgroup analysis** (§5.10) and through the flexible baseline hazard, not through a clustering method that answers a different question.

**(c) Static and time-varying Cox as the primary model. Demoted to comparator.**
Retained, but only as a **deliberately weak comparator**, in order to quantify what the field's default choice costs. Fitting a time-varying-covariate Cox model on hourly person-time data is, incidentally, considerably *more* computationally demanding than the discrete-time alternative — the partial likelihood requires constructing a risk set at every distinct event time across millions of person-hours — so this demotion reduces rather than increases the computational burden.

### 3.3 What is added, and why

| Addition | Marginal cost | Why it is non-negotiable |
|---|---|---|
| 2 additional label variants | **Low** — the cohort query is parameterised, not rewritten | Cohen et al. (2024): the label moves performance as much as the model |
| Person-hour table construction | **Neutral** — replaces the counting-process format the time-varying Cox would have required anyway | Native to the model and to the Utility Score |
| Temporal split | **Near-zero** — one filter on admission-year group | Guo et al. (2022): sepsis is the worst-affected task |
| Treatment-anchored evaluation | **Low** — one additional timestamp per patient (first culture / first antibiotic) | Kamran et al. (2024): otherwise the model partly predicts clinician behaviour |
| Utility Score | **Moderate** — the PhysioNet 2019 scoring logic is publicly specified | Wang et al. (2025): it is the metric that reveals the collapse |
| Calibration, AUPRC, alert burden | **Low** — standard, well-tooled | Van Calster et al. (2019); Moor et al. (2023) |
| Gradient-boosted comparator | **Low** — a well-established off-the-shelf implementation on an existing feature matrix | Reyna et al. (2020): published comparisons do not transfer |
| Subgroup + subgroup-label analysis | **Low** — a stratified re-tabulation | Wang, Li, Naidech, & Luo (2022) |
| Sample-size calculation | **Low** — a closed-form calculation | Riley et al. (2019) |
| Pre-registration | **Low** — two weeks, front-loaded, concurrent with credentialing | Self-consistency (see below) |
| Variance-decomposition table | **Near-zero** — a re-tabulation of results already produced | It is the contribution |

**On pre-registration.** This is the one addition that is *logically* rather than merely methodologically required. The study's thesis is that **analyst degrees of freedom drive results in this field**. An unpre-registered study advancing that thesis would be self-refuting: its own findings would be indistinguishable from an artefact of the very forking paths it purports to measure. Phase 0 is therefore not bureaucratic overhead; it is the condition under which the result means anything.

### 3.4 The effort ledger: why Version 2.0 is not a larger project

A supervisor's first and entirely reasonable objection will be that Version 2.0 looks more ambitious. The ledger says otherwise.

| Removed from Version 1.0 | Added in Version 2.0 |
|---|---|
| Time-varying Cox partial-likelihood machinery on hourly data (computationally heavy) | Multinomial pooled logistic regression (a GLM) |
| Group-based trajectory modelling | — |
| Propensity score matching | — |
| Inverse probability weighting | — |
| Doubly robust estimation | — |
| E-value sensitivity analysis | — |
| Restricted cubic splines as a separate analytic phase | RCS **absorbed** into the model as the baseline-hazard and non-linearity specification |
| Bespoke MIMIC-IV → eICU variable mapping (Version 1.0 risk R6, Med/High) | `ricu` harmonisation layer (Bennett et al., 2023) |
| — | 2 extra label variants (parameterised query) |
| — | Utility Score, calibration, AUPRC, alert burden |
| — | Gradient-boosted comparator |
| — | Subgroup analysis; sample-size calculation; pre-registration |

**Net assessment.** The removals are computationally and conceptually heavier than the additions. Version 2.0 is **comparable in total effort, materially lower in delivery risk, and substantially higher in contribution**. The two heaviest risk items in Version 1.0 — credentialing delay (R1) and cross-database schema mismatch (R6), both rated Medium likelihood with High impact — are both largely retired by a single dependency (`ricu`), which supplies demo datasets requiring no credentialed access and a peer-reviewed harmonisation layer covering both target databases.

### 3.5 Anticipated objections, and their answers

**"You have abandoned the survival-analysis framing that motivated the project."**
No. D'Agostino et al. (1990) prove that pooled logistic regression is asymptotically equivalent to time-dependent-covariate Cox regression when intervals are short and per-interval event probabilities are small. Hourly bins with a low per-hour probability of sepsis onset is exactly that regime. The proposed model **is** the time-varying Cox model, expressed in the form the data actually takes — and expressed in a form that additionally accommodates competing risks, requires no proportionality, and emits the hourly score the evaluation metric consumes. The framework is not abandoned; it is implemented correctly.

**"This is a methods study, not a modelling study. Is it appropriate for an MSc?"**
It is a modelling study *and* a methods study: a fitted, interpretable, externally validated sepsis-onset model is a deliverable (§7). What has changed is that the model's *performance* is no longer the contribution, which means the project cannot fail on performance grounds. Given that ninety-one such models already exist and that leaderboard rank does not transfer out of distribution (Reyna et al., 2020), a project whose success is contingent on the ninety-second model outperforming the previous ninety-one is a considerably riskier MSc than one whose contribution is produced regardless of the direction of the result.

**"Three label variants triples the work."**
It does not. The cohort query is parameterised by the identification rule; the downstream pipeline is run three times by a loop. The marginal cost is compute time, not analyst time. And the floor is **two** variants (§6.4, R6) — the label-variance result survives with two.

**"Beating NEWS2 was the point."**
Mellhammar et al. (2020) already attempted exactly this — a LASSO-derived statistical score, benchmarked against NEWS2 — and failed. Making that the criterion of success is making the project's success contingent on succeeding where a published, peer-reviewed attempt on a purpose-built cohort did not. Version 2.0 still reports the NEWS2 comparison; it simply does not stake the dissertation on the outcome.
---

## 4. Research Questions, Hypotheses, and Objectives

### 4.1 Primary research question

> **In real-time sepsis onset prediction on MIMIC-IV, how is predictive performance and inferential validity partitioned between (a) the choice of model class — an interpretable dynamic discrete-time survival model versus a gradient-boosted machine-learning baseline — and (b) the analyst's discretionary methodological choices: the operationalisation of the Sepsis-3 onset label, the temporal versus random validation split, the anchoring of the prediction time relative to clinical action, and the choice of evaluation metric?**

### 4.2 Sub-questions

**SQ1 (Inference).** Are the coefficients of an interpretable dynamic survival model for sepsis onset **stable in sign and magnitude** across (i) three defensible operationalisations of the Sepsis-3 onset rule, and (ii) evaluation anchored before versus after the first clinical action (culture order or antibiotic administration)?

**SQ2 (Performance).** Under a **fixed** label, a **fixed** temporal split, and a **utility-based** metric, what is the performance gap between the interpretable discrete-time hazard model and a gradient-boosted baseline — and how does that gap compare in magnitude with the variance induced by the label alone?

**SQ3 (Generalisation).** How much of the internal-validation performance is lost under (i) a temporal split within MIMIC-IV and (ii) external validation on eICU-CRD — and does the ranking of metrics diverge, such that AUROC is preserved while the Utility Score is not?

**SQ4 (Equity).** Are the answers to SQ1–SQ3 stable across demographic subgroups defined by race, ethnicity, language, and insurance status, given that the label itself is known to be demographically non-neutral (Wang, Li, Naidech, & Luo, 2022)?

### 4.3 Pre-registered hypotheses

All hypotheses are directional, falsifiable, and pre-registered in Phase 0 before any modelling is performed. Thresholds are stated in advance and derived from published effect sizes.

| ID | Hypothesis | Directional prediction | Source of the prediction |
|---|---|---|---|
| **H1** | *Label dominance.* The spread in AUROC across the three label variants (model class held fixed) will be **at least as large** as the spread across model classes (label held fixed). | Label swing 0–6%; model gain 1–5% | Cohen et al. (2024) |
| **H2** | *Coefficient instability.* At least one covariate in the primary model will **change sign**, or change in magnitude by a factor ≥ 2, across the three label variants. | Framing can reverse the direction of a covariate effect | Lauritsen et al. (2021) |
| **H3** | *Leakage.* Restricting evaluation to predictions issued **before** the first culture order or antibiotic administration will reduce AUROC by **≥ 0.03** relative to unrestricted evaluation. | Apparent accuracy is substantially inflated when clinician action is not excluded | Kamran et al. (2024) |
| **H4** | *Split optimism.* Temporal-split AUROC will be lower than random-split AUROC by **≥ 0.02**. | Sepsis is the worst-degraded of four MIMIC-IV tasks under temporal shift | Guo et al. (2022) |
| **H5** | *Metric divergence.* The **proportional** decline from internal to external validation will be **substantially larger for the Utility Score than for AUROC**, with the Utility Score potentially crossing zero. | AUROC 0.811 → 0.783 (n.s.); Utility +0.381 → −0.164 | Wang et al. (2025) |
| **H6** | *Model-class null.* Under a fixed label, fixed temporal split, and fixed metric, the discrete-time hazard model will **not be inferior** to gradient-boosted trees by more than **0.02 AUROC**. | No performance benefit of ML over logistic regression for clinical prediction | Christodoulou et al. (2019) — tested against the counter-evidence of Fagerström et al. (2019), who found a large *lead-time* advantage for a deep model on this specific task |

**A note on H6.** H1 and H6 are, deliberately, in productive tension. H6 asserts that the model class barely matters; Fagerström et al. (2019) found that on the lead-time axis specifically it matters a great deal. The study is designed so that **either outcome is informative**: if H6 holds, the field gains a defence of interpretable modelling it currently lacks; if H6 is rejected, the study localises precisely *where* the interpretable model loses — on discrimination, on calibration, on lead time, or on utility — which no published study has done under a fixed label.

**Contrast with Version 1.0.** Version 1.0's stated null hypothesis was "the proportional-hazards assumption will hold for at least half of the included covariates." This is a model diagnostic, not a scientific hypothesis: it makes no prediction about the world, its threshold ("half") is arbitrary, and neither its confirmation nor its rejection tells a reader anything they could use. The six hypotheses above each make a quantitative prediction, each is falsifiable, and each has a named source from which its threshold is derived.

### 4.4 Objectives

**Primary objective.** To quantify the relative contribution of **model class** versus **analyst discretion** (label operationalisation, split strategy, prediction-time anchoring, evaluation metric) to both the predictive performance and the inferential stability of real-time sepsis onset models on MIMIC-IV.

**Secondary objectives.**

- **O1.** Pre-register the protocol — label variants, framing, split, metrics, hypotheses, and thresholds — before any modelling, and conduct a PROBAST+AI self-appraisal at design time (Moons et al., 2025).
- **O2.** Construct, using `ricu` (Bennett et al., 2023), a reproducible person-hour ICU cohort from MIMIC-IV under **three pre-specified Sepsis-3 onset operationalisations**, and report the resulting variation in cohort size and event count as a **primary descriptive result** — replicating Cohen et al.'s (2024) MIMIC-III finding on MIMIC-IV, where it has not been shown.
- **O3.** Specify and fit a **dynamic discrete-time competing-risks hazard model** (multinomial pooled logistic regression over person-hours, with a spline baseline hazard and time-varying covariates), following Heyard et al. (2019) and Tutz and Schmid (2016), with cause-specific handling of the competing events of discharge alive and death without sepsis.
- **O4.** Fit comparators under **identical** cohort, label, split, features, and metrics: NEWS2; a static Cox proportional-hazards model (as a deliberately weak baseline, with Schoenfeld-residual testing, to quantify the cost of the field's default choice); and gradient-boosted trees.
- **O5.** Evaluate under a **temporal split** as primary, reporting the random split alongside to quantify optimism (Guo et al., 2022), and under a **treatment-anchored** prediction window (Kamran et al., 2024).
- **O6.** Report a metric suite adequate to the failure mode: the **PhysioNet Utility Score** and **calibration** (intercept, slope, flexible curve) as primary; AUROC, AUPRC, discrete-time cause-specific AUC and concordance index (Heyard et al., 2020), decision-curve net benefit (Vickers & Elkin, 2006), **alert burden** (false alerts per true alert, against Moor et al.'s benchmark of 1.4), and lead time relative to clinical recognition as secondary.
- **O7.** Externally validate on **eICU-CRD**, pre-registering an expected degradation of ≈ 0.085 AUC (Moor et al., 2023) and testing whether the Utility Score remains positive.
- **O8.** Report **subgroup performance and subgroup label-sensitivity** by race, ethnicity, language, and insurance status (Wang, Li, Naidech, & Luo, 2022).
- **O9.** Produce the **variance-decomposition table** attributing performance and coefficient variation to model class, label, split, anchoring, metric, and subgroup.
- **O10.** Report in conformity with **TRIPOD+AI** (Collins et al., 2024) and release the full `ricu`-based pipeline under an open licence, addressing the low reproducibility identified by Moor et al. (2021).

---

## 5. Methodology

### 5.1 Design and paradigm

A quantitative, hypothesis-driven, retrospective prognostic-model development and validation study, with an embedded **methodological variance-decomposition component** that constitutes the primary contribution. The study is non-interventional, uses only de-identified secondary data, and makes no claim to clinical deployability. It is designed and reported as a TRIPOD+AI study (Collins et al., 2024).

### 5.2 Data sources and access

- **Development:** MIMIC-IV (Johnson et al., 2023), a single-centre ICU electronic health record database from Beth Israel Deaconess Medical Center, accessed via PhysioNet under credentialed access. The database's `anchor_year_group` field supports the temporal split.
- **External validation:** eICU-CRD (Pollard et al., 2018), covering over 200,000 ICU admissions across 208 US hospitals.
- **Stretch (if time permits):** AmsterdamUMCdb or HiRID, both supported by `ricu`, to obtain a *larger* distributional shift — Moor et al. (2023) show the external penalty scales with the distance of the shift, so a non-US cohort is more informative than a second US one.
- **Extraction layer:** `ricu` (Bennett et al., 2023), which provides a dataset-agnostic interface across all of the above, handles the timestamp-representation heterogeneity between MIMIC (shifted absolute times) and eICU (times relative to admission), and — critically for the project schedule — distributes `mimic.demo` and `eicu.demo` subsets that **require no credentialed access**, allowing the entire pipeline to be built and unit-tested from Week 1.

### 5.3 Cohort construction under multiple labels

Adult ICU admissions. Exclusions pre-specified in Phase 0 (minimum stay length; sepsis present on admission, since the target is *incident* onset in the ICU).

**Three Sepsis-3 onset operationalisations** will be implemented, following Cohen et al. (2024) and the identification algorithms compared by Johnson et al. (2018). These vary in the parameterisation of the suspicion-of-infection window relative to the SOFA-increase window, and in the reference from which the SOFA baseline is taken. The exact three variants will be fixed in Phase 0 and will not be modified thereafter.

For each variant, the study will report the number of qualifying admissions, the number of onset events, and the number of at-risk person-hours. **This is a primary result.** Cohen et al. (2024) found a range of 867–2,178 admissions on MIMIC-III; whether a comparable spread occurs on MIMIC-IV is an open question that this study answers, and it answers it regardless of what happens downstream.

**No case–control matching is performed.** In the person-hour design, every eligible admission contributes all of its at-risk hours; there is no separate control cohort and therefore no control-alignment step. This dissolves the trap Moor et al. (2021) identify — that a control aligned near discharge is trivially separable from a case aligned near onset — rather than attempting to navigate it.

### 5.4 Temporal framing and person-hour construction

**Hourly binning**, following the convention established by the PhysioNet/CinC 2019 Challenge (Reyna et al., 2020) and AISE (Nemati et al., 2018). Version 1.0's justification of hourly resolution — that vitals are charted on minute-to-hour timescales, labs on 4–12 hour timescales, and clinical interventions titrated on 30-minute-to-multi-hour cycles, so that sub-hourly prediction is clinically redundant and would require waveform data the databases do not contain — is **retained in full**. It was one of the strongest passages in Version 1.0 and remains correct.

Each admission is expanded into a **person-hour table**: one row per patient per hour at risk, from the end of a minimum observation window (fixed in Phase 0) until the first of sepsis onset, ICU discharge alive, death without sepsis, or administrative censoring.

**Covariates** (time-varying, per hour): current values of vitals (heart rate, respiratory rate, temperature, SpO₂, systolic and mean arterial pressure) and labs (white cell count, lactate, creatinine, platelets, bilirubin); rolling slopes over the preceding six hours (a *local* deterioration signal within the expanding record); lagged values; hours since ICU admission; and **informative-missingness indicators** — binary flags recording whether each laboratory value was measured in a given hour. The missingness flags are retained deliberately: the decision to order a lactate is itself clinically informative. But they are also, per Kamran et al. (2024), a **direct channel for clinician-suspicion leakage**, and their coefficients will therefore be reported and interpreted with that explicitly in view. Missing values are carried forward from the last observation, mirroring what the clinician actually knows at that hour.

**Framing** (Lauritsen et al., 2021) is pre-specified: expanding observation window; prediction horizon fixed in Phase 0 (candidate: onset within the next 6 hours, matching Reyna et al.'s Challenge target, to enable direct comparability with the Utility Score); hourly window shift; prediction triggered at every at-risk hour.

### 5.5 Primary model: dynamic discrete-time competing-risks hazard model

For patient *i* at hour *t*, let the competing events be *r* ∈ {1 = sepsis onset, 2 = discharge alive, 3 = death without sepsis}, with **conditional survival** (remaining in the ICU, alive and sepsis-free) as the reference category. The discrete cause-specific hazard is specified as a multinomial logit (Tutz & Schmid, 2016, Ch. 8; Heyard et al., 2020):

$$
\lambda_r(t \mid X_{it}) \;=\; P(T_i = t,\; R_i = r \mid T_i \geq t,\; X_{it}) \;=\;
\frac{\exp\!\big(\alpha_r(t) + \beta_r^{\top} X_{it}\big)}
{1 + \sum_{s=1}^{3}\exp\!\big(\alpha_s(t) + \beta_s^{\top} X_{it}\big)}
$$

where:

- **α_r(t)** is the cause-specific baseline log-hazard, modelled as a **restricted cubic spline in hours since ICU admission**. Because the baseline hazard is estimated flexibly rather than assumed constant or proportional, **no proportional-hazards assumption is imposed.**
- **β_r** are cause-specific coefficients. Where a covariate's effect is expected to vary with time-in-ICU, this is captured by interacting the covariate with spline terms in *t* — i.e. β_r(t) — which is a *natural extension* of this model class rather than a repair to a violated assumption.
- **X_it** are the time-varying covariates of §5.4.

**Interpretation.** Each coefficient is the log-odds of the corresponding event occurring in the next hour, conditional on the patient having remained in the ICU, alive and sepsis-free, up to that hour. This is arguably a *more* clinically legible quantity than a hazard ratio from a continuous-time Cox model.

**Why this is the right model — the seven-point warrant.**

1. **It is the Cox model.** D'Agostino et al. (1990) prove that pooled logistic regression is asymptotically equivalent to time-dependent-covariate Cox regression when intervals are short and per-interval event probabilities are small — exactly the hourly, low-prevalence regime here. This is not a departure from Version 1.0's methodological commitment but its correct implementation.
2. **No proportional-hazards assumption.** Kasal et al.'s (2004) finding is dissolved rather than tested.
3. **Competing risks handled natively.** Discharge alive is an *informative* competing event (Resche-Rigon et al., 2006), and the cause-specific formulation models it as such rather than treating it as non-informative censoring.
4. **Schoenfeld's objection is answered by construction.** Schoenfeld (2006) argues survival methods are inappropriate for ICU outcome studies and that logistic regression should be used instead. This model *is* a logistic regression — while retaining the time-to-event structure he would discard.
5. **It emits the right object.** The output is a per-hour risk score, which is precisely what the Utility Score (Reyna et al., 2020) consumes. No reconciliation between the model's time scale and the evaluation's time scale is required.
6. **It is computationally tractable.** A generalized linear model over a long person-hour table, in contrast to a time-varying Cox partial likelihood requiring risk-set construction at every distinct event time.
7. **It has a validated ICU precedent.** Heyard et al. (2019) built exactly this architecture — dynamic, discrete-time, competing-risks, landmarked, on ICU records — for ventilator-associated pneumonia; Heyard et al. (2020) supply the matching validation estimators.

**Estimation note.** Because a patient contributes many correlated person-hour rows, standard errors will be computed using a **cluster-robust (sandwich) variance estimator clustered on ICU stay**. Naïve GLM standard errors would be anti-conservative. Coefficient penalisation (ridge or LASSO) will be considered and, if used, will be pre-specified; note Riley et al.'s finding that penalisation can produce unreliable models at small sample sizes, so the sample-size calculation (§5.9) precedes this decision rather than substituting for it.

### 5.6 Comparators

All comparators are fitted on the **identical cohort, label, temporal split, feature set, and metric suite**. This is the only comparison that carries evidential weight, because Reyna et al. (2020) demonstrate that published rankings do not transfer across sites (ρ ≈ −0.03 to 0.01 to an unseen hospital system) and Cohen et al. (2024) demonstrate that cross-paper comparison under differing labels is uninterpretable.

1. **NEWS2** — the headline rule-based comparator (Evans et al., 2021, having recommended against qSOFA as a sole screening tool).
2. **SIRS and qSOFA** — reported for descriptive continuity with the literature only; not treated as the bar to be cleared.
3. **Static Cox proportional-hazards model** — the field's default, retained *as a deliberately weak baseline*, with formal Schoenfeld-residual testing. Its purpose is to answer the question Version 1.0 could not: *what does the default choice actually cost?*
4. **Gradient-boosted trees** — mandatory. The modern ML baseline, and the model class used by the Epic Sepsis Model version 2 (Wong et al., 2026) and by Dutta et al. (2026).
5. **A dynamic deep survival model (stretch, optional).** If time permits, a recurrent or attention-based model. The principled choice is one sharing the *same estimand* — a dynamic discrete-time cause-specific hazard with competing risks — rather than an arbitrary LSTM, so that any observed difference is attributable to the functional form and not to a change of target.

### 5.7 Validation architecture

| Layer | Design | Purpose |
|---|---|---|
| **Internal (primary)** | **Temporal split** on MIMIC-IV `anchor_year_group`: train on early groups, test on the latest | The honest internal estimate (Guo et al., 2022) |
| **Internal (secondary)** | Random patient-level split | Reported *solely* to quantify the optimism of the design Version 1.0 proposed |
| **Prediction-time anchoring** | Restricted to hours **before** first culture order / first antibiotic | Removes clinician-suspicion leakage (Kamran et al., 2024) |
| **External (primary)** | eICU-CRD via `ricu` | The generalisation test |
| **External (fallback)** | Within-MIMIC-IV temporal external validation (earliest year-group → latest) | Evidence-backed substitute if harmonisation fails (Guo et al., 2022) |
| **External (stretch)** | AmsterdamUMCdb or HiRID | A *larger* shift, hence more informative (Moor et al., 2023) |

The expected external degradation of **≈ 0.085 AUC** (Moor et al., 2023) is **pre-registered**. A materially *smaller* observed drop will be interpreted as evidence that the external data is insufficiently distant — not as evidence of an unusually robust model.

### 5.8 Evaluation metrics

**Primary.**
- **PhysioNet Utility Score** (Reyna et al., 2020) — rewards timely prediction; penalises late predictions, missed detections, and false alarms; **can go negative**, which is what makes the collapse documented by Wang et al. (2025) legible at all.
- **Calibration** — intercept, slope, and a flexible calibration curve (Van Calster et al., 2019). For the competing-risks model, cause-specific calibration via the multinomial recalibration approach of Heyard et al. (2020).

**Secondary.**
- **AUPRC** — mandatory given low per-hour event prevalence. AUROC and AUPRC diverge sharply in this setting.
- **AUROC** — reported for comparability with the literature, and **explicitly designated descriptive rather than primary**, on the evidence of Wang et al. (2025).
- **Discrete-time cause-specific AUC and concordance index** (Heyard et al., 2020) — the model-class-appropriate discrimination measures.
- **Decision-curve net benefit** across clinically plausible thresholds (Vickers & Elkin, 2006).
- **Alert burden** — false alerts per true alert, benchmarked against Moor et al.'s (2023) reported 1.4.
- **Lead time** — measured relative to **clinical recognition** (first culture/antibiotic), not to the label. Benchmarked against Moor et al.'s honest 3.7 hours (95% CI 3.0–4.3), not against TREWScore's 28-hour headline.

### 5.9 Sample size and precision

Version 1.0 contains **no sample-size justification**. Version 2.0 performs a formal calculation using Riley et al. (2019, Part II), targeting: (i) a global shrinkage factor ≥ 0.9; (ii) an absolute difference ≤ 0.05 between apparent and adjusted Nagelkerke R²; and (iii) precise estimation of the overall event rate. The anticipated Cox–Snell R² will be back-derived from an anticipated C-statistic using the method of Riley, Van Calster, and Collins (2021), taking Moor et al.'s (2023) internal AUC of 0.846 as the anticipated discrimination.

**The calculation is performed separately for each label variant**, because each yields a different event count — and if a variant proves underpowered for the candidate predictor set, *that is itself a finding*, and one directly relevant to the interpretation of the published literature that uses it. The traditional "ten events per variable" heuristic is not used; van Smeden et al. have shown it lacks rationale.

A subtlety specific to the person-period design will be stated explicitly in the write-up: although *n* is the number of person-hours (potentially in the millions), the effective information is governed by the number of **onset events**, and the clustering of hours within patients means precision does not grow with person-hours in the way a naïve reading would suggest.

### 5.10 Equity analysis

Subgroups: race, ethnicity, primary language, and insurance status, following Wang, Li, Naidech, and Luo (2022). Two analyses, and the second is the novel one:

1. **Subgroup performance.** Utility Score, calibration, AUPRC, and alert burden, computed within subgroup.
2. **Subgroup label-sensitivity.** For each subgroup, the *change in who is identified as septic* across the three label variants. Wang, Li, Naidech, and Luo (2022) established that different sepsis criteria select demographically different populations; this study asks whether the **magnitude of that differential varies by subgroup**, and whether subgroups whose membership is most label-sensitive are also those for whom the model performs worst. To this author's knowledge, this conjunction has not been reported for any sepsis model.

### 5.11 The variance decomposition

The study's principal output is a single table attributing observed variation — in performance metrics and in fitted coefficients — to each of the following factors, with all others held fixed:

| Factor | Levels |
|---|---|
| Model class | Discrete-time hazard / static Cox / gradient-boosted trees / NEWS2 |
| Label operationalisation | Variant A / B / C |
| Validation split | Temporal / random |
| Prediction-time anchoring | Treatment-anchored / unanchored |
| Evaluation metric | Utility Score / calibration / AUROC / AUPRC |
| Subgroup | Race, ethnicity, language, insurance |

If Version 1.0's implicit premise is correct, **model class dominates**. If the literature reviewed in §2 is correct, it does not. **That table is the dissertation.**

### 5.12 Reporting, appraisal, and reproducibility

TRIPOD+AI (Collins et al., 2024) for reporting; PROBAST+AI (Moons et al., 2025) self-appraisal conducted in Phase 0, not at write-up, because its participant-selection, outcome-definition, and analysis domains are exactly where the label problem does its damage and cannot be repaired retrospectively. The protocol will be pre-registered on a public registry. The complete `ricu`-based extraction and modelling pipeline — parameterised by label definition — will be released under an open licence. Given that Moor et al. (2021) identify **low reproducibility** as the field's defining methodological weakness, a parameterised, harmonised, openly released cohort pipeline is a contribution in its own right, independent of the modelling results.

### 5.13 Ethics

De-identified secondary data only, accessed under PhysioNet credentialed agreements for MIMIC-IV and eICU-CRD. No human participants; no primary data collection; ethical approval for primary collection therefore not required (institutional ethics review to be sought as per departmental policy for secondary-data projects). No re-identification will be attempted; processing confined to secure environments. Internal, temporal, and external performance will be reported **side by side**, so that generalisability is not overstated from internal results alone — a reporting commitment that is, in this field, an ethical one, given the demonstrated deployment harms of models validated only internally (Wong et al., 2021; Ostermayer et al., 2024). The artefact is a research object and will carry an explicit non-clinical-use disclaimer.
---

## 6. Project Plan

### 6.1 Work breakdown structure

**Phase 0 — Pre-registration and protocol (Weeks 1–2).** *New, and non-optional.*
Fix the three label variants; fix the framing (observation window, prediction horizon, trigger); fix the split; fix the primary metrics; fix the hypotheses and their thresholds. Conduct the PROBAST+AI self-appraisal. Perform the Riley et al. (2019) sample-size calculation. Publish the protocol to a public registry.
*Rationale:* the study's thesis is that analyst degrees of freedom drive results. An unpre-registered version of it would be self-refuting.
**Deliverable:** registered protocol.

**Phase 1 — Access and environment (Weeks 1–3, concurrent with Phase 0).**
CITI training; PhysioNet credentialing for MIMIC-IV and eICU-CRD; `ricu` installation; repository setup. **Pipeline prototyping begins immediately on `mimic.demo` and `eicu.demo`, which require no credentialed access** (Bennett et al., 2023). Credentialing is therefore *not* on the critical path for pipeline development.
**Deliverable:** working extraction prototype on demo data.

**Phase 2 — Cohort and person-hour construction under three labels (Weeks 3–7).**
Parameterised `ricu` extraction; three Sepsis-3 onset variants; person-hour table construction; covariate engineering (current values, six-hour slopes, lags, missingness indicators); competing-event coding; treatment-anchor timestamps (first culture, first antibiotic).
**Deliverable — and the first reportable result:** the cohort-size and event-count table across the three label variants. *This result is publishable on its own*, and it is delivered by Week 7.

**Phase 3 — Primary model and comparators (Weeks 8–11).**
Fit the dynamic discrete-time competing-risks hazard model under each label variant. Fit NEWS2, SIRS, qSOFA, the static Cox comparator (with Schoenfeld-residual testing), and gradient-boosted trees — all under identical conditions.
**Deliverable:** fitted models; coefficient tables across label variants (→ H2).

**Phase 4 — Evaluation (Weeks 12–15).**
Temporal split (primary) and random split (optimism quantification). Treatment-anchored and unanchored evaluation. Full metric suite: Utility Score, calibration, AUPRC, AUROC, discrete-time cause-specific AUC and C-index, decision-curve net benefit, alert burden, lead time.
**Deliverable:** internal validation complete; H1, H3, H4, H6 tested.

**Phase 5 — External validation (Weeks 16–18).**
eICU-CRD via `ricu`. Pre-registered expected degradation ≈ 0.085 AUC. Test whether the Utility Score remains positive.
**Deliverable:** external validation; H5 tested.

**Phase 6 — Variance decomposition and equity (Weeks 19–20).**
The decomposition table (§5.11). Subgroup performance and subgroup label-sensitivity.
**Deliverable:** the central table; SQ4 answered.

**Phase 7 — Writing and release (Weeks 17–22, overlapping Phases 5–6).**
TRIPOD+AI-conformant dissertation; open release of the pipeline.
**Deliverable:** submission.

### 6.2 Timeline

```
Project timeline (22 weeks)
      1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22
P0 Pre-registration + protocol   [====]
P1 Access + demo prototyping     [======]
P2 Cohort + person-hours (x3)          [==============]
M1 Label-variance result locked                       *
P3 Primary model + comparators                        [==========]
M2 Models locked                                                 *
P4 Evaluation (temporal/random)                                  [==========]
M3 Internal validation complete                                             *
P5 External validation (eICU)                                               [========]
M4 External validation complete                                                    *
P6 Variance decomposition + equity                                                 [=====]
P7 Writing and release                                              [==================]
M5 Submission                                                                             *
```

**Critical path:** P2 → P3 → P4 → P5. Phase 0 and Phase 1 run concurrently and are not on the critical path, because demo-data prototyping proceeds without credentialing.

**A structural feature worth noting:** the first reportable result (M1, the label-variance table) lands in **Week 7**. Version 1.0's first substantive result — baseline models — landed in Week 8, and its *contribution-bearing* result, the time-varying model, in Week 12. Version 2.0 therefore front-loads its contribution, which materially reduces the risk of a late-stage failure leaving the dissertation without a finding.

### 6.3 Milestones and go/no-go gates

| Gate | Week | Decision | Action if not met |
|---|---|---|---|
| **G0** | 2 | Protocol registered? | Blocking. Do not proceed to modelling. |
| **G1** | 3 | PhysioNet credentialing granted? | **Non-blocking.** Continue on `mimic.demo`/`eicu.demo`; escalate to supervisor. |
| **G2** | 7 | ≥2 label-variant person-hour tables built and validated? | Floor is **two** variants. The label-variance result survives with two. |
| **G3** | 15 | Internal validation complete? | Drop the optional deep-survival comparator and the non-US stretch cohort. |
| **G4** | 18 | eICU harmonisation working? | **Fall back** to within-MIMIC-IV temporal external validation (earliest year-group → latest). This is an *evidence-backed* substitute, not a consolation prize: Guo et al. (2022) established that this shift is the largest of any MIMIC-IV task for sepsis specifically. |

### 6.4 Risk register

| # | Risk | L | I | Mitigation | Change vs. V1.0 |
|---|---|---|---|---|---|
| **R1** | PhysioNet credentialing delayed | Med | **Low** | `mimic.demo` and `eicu.demo` require no credentialed access (Bennett et al., 2023). Full pipeline built and unit-tested on demo data from Week 1. Credentialing is off the critical path. | **Impact downgraded** from High |
| **R2** | MIMIC-IV ↔ eICU schema/variable mismatch | **Low** | Med | `ricu` supplies a peer-reviewed harmonisation layer covering both, handling the absolute-vs-relative timestamp problem; used by Moor et al. (2023) for exactly this purpose. Fallback at G4. | **Likelihood downgraded** from Med; this was V1.0's single largest risk |
| **R3** | Person-hour table (millions of rows) exceeds available compute | Med | Med | The model is a GLM. Fit via iteratively reweighted least squares in memory, or with out-of-core/streaming GLM tooling. If necessary, apply case–control sampling *within* person-hours with an offset correction, which is standard for rare-event pooled logistic regression. | New |
| **R4** | Extreme class imbalance (very low per-hour onset probability) | High | **Low** | **Expected, not adverse.** This is precisely why AUPRC, calibration, and the Utility Score are primary and AUROC is descriptive. The imbalance is a feature of the problem the study is designed to characterise. | **Reframed** — was Med impact in V1.0 |
| **R5** | One or more label variants yields too few events for stable estimation | Med | Med | Riley et al. (2019) sample-size calculation performed in Phase 0, *per variant*, before modelling. If a variant is underpowered, **that is a finding** — and one directly bearing on the interpretation of published studies using it. | New |
| **R6** | Three label variants infeasible in time | Med | Med | Floor is two (gate G2). The label-variance result survives with two. | New |
| **R7** | Deep-survival comparator not delivered | Med | **Low** | Explicitly scoped as optional. Gradient-boosted trees is the mandatory ML comparator and is low-cost. | Reframed |
| **R8** | **The discrete-time model does not outperform gradient boosting** | **High** | **Low** | This is **pre-registered hypothesis H6**, not a failure. The variance decomposition — the contribution — is produced regardless of the direction of the result. | **The key structural change.** In V1.0 this was risk R3 (Med/Med) requiring mitigation. Here it is a *result*. |
| **R9** | Utility Score implementation is non-trivial | Low | Med | The Challenge scoring logic is fully specified in Reyna et al. (2020) and its reference implementation is publicly released. Unit-tested on demo data in Phase 1. | New |
| **R10** | Supervisor or personal availability | Low | Med | Milestones at Weeks 7, 11, 15, 18; writing begins Week 17, overlapping analysis; buffer retained. | Retained |

**The most important line in this table is R8.** In Version 1.0, the outcome "the time-varying Cox model does not outperform the static baseline" was a Medium/Medium risk requiring active mitigation — which is to say, Version 1.0's success was contingent on a performance result it could not guarantee, in a field where ninety-one prior models exist and leaderboard rank does not transfer out of distribution. In Version 2.0, that same outcome is a pre-registered hypothesis whose confirmation and whose rejection are *equally publishable*. **The project cannot fail on performance grounds, because performance is not the contribution.** This is the single strongest argument for the revision.

### 6.5 Resources

- **Data:** PhysioNet credentialed access to MIMIC-IV and eICU-CRD (free). Demo subsets require no credentialing.
- **Compute:** Standard CPU. **No GPU required** for the primary model, all comparators except the optional deep-survival stretch, and the entire evaluation suite. The primary model is a generalized linear model.
- **Storage:** Modest, for extracted cohort and person-hour tables (the largest object; sizing to be confirmed in Phase 2).
- **Software:** R (`ricu` for extraction and harmonisation; `glm`/`nnet`/`VGAM` for the multinomial discrete-time hazard model; `survival` and `rms` for the Cox comparator and Schoenfeld residuals; `discSurv` (Welchowski & Schmid) for discrete-time survival utilities; `dcurves` for decision-curve analysis; `pmsampsize` for the Riley sample-size calculation). Python optional for gradient boosting and the Utility Score. Git/GitHub for version control; reproducible notebooks throughout.
- **Cost:** None. No paid tools, no human-participant data, no GPU compute.

---

## 7. Expected Contributions and Deliverables

### 7.1 Contributions

1. **The first variance decomposition of model versus analyst discretion for real-time sepsis onset prediction on MIMIC-IV.** Cohen et al. (2024) performed the label half of this on MIMIC-III with generic models; Guo et al. (2022) performed the temporal-shift half on MIMIC-IV without varying the label; nobody has done both, for a survival model, with a utility metric.
2. **The first test of whether hazard-type coefficients for sepsis onset are stable across defensible readings of Sepsis-3.** If they are, the field gains a defence of interpretable modelling that it currently lacks. If they are not, then a substantial published literature of hazard ratios and odds ratios for sepsis is, in part, reporting undocumented labelling decisions — which would be a more consequential finding than any new model.
3. **A correctly specified interpretable dynamic survival model for sepsis onset** that requires no proportional-hazards assumption, handles the informative competing risk of discharge, answers the Schoenfeld (2006) objection by construction, and emits the hourly score the field's utility metric consumes.
4. **The first reported conjunction of subgroup performance and subgroup label-sensitivity** for a sepsis model (Wang, Li, Naidech, & Luo, 2022, established each separately).
5. **An open, parameterised, harmonised extraction pipeline**, addressing the low reproducibility that Moor et al. (2021) identify as the field's defining weakness.

### 7.2 Deliverables

| # | Deliverable | Week |
|---|---|---|
| 1 | Pre-registered protocol + PROBAST+AI self-appraisal + sample-size calculation | 2 |
| 2 | Open `ricu`-based, label-parameterised cohort and person-hour pipeline | 7 |
| 3 | **Label-variance table** (cohort size, event count, person-hours × 3 variants) | 7 |
| 4 | Fitted models + coefficient-stability tables across label variants | 11 |
| 5 | Full evaluation suite: Utility Score, calibration, AUPRC, alert burden, DCA, lead time | 15 |
| 6 | External validation (eICU-CRD, or temporal fallback) | 18 |
| 7 | **The variance-decomposition table** | 20 |
| 8 | TRIPOD+AI-conformant dissertation + open code release | 22 |

### 7.3 Scope boundaries

Out of scope: prospective deployment; clinical decision-making; paediatric and neonatal sepsis; biomarker discovery; reinforcement-learning approaches to sepsis *treatment* (as distinct from prediction); waveform-level (sub-hourly) modelling, which would require continuous bedside monitor data the target databases do not contain and a fundamentally different model architecture.

---

## Synthesis & Takeaways

Version 1.0 asked: *can a statistical survival model predict sepsis onset on MIMIC-IV as well as the rule-based scores?* It is a reasonable question, and it was asked in good faith on the basis of a competent literature review. The extended review shows that it is the wrong question, for a specific and instructive reason: **it presupposes that the model is the thing that varies.**

The evidence says otherwise, and it says so with unusual consistency. Cohen et al. (2024) held the data fixed and varied only the reading of the onset rule, and the cohort moved by a factor of 2.5 while performance moved as much as the entire choice of modelling paradigm. Dutta et al. (2026) reproduced that prospectively across 198,494 encounters with a commercial model. Kamran et al. (2024) showed that the label is partly made of clinician behaviour, so that a model predicting it partly predicts the clinician. Lauritsen et al. (2021) showed that framing can reverse the sign of a coefficient — which is to say that the very interpretability that motivates the statistical approach is contingent on choices the field does not document. Guo et al. (2022) showed that a random split on MIMIC-IV flatters a sepsis model more than it flatters any neighbouring task. And Wang et al. (2025) showed that across ninety-one models, AUROC held steady while clinical utility went *negative* — meaning that the metric Version 1.0 nominated as primary is the metric that hides the failure.

Assembled, these findings describe a field in which the model has been the *least* consequential of the analyst's decisions, and the only one anybody reports carefully.

The revised project takes that seriously. It changes the primary model to the one the data's structure actually calls for — a dynamic discrete-time competing-risks hazard model, which D'Agostino et al. (1990) prove is the time-dependent Cox model in the regime that obtains here, and which Heyard et al. (2019, 2020) have already validated as an architecture on ICU data. It promotes the label, the split, the anchoring, and the metric from nuisance parameters to objects of study. And it makes the contribution a **decomposition** rather than a **performance claim** — with the consequence that the project's success no longer depends on winning a competition whose leaderboard, per Reyna et al. (2020), carries approximately zero information about performance at any hospital the model has not seen.

Three properties of the revision are worth stating plainly to a supervisor or examiner.

**It is not a larger project.** The removals — the time-varying Cox partial likelihood on hourly data, group-based trajectory modelling, and the propensity-score/inverse-probability-weighting/E-value apparatus (which are causal-inference instruments with no role in a prediction study) — are heavier than the additions. `ricu` retires the two largest risks Version 1.0 carried.

**It cannot fail on performance grounds.** Version 1.0's risk R3 — "the time-varying Cox model does not outperform the static baseline" — was a genuine threat to the dissertation. In Version 2.0 that same outcome is pre-registered hypothesis H6, and its rejection is as publishable as its confirmation. The first reportable result arrives in Week 7.

**It answers a question the field's strongest recent papers explicitly leave open.** Cohen et al. (2024) did the label half on MIMIC-III with generic models. Guo et al. (2022) did the temporal half on MIMIC-IV without varying the label. Wang et al. (2025) documented the metric divergence across ninety-one studies without controlling any of it. Nobody has held the model fixed and measured how much everything else was doing — and the tools of classical statistics, which Version 1.0 was right to want to use, are unusually well suited to precisely that task.

Version 1.0's instinct was sound. Statistics *does* have something to offer here. The offer is simply not another model. It is the discipline to find out what the models have been measuring.

---

## Bibliography

*APA (7th ed.). Verification notes follow the list.*

Bennett, N., Plečko, D., Ukor, I.-F., Meinshausen, N., & Bühlmann, P. (2023). ricu: R's interface to intensive care data. *GigaScience, 12*, giad041. https://doi.org/10.1093/gigascience/giad041

Christodoulou, E., Ma, J., Collins, G. S., Steyerberg, E. W., Verbakel, J. Y., & Van Calster, B. (2019). A systematic review shows no performance benefit of machine learning over logistic regression for clinical prediction models. *Journal of Clinical Epidemiology, 110*, 12–22. https://doi.org/10.1016/j.jclinepi.2019.02.004

Cohen, S. N., Foster, J., Foster, P., Lou, H., Lyons, T., Morley, S., Morrill, J., Ni, H., Palmer, E., Wang, B., Wu, Y., Yang, L., & Yang, W. (2024). Subtle variation in sepsis-III definitions markedly influences predictive performance within and across methods. *Scientific Reports, 14*(1), 1920. https://doi.org/10.1038/s41598-024-51989-6

Collins, G. S., Moons, K. G. M., Dhiman, P., Riley, R. D., Beam, A. L., Van Calster, B., et al. (2024). TRIPOD+AI statement: Updated guidance for reporting clinical prediction models that use regression or machine learning methods. *BMJ, 385*, e078378. https://doi.org/10.1136/bmj-2023-078378

Cox, D. R. (1972). Regression models and life-tables. *Journal of the Royal Statistical Society: Series B (Methodological), 34*(2), 187–202.

D'Agostino, R. B., Lee, M.-L., Belanger, A. J., Cupples, L. A., Anderson, K., & Kannel, W. B. (1990). Relation of pooled logistic regression to time dependent Cox regression analysis: The Framingham Heart Study. *Statistics in Medicine, 9*(12), 1501–1515. https://doi.org/10.1002/sim.4780091214

Dutta, S., McMurry, R., Tasi, M. C., et al. (2026). Performance of a sepsis prediction model across different sepsis definitions. *JAMA Network Open, 9*(4), e265599. https://doi.org/10.1001/jamanetworkopen.2026.5599

Evans, L., Rhodes, A., Alhazzani, W., et al. (2021). Surviving Sepsis Campaign: International guidelines for management of sepsis and septic shock 2021. *Critical Care Medicine, 49*(11), e1063–e1143. https://doi.org/10.1097/CCM.0000000000005337

Fagerström, J., Bång, M., Wilhelms, D., & Chew, M. S. (2019). LiSep LSTM: A machine learning algorithm for early detection of septic shock. *Scientific Reports, 9*, 15132. https://doi.org/10.1038/s41598-019-51219-4

Fine, J. P., & Gray, R. J. (1999). A proportional hazards model for the subdistribution of a competing risk. *Journal of the American Statistical Association, 94*(446), 496–509. https://doi.org/10.1080/01621459.1999.10474144

Guo, L. L., Pfohl, S. R., Fries, J., Johnson, A. E. W., Posada, J., Aftandilian, C., Shah, N., & Sung, L. (2022). Evaluation of domain generalization and adaptation on improving model robustness to temporal dataset shift in clinical medicine. *Scientific Reports, 12*(1), 2726. https://doi.org/10.1038/s41598-022-06484-1

Henry, K. E., Hager, D. N., Pronovost, P. J., & Saria, S. (2015). A targeted real-time early warning score (TREWScore) for septic shock. *Science Translational Medicine, 7*(299), 299ra122. https://doi.org/10.1126/scitranslmed.aab3719

Heyard, R., Timsit, J.-F., Essaied, W., Held, L., & COMBACTE-MAGNET Consortium. (2019). Dynamic clinical prediction models for discrete time-to-event data with competing risks—A case study on the OUTCOMEREA database. *Biometrical Journal, 61*(3), 514–534.

Heyard, R., Timsit, J.-F., Held, L., & COMBACTE-MAGNET Consortium. (2020). Validation of discrete time-to-event prediction models in the presence of competing risks. *Biometrical Journal, 62*(3), 643–657. https://doi.org/10.1002/bimj.201800293

Johnson, A. E. W., Aboab, J., Raffa, J. D., Pollard, T. J., Deliberato, R. O., Celi, L. A., & Stone, D. J. (2018). A comparative analysis of sepsis identification methods in an electronic database. *Critical Care Medicine, 46*(4), 494–499. https://doi.org/10.1097/CCM.0000000000002965

Johnson, A. E. W., Bulgarelli, L., Shen, L., et al. (2023). MIMIC-IV, a freely accessible electronic health record dataset. *Scientific Data, 10*(1), 1. https://doi.org/10.1038/s41597-022-01899-x

Kamran, F., Tjandra, D., Heiler, A., Virzi, J., Singh, K., King, J. E., Valley, T. S., & Wiens, J. (2024). Evaluation of sepsis prediction models before onset of treatment. *NEJM AI, 1*(3). https://doi.org/10.1056/AIoa2300032

Kasal, J., Jovanovic, Z., Clermont, G., et al. (2004). Comparison of Cox and Gray's survival models in severe sepsis. *Critical Care Medicine, 32*(3). https://doi.org/10.1097/01.CCM.0000114819.37569.4B *(See note b.)*

Lauritsen, S. M., Thiesson, B., Jørgensen, M. J., Riis, A. H., Espelund, U. S., Weile, J. B., & Lange, J. (2021). The framing of machine learning risk prediction models illustrated by evaluation of sepsis in general wards. *npj Digital Medicine, 4*(1), 158. https://doi.org/10.1038/s41746-021-00529-x

Mellhammar, L., Linder, A., Tverring, J., et al. (2020). Scores for sepsis detection and risk stratification—Construction of a novel score using a statistical approach and validation of RETTS. *PLoS ONE, 15*(2), e0229210. https://doi.org/10.1371/journal.pone.0229210

Moons, K. G. M., Damen, J. A. A., Kaul, T., et al. (2025). PROBAST+AI: An updated quality, risk of bias, and applicability assessment tool for prediction models using regression or artificial intelligence methods. *BMJ, 388*, e082505. https://doi.org/10.1136/bmj-2024-082505

Moor, M., Bennett, N., Plečko, D., Horn, M., Rieck, B., Meinshausen, N., Bühlmann, P., & Borgwardt, K. (2023). Predicting sepsis using deep learning across international sites: A retrospective development and validation study. *eClinicalMedicine, 62*, 102124. https://doi.org/10.1016/j.eclinm.2023.102124

Moor, M., Rieck, B., Horn, M., Jutzeler, C. R., & Borgwardt, K. (2021). Early prediction of sepsis in the ICU using machine learning: A systematic review. *Frontiers in Medicine, 8*, 607952. https://doi.org/10.3389/fmed.2021.607952

Nemati, S., Holder, A., Razmi, F., Stanley, M. D., Clifford, G. D., & Buchman, T. G. (2018). An interpretable machine learning model for accurate prediction of sepsis in the ICU. *Critical Care Medicine, 46*(4), 547–553. https://doi.org/10.1097/CCM.0000000000002936

Ngwa, J. S., Cabral, H. J., Cheng, D. M., Pencina, M. J., Gagnon, D. R., LaValley, M. P., & Cupples, L. A. (2016). A comparison of time dependent Cox regression, pooled logistic regression and cross sectional pooling with simulations and an application to the Framingham Heart Study. *BMC Medical Research Methodology, 16*(1), 148. https://doi.org/10.1186/s12874-016-0248-6

Ostermayer, D. G., Braunheim, B., Mehta, A. M., Ward, J., Andrabi, S., & Sirajuddin, A. M. (2024). External validation of the Epic sepsis predictive model in 2 county emergency departments. *JAMIA Open, 7*(4), ooae133. https://doi.org/10.1093/jamiaopen/ooae133

Pollard, T. J., Johnson, A. E. W., Raffa, J. D., Celi, L. A., Mark, R. G., & Badawi, O. (2018). The eICU Collaborative Research Database, a freely available multi-center database for critical care research. *Scientific Data, 5*, 180178. https://doi.org/10.1038/sdata.2018.178

Resche-Rigon, M., Azoulay, E., & Chevret, S. (2006). Evaluating mortality in intensive care units: Contribution of competing risks analyses. *Critical Care, 10*(1), R5. https://doi.org/10.1186/cc3921

Reyna, M. A., Josef, C. S., Jeter, R., Shashikumar, S. P., Westover, M. B., Nemati, S., Clifford, G. D., & Sharma, A. (2020). Early prediction of sepsis from clinical data: The PhysioNet/Computing in Cardiology Challenge 2019. *Critical Care Medicine, 48*(2), 210–217. https://doi.org/10.1097/CCM.0000000000004145

Riley, R. D., Ensor, J., Snell, K. I. E., et al. (2020). Calculating the sample size required for developing a clinical prediction model. *BMJ, 368*, m441. https://doi.org/10.1136/bmj.m441

Riley, R. D., Snell, K. I. E., Ensor, J., Burke, D. L., Harrell, F. E., Jr., Moons, K. G. M., & Collins, G. S. (2019). Minimum sample size for developing a multivariable prediction model: PART II — Binary and time-to-event outcomes. *Statistics in Medicine, 38*(7), 1276–1296. https://doi.org/10.1002/sim.7992

Riley, R. D., Van Calster, B., & Collins, G. S. (2021). A note on estimating the Cox-Snell R² from a reported C statistic (AUROC) to inform sample size calculations for developing a prediction model with a binary outcome. *Statistics in Medicine, 40*(4), 859–864.

Schmid, M., & Berger, M. (2021). Competing risks analysis for discrete time-to-event data. *WIREs Computational Statistics, 13*, e1529. https://doi.org/10.1002/wics.1529

Schoenfeld, D. (2006). Survival methods, including those using competing risk analysis, are not appropriate for intensive care unit outcome studies. *Critical Care, 10*(1), 103. https://doi.org/10.1186/cc3949

Seymour, C. W., Kennedy, J. N., Wang, S., et al. (2019). Derivation, validation, and potential treatment implications of novel clinical phenotypes for sepsis. *JAMA, 321*(20), 2003–2017. https://doi.org/10.1001/jama.2019.5791

Singer, M., Deutschman, C. S., Seymour, C. W., et al. (2016). The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). *JAMA, 315*(8), 801–810. https://doi.org/10.1001/jama.2016.0287

Tutz, G., & Schmid, M. (2016). *Modeling discrete time-to-event data.* Springer.

Van Calster, B., McLernon, D. J., van Smeden, M., Wynants, L., & Steyerberg, E. W. (2019). Calibration: The Achilles heel of predictive analytics. *BMC Medicine, 17*(1), 230. https://doi.org/10.1186/s12916-019-1466-7

van Houwelingen, H. C. (2007). Dynamic prediction by landmarking in event history analysis. *Scandinavian Journal of Statistics, 34*(1), 70–85. https://doi.org/10.1111/j.1467-9469.2006.00529.x

van Houwelingen, H., & Putter, H. (2011). *Dynamic prediction in clinical survival analysis.* Chapman & Hall/CRC.

Vickers, A. J., & Elkin, E. B. (2006). Decision curve analysis: A novel method for evaluating prediction models. *Medical Decision Making, 26*(6), 565–574. https://doi.org/10.1177/0272989X06295361

Wang, H., Li, Y., Naidech, A., & Luo, Y. (2022). Comparison between machine learning methods for mortality prediction for sepsis patients with different social determinants. *BMC Medical Informatics and Decision Making, 22*(Suppl 2), 156. https://doi.org/10.1186/s12911-022-01871-0

Wang, Z., Wang, W., Sun, C., Li, J., Xie, S., Xu, J., Zou, K., Jin, Y., Yan, S., Liao, X., Kang, Y., Coopersmith, C. M., & Sun, X. (2025). A methodological systematic review of validation and performance of sepsis real-time prediction models. *npj Digital Medicine, 8*(1), 190. https://doi.org/10.1038/s41746-025-01587-1

Wong, A., et al. (2026). Multicenter prospective validation of an updated proprietary sepsis prediction model. *JAMA Network Open.* *(See note c.)*

Wong, A., Otles, E., Donnelly, J. P., et al. (2021). External validation of a widely implemented proprietary sepsis prediction model in hospitalized patients. *JAMA Internal Medicine, 181*(8), 1065–1070. https://doi.org/10.1001/jamainternmed.2021.2626

---

### Verification notes

**(a) Truncated author lists.** Where a source is cited with "*et al.*" after three or more named authors, the full author list was **not verified** in this search pass. No author name in this bibliography has been supplied from memory or inference; where the list could not be confirmed against a publisher, PubMed, or PMC record, it was truncated rather than completed.

**(b) Kasal et al. (2004).** Carried forward from the base literature review. DOI reproduced as given there; volume and page metadata **not independently re-derived** in this pass.

**(c) Wong et al. (2026).** First author, title, journal, year, and substantive results (227,091 encounters; four US health systems; AUROC 0.82–0.92; low PPV; high alert burden) confirmed via the PMC record (PMC12949446). **Volume, issue, and article number not captured**; recorded as *not available*.

**(d) Riley, Van Calster, and Collins (2021).** Authors, title, journal, year, volume, and pages confirmed via a citation record; **DOI not verified** in this pass.

**(e) Software references.** The `discSurv` R package (Welchowski & Schmid) and `ricu` demo datasets (`mimic.demo`, `eicu.demo`) are referenced in §5.9 and §6.5 on the basis of the `ricu` documentation and the discrete-time survival literature located in this pass. Package versions are **not fixed** here and must be pinned at Phase 1.

**(f) van Smeden et al.** The finding that there is no rationale for the "ten events per variable" heuristic is referenced in §5.9 on the basis of its citation within the Riley sample-size literature. The **primary reference was not independently retrieved** in this pass and should be located before it is cited in the dissertation.

**(g) Sources cited from the extended literature review.** All other sources above were verified against a publisher, PubMed, PMC, or institutional-repository record during the compilation of the companion extended literature review (13 July 2026), where the full verification notes are recorded.
