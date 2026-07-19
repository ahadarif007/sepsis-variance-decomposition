# Statistical and Machine-Learning Approaches to Real-Time Sepsis Onset Prediction on MIMIC-IV: An Extended Critical Literature Review

**Document type:** Extended literature review (Level 2), superseding and incorporating *A Literature Review of Statistical Modeling Approaches for Real-Time Sepsis Prediction Using the MIMIC-IV Database* (hereafter, "the base review")
**Date of compilation:** 13 July 2026
**Citation style:** APA (7th ed.)

---

## Abstract

The base review synthesised eighteen peer-reviewed statistical studies of sepsis prediction and prognosis on the MIMIC-IV database and concluded that the field exhibits three deficiencies: a bias toward post-diagnosis prognosis over pre-onset detection; an untested proportional-hazards assumption; and an asymmetry in external validation. This extended review interrogates those conclusions against a substantially enlarged evidence base of fifty sources — forty-six verified against publisher, PubMed, or PMC records in this pass, and four carried forward from the base review, drawn from the sepsis-definition literature, the survival-analysis methodology literature, the machine-learning benchmark literature, the deployment and prospective-evaluation literature, and the reporting-standards literature — domains the base review either excluded by design or did not reach.

Three findings materially revise the base review's position. First, the base review's premise that hazard ratios furnish transparent, clinically interpretable quantities is **conditional on a label that the literature shows to be unstable**. Cohen et al. (2024) demonstrate that on MIMIC-III the identified sepsis cohort varies from 867 to 2,178 admissions depending purely on how the Sepsis-3 onset time is operationalised, and that model performance is more sensitive to that choice than to the choice of model. Lauritsen et al. (2021) show that problem framing can reverse the *direction* of a covariate's estimated effect. For a Cox model whose epistemic value rests on the sign and magnitude of its coefficients, this is not a robustness footnote but a threat to the central claim.

Second, the base review's assertion that no statistical onset model has been fitted on a modern MIMIC release is **incorrect as stated**. Fagerström, Bång, Wilhelms, and Chew (2019) fitted a Cox proportional-hazards model on MIMIC-III using Henry et al.'s (2015) exact feature set and target definition, as a head-to-head baseline against an LSTM, and found the LSTM detected septic shock up to twenty hours earlier at comparable sensitivity and specificity. This both narrows the claimed gap and establishes the performance bar any new statistical model must clear.

Third, and most consequentially, the field's evaluation practice is shown to be **actively misleading rather than merely incomplete**. Wang et al. (2025), reviewing ninety-one real-time sepsis prediction models, report that median AUROC declines only modestly under external validation (0.811 internal to 0.783 external, not a statistically significant difference), while the median clinical Utility Score collapses from 0.381 to **−0.164** — that is, from useful to worse than issuing no alert at all. Discrimination is therefore not simply an insufficient metric; it *conceals* the failure it is being used to exclude. Compounding this, Guo et al. (2022) find that among four clinical prediction tasks benchmarked on MIMIC-IV itself, sepsis prediction suffers the **worst** degradation under temporal dataset shift, which means that a random train/test split on MIMIC-IV is optimistically biased for precisely this task.

The synthesis concludes that a study whose contribution is "a Cox model for sepsis onset on MIMIC-IV" is unlikely to be either novel or defensible: ninety-one such models already exist, they do not generalise, and the interpretability that motivates the statistical choice is contingent on a label the field has not stabilised. A reframed research question is proposed, in which the label, the temporal split, and the evaluation metric are promoted from nuisance parameters to objects of study, and the contribution becomes a variance decomposition — how much of the apparent difference between interpretable survival models and machine-learning models is attributable to the model, and how much to the analyst's discretionary choices. A revised set of objectives, a six-phase study plan, and a threats-to-validity register are provided.

**Keywords:** sepsis; MIMIC-IV; survival analysis; discrete-time hazard models; external validation; temporal dataset shift; clinical utility; label definition; TRIPOD+AI

---

## 1. Scope, Method, and Relationship to the Base Review

### 1.1 Rationale for extension

The base review was explicitly scoped to *purely statistical, non-machine-learning* methods, treating machine learning as "an explicit future extension rather than as part of the current scope." That scoping decision was defensible as a way of bounding an initial survey, but it carries a cost that becomes visible only once the boundary is crossed: the most severe threats to a statistical sepsis-onset model on MIMIC-IV have been characterised *in the machine-learning and prediction-methodology literatures*, not in the classical-statistics literature. The label-instability result, the temporal-shift result, the utility-collapse result, and the deployment-failure results all sit outside the base review's perimeter. A review that excludes them does not merely omit context; it omits the evidence that would falsify its own research plan.

This extension therefore deliberately crosses the boundary. It retains the base review's substantive interest — an interpretable, assumption-tested, externally validated statistical model for real-time sepsis onset — but treats the machine-learning literature as the source of *methodological constraints on that project*, rather than as a rival tradition to be surveyed later.

### 1.2 Search and verification procedure

Thirty-five structured searches were executed, spanning the foundational-definition literature through to the 2026 primary literature, targeting: Sepsis-3 and sepsis-identification methodology; the MIMIC-IV and eICU-CRD data resources; survival-analysis methodology for longitudinal and competing-risk settings; sepsis onset-prediction models (statistical and machine-learning); systematic reviews of sepsis prediction; external, temporal, and prospective validation; calibration and clinical-utility metrics; algorithmic fairness in sepsis models; reporting and risk-of-bias standards; and the 2025–2026 MIMIC-IV statistical corpus.

Every source cited in Section 2 was verified against a publisher record, PubMed record, PMC record, or institutional repository entry, and journal, volume, year, and DOI were confirmed. Where a specific numerical claim is reported below, it was located in the abstract, results text, or a publisher-hosted record of the source itself, not inferred from a secondary citation. Four items encountered in secondary citation lists could not be verified to that standard and were therefore **excluded**, and one item is included with an explicit note of incomplete metadata (Section 5, note b). Figures carried forward from the base review that were not re-derived in this pass are marked as such.

This remains a **narrative critical review, not a PRISMA-conformant systematic review**. It makes no claim to exhaustive coverage of the MIMIC-IV sepsis literature, which is large and growing rapidly; it claims instead to have located the methodological literature that bears decisively on the base review's proposed study. Section 4.6 states the limitations of this method.

### 1.3 What is new relative to the base review

| Dimension | Base review | This extension |
|---|---|---|
| Sources | 19 (18 studies + 1 review) | 50 (46 newly verified; 4 carried forward) |
| Scope | Statistical methods only | Statistical + ML + methodology + deployment + standards |
| Label definition | Treated as given (Sepsis-3) | Treated as a **primary source of variance** (§2.2) |
| Validation | Internal vs. external | Internal / temporal / external / prospective, with quantified gradient (§3.2) |
| Evaluation metric | AUC, sensitivity, specificity, lead time | Adds calibration, AUPRC, Utility Score, alert burden, decision curves (§2.7, §3.3) |
| Competing risks | Not addressed | Addressed, including an unresolved methodological dispute (§2.3) |
| Equity | Not addressed | Addressed as a validity requirement (§2.9) |
| Reporting standards | Not addressed | TRIPOD+AI / PROBAST+AI (§2.11) |
| Currency | Corpus to ~2026 (mixed) | Explicit 2025–2026 currency check (§2.10) |
| Central gap claim | Accepted | **Partially falsified** (§3.6) |
---

## 2. Summary by Source

Sources are grouped into eleven thematic clusters. Within each, the summary states what the source establishes, and — where relevant — what it implies for a statistical sepsis-onset model on MIMIC-IV.

### 2.1 Definitions, epidemiology, and data infrastructure

**Singer, M., Deutschman, C. S., Seymour, C. W., et al. (2016).** *The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3).* JAMA, 315(8), 801–810.
Establishes the operative definition: life-threatening organ dysfunction arising from a dysregulated host response to infection, operationalised as an acute rise of at least two points in the SOFA score in a patient with suspected infection. Every source below that speaks of "sepsis onset" is, at bottom, speaking of a *rule for reading two clocks* — the suspicion-of-infection clock and the organ-dysfunction clock — and Section 2.2 shows that the field has not agreed on how to read them.

**GBD 2021 Global Sepsis Collaborators. (2025).** *Global, regional, and national sepsis incidence and mortality, 1990–2021: a systematic analysis.* The Lancet Global Health, 13(12), e2013–e2026.
The current epidemiological anchor, superseding Rudd et al. (2020) for burden estimates. Sepsis-related deaths attributable to infectious underlying causes fell from 11.8 million in 1990 to 8.34 million in 2019, then rose by 86.4% to 15.5 million in 2021; deaths from non-infectious underlying causes rose from 4.69 million to 5.81 million over the full period. The global burden **increased in 2020 and 2021, reversing three decades of progress**. This matters methodologically as well as rhetorically: a disease whose incidence and case-mix moved sharply in 2020–2021 is, by definition, a disease exhibiting distributional shift — which is the subject of §2.6.

**Rudd, K. E., Johnson, S. C., Agesa, K. M., et al. (2020).** *Global, regional, and national sepsis incidence and mortality, 1990–2017: analysis for the Global Burden of Disease Study.* The Lancet, 395(10219), 200–211.
Estimated 48.9 million incident cases (95% UI 38.9–62.9) and 11.0 million sepsis-related deaths (10.1–12.0) in 2017, representing 19.7% of all global deaths (18.2–21.4). Retained as the citation of record for the pre-pandemic baseline.

**Evans, L., Rhodes, A., Alhazzani, W., et al. (2021).** *Surviving Sepsis Campaign: International Guidelines for Management of Sepsis and Septic Shock 2021.* Critical Care Medicine, 49(11), e1063–e1143.
Two provisions bear directly on the base review's study plan. First, the panel issues a **strong recommendation against using qSOFA as a sole screening tool**, on the grounds of poor sensitivity. Second, the guidelines recommend antimicrobials as early as possible, ideally within one hour of recognition. The first provision undermines a benchmark the base review proposes to beat: demonstrating superiority over a score that the governing clinical guideline has already told practitioners not to use for screening is a weak claim. The second establishes the clinical mechanism through which any lead time must be cashed out.

**Johnson, A. E. W., Bulgarelli, L., Shen, L., et al. (2023).** *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data, 10(1), 1.
The resource paper. MIMIC-IV is drawn from the electronic health record of a single institution — Beth Israel Deaconess Medical Center — and this single-centre provenance is the origin of the generalisation problem documented in §2.6. Guo et al. (2022) report the database as containing de-identified records for 382,278 ICU or emergency-department patients.

**Pollard, T. J., Johnson, A. E. W., Raffa, J. D., Celi, L. A., Mark, R. G., & Badawi, O. (2018).** *The eICU Collaborative Research Database, a freely available multi-center database for critical care research.* Scientific Data, 5, 180178.
Over 200,000 ICU admissions across multiple United States hospitals. This is the external-validation cohort the base review's plan nominates, and it remains the correct first choice; §4.4 argues for adding at least one non-US cohort, following Moor et al. (2023).

### 2.2 The label problem: what counts as sepsis onset

This cluster is the single most important addition to the base review, and it is the reason the proposed research question is reframed in §4.2.

**Johnson, A. E. W., Aboab, J., Raffa, J. D., Pollard, T. J., Deliberato, R. O., Celi, L. A., & Stone, D. J. (2018).** *A comparative analysis of sepsis identification methods in an electronic database.* Critical Care Medicine, 46(4), 494–499.
Compared five retrospective algorithms for identifying sepsis, including the Sepsis-3 clinical criteria, in a cohort of 11,791 qualifying ICU admissions drawn from 23,620. Agreement across the five criteria was, on the authors' own assessment, only acceptable — Cronbach's alpha in the range 0.40–0.62. Since these algorithms are the very SQL that MIMIC-based studies run to construct their cohorts, this establishes that "the MIMIC sepsis cohort" is not a single object. Different studies claiming to study the same disease in the same database are, measurably, not studying the same patients.

**Cohen, S. N., Foster, J., Foster, P., Lou, H., Lyons, T., Morley, S., Morrill, J., Ni, H., Palmer, E., Wang, B., Wu, Y., Yang, L., & Yang, W. (2024).** *Subtle variation in sepsis-III definitions markedly influences predictive performance within and across methods.* Scientific Reports, 14(1), 1920.
**The decisive paper for this project.** Working in MIMIC-III, the authors held the data fixed and varied only the interpretation of Sepsis-3 onset time, across three defensible readings of the same consensus definition. The number of identified septic ICU admissions ranged from **867 to 2,178** — a factor of 2.5 — purely as a function of that reading. They then trained representative models spanning tree-based, deep-learning, **and survival-analysis** families under each definition. Two results follow. Holding the definition fixed, the best-performing method gained 1–5% AUROC over its rivals. Holding the method fixed and varying the onset definition produced swings of 0–6% AUROC. In other words, *the analyst's discretionary reading of the label moves performance at least as much as the entire choice of modelling paradigm.*

The implication for a Cox-based project is severe and specific. The base review's justification for preferring statistical models is that they "produce directly interpretable hazard ratios." But a hazard ratio is only interpretable if the event whose hazard is being modelled is a stable object. Cohen et al. show it is not. A reported hazard ratio for, say, lactate on sepsis onset in MIMIC-IV is therefore a joint function of the biology and of an undocumented labelling decision — and the literature currently gives the reader no way to separate them.

**Lauritsen, S. M., Thiesson, B., Jørgensen, M. J., Riis, A. H., Espelund, U. S., Weile, J. B., & Lange, J. (2021).** *The framing of machine learning risk prediction models illustrated by evaluation of sepsis in general wards.* npj Digital Medicine, 4(1), 158.
Introduces a formal vocabulary for *framing*: the observation window, the prediction window, the window shift, and the event that triggers a prediction. The authors enumerate eight possible framing structures and evaluate four of them on the same underlying data. Framing determines both discrimination and calibration. Critically, they report that framing can produce **opposing interpretations of the same physiological variable** — their worked example is SpO₂, whose apparent relationship to sepsis risk reverses direction depending on how the prediction problem is framed. Their conclusion is that a model with strong discrimination *and* strong calibration may nonetheless be clinically unusable.

Taken with Cohen et al., this closes a trap around the interpretability argument. If framing can flip the sign of a coefficient, then the coefficient is reporting a property of the study design as much as a property of the patient. An uninterpretable model that is wrong is a nuisance; an *interpretable* model that is confidently wrong about the direction of a physiological effect is a hazard, because clinicians will act on the direction.

**Kamran, F., Tjandra, D., Heiler, A., Virzi, J., Singh, K., King, J. E., Valley, T. S., & Wiens, J. (2024).** *Evaluation of sepsis prediction models before onset of treatment.* NEJM AI, 1(3).
**The circularity result, and the deepest threat to the whole enterprise.** The Sepsis-3 label is not a purely physiological event. Its "suspected infection" component is operationalised through *clinician actions* — the ordering of a blood culture and the administration of an antibiotic. But clinicians frequently recognise and begin treating sepsis *before* the formal Sepsis-3 criteria are met. A model trained to predict the moment the criteria are met is therefore partly trained to predict **when the clinician will act**, and the physiological signal available at prediction time is contaminated by the clinician's own developing suspicion (through the ordering of tests, the escalation of monitoring, and the recording of observations that would not otherwise exist).

Kamran and colleagues re-evaluated model performance restricted to alerts arriving *before* clinical action, and found that apparent accuracy is substantially inflated when this restriction is not imposed — the model had learned to encode clinician suspicion rather than independent physiological signal. Their co-author Tjandra states the methodological point directly: evaluating a model on data gathered after the clinician has already suspected sepsis makes performance look strong while failing to reflect what would actually help in practice.

The implication for a Cox or discrete-time hazard model on MIMIC-IV is exact and unforgiving. A hazard ratio estimated on the interval up to Sepsis-3 onset is, in part, a hazard ratio *for clinician behaviour*. Lactate is drawn because someone is worried. The "predictor" and the "outcome" share a common cause — the clinician's suspicion — and no amount of proportional-hazards testing will detect this, because the model is correctly estimating the hazard of a contaminated event. The remedy is not statistical but definitional: the evaluation must be anchored to a prediction time that precedes clinical action, and lead time must be measured relative to *clinical recognition*, not to the label.

**Dutta, S., McMurry, R., Tasi, M. C., et al. (2026).** *Performance of a sepsis prediction model across different sepsis definitions.* JAMA Network Open, 9(4), e265599.
**The deployed corroboration of Cohen et al. (2024), and confirmation that the label problem is not a MIMIC artefact.** A locally trained gradient-boosted early-detection model, generating predictions every fifteen minutes across nine acute-care hospitals, was evaluated on 198,494 encounters against *three* electronically computable sepsis definitions: Sepsis-3, the SEP-1 management bundle, and the CDC Adult Sepsis Event. Model performance **varied substantially by definition**, with good discrimination throughout but modest and variable precision and positive predictive value. Expected calibration error differed by definition (0.05 for Sepsis-3, 0.06 for Adult Sepsis Event, 0.07 for SEP-1), and decision-curve analysis showed higher standardised net benefit under Sepsis-3 and SEP-1 than under Adult Sepsis Event. Notably, temporal performance drift was *not* detected over the study period — a useful counterweight to Guo et al. (2022), and a reminder that shift over eighteen months within one health system is a different animal from shift across a decade of MIMIC-IV.

Cohen et al. established definitional sensitivity retrospectively, in MIMIC-III, at n ≈ 2,000, with research models. Dutta et al. reproduce it prospectively, in a live deployment, at n ≈ 200,000, with a commercial model. The finding is therefore robust to dataset, scale, model class, and setting. It should be treated as an established property of the problem, not as a curiosity.

**Seymour, C. W., Liu, V. X., Iwashyna, T. J., et al. (2016).** *Assessment of clinical criteria for sepsis: for the Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3).* JAMA, 315(8), 762–774.
The companion derivation paper for the Sepsis-3 clinical criteria, and the origin of the suspicion-of-infection time window whose parameterisation Cohen et al. later show to be consequential.

**Seymour, C. W., Kennedy, J. N., Wang, S., et al. (2019).** *Derivation, validation, and potential treatment implications of novel clinical phenotypes for sepsis.* JAMA, 321(20), 2003–2017.
Across 63,858 patients in three observational cohorts, derived four clinical sepsis phenotypes (α, β, γ, δ) with distinct laboratory profiles, organ-dysfunction patterns, biomarker correlates, and mortality, and showed by simulation that these phenotypes may modulate treatment effects. This is the clinical warrant for the base review's interest in trajectory modelling: sepsis is not one process, and a single averaged hazard ratio is a summary over a mixture. It is also a warning — a model that performs well on average may perform badly on the phenotype that most needs it.

### 2.3 Survival-analytic foundations and their ICU-specific hazards

**Cox, D. R. (1972).** *Regression models and life-tables.* Journal of the Royal Statistical Society, Series B, 34(2), 187–202.
The origin of the method whose assumptions the remainder of this cluster interrogates.

**Kasal, J., Jovanovic, Z., Clermont, G., et al. (2004).** *Comparison of Cox and Gray's survival models in severe sepsis.* Critical Care Medicine.
Carried forward from the base review. Compared a standard Cox model against Gray's flexible survival model in a large severe-sepsis cohort and found that hazards for death after sepsis are frequently **non-proportional**. The base review correctly identifies this as an under-cited methodological caution.

**Resche-Rigon, M., Azoulay, E., & Chevret, S. (2006).** *Evaluating mortality in intensive care units: contribution of competing risks analyses.* Critical Care, 10(1), R5.
Argues that in ICU cohorts, discharge alive is not a non-informative censoring event: patients discharged alive are systematically unlike those who remain in hospital, so the independent-censoring assumption underlying Kaplan–Meier estimation is violated. The authors demonstrate cumulative incidence functions and the Fine–Gray subdistribution hazard model as the appropriate remedy.

**Fine, J. P., & Gray, R. J. (1999).** *A proportional hazards model for the subdistribution of a competing risk.* Journal of the American Statistical Association, 94(446), 496–509.
The method Resche-Rigon et al. invoke.

**Schoenfeld, D. (2006).** *Survival methods, including those using competing risk analysis, are not appropriate for intensive care unit outcome studies.* Critical Care, 10(1), 103.
The rebuttal — and, importantly for this project, **the dispute has not been resolved**. Schoenfeld's position is that ICU outcome studies should compare the *proportion* of patients dying in hospital, and that studies seeking prognostic covariates should use logistic regression rather than any survival method, competing-risks-corrected or otherwise.

This exchange is directly load-bearing for the base review's plan, which proposes a Cox model on MIMIC-IV and does not engage it. There is no assumption-free route through: a naive Cox model on ICU data violates independent censoring (per Resche-Rigon et al.); a Fine–Gray correction addresses that but attracts Schoenfeld's objection; and, as noted below, landmarking does not restore proportional hazards either. A defensible proposal must **take a position** on this dispute and justify it, rather than pass over it.

**van Houwelingen, H. C. (2007).** *Dynamic prediction by landmarking in event history analysis.* Scandinavian Journal of Statistics, 34(1), 70–85.
**van Houwelingen, H., & Putter, H. (2011).** *Dynamic prediction in clinical survival analysis.* Chapman & Hall/CRC.
The landmarking approach: at each prediction time, refit a survival model on the subset of patients still at risk, conditioning on information observed up to that time. This is the pragmatic route to a continuously updated risk score, and it is what the base review gestures toward in proposing a "time-varying Cox or landmark model."

A caveat the base review does not record: the landmark model does **not** in general satisfy the proportional-hazards assumption. Putter and van Houwelingen's own analysis of the relationship between time-dependent Cox models and landmarking establishes this. Landmarking is therefore not an escape from the proportional-hazards problem; it is a different model with its own approximation error, which happens to be robust in practice.

**Rizopoulos, D. (2011).** *Dynamic predictions and prospective accuracy in joint models for longitudinal and time-to-event data.* Biometrics, 67(3), 819–829.
**Rizopoulos, D., Molenberghs, G., & Lesaffre, E. M. E. H. (2017).** *Dynamic predictions with time-dependent covariates in survival analysis using joint modeling and landmarking.* Biometrical Journal, 59(6), 1261–1276.
The principal alternative: jointly model the longitudinal biomarker trajectories and the event process through shared latent structure. Joint models outperform landmarking when the longitudinal sub-model is correctly specified, but they are computationally expensive, require a common baseline time, and scale poorly to the heterogeneous, irregularly sampled, high-dimensional streams characteristic of an ICU electronic health record. For a MIMIC-IV cohort with dozens of covariates sampled at wildly different frequencies, landmarking is the realistic choice — but it should be chosen with the trade-off stated, not by default.

### 2.4 Statistical models for sepsis onset: the direct precedents

**Henry, K. E., Hager, D. N., Pronovost, P. J., & Saria, S. (2015).** *A targeted real-time early warning score (TREWScore) for septic shock.* Science Translational Medicine, 7(299), 299ra122.
Carried forward from the base review. A Cox proportional-hazards model fitted to MIMIC-II vitals and laboratory values to predict septic shock onset, reported at AUC 0.83 with a median lead time of 28 hours. This remains the canonical statistical benchmark and the origin of the feature set that later work reuses.

**Fagerström, J., Bång, M., Wilhelms, D., & Chew, M. S. (2019).** *LiSep LSTM: A machine learning algorithm for early detection of septic shock.* Scientific Reports, 9, 15132.
**Not identified in the base review, and materially revises its central gap claim.** The authors trained an LSTM network on MIMIC-III using **Henry et al.'s exact input variables and exact septic-shock target definition**, and fitted a **Cox proportional-hazards model on the same data as a direct baseline**. The LSTM detected patients up to **twenty hours earlier** than the Cox model at comparable sensitivity and specificity.

Three consequences follow. (i) A Cox proportional-hazards model *for septic shock onset* has already been fitted on a modern MIMIC release; the base review's statement that this has not been revisited since MIMIC-II is not correct as written. (ii) It has been beaten, on the specific axis — lead time — that motivates the entire enterprise, and beaten by a margin (twenty hours) that dwarfs typical AUROC differences. (iii) Because the comparison was run under a *single fixed label*, it is one of the very few internally valid statistics-versus-ML comparisons in this literature; per Cohen et al. (2024), cross-paper comparisons under differing labels are close to uninterpretable.

The honest reading is that the residual gap is narrower and harder than the base review supposed: it is not "nobody has fitted a Cox model for onset on MIMIC," but "nobody has fitted a *properly specified, assumption-tested, label-sensitivity-analysed, temporally validated* survival model for onset on MIMIC-IV." That is still a real gap — it is simply a more demanding one.

**Liu, R., Greenstein, J. L., Granite, S. J., et al. (2019).** *Data-driven discovery of a novel sepsis pre-shock state predicts impending septic shock in the ICU.* Scientific Reports, 9, 6145.
Develops a statistical-learning characterisation of a "pre-shock" state, and offers a pointed methodological criticism of fixed-horizon prediction designs: a classifier that predicts at a fixed interval prior to onset is only constructible retrospectively, when the onset time is already known. This is an elegant statement of the leakage risk that Lauritsen et al. formalise as framing.

**Morrill, J. H., Kormilitzin, A., Nevado-Holgado, A. J., et al. (2020).** *The signature-based model for early detection of sepsis from electronic health records in the intensive care unit.* Critical Care Medicine.
Carried forward from the base review. Path-signature feature transformation combined with regression, sitting closer to the statistical tradition than most Challenge entries.

**Mellhammar, L., Linder, A., Tverring, J., et al. (2020).** *Scores for sepsis detection and risk stratification — construction of a novel score using a statistical approach and validation of RETTS.* PLoS ONE, 15(2), e0229210.
Carried forward. A LASSO-derived score (SHEWS) that **failed to outperform the existing NEWS2 score**. The base review correctly flags this as a valuable negative result; this extension emphasises that it is also a *direct precedent for the base review's own plan*, which proposes to derive a statistical score and benchmark it against rule-based scores. It has been tried, and it did not work.

### 2.5 Machine-learning benchmarks and the statistics-versus-ML question

**Christodoulou, E., Ma, J., Collins, G. S., Steyerberg, E. W., Verbakel, J. Y., & Van Calster, B. (2019).** *A systematic review shows no performance benefit of machine learning over logistic regression for clinical prediction models.* Journal of Clinical Epidemiology, 110, 12–22.
Across 71 studies selected from 927 screened, the authors found no performance advantage of machine learning over logistic regression for binary clinical outcomes; they also observed potential bias in the validation procedures of 48 studies (68%). This is the strongest available warrant for the base review's decision to treat classical statistics as a serious contender rather than a historical relic — and it should be cited in support of that decision, which the base review does not do.

The warrant has a boundary, however. Christodoulou et al. examined *binary outcomes on tabular data*. Sepsis onset prediction is not that problem: it is a temporal problem over irregularly sampled multivariate streams, where the quantity of interest is a lead time. Fagerström et al. (2019) show that on precisely this axis, the deep model wins substantially. The defensible position is therefore narrower than "statistics is as good as ML": it is *"statistics is as good as ML for static risk stratification, and the temporal early-warning task is the one place where that equivalence has been shown to break."*

**Nemati, S., Holder, A., Razmi, F., Stanley, M. D., Clifford, G. D., & Buchman, T. G. (2018).** *An interpretable machine learning model for accurate prediction of sepsis in the ICU.* Critical Care Medicine, 46(4), 547–553.
The Artificial Intelligence Sepsis Expert (AISE). Developed on roughly 31,000 ICU admissions across two Emory hospitals and validated on over 52,000 MIMIC-III patients, using 65 hourly-computed features. Reported AUROC of 0.83–0.85 for prediction 4, 6, 8, and 12 hours ahead of clinical recognition, with development and validation performance described as indistinguishable. Notably, AISE is a *modified Weibull–Cox proportional hazards* formulation — that is, the leading "machine learning" sepsis model of its generation is itself built on a survival-analytic backbone, which somewhat dissolves the statistics-versus-ML dichotomy the base review erects.

**Desautels, T., Calvert, J., Hoffman, J., et al. (2016).** *Prediction of sepsis in the intensive care unit with minimal electronic health record data: A machine learning approach.* JMIR Medical Informatics, 4(3), e28.
InSight, developed on MIMIC-III using a minimal vital-sign feature set. Establishes the low-data-requirement end of the design space.

**Reyna, M. A., Josef, C. S., Jeter, R., Shashikumar, S. P., Westover, M. B., Nemati, S., Clifford, G. D., & Sharma, A. (2020).** *Early prediction of sepsis from clinical data: The PhysioNet/Computing in Cardiology Challenge 2019.* Critical Care Medicine, 48(2), 210–217.
Discussed in §2.6 for its generalisation finding, and in §2.7 for its Utility Score. Design: 40,336 patient records from two hospital systems released to participants; 22,761 records from three systems held back; 104 teams; 853 entries; the task defined as prediction six hours before clinical recognition of Sepsis-3 sepsis, scored on a purpose-built clinical utility metric that rewards early prediction and penalises late predictions, missed predictions, and false alarms. This is the field's most disciplined benchmark and the source of the hourly-binning convention the base review's Gap 1 correctly identifies as under-justified.

**Moor, M., Rieck, B., Horn, M., Jutzeler, C. R., & Borgwardt, K. (2021).** *Early prediction of sepsis in the ICU using machine learning: A systematic review.* Frontiers in Medicine, 8, 607952.
Systematic review of machine-learning sepsis-onset prediction in adult ICU patients. Principal finding: **low comparability and reproducibility across studies**. The authors give particular attention to case–control matching — specifically, how the "onset time" of a *control* patient is chosen, since a control aligned near discharge is trivially easy to distinguish from a case aligned near sepsis onset, inflating apparent performance. This is a concrete, actionable design trap that the base review's study plan does not currently guard against.

### 2.6 Validation, generalisation, and temporal shift

**Reyna et al. (2020)**, *op. cit.* — the generalisation result.
The Challenge organisers report that team Utility Scores were strongly rank-correlated between the two hospital systems whose data participants had seen during training (Spearman ρ = 0.949), but essentially **uncorrelated** with performance on the third, unseen hospital system (ρ = −0.033 and ρ = 0.013). The ranking of algorithms, in other words, carried almost no information about their performance out of distribution. For any project that intends to select a model by comparing it against published competitors, this is a foundational warning: *leaderboard position on a seen distribution does not predict performance on an unseen one.*

**Moor, M., Bennett, N., Plečko, D., Horn, M., Rieck, B., Meinshausen, N., Bühlmann, P., & Borgwardt, K. (2023).** *Predicting sepsis using deep learning across international sites: a retrospective development and validation study.* eClinicalMedicine, 62, 102124.
The best-quantified external-validation study in the literature. Harmonised 136,478 ICU admissions across four databases spanning the United States, the Netherlands, and Switzerland. Internal (within-site) AUC was 0.846 (95% CI 0.841–0.852); **external (cross-site) AUC fell to 0.761 (95% CI 0.746–0.770)**; with access to a 10% fine-tuning sample from the target site, performance recovered to 0.807 (95% CI 0.801–0.813). The deployed system raised 1.4 false alerts per true alert and detected 80% of septic patients a median of 3.7 hours (95% CI 3.0–4.3) before onset.

Three numbers to carry forward. The external penalty is roughly **0.085 AUC**. Roughly half of it is recoverable by local fine-tuning — which is an argument for site-specific recalibration rather than for a universal model. And the honest lead time of a good modern system is **under four hours**, not the 28 hours of the original TREWScore headline.

**Wang, Z., Wang, W., Sun, C., Li, J., Xie, S., Xu, J., Zou, K., Jin, Y., Yan, S., Liao, X., Kang, Y., Coopersmith, C. M., & Sun, X. (2025).** *A methodological systematic review of validation and performance of sepsis real-time prediction models.* npj Digital Medicine, 8(1), 190.
Ninety-one sepsis real-time prediction models reviewed. Only 54.9% applied full-window validation reporting both model-level and outcome-level metrics. Median AUROC was 0.886 at six hours pre-onset and 0.861 at twelve hours, falling to 0.783 under full-window external validation. Under full-window evaluation, median internal AUROC was 0.811 (IQR 0.760–0.842) and median external AUROC 0.783 (IQR 0.755–0.865) — **a difference the authors report as not statistically significant**.

And then the finding that reorganises the field: the **median Utility Score fell from 0.381 under internal validation to −0.164 under external validation.** A negative Utility Score, on the Challenge metric, means the model does *net harm* relative to issuing no alerts at all. Discrimination barely moved. Clinical value inverted. This is elaborated in §3.3.

**Guo, L. L., Pfohl, S. R., Fries, J., Johnson, A. E. W., Posada, J., Aftandilian, C., Shah, N., & Sung, L. (2022).** *Evaluation of domain generalization and adaptation on improving model robustness to temporal dataset shift in clinical medicine.* Scientific Reports, 12(1), 2726.
**The most directly actionable paper in this review for a MIMIC-IV study.** Partitioned MIMIC-IV ICU patients into year groups (2008–2010, 2011–2013, 2014–2016, 2017–2019) and evaluated four prediction tasks — mortality, long length of stay, **sepsis**, and invasive ventilation — under temporal shift. Two findings.

First, the impact of temporal shift was heterogeneous across tasks, and **the worst-affected task was sepsis prediction**. A model trained on 2008–2010 and applied to 2017–2019 produced, in the authors' illustrative framing, one additional false negative among every eleven septic patients per hundred consecutive admissions, relative to the model applied in-period.

Second, domain-generalisation and unsupervised domain-adaptation algorithms **failed to beat plain empirical risk minimisation** (AUROC differences ranging from −0.003 to 0.050). There is, at present, no algorithmic fix.

The consequence is precise and unavoidable: **a random train/test split on MIMIC-IV is optimistically biased for the sepsis task specifically.** The base review's Phase 3 proposes to "validate internally via train/test split." As written, that design will overstate the model's performance, and it will do so more for this outcome than for any of the neighbouring ICU outcomes a reader might use to calibrate their scepticism.

**Nestor, B., McDermott, M. B. A., Boag, W., et al. (2019).** *Feature robustness in non-stationary health records: caveats to deployable model performance in common clinical machine learning tasks.* Proceedings of Machine Learning for Healthcare (PMLR).
Complements Guo et al. by showing that measured non-stationarity in MIMIC is driven substantially by **changes in the hospital's information systems** — an EHR transition — rather than by change in the underlying patient population. Shift in these databases is partly an artefact of institutional record-keeping, which is a caution against interpreting drift-driven coefficient changes as biology.

### 2.7 Calibration, clinical utility, and alert burden

**Van Calster, B., McLernon, D. J., van Smeden, M., Wynants, L., & Steyerberg, E. W., on behalf of Topic Group 'Evaluating diagnostic tests and prediction models' of the STRATOS initiative. (2019).** *Calibration: the Achilles heel of predictive analytics.* BMC Medicine, 17(1), 230.
Argues that calibration — the correspondence between predicted probability and observed event frequency — receives far too little attention, and that poorly calibrated models are actively misleading and potentially harmful for clinical decision-making. Any model intended to drive a threshold-based action ("alert if predicted risk exceeds x") is a calibration-dependent instrument, whatever its AUROC. The base review's objectives list discrimination and lead time; calibration appears only implicitly, via decision curve analysis. That is insufficient.

**Reyna et al. (2020)**, *op. cit.* — the Utility Score.
The Challenge's contribution to evaluation methodology is a metric that assigns a positive reward for a true prediction made in a clinically useful window, a diminishing reward for a late one, and explicit penalties for missed detections and false alarms. It is, uniquely in this literature, a metric that can go **negative** — which is what makes Wang et al.'s (2025) external median of −0.164 legible.

**Moor et al. (2023)**, *op. cit.* — the alert-burden benchmark: 1.4 false alerts per true alert. Any proposed model should report this quantity, and a figure substantially worse than 1.4 should be treated as disqualifying rather than as a limitation to be noted in the discussion.

**Multisite external validation of Duke Health's Sepsis Watch model. (2025).** npj Digital Medicine. DOI: 10.1038/s41746-025-01664-5. *(See Section 5, note b, regarding incomplete author metadata.)*
Across 205,005 encounters from 101,584 patients at four community emergency-department sites, AUROC ranged from **0.906 to 0.960** — while AUPRC ranged from **0.177 to 0.252**. The divergence is the point. Under the low event prevalence characteristic of sepsis screening, a model can post a near-ceiling AUROC while its precision–recall performance remains poor, because AUROC is insensitive to the vast excess of true negatives. Reporting AUROC alone in a low-prevalence setting is not merely incomplete; it is flattering by construction.

### 2.8 Deployment, prospective evidence, and harm

**Wong, A., Otles, E., Donnelly, J. P., et al. (2021).** *External validation of a widely implemented proprietary sepsis prediction model in hospitalized patients.* JAMA Internal Medicine, 181(8), 1065–1070.
The Epic Sepsis Model, deployed across hundreds of United States hospitals, evaluated on 38,455 hospitalisations of 27,697 patients at Michigan Medicine between December 2018 and October 2019. AUC of **0.63** (95% CI 0.62–0.64); sensitivity 33%; specificity 83%; positive predictive value 12%; negative predictive value 95%. A model with a 12% PPV generates roughly seven false alerts for every true one.

**Habib, A. R., Lin, A. L., & Grant, R. W. (2021).** *The Epic Sepsis Model falls short — the importance of external validation.* JAMA Internal Medicine, 181(8), 1040–1041.
The accompanying editorial, which frames the episode as a failure of external validation rather than of modelling technique per se.

**Ostermayer, D. G., Braunheim, B., Mehta, A. M., Ward, J., Andrabi, S., & Sirajuddin, A. M. (2024).** *External validation of the Epic sepsis predictive model in 2 county emergency departments.* JAMIA Open, 7(4), ooae133.
A second, independent external validation across 145,885 emergency-department encounters. Within a six-hour window, sensitivity was **14.7%**, specificity 95.3%, PPV 7.6%, NPV 97.7%. Performance was worse than in Wong et al. — that is, the failure replicated and deepened in a different care setting and a different patient mix.

**Wong, A., et al. (2026).** *Multicenter prospective validation of an updated proprietary sepsis prediction model.* JAMA Network Open. *(See Section 5, note c, regarding incomplete volume metadata.)*
**The qualification — and it is an important one, because it cuts against this review's own narrative.** Epic's version 1 model was a logistic regression; version 2 is a gradient-boosted tree ensemble that can be **locally retrained** at the implementing institution. Across 227,091 inpatient encounters at four large United States health systems (August 2023 to March 2025), version 2 achieved AUROC between **0.82 and 0.92** — a very large improvement on version 1's 0.63 (Wong et al., 2021). However, the authors report high institutional variability, low positive predictive value, and high alert burden, and they recommend that implementing institutions conduct local validation, integrate workflows to absorb false positives, and adopt alert-silencing strategies.

Two readings are available and they should both be stated. The uncharitable reading of Christodoulou et al. (2019) — that logistic regression is never beaten — does not survive this result: the model class changed from logistic regression to gradient boosting and discrimination improved enormously. The more careful reading is that version 2 also changed from *globally trained* to *locally trainable*, and Moor et al. (2023) have already shown that local fine-tuning recovers roughly half of the external penalty (0.761 → 0.807). The improvement is therefore confounded between model class and localisation, and the published evidence does not permit the two to be separated.

What is *not* ambiguous is that PPV remained low and alert burden high even at AUROC 0.92. This is the AUROC illusion of §3.3, observed in the field's largest deployment: discrimination near ceiling, clinical usability still contested.

**Adams, R., Henry, K. E., Sridharan, A., et al. (2022).** *Prospective, multi-site study of patient outcomes after implementation of the TREWS machine learning-based early warning system for sepsis.* Nature Medicine, 28(7), 1455–1460.
The strongest positive deployment evidence in the field. TREWS monitored 590,736 patients across five hospitals; the analysis focused on 6,877 septic patients flagged before antibiotics were initiated. Adjusting for presentation and severity, patients whose alert was confirmed by a clinician within three hours showed a 3.3% absolute reduction in in-hospital mortality (95% CI 1.7–5.1) and an 18.7% relative reduction (95% CI 9.4–27.0), with reductions in organ failure and length of stay.

**Henry, K. E., Adams, R., Parent, C., et al. (2022).** *Factors driving provider adoption of the TREWS machine learning-based early warning system and its effects on sepsis treatment timing.* Nature Medicine, 28(7), 1447–1454.
The companion paper: alert confirmation within three hours was associated with a 1.85-hour reduction (95% CI 1.66–2.00) in time to antibiotic ordering.

*Critical note.* The Adams et al. design compares patients whose alerts clinicians *chose to confirm quickly* against those whose alerts they did not. Whether clinician responsiveness is itself a marker of patient legibility — that is, whether the sickest and most obviously septic patients are also the ones whose alerts get confirmed fastest — is a confounding-by-indication question that has been raised in the subsequent literature and contested by the original authors. The exchange occurred substantially in preprint and commentary form and is therefore not cited here as settled evidence, but the reader should treat the 3.3% figure as an association under a strong and disputed adjustment, not as a causal effect.

**Shimabukuro, D. W., Barton, C. W., Feldman, M. D., Mataraso, S. J., & Das, R. (2017).** *Effect of a machine learning-based severe sepsis prediction algorithm on patient survival and hospital length of stay: a randomised clinical trial.* BMJ Open Respiratory Research, 4(1), e000234.
**The only randomised controlled trial in this literature.** Two medical–surgical ICUs at a single centre (UCSF), 32 monitored beds, conducted from December 2016 to February 2017.

The significance of this source is what it reveals about the evidence base as a whole. Ninety-one real-time sepsis prediction models exist (Wang et al., 2025). Exactly one has been tested in a randomised trial, and that trial ran for three months in thirty-two beds at one hospital. The gap between the volume of modelling activity and the volume of interventional evidence is the field's defining pathology, and no additional retrospective model — statistical or otherwise — narrows it.

**Seymour, C. W., Gesten, F., Prescott, H. C., et al. (2017).** *Time to treatment and mortality during mandated emergency care for sepsis.* New England Journal of Medicine, 376(23), 2235–2244.
Across 49,331 patients at 149 New York hospitals, each additional hour to completion of the three-hour sepsis bundle was associated with an odds ratio of 1.04 for in-hospital mortality (95% CI 1.02–1.05), and each additional hour to antibiotic administration with an odds ratio of 1.04 (95% CI 1.03–1.06). Time to completion of an intravenous fluid bolus showed no significant association (OR 1.01; 95% CI 0.99–1.02; P = 0.21).

This is the source of the field's justifying premise — and it also bounds it. If the hazard of delay is approximately 4% per hour on the odds scale, then a model delivering the 3.7-hour honest lead time reported by Moor et al. (2023), *and* achieving perfect clinician response, would purchase an odds-ratio improvement on the order of 1.04³·⁷ ≈ 1.16. That is a real but modest effect, and it is available only if the alert is acted upon, only if the patient would not otherwise have been recognised, and only after the false alerts have been paid for. The arithmetic is the present author's, applied to Seymour et al.'s reported estimates; but it is arithmetic that any proposal in this space should perform explicitly rather than leave implicit.

### 2.9 Equity and subgroup validity

**Wang, H., Li, Y., Naidech, A., & Luo, Y. (2022).** *Comparison between machine learning methods for mortality prediction for sepsis patients with different social determinants.* BMC Medical Informatics and Decision Making, 22(Suppl 2), 156.
Analysed 11,791 MIMIC-III critical-care patients, of whom 5,783 met Sepsis-3 criteria. Two findings, and the second depends on the first.

First, the *six* competing sepsis identification criteria selected systematically different sub-populations with respect to race, marital status, insurance type, and language. Who counts as septic in MIMIC is not demographically neutral.

Second, mortality-prediction performance degraded significantly when a model trained on the full population was applied to Asian patients, Hispanic patients, and Spanish-speaking patients; pairwise testing detected significant discrepancies between Asian and White patients, between Asian patients and patients of other races, and between English-speaking and Spanish-speaking patients.

The conjunction is what matters. The label is differentially sensitive by subgroup, *and* model performance is differentially poor for the same subgroups. Subgroup analysis is therefore not a robustness check to be appended in a sensitivity section; it is a validity requirement, and it is entangled with the label problem of §2.2. The base review does not address equity at all.

### 2.10 Currency check: the MIMIC-IV statistical corpus, 2025–2026

A targeted scan of the most recent MIMIC-IV sepsis literature was performed to test whether the base review's characterisation still holds in mid-2026. It does — with one qualification.

The dominant form remains what the base review's Theme C identified: a candidate biomarker or composite index is regressed on mortality, using an almost invariant analytic pipeline of LASSO or Boruta variable selection, followed by Cox and/or logistic regression, restricted cubic splines for non-linearity, Kaplan–Meier curves with log-rank tests, a nomogram, and ROC, calibration, and decision-curve analyses. Representative examples located in this pass, all published in 2025–2026, include: the endothelial activation and stress index as a predictor of 28-day mortality in pulmonary sepsis (MIMIC-IV, n = 5,416, with an external tertiary-hospital cohort from 2022–2025); the creatinine-to-albumin ratio in sepsis-associated acute kidney injury (MIMIC-IV v2.2, n = 2,712, externally validated in 412 patients); nine inflammation-derived haematological indices for 28-day mortality (MIMIC-IV development, Guangxi Medical University external validation, with a 24-hour landmark); the albumin-to-neutrophil-lymphocyte ratio (MIMIC-IV v3.1, n = 6,288); a nomogram for in-hospital mortality in intra-abdominal sepsis (MIMIC-IV development, eICU external validation); and a four-predictor day-1 nomogram for sepsis-associated encephalopathy (MIMIC-IV 2008–2022, n = 6,780).

**The qualification is a genuine improvement:** external validation is now common in this sub-literature, rather than exceptional. The base review's Gap 3 — a validation asymmetry — is therefore closing on the prognosis side.

**The gap that remains open is exactly the one the base review named.** Every study located in this scan predicts an outcome *after* sepsis has been diagnosed. Not one predicts onset. As of mid-2026, the pre-onset statistical modelling gap on MIMIC-IV is still open. This is now an empirically checked claim rather than an asserted one.

One further datum from this scan is worth recording, because it shows the field naming its own gap. A 2025 *Scientific Reports* study applying survival analysis to sepsis patients lists, among its stated limitations, that it lacks external validation, that the proportional-hazards assumption may not hold across covariates or subgroups, and that it incorporates neither time-varying covariates nor competing risks. The methodological deficits the base review identifies are no longer unrecognised by the field; they are being confessed in limitations sections while the pipeline continues unchanged.

### 2.11 Reporting and appraisal standards

**Collins, G. S., Reitsma, J. B., Altman, D. G., & Moons, K. G. M. (2015).** *Transparent reporting of a multivariable prediction model for individual prognosis or diagnosis (TRIPOD): the TRIPOD statement.* BMJ, 350, g7594.

**Collins, G. S., Moons, K. G. M., Dhiman, P., Riley, R. D., Beam, A. L., Van Calster, B., et al. (2024).** *TRIPOD+AI statement: updated guidance for reporting clinical prediction models that use regression or machine learning methods.* BMJ, 385, e078378.
Supersedes TRIPOD 2015 and is explicitly designed to cover **both regression and machine-learning** prediction models — which is to say, the reporting standard has already abandoned the statistics-versus-ML dichotomy that the base review's scoping relies upon. A study reporting a Cox model for sepsis onset in 2026 is a TRIPOD+AI study.

**Moons, K. G. M., Damen, J. A. A., Kaul, T., Hooft, L., Andaur Navarro, C., Dhiman, P., et al. (2025).** *PROBAST+AI: an updated quality, risk of bias, and applicability assessment tool for prediction models using regression or artificial intelligence methods.* BMJ, 388, e082505.
The corresponding risk-of-bias instrument. A self-appraisal against PROBAST+AI should be conducted at design time, not at write-up, because several of its domains — participant selection, outcome definition, and analysis — are precisely where the label problem of §2.2 does its damage, and they cannot be repaired retrospectively.

**Fleuren, L. M., Klausch, T. L. T., Zwager, C. L., et al. (2020).** *Machine learning for the prediction of sepsis: a systematic review and meta-analysis of diagnostic test accuracy.* Intensive Care Medicine, 46(3), 383–400.
Carried forward from the base review. Found that machine-learning models can predict sepsis onset ahead of time on retrospective data, with substantial between-study heterogeneity limiting pooled comparison — heterogeneity that Cohen et al. (2024) later show is partly attributable to label variation rather than to genuine methodological difference.
---

## 3. Comparative Analysis

### 3.1 Two literatures, one database, and a false dichotomy

The base review organises the field as two traditions — classical statistics and machine learning — and elects to survey the first while deferring the second. The enlarged evidence base does not support that partition.

Consider the boundary cases. The Artificial Intelligence Sepsis Expert (Nemati et al., 2018), routinely classified as a machine-learning system, is built on a modified Weibull–Cox proportional-hazards formulation. TREWScore (Henry et al., 2015), the base review's foundational *statistical* benchmark, is described throughout the machine-learning literature as an early machine-learning early-warning system, and its commercial successor TREWS is marketed as such (Adams et al., 2022). The signature-based model (Morrill et al., 2020) applies a feature transformation from rough-path theory and then regresses. Cohen et al. (2024) place tree-based, deep-learning, and survival-analysis models in a single comparison frame because the distinction is not load-bearing for the question they ask. And TRIPOD+AI (Collins et al., 2024) — the governing reporting standard — covers "regression **or** machine learning" under a single checklist, having concluded that the reporting problems are common to both.

The partition that *is* load-bearing runs elsewhere. It separates models by **what they assume about time**:

- **Static models** take a snapshot (baseline, or day 1, or the worst value in the first 24 hours) and issue one prediction. Almost the entire MIMIC-IV statistical corpus surveyed in the base review's Theme C, and in the 2025–2026 refresh of §2.10, sits here — including the LASSO-plus-nomogram cluster. These are *prognostic* instruments and cannot, in principle, perform real-time onset detection.
- **Dynamic models** consume a stream and update a risk estimate as it arrives. TREWScore, AISE, LiSep, the Challenge entries, Moor et al.'s deep model, landmark models, and joint models sit here. Whether the update rule is a Cox partial likelihood, a recurrent network, or a gradient-boosted hazard is a *secondary* question.

Reframing the taxonomy this way clarifies the base review's own finding. Its central observation — that MIMIC-IV statistical work is overwhelmingly prognostic rather than pre-onset — is not really a fact about *statistics*. It is a fact about *static* models, which happen to be the ones the biomarker-association literature reaches for, because that literature is asking an aetiological question ("is index X associated with death?") and not a prediction question at all. The base review has, in effect, discovered that association studies are not prediction studies. That is a correct and useful observation, but it does not license the inference that *statistical* methods have neglected onset prediction — because Henry et al. (2015), Fagerström et al. (2019), and the survival-analysis arm of Cohen et al. (2024) did not.

### 3.2 The generalisation gradient

Assembling the validation evidence into a single comparison exposes a strikingly consistent structure.

| Study | Model | Setting | Internal | External / prospective | Δ |
|---|---|---|---|---|---|
| Nemati et al. (2018) | AISE (Weibull–Cox) | Emory → MIMIC-III | AUROC 0.83–0.85 | Reported as indistinguishable | ≈ 0 |
| Reyna et al. (2020) | 853 Challenge entries | 2 seen systems → 1 unseen | ρ = 0.949 (rank, seen-to-seen) | **ρ = −0.033, 0.013** (rank, to unseen) | Rank information ≈ 0 |
| Moor et al. (2023) | Deep temporal model | 4 international ICU databases | AUC 0.846 | AUC 0.761 (0.807 with 10% fine-tuning) | **−0.085** |
| Wang et al. (2025) | 91 SRPMs (meta-level) | Mixed | AUROC 0.811; Utility 0.381 | AUROC 0.783 (n.s.); **Utility −0.164** | AUROC −0.028; **Utility −0.545** |
| Wong et al. (2021) | Epic Sepsis Model | Proprietary → Michigan | Vendor-reported 0.73–0.83 | **AUC 0.63**; PPV 12% | ≈ −0.15 |
| Ostermayer et al. (2024) | Epic ESPM v1 | Proprietary → 2 county EDs | — | **Sensitivity 14.7%; PPV 7.6%** | Worse still |
| Guo et al. (2022) | Feed-forward NN | MIMIC-IV, within-database, across years | — | Sepsis = **worst-degraded** of four tasks | Task-specific |

*Note.* Nemati et al.'s internal-external equivalence is the exception, and it is instructive: their "external" set (MIMIC-III) shares an era, a country, and a care model with the development set (Emory), which is a mild distribution shift by the standards of Moor et al.'s Netherlands-and-Switzerland comparison. The apparent counter-example is better read as evidence that the *magnitude* of the external penalty scales with the *distance* of the shift.

Three regularities follow.

**(a) The external penalty for a well-built model is roughly 0.08–0.09 AUC.** This is Moor et al.'s 0.846 → 0.761, and it is consistent with the direction, if not the significance, of Wang et al.'s meta-level 0.811 → 0.783. Any proposal should pre-specify this as the expected degradation and treat a smaller observed drop as evidence of insufficiently distant external data rather than as evidence of an unusually robust model.

**(b) Proprietary deployed models perform far worse than the research literature would predict.** The Epic Sepsis Model's 0.63 (Wong et al., 2021) and the county-ED sensitivity of 14.7% (Ostermayer et al., 2024) sit outside the distribution of published research AUROCs entirely. This is a publication-bias signature, and it is the strongest available argument that the retrospective literature systematically overstates what is achievable.

**(c) Rank order does not transfer.** Reyna et al.'s near-zero rank correlation to the unseen hospital system is, for the purposes of the present project, the most subversive finding in the entire corpus. It says that if one selects a modelling approach by consulting the published performance of competing approaches, one is consulting a signal with approximately no out-of-distribution content. The base review's Objective 4 — to benchmark the proposed model's discriminative performance against SIRS, qSOFA, and NEWS — is therefore under-specified: the benchmark is only informative if it is run *on the same data, under the same label, with the same split*, and even then it licenses no inference about which model would win at a different hospital.

### 3.3 The AUROC illusion

The single most important comparison in this review is between two rows of the table above, both drawn from Wang et al. (2025):

- Median AUROC, internal → external: **0.811 → 0.783** (reported as not statistically significant).
- Median Utility Score, internal → external: **0.381 → −0.164**.

The same models, the same transition, and two metrics that tell opposite stories. Discrimination is essentially preserved. Clinical utility inverts — from meaningfully positive to *negative*, meaning that on the Challenge's utility calculus, deploying the median externally validated sepsis prediction model is worse than deploying nothing.

The mechanism is not mysterious. AUROC is a ranking statistic: it asks whether septic patients receive higher scores than non-septic patients, and it is invariant to any monotone transformation of the score. It therefore cannot see miscalibration, and under low prevalence it is dominated by the enormous population of easily-classified true negatives. What changes across sites is not primarily the *ordering* of patients but the *location* of the score distribution relative to the alerting threshold — which is precisely what determines the false-alarm rate, and therefore the utility. Van Calster et al. (2019) name this the Achilles heel; the Sepsis Watch validation makes it visible in a second way, reporting AUROC between 0.906 and 0.960 alongside AUPRC between 0.177 and 0.252 across the same four sites.

The consequence for the base review's evaluation plan is direct and, I think, unavoidable. Its Objective 4 nominates AUC, sensitivity, specificity, and lead time. On the evidence above, **a study reporting those four quantities and concluding that its model generalises would have failed to measure the thing that fails.** Calibration (intercept and slope, plus a flexible calibration curve), AUPRC, the Utility Score, alert burden, and decision-curve analysis are not enhancements to that list; they are the list.

### 3.4 Does interpretability survive the label problem?

The base review's core argument for the statistical tradition is epistemic rather than performance-based: hazard ratios are interpretable, assumptions are checkable, and the model can be transparently benchmarked against rule-based scores. Christodoulou et al. (2019) supply the supporting premise that little or no discriminative performance is sacrificed by this choice.

Cohen et al. (2024) and Lauritsen et al. (2021) jointly attack the argument at its root. If the identified cohort varies by a factor of 2.5 with the reading of the onset rule, and if problem framing can *reverse the sign* of a covariate's estimated association, then a hazard ratio reported without an accompanying label-sensitivity analysis is not an interpretable quantity. It is a number whose provenance is partly biological and partly bureaucratic, and the reader is given no means of decomposing it.

This does not defeat the case for interpretable models. It relocates it. The interpretability of a statistical model is a **conditional** property: it holds *given a stable and explicitly specified estimand*. The field has not supplied one. And here the argument turns, because the discipline required to supply one is exactly the discipline that classical statistics is better equipped to impose than deep learning is. A hazard ratio that is shown to be stable across three defensible readings of the Sepsis-3 onset rule is a genuinely interpretable quantity; a hazard ratio that is shown to *flip* across those readings is a genuinely important negative result. Either way, the analysis is informative — and it is an analysis that essentially nobody in this literature has performed for a survival model on MIMIC-IV.

That observation is the seed of the reframed research question in §4.2.

### 3.5 The unresolved survival-methods dispute

The base review proposes a Cox model and identifies the proportional-hazards assumption as the assumption to test. The enlarged evidence base shows that the assumption problem is deeper and has no clean resolution:

1. **Proportional hazards frequently fails** in sepsis cohorts (Kasal et al., 2004).
2. **Independent censoring also fails**, because discharge alive is an informative competing event (Resche-Rigon et al., 2006). The standard remedy is the Fine–Gray subdistribution hazard model (Fine & Gray, 1999).
3. **The remedy is itself contested.** Schoenfeld (2006) argues that survival methods, explicitly including competing-risks methods, are inappropriate for ICU outcome studies, and that logistic regression on in-hospital death is preferable.
4. **Landmarking does not restore proportional hazards.** The landmark model does not in general satisfy the PH assumption, a point established in van Houwelingen and Putter's own treatment of the method (van Houwelingen, 2007; van Houwelingen & Putter, 2011).
5. **Joint models restore rigour at a cost** in computation, in the requirement for a common baseline time, and in sensitivity to misspecification of the longitudinal sub-model (Rizopoulos, 2011; Rizopoulos et al., 2017) — costs that are prohibitive at MIMIC-IV's dimensionality and sampling irregularity.

There is no assumption-free route. What there *is*, however, is a formulation that the base review does not consider and that dissolves several of these problems simultaneously: the **discrete-time hazard model**, fitted as a pooled logistic regression over person-hour records with time-varying covariates and a flexible baseline hazard.

Its properties are worth stating plainly, because it appears to be the right primary model for this project:

- It is **native to the data's actual structure.** ICU data is already binned hourly by convention (Reyna et al., 2020; Nemati et al., 2018). A discrete-time hazard model *is* an hourly risk score; no reconciliation between the model's time scale and the deployment's time scale is required.
- It **does not require proportional hazards.** Time-varying coefficients are natural, not an extension. The base review's Gap 2 is dissolved rather than tested.
- It **accommodates competing risks** directly via a multinomial or cause-specific formulation over the person-hour, so that discharge alive and death without sepsis are modelled as what they are.
- It is **fully interpretable**: coefficients are log-odds of onset in the next hour, given survival sepsis-free to this hour — arguably a *more* clinically legible quantity than a hazard ratio.
- It **answers Schoenfeld's objection**, being a logistic regression, while retaining the time-to-event structure Schoenfeld would discard.
- It is **directly comparable to the machine-learning literature**, because it emits exactly the object the Challenge utility metric consumes: an hourly risk score.

The base review's Phase 2 proposes to "fit a Cox proportional hazards model … and formally test the proportional-hazards assumption … extend to a time-varying Cox or landmark model." The recommendation here is stronger: **do not begin with a static Cox model at all.** Begin with the discrete-time hazard model, and use the static Cox as a deliberately weak comparator to quantify what the field's default choice costs.

### 3.6 Where the base review's gap claims hold — and where they do not

| Base review claim | Verdict | Basis |
|---|---|---|
| **Gap 1.** MIMIC-IV statistical work is dominated by post-diagnosis prognosis, not pre-onset detection | **Upheld, and re-confirmed for 2025–2026** | §2.10 currency scan: every located 2025–26 MIMIC-IV statistical study is prognostic |
| Gap 1 (corollary): temporal resolution and prediction mechanism are rarely justified | **Upheld and strengthened** | Lauritsen et al. (2021) formalise framing; Moor et al. (2021) identify control-alignment as a specific unaddressed trap |
| **Gap 2.** The proportional-hazards assumption is untested in MIMIC-IV Cox work | **Upheld as a claim about reporting; superseded as a research direction** | Correct that PH testing is not reported. But PH is one of *at least three* failing assumptions (§3.5), and the discrete-time formulation dissolves it rather than testing it |
| **Gap 3.** External validation is absent from onset-prediction work | **Substantially overtaken** | External validation is now standard in the prognosis literature (§2.10); and for onset prediction it is not merely absent but *quantified as failing* (Moor et al., 2023; Reyna et al., 2020; Wang et al., 2025) |
| **Claim.** No statistical onset model has been fitted on a modern MIMIC release since Henry et al. (2015) on MIMIC-II | **Falsified** | Fagerström et al. (2019) fitted a Cox PH model on MIMIC-III with Henry et al.'s features and target, and were beaten by an LSTM by up to 20 hours of lead time |
| **Claim.** This is the first review to synthesise the classical-statistics MIMIC-IV sepsis literature as a distinct category | **Plausible but of doubtful value** | The category does not carve the field at its joints (§3.1); the informative partition is static vs. dynamic, not statistical vs. ML |
| **Implicit premise.** Hazard ratios furnish transparent, interpretable clinical quantities | **Conditional, and the condition is unmet** | Cohen et al. (2024); Lauritsen et al. (2021) — see §3.4 |
| **Unaddressed.** Temporal dataset shift within MIMIC-IV | **Critical omission** | Guo et al. (2022): sepsis is the worst-affected of four MIMIC-IV tasks; random splits are optimistically biased |
| **Unaddressed.** Subgroup and equity validity | **Critical omission** | Wang, Li, Naidech, & Luo (2022) |
| **Unaddressed.** Calibration and clinical utility as primary endpoints | **Critical omission** | Wang et al. (2025): utility inverts while AUROC holds |
---

## 4. Synthesis & Takeaways

### 4.1 Twelve propositions the evidence supports

1. **Sepsis onset is not a well-defined event.** Five to six defensible identification algorithms disagree substantially (Johnson et al., 2018), the identified cohort varies by a factor of 2.5 with the reading of the onset rule (Cohen et al., 2024), and this sensitivity reproduces prospectively at scale in a live deployment (Dutta et al., 2026).

2. **Label choice moves performance at least as much as model choice.** Definition variation produces swings of 0–6% AUROC; the best model gains 1–5% (Cohen et al., 2024). Any paper reporting the second without the first is reporting noise as signal.

3. **The label is contaminated by clinician behaviour.** Sepsis-3 onset is partly defined by clinician actions (culture, antibiotic), and models trained to predict it partly learn to predict clinician suspicion (Kamran et al., 2024). This is a threat to *causal interpretation* of coefficients, not merely to performance.

4. **Framing can reverse the sign of an estimated effect** (Lauritsen et al., 2021). This is fatal to an unqualified interpretability claim.

5. **Cross-paper performance comparisons in this literature are close to meaningless**, because labels, cohorts, framings, and splits differ (Cohen et al., 2024; Moor et al., 2021; Fleuren et al., 2020). Only within-study, same-label, same-split comparisons carry information.

6. **The external-validation penalty for a well-built model is roughly 0.08–0.09 AUC**, of which about half is recoverable by local fine-tuning (Moor et al., 2023).

7. **AUROC conceals the failure it is used to exclude.** Median AUROC falls only 0.028 from internal to external validation (not statistically significant), while median clinical Utility Score falls from +0.381 to **−0.164** (Wang et al., 2025). Under low prevalence, AUROC of 0.906–0.960 can coexist with AUPRC of 0.177–0.252, and AUROC of 0.92 with low PPV and high alert burden (Wong et al., 2026).

8. **Within MIMIC-IV, sepsis is the prediction task most damaged by temporal shift**, and no domain-generalisation method currently fixes it (Guo et al., 2022). A random train/test split on MIMIC-IV is therefore optimistically biased for this task specifically.

9. **There is no assumption-free survival model for ICU data.** Proportional hazards fails (Kasal et al., 2004); independent censoring fails (Resche-Rigon et al., 2006); the competing-risks remedy is itself disputed (Schoenfeld, 2006); landmarking does not restore PH (van Houwelingen, 2007); joint models do not scale. The **discrete-time hazard model** dissolves more of these problems at once than any alternative and is native to the data's hourly structure.

10. **The statistics-versus-machine-learning dichotomy does not carve the field at its joints.** AISE is a Weibull–Cox model; TREWScore is marketed as machine learning; TRIPOD+AI covers both under one checklist. The informative partition is **static versus dynamic**.

11. **The clinical value of lead time is real but bounded.** Delay carries an odds ratio of approximately 1.04 per hour (Seymour et al., 2017); the honest lead time of a good modern system is under four hours (Moor et al., 2023); and only one randomised trial exists, conducted in thirty-two beds over three months (Shimabukuro et al., 2017).

12. **Model performance and label sensitivity are both inequitable.** Sepsis criteria select demographically non-neutral sub-populations, and prediction degrades for Asian, Hispanic, and Spanish-speaking patients (Wang, Li, Naidech, & Luo, 2022).

### 4.2 The central problem with the base review's proposed study — and the reframing

The base review proposes to build "a time-varying Cox model for real-time sepsis onset detection on MIMIC-IV," benchmarked against SIRS, qSOFA, and NEWS, and validated internally and on eICU-CRD.

Assessed against the propositions above, this proposal has four difficulties, and they compound.

**It is not novel.** Ninety-one real-time sepsis prediction models already exist (Wang et al., 2025). A Cox model for onset on MIMIC has already been fitted (Fagerström et al., 2019) and beaten by twenty hours of lead time.

**Its benchmark is weak.** The governing clinical guideline already recommends *against* qSOFA as a screening tool (Evans et al., 2021), and a LASSO-derived score has already failed to beat NEWS2 (Mellhammar et al., 2020).

**Its validation design is optimistically biased.** A random internal split understates degradation more for sepsis than for any neighbouring MIMIC-IV task (Guo et al., 2022).

**Its evaluation metrics cannot detect the characteristic failure mode.** AUC, sensitivity, specificity, and lead time are all preserved across the transition in which clinical utility inverts (Wang et al., 2025).

And yet the underlying instinct is sound. The field *does* need interpretable, assumption-honest, well-validated models. The error is in the object of study. The base review treats the label, the split, and the metric as *nuisance parameters* to be fixed by convention so that the model can be evaluated. The literature says the opposite: **the label, the split, and the metric are where the variance lives, and the model is comparatively unimportant.**

That inversion is the contribution. It converts the project from a ninety-second entry into a crowded field into a methodological study that the field measurably needs and that essentially nobody has done for a survival model on MIMIC-IV.

> ### Reframed research question
>
> **In real-time sepsis onset prediction on MIMIC-IV, how is predictive performance and inferential validity partitioned between (a) the choice of model class — interpretable discrete-time survival model versus gradient-boosted and recurrent machine-learning baselines — and (b) the analyst's discretionary methodological choices, namely the operationalisation of the Sepsis-3 onset label, the alignment of controls, the temporal versus random validation split, and the evaluation metric?**
>
> **Sub-question 1 (inference).** Are the hazard ratios estimated by an interpretable survival model *stable in sign and magnitude* across defensible operationalisations of the Sepsis-3 onset rule, and across prediction times anchored before versus after clinical action?
>
> **Sub-question 2 (performance).** Under a fixed label, a temporal split, and a utility-based metric, what is the true performance gap between an interpretable discrete-time hazard model and a modern machine-learning baseline — and how does that gap compare with the variance induced by the label alone?
>
> **Sub-question 3 (equity).** Are the answers to (1) and (2) stable across demographic subgroups, given that the label itself is known to be demographically non-neutral?

This question is answerable with MIMIC-IV, is directly motivated by the strongest evidence in the field, and produces a publishable result **whichever way it comes out.** If the hazard ratios are stable, the field gains a defence of interpretable modelling that it currently lacks. If they are unstable, the field learns that a large body of published hazard ratios for sepsis are artefacts of undocumented labelling decisions — which would be a more important finding than any new model.

### 4.3 Revised objectives

**Primary objective.** To quantify the relative contribution of model class versus analyst discretion (label operationalisation, control alignment, split strategy, evaluation metric) to both the *predictive performance* and the *inferential stability* of real-time sepsis onset models on MIMIC-IV.

**Secondary objectives.**

1. To specify a **discrete-time hazard model** (pooled logistic regression over person-hour records, with time-varying covariates, a spline-flexible baseline hazard, and cause-specific handling of the competing events of discharge and death without sepsis) as the primary interpretable model, and to justify this choice against the static Cox model on the grounds set out in §3.5.
2. To implement **at least three defensible operationalisations of Sepsis-3 onset**, following Cohen et al. (2024) and the identification algorithms compared by Johnson et al. (2018), and to report all primary results under each — treating cross-label variance as a *primary result*, not a sensitivity analysis.
3. To evaluate under a **treatment-anchored prediction time**, following Kamran et al. (2024): restricting evaluation to predictions issued before the first culture order or antibiotic administration, and measuring lead time relative to *clinical recognition* rather than to the label.
4. To adopt a **temporal split** (early MIMIC-IV anchor years for training, late years for testing), reporting the random-split result alongside it in order to quantify the optimism explicitly, following Guo et al. (2022).
5. To guard explicitly against **control-alignment leakage**, following Moor et al. (2021), by pre-specifying how the pseudo-onset time of non-septic controls is drawn.
6. To evaluate on a metric set adequate to the failure mode: **AUROC, AUPRC, calibration intercept and slope with a flexible calibration curve, the PhysioNet Utility Score, alert burden (false alerts per true alert), and decision-curve net benefit** — with the Utility Score and calibration treated as primary and AUROC as descriptive only.
7. To benchmark against comparators that are informative: **NEWS2** (rather than qSOFA alone, per Evans et al., 2021), a **gradient-boosted tree**, and a **recurrent or temporal-convolutional baseline** — all fitted on the *identical* cohort, label, split, and metric, since cross-paper comparison is uninformative (§3.2c).
8. To externally validate on **eICU-CRD** (Pollard et al., 2018), pre-registering the expected degradation of approximately 0.08 AUC and testing whether the Utility Score remains positive — the quantity that Wang et al. (2025) show typically does not.
9. To report **subgroup performance and subgroup label-sensitivity** by race, ethnicity, language, and insurance status (Wang, Li, Naidech, & Luo, 2022).
10. To report in conformity with **TRIPOD+AI** (Collins et al., 2024) and to conduct a design-time self-appraisal against **PROBAST+AI** (Moons et al., 2025).

### 4.4 Revised study plan

**Phase 0 — Pre-registration and protocol (new; non-optional).**
Pre-specify the label variants, the control-alignment rule, the split, the primary metric, and the hypothesis. Conduct the PROBAST+AI self-appraisal *now*, because its participant-selection, outcome-definition, and analysis domains cannot be repaired after the fact. Without this phase, every subsequent result is a garden-of-forking-paths artefact — and given that the entire thesis of the study is that analyst discretion drives results, an unpre-registered version of it would be self-refuting.

**Phase 1 — Cohort construction under multiple labels.**
Extract the MIMIC-IV ICU cohort (v3.1). Construct ≥3 Sepsis-3 onset variants. Report the cohort-size variation as a headline descriptive result, replicating Cohen et al.'s (2024) 867-to-2,178 finding on MIMIC-IV, where it has not been shown. Define the competing events (discharge alive, death without sepsis). Draw control pseudo-onset times under a pre-specified rule. Bin to hourly person-time records. Document missingness and the imputation rule; do not interpolate across the prediction boundary.

**Phase 2 — Primary model.**
Fit the discrete-time hazard model: pooled logistic regression over person-hours, time-varying covariates, restricted cubic splines on both the covariates (for non-linearity) and on time-in-ICU (for a flexible baseline hazard), with cause-specific competing-event handling. Fit under each label variant. Fit the static Cox model as a *deliberately weak comparator*, and test proportional hazards via Schoenfeld residuals — not because the Cox model is the intended product, but to quantify what the field's default choice costs.

**Phase 3 — Benchmarks under identical conditions.**
NEWS2; gradient-boosted trees; a recurrent baseline. Identical cohort, label, split, features, and metric. This is the only comparison in the study that carries evidential weight (§3.2c).

**Phase 4 — Evaluation.**
Temporal split as primary; random split reported for optimism quantification. Treatment-anchored evaluation window. Full metric set (Objective 6). Subgroup analyses. Report alert burden against Moor et al.'s (2023) benchmark of 1.4 false alerts per true alert.

**Phase 5 — External validation.**
eICU-CRD, with the ~0.08 AUC degradation pre-registered as the expected value. Report whether the Utility Score survives the transition. If resources permit, extend to a non-US database (AmsterdamUMCdb or HiRID), following Moor et al. (2023) — the shift is larger and therefore more informative.

**Phase 6 — The variance decomposition (the actual contribution).**
Report, in a single table, the variance in performance and in coefficient estimates attributable to: model class; label operationalisation; control alignment; split strategy; evaluation metric; and subgroup. If the base review's instinct is right, model class dominates. If the literature reviewed here is right, it does not. **That table is the paper.**

### 4.5 Threats to validity and mitigations

| Threat | Source | Mitigation |
|---|---|---|
| Label instability | Cohen et al. (2024); Johnson et al. (2018); Dutta et al. (2026) | ≥3 label variants; cross-label variance reported as a primary result |
| Treatment/suspicion leakage into the label | Kamran et al. (2024) | Treatment-anchored evaluation; lead time measured against clinical recognition |
| Framing artefacts reversing coefficient signs | Lauritsen et al. (2021) | Pre-specified framing; report coefficient stability across framings |
| Control-alignment leakage | Moor et al. (2021) | Pre-specified pseudo-onset rule for controls |
| Optimistic internal validation | Guo et al. (2022) | Temporal split primary; random split reported for contrast |
| Non-proportional hazards | Kasal et al. (2004) | Discrete-time formulation (assumption not required); Cox fitted only as comparator |
| Informative censoring by discharge | Resche-Rigon et al. (2006) | Cause-specific competing-event model |
| Objection to survival methods in ICU outcomes | Schoenfeld (2006) | Discrete-time model *is* a logistic regression; the objection is answered by construction |
| AUROC concealing utility collapse | Wang et al. (2025); Wong et al. (2026) | Utility Score and calibration as primary endpoints |
| Low-prevalence inflation of AUROC | Sepsis Watch validation (2025) | AUPRC reported alongside |
| Alert burden | Moor et al. (2023) | False alerts per true alert reported against the 1.4 benchmark |
| Inequitable performance and labelling | Wang, Li, Naidech, & Luo (2022) | Subgroup performance *and* subgroup label-sensitivity |
| Analyst degrees of freedom | The study's own thesis | Phase 0 pre-registration |
| Publication-bias-inflated expectations | Wong et al. (2021); Ostermayer et al. (2024) | Pre-register expected external degradation; treat a small drop as suspicious |

### 4.6 Limitations of this review

This extension is a **narrative critical review**, not a systematic review, and it inherits several of the limitations the base review acknowledges of itself.

*Search.* Thirty-five structured searches were executed against general web search and publisher records rather than a single reproducible Boolean query against PubMed, Scopus, Embase, or Web of Science with a fixed date range. Coverage is therefore not exhaustive, and the hit counts are not reproducible. Relevant work indexed only in databases not surfaced by general search may have been missed.

*Selection.* Sources were selected for their bearing on the base review's proposed study, not by a pre-specified inclusion protocol. This is a purposive, argument-driven sample. It is well suited to identifying threats to a specific research plan and poorly suited to estimating the field's central tendency. In particular, the deployment-failure literature (§2.8) is over-represented relative to its share of publications, because it is the literature that most sharply constrains the proposal — and a reader seeking a balanced portrait of the field's overall success rate should not take §2.8 as that portrait.

*Single reviewer.* Screening, thematic classification, and appraisal were performed without a second independent reviewer, so classification and confirmation bias are not excluded.

*The 2025–2026 currency scan (§2.10) is illustrative, not exhaustive.* It establishes that the prognosis-dominant pattern persists and that no located study predicts onset; it does not establish that no such study exists.

*Metadata completeness.* Two sources are cited with incomplete metadata, flagged explicitly in the bibliography (notes b and c). Four further items encountered in secondary citation lists could not be verified against a publisher, PubMed, or PMC record and were excluded rather than cited. Figures carried forward from the base review without independent re-derivation are marked as such.

*Quantitative claims.* Where a numerical result is reported above, it was located in the source's own abstract, results text, or publisher record. The one exception is explicitly marked: the odds-ratio compounding calculation in §2.8 (1.04³·⁷ ≈ 1.16) is the present author's arithmetic applied to Seymour et al.'s (2017) reported per-hour estimate, and it is offered as a sanity check on the field's justifying premise rather than as a finding of that paper.

*What this review does not do.* It does not systematically survey deep-learning architectures for sepsis (a large literature in its own right), does not address paediatric or neonatal sepsis, does not address biomarker discovery, and does not address the reinforcement-learning literature on sepsis *treatment* (as distinct from prediction), which raises a separate and substantial set of methodological problems.

### 4.7 Concluding assessment

The base review's diagnosis — that MIMIC-IV sepsis modelling is dominated by post-diagnosis prognosis, under-tests its assumptions, and under-validates — is **substantially correct**, and its 2025–2026 currency has been confirmed rather than eroded (§2.10). It is a competent survey of the terrain it chose to survey.

Its prescription, however, does not follow from the wider evidence. A time-varying Cox model for sepsis onset on MIMIC-IV is not a gap in the literature so much as a **space the literature has already visited and left**, having found that the model is not the binding constraint. Fagerström et al. (2019) fitted the model; Wang et al. (2025) counted ninety more; Reyna et al. (2020) showed the rankings do not transfer; Moor et al. (2023) measured the fall; Guo et al. (2022) showed the internal split was lying; Wang et al. (2025) showed the AUROC was lying too; Cohen et al. (2024) and Dutta et al. (2026) showed the label was moving under everyone's feet; and Kamran et al. (2024) showed the label was partly made of clinician behaviour in the first place.

The honest reading of that sequence is that the field does not need a ninety-second sepsis model. It needs somebody to hold the model fixed and measure how much everything *else* was doing. The tools of classical statistics — a clearly specified estimand, an explicit hazard, a stated assumption set, a reported variance decomposition — are unusually well suited to exactly that task. The base review's instinct that statistics has something to offer here is sound; the offer is simply not another model, but the discipline to find out what the models have been measuring.
---

## 5. Bibliography

*Citation style: APA (7th ed.). Verification notes follow the list.*

Adams, R., Henry, K. E., Sridharan, A., et al. (2022). Prospective, multi-site study of patient outcomes after implementation of the TREWS machine learning-based early warning system for sepsis. *Nature Medicine, 28*(7), 1455–1460. https://doi.org/10.1038/s41591-022-01894-0

Christodoulou, E., Ma, J., Collins, G. S., Steyerberg, E. W., Verbakel, J. Y., & Van Calster, B. (2019). A systematic review shows no performance benefit of machine learning over logistic regression for clinical prediction models. *Journal of Clinical Epidemiology, 110*, 12–22. https://doi.org/10.1016/j.jclinepi.2019.02.004

Cohen, S. N., Foster, J., Foster, P., Lou, H., Lyons, T., Morley, S., Morrill, J., Ni, H., Palmer, E., Wang, B., Wu, Y., Yang, L., & Yang, W. (2024). Subtle variation in sepsis-III definitions markedly influences predictive performance within and across methods. *Scientific Reports, 14*(1), 1920. https://doi.org/10.1038/s41598-024-51989-6

Collins, G. S., Moons, K. G. M., Dhiman, P., Riley, R. D., Beam, A. L., Van Calster, B., et al. (2024). TRIPOD+AI statement: Updated guidance for reporting clinical prediction models that use regression or machine learning methods. *BMJ, 385*, e078378. https://doi.org/10.1136/bmj-2023-078378

Collins, G. S., Reitsma, J. B., Altman, D. G., & Moons, K. G. M. (2015). Transparent reporting of a multivariable prediction model for individual prognosis or diagnosis (TRIPOD): The TRIPOD statement. *BMJ, 350*, g7594. https://doi.org/10.1136/bmj.g7594

Cox, D. R. (1972). Regression models and life-tables. *Journal of the Royal Statistical Society: Series B (Methodological), 34*(2), 187–202.

Desautels, T., Calvert, J., Hoffman, J., et al. (2016). Prediction of sepsis in the intensive care unit with minimal electronic health record data: A machine learning approach. *JMIR Medical Informatics, 4*(3), e28. https://doi.org/10.2196/medinform.5909

Dutta, S., McMurry, R., Tasi, M. C., et al. (2026). Performance of a sepsis prediction model across different sepsis definitions. *JAMA Network Open, 9*(4), e265599. https://doi.org/10.1001/jamanetworkopen.2026.5599

Evans, L., Rhodes, A., Alhazzani, W., et al. (2021). Surviving Sepsis Campaign: International guidelines for management of sepsis and septic shock 2021. *Critical Care Medicine, 49*(11), e1063–e1143. https://doi.org/10.1097/CCM.0000000000005337

Fagerström, J., Bång, M., Wilhelms, D., & Chew, M. S. (2019). LiSep LSTM: A machine learning algorithm for early detection of septic shock. *Scientific Reports, 9*, 15132. https://doi.org/10.1038/s41598-019-51219-4

Fine, J. P., & Gray, R. J. (1999). A proportional hazards model for the subdistribution of a competing risk. *Journal of the American Statistical Association, 94*(446), 496–509. https://doi.org/10.1080/01621459.1999.10474144

Fleuren, L. M., Klausch, T. L. T., Zwager, C. L., et al. (2020). Machine learning for the prediction of sepsis: A systematic review and meta-analysis of diagnostic test accuracy. *Intensive Care Medicine, 46*(3), 383–400. https://doi.org/10.1007/s00134-019-05872-y

GBD 2021 Global Sepsis Collaborators. (2025). Global, regional, and national sepsis incidence and mortality, 1990–2021: A systematic analysis for the Global Burden of Disease Study 2021. *The Lancet Global Health, 13*(12), e2013–e2026. https://doi.org/10.1016/S2214-109X(25)00356-0

Guo, L. L., Pfohl, S. R., Fries, J., Johnson, A. E. W., Posada, J., Aftandilian, C., Shah, N., & Sung, L. (2022). Evaluation of domain generalization and adaptation on improving model robustness to temporal dataset shift in clinical medicine. *Scientific Reports, 12*(1), 2726. https://doi.org/10.1038/s41598-022-06484-1

Habib, A. R., Lin, A. L., & Grant, R. W. (2021). The Epic Sepsis Model falls short—The importance of external validation [Editorial]. *JAMA Internal Medicine, 181*(8). *(See note d.)*

Henry, K. E., Adams, R., Parent, C., et al. (2022). Factors driving provider adoption of the TREWS machine learning-based early warning system and its effects on sepsis treatment timing. *Nature Medicine, 28*(7), 1447–1454. https://doi.org/10.1038/s41591-022-01895-z

Henry, K. E., Hager, D. N., Pronovost, P. J., & Saria, S. (2015). A targeted real-time early warning score (TREWScore) for septic shock. *Science Translational Medicine, 7*(299), 299ra122. https://doi.org/10.1126/scitranslmed.aab3719

Johnson, A. E. W., Aboab, J., Raffa, J. D., Pollard, T. J., Deliberato, R. O., Celi, L. A., & Stone, D. J. (2018). A comparative analysis of sepsis identification methods in an electronic database. *Critical Care Medicine, 46*(4), 494–499. https://doi.org/10.1097/CCM.0000000000002965

Johnson, A. E. W., Bulgarelli, L., Shen, L., et al. (2023). MIMIC-IV, a freely accessible electronic health record dataset. *Scientific Data, 10*(1), 1. https://doi.org/10.1038/s41597-022-01899-x

Kamran, F., Tjandra, D., Heiler, A., Virzi, J., Singh, K., King, J. E., Valley, T. S., & Wiens, J. (2024). Evaluation of sepsis prediction models before onset of treatment. *NEJM AI, 1*(3). https://doi.org/10.1056/AIoa2300032

Kasal, J., Jovanovic, Z., Clermont, G., et al. (2004). Comparison of Cox and Gray's survival models in severe sepsis. *Critical Care Medicine, 32*(3). https://doi.org/10.1097/01.CCM.0000114819.37569.4B *(Carried forward from the base review; see note e.)*

Lauritsen, S. M., Thiesson, B., Jørgensen, M. J., Riis, A. H., Espelund, U. S., Weile, J. B., & Lange, J. (2021). The framing of machine learning risk prediction models illustrated by evaluation of sepsis in general wards. *npj Digital Medicine, 4*(1), 158. https://doi.org/10.1038/s41746-021-00529-x

Liaw, P. C., et al. (2019). *Critical Care Explorations.* https://doi.org/10.1097/CCE.0000000000000032 *(Carried forward from the base review; see note e.)*

Liu, R., et al. (2019). Data-driven discovery of a novel sepsis pre-shock state predicts impending septic shock in the ICU. *Scientific Reports, 9.* https://doi.org/10.1038/s41598-019-42637-5

Mellhammar, L., Linder, A., Tverring, J., et al. (2020). Scores for sepsis detection and risk stratification—Construction of a novel score using a statistical approach and validation of RETTS. *PLoS ONE, 15*(2), e0229210. https://doi.org/10.1371/journal.pone.0229210

Moons, K. G. M., Damen, J. A. A., Kaul, T., et al. (2025). PROBAST+AI: An updated quality, risk of bias, and applicability assessment tool for prediction models using regression or artificial intelligence methods. *BMJ, 388*, e082505. https://doi.org/10.1136/bmj-2024-082505

Moor, M., Bennett, N., Plečko, D., Horn, M., Rieck, B., Meinshausen, N., Bühlmann, P., & Borgwardt, K. (2023). Predicting sepsis using deep learning across international sites: A retrospective development and validation study. *eClinicalMedicine, 62*, 102124. https://doi.org/10.1016/j.eclinm.2023.102124

Moor, M., Rieck, B., Horn, M., Jutzeler, C. R., & Borgwardt, K. (2021). Early prediction of sepsis in the ICU using machine learning: A systematic review. *Frontiers in Medicine, 8*, 607952. https://doi.org/10.3389/fmed.2021.607952

Morrill, J. H., Kormilitzin, A., Nevado-Holgado, A. J., et al. (2020). The signature-based model for early detection of sepsis from electronic health records in the intensive care unit. *Critical Care Medicine.* https://doi.org/10.1097/CCM.0000000000004510 *(Carried forward from the base review; see note e.)*

Nemati, S., Holder, A., Razmi, F., Stanley, M. D., Clifford, G. D., & Buchman, T. G. (2018). An interpretable machine learning model for accurate prediction of sepsis in the ICU. *Critical Care Medicine, 46*(4), 547–553. https://doi.org/10.1097/CCM.0000000000002936

Nestor, B., McDermott, M. B. A., Boag, W., et al. (2019). Feature robustness in non-stationary health records: Caveats to deployable model performance in common clinical machine learning tasks. *Proceedings of Machine Learning Research (Machine Learning for Healthcare Conference), 106*, 381–405.

Ostermayer, D. G., Braunheim, B., Mehta, A. M., Ward, J., Andrabi, S., & Sirajuddin, A. M. (2024). External validation of the Epic sepsis predictive model in 2 county emergency departments. *JAMIA Open, 7*(4), ooae133. https://doi.org/10.1093/jamiaopen/ooae133

Pollard, T. J., Johnson, A. E. W., Raffa, J. D., Celi, L. A., Mark, R. G., & Badawi, O. (2018). The eICU Collaborative Research Database, a freely available multi-center database for critical care research. *Scientific Data, 5*, 180178. https://doi.org/10.1038/sdata.2018.178

Resche-Rigon, M., Azoulay, E., & Chevret, S. (2006). Evaluating mortality in intensive care units: Contribution of competing risks analyses. *Critical Care, 10*(1), R5. https://doi.org/10.1186/cc3921

Reyna, M. A., Josef, C. S., Jeter, R., Shashikumar, S. P., Westover, M. B., Nemati, S., Clifford, G. D., & Sharma, A. (2020). Early prediction of sepsis from clinical data: The PhysioNet/Computing in Cardiology Challenge 2019. *Critical Care Medicine, 48*(2), 210–217. https://doi.org/10.1097/CCM.0000000000004145

Rizopoulos, D. (2011). Dynamic predictions and prospective accuracy in joint models for longitudinal and time-to-event data. *Biometrics, 67*(3), 819–829. https://doi.org/10.1111/j.1541-0420.2010.01546.x

Rizopoulos, D., Molenberghs, G., & Lesaffre, E. M. E. H. (2017). Dynamic predictions with time-dependent covariates in survival analysis using joint modeling and landmarking. *Biometrical Journal, 59*(6), 1261–1276. https://doi.org/10.1002/bimj.201600238

Rudd, K. E., Johnson, S. C., Agesa, K. M., et al. (2020). Global, regional, and national sepsis incidence and mortality, 1990–2017: Analysis for the Global Burden of Disease Study. *The Lancet, 395*(10219), 200–211. https://doi.org/10.1016/S0140-6736(19)32989-7

Schoenfeld, D. (2006). Survival methods, including those using competing risk analysis, are not appropriate for intensive care unit outcome studies. *Critical Care, 10*(1), 103. https://doi.org/10.1186/cc3949

Seymour, C. W., Gesten, F., Prescott, H. C., et al. (2017). Time to treatment and mortality during mandated emergency care for sepsis. *New England Journal of Medicine, 376*(23), 2235–2244. https://doi.org/10.1056/NEJMoa1703058

Seymour, C. W., Kennedy, J. N., Wang, S., et al. (2019). Derivation, validation, and potential treatment implications of novel clinical phenotypes for sepsis. *JAMA, 321*(20), 2003–2017. https://doi.org/10.1001/jama.2019.5791

Seymour, C. W., Liu, V. X., Iwashyna, T. J., et al. (2016). Assessment of clinical criteria for sepsis: For the Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). *JAMA, 315*(8), 762–774. https://doi.org/10.1001/jama.2016.0288

Shimabukuro, D. W., Barton, C. W., Feldman, M. D., Mataraso, S. J., & Das, R. (2017). Effect of a machine learning-based severe sepsis prediction algorithm on patient survival and hospital length of stay: A randomised clinical trial. *BMJ Open Respiratory Research, 4*(1), e000234. https://doi.org/10.1136/bmjresp-2017-000234

Singer, M., Deutschman, C. S., Seymour, C. W., et al. (2016). The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). *JAMA, 315*(8), 801–810. https://doi.org/10.1001/jama.2016.0287

Van Calster, B., McLernon, D. J., van Smeden, M., Wynants, L., & Steyerberg, E. W. (2019). Calibration: The Achilles heel of predictive analytics. *BMC Medicine, 17*(1), 230. https://doi.org/10.1186/s12916-019-1466-7

van Houwelingen, H. C. (2007). Dynamic prediction by landmarking in event history analysis. *Scandinavian Journal of Statistics, 34*(1), 70–85. https://doi.org/10.1111/j.1467-9469.2006.00529.x

van Houwelingen, H., & Putter, H. (2011). *Dynamic prediction in clinical survival analysis.* Chapman & Hall/CRC.

Wang, H., Li, Y., Naidech, A., & Luo, Y. (2022). Comparison between machine learning methods for mortality prediction for sepsis patients with different social determinants. *BMC Medical Informatics and Decision Making, 22*(Suppl 2), 156. https://doi.org/10.1186/s12911-022-01871-0

Wang, Z., Wang, W., Sun, C., Li, J., Xie, S., Xu, J., Zou, K., Jin, Y., Yan, S., Liao, X., Kang, Y., Coopersmith, C. M., & Sun, X. (2025). A methodological systematic review of validation and performance of sepsis real-time prediction models. *npj Digital Medicine, 8*(1), 190. https://doi.org/10.1038/s41746-025-01587-1

Wong, A., et al. (2026). Multicenter prospective validation of an updated proprietary sepsis prediction model. *JAMA Network Open.* *(See note c.)*

Wong, A., Otles, E., Donnelly, J. P., et al. (2021). External validation of a widely implemented proprietary sepsis prediction model in hospitalized patients. *JAMA Internal Medicine, 181*(8), 1065–1070. https://doi.org/10.1001/jamainternmed.2021.2626

[Multisite external validation of the Sepsis Watch model]. (2025). *npj Digital Medicine.* https://doi.org/10.1038/s41746-025-01664-5 *(See note b.)*

---

### Verification notes

**(a) Truncated author lists.** Where a source is cited as "*et al.*" after three named authors, the full author list was **not verified** in this search pass. Names given are those confirmed against a publisher, PubMed, or PMC record. No author name in this bibliography has been supplied from memory or inference; where the list could not be confirmed, it was truncated rather than completed.

**(b) Sepsis Watch multisite validation (2025).** Journal, year, and DOI confirmed; the **author list was not retrieved** in this pass and is therefore recorded as *not available*. The substantive figures cited in §2.7 (AUROC 0.906–0.960; AUPRC 0.177–0.252; 205,005 encounters; 101,584 patients; four sites) were located in the publisher record. Readers should retrieve the full citation from the DOI before citing it themselves.

**(c) Wong et al. (2026).** First author, title, journal, year, and substantive results (227,091 encounters; four US health systems; AUROC 0.82–0.92; low PPV; high alert burden) confirmed via the PMC record (PMC12949446). **Volume, issue, and article number were not captured** in this pass and are recorded as *not available*.

**(d) Habib et al. (2021).** Authors, title, journal, year, and volume confirmed. **Page range and DOI not verified** in this pass.

**(e) Sources carried forward from the base review.** Kasal et al. (2004), Liaw et al. (2019), Morrill et al. (2020), and Mellhammar et al. (2020) are retained from the base review's reference list. Their DOIs are reproduced as given there. Full bibliographic metadata for Kasal et al., Liaw et al., and Morrill et al. was **not independently re-derived** in this pass; the base review reports having verified each against PubMed or a publisher record. Substantive claims attributed to them above are drawn from the base review's characterisation, not from independent reading of the full texts, and are so marked in Section 2.

**(f) Exclusions.** Four items encountered in secondary citation lists during this search — including a widely referenced commentary disputing the causal interpretation of Adams et al. (2022), which appears to exist principally in preprint and correspondence form — could not be verified against a peer-reviewed publisher record and have therefore been **excluded** rather than cited. The substance of that dispute is noted in §2.8 with an explicit statement that it is not cited as settled evidence.

**(g) The base document.** *A Literature Review of Statistical Modeling Approaches for Real-Time Sepsis Prediction Using the MIMIC-IV Database* (unpublished manuscript, supplied by the author) is the object of this extension and is cited throughout as "the base review."

**(h) Author's own arithmetic.** One quantitative statement in this review is not drawn from any source: the compounding calculation in §2.8 (1.04³·⁷ ≈ 1.16), which applies Seymour et al.'s (2017) reported per-hour odds ratio to Moor et al.'s (2023) reported lead time. It is flagged in situ.
