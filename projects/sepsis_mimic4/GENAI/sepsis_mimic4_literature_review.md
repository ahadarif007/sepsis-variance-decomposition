# A Literature Review of Statistical Modeling Approaches for Real-Time Sepsis Prediction Using the MIMIC-IV Database

---

## Abstract

Sepsis is a leading cause of death in intensive care units (ICUs), and early recognition remains difficult despite decades of scoring-system development. While machine learning has come to dominate recent sepsis-prediction research on the MIMIC-IV database, purely statistical approaches, such as Cox proportional hazards models, logistic regression, and trajectory-based methods, remain the interpretable foundation of the field and are directly comparable to clinically established scores (SIRS, qSOFA, NEWS). This review examines the current state of purely statistical (non-machine-learning) sepsis prediction and prognosis modeling using MIMIC-IV, with a particular focus on real-time framing. Sources were identified through targeted web-based literature searches (queries listed in Section II) supplemented by a secondary candidate list from an AI-assisted literature discovery tool, with all candidates individually verified against PubMed/DOI records for peer-reviewed status; 18 peer-reviewed statistical studies were included in the final synthesis, drawn from an initial pool of approximately 30 candidate records screened for topical relevance and non-ML methodology. The review finds that statistical MIMIC-IV research is dominated by post-diagnosis prognostic modeling (mortality prediction) rather than pre-onset early detection, that the proportional-hazards assumption is rarely tested, and that validation is almost always internal-only. These findings motivate a research question, objectives, and study plan for a time-varying statistical model of real-time sepsis onset on MIMIC-IV.

---

## I. Introduction

Sepsis is defined under the Sepsis-3 consensus as life-threatening organ dysfunction caused by a dysregulated host response to infection, and this definition remains the clinical and research standard used across ICU studies and dataset labeling. Sepsis remains a major cause of ICU mortality worldwide, and because early treatment materially improves survival, early and reliable prediction of its onset is of direct clinical significance.

Two broad modeling traditions have addressed this problem. The first, and by far the more actively published in recent years, is machine learning (gradient-boosted trees, deep temporal networks). The second, older and still foundational, is classical statistics: Cox proportional hazards regression, logistic regression, survival analysis, and trajectory modeling. Statistical models have a specific advantage for real-time clinical deployment: they produce directly interpretable hazard ratios and odds ratios, they can be checked against formal assumptions (such as proportional hazards), and they can be benchmarked transparently against existing rule-based scores such as SIRS, qSOFA, and NEWS. This review focuses deliberately and exclusively on this statistical tradition, treating machine learning and deep learning approaches as an explicit future extension rather than as part of the current scope.

This review is guided by the following research questions:

- **RQ1.** Which statistical modeling approaches (Cox proportional hazards, logistic regression, trajectory modeling, and related methods) have been applied to sepsis prediction or prognosis using MIMIC-IV, and what do they find?
- **RQ2.** Do existing statistical MIMIC-IV studies address real-time, pre-onset prediction of sepsis, or do they predominantly address post-diagnosis prognosis (mortality)?
- **RQ3.** To what extent do existing statistical sepsis models test their underlying assumptions (for example, proportional hazards) and validate externally, rather than relying on a single internal cohort?

The remainder of this review is structured as follows. Section II describes the search methodology and study categorization. Section III positions this review against prior surveys in the sepsis-prediction space. Section IV presents the thematic synthesis of included studies. Section V discusses the findings in relation to the three research questions above. Section VI identifies research gaps and proposes a research question, objectives, and study plan. Section VII concludes. Section VIII discusses the limitations of this review's own methodology.

---

## II. Methodology

### A. Search Strategy

**1) Sources:** Literature was identified through a web-based search process covering PubMed-indexed biomedical literature, publisher sites (Frontiers, Nature/Scientific Reports, BMJ Open, Wiley, Springer, Oxford Academic), and PMC full-text records. This was supplemented by a secondary candidate list of 11 papers supplied via an AI-assisted literature discovery tool (a Consensus/Elicit-style summarization service), each of which was independently re-verified against PubMed or the publisher record for peer-reviewed status and a valid DOI before inclusion.

**2) Search Terms:** The primary queries used were:

```
sepsis prediction MIMIC-IV statistical model real-time
sepsis early warning score logistic regression MIMIC-IV
survival analysis Cox model
TREWScore Henry targeted real-time early warning score
sepsis Cox proportional hazards model
```

together with per-candidate verification queries of the form `[study title/authors] MIMIC-IV doi journal`, used once a candidate paper's identity was known, to confirm its DOI and publication venue.

**3) Inclusion Criteria:** (i) peer-reviewed journal articles; (ii) sepsis prediction, detection, or prognosis in adult ICU or emergency department settings; (iii) use of the MIMIC-II, MIMIC-III, or MIMIC-IV database (or, for foundational/benchmark papers, a directly comparable ICU physiological time-series dataset); (iv) a statistical modeling approach (Cox regression, logistic regression, survival analysis, trajectory modeling, LASSO-based variable selection feeding a regression model) as the primary or a clearly separable analytic method.

**4) Exclusion Criteria:** Studies were excluded if they were: preprints without a verifiable peer-reviewed version (medRxiv, arXiv, ResearchGate-only postings); paediatric/neonatal cohorts; non-English; or if machine learning/deep learning (XGBoost, random forest, neural networks) was the sole or primary predictive method with no separable statistical component. One candidate (a BMJ Open paper on sepsis-associated thrombocytopenia, encountered only via the secondary candidate list) could not be independently verified against a PubMed or publisher record and was excluded on this basis.

**5) Screening Process:** Approximately 13 distinct search queries were executed, together with per-paper verification searches for the 11 candidates supplied via the secondary discovery tool. Across all searches, approximately 90 individual result snippets were reviewed (with substantial overlap, since the same well-cited papers, such as Henry et al.'s TREWScore, recurred across multiple queries). After removing duplicates and papers that were purely machine-learning-based, approximately 30 unique candidate studies were screened at abstract/snippet level for topical and methodological fit. Of these, 18 met the inclusion criteria and were retained for full synthesis; the remainder were excluded for being ML/DL-primary, unverifiable, or off-topic (e.g., pediatric cohorts, non-sepsis outcomes).

*Note on methodology transparency:* this was not a single-database PRISMA-style systematic review (no unified PubMed/Scopus/Embase query was run against a fixed date range with a single reproducible hit count). This constraint, and its implications, are discussed explicitly in Section VIII.

### B. Study Categorisation

Included studies were classified along three dimensions:

1. **Statistical method family:** static Cox regression, time-varying/longitudinal Cox regression, logistic regression (including LASSO-selected nomograms), group-based trajectory modeling (GBTM), restricted cubic splines (RCS) for nonlinearity, and causal-adjustment methods (propensity score matching, inverse probability weighting, doubly robust estimation).
2. **Prediction target:** pre-onset sepsis/septic-shock detection versus post-diagnosis prognosis (mortality, organ dysfunction, complication risk).
3. **Validation type:** internal-only (train/test split within one cohort) versus external (a second independent cohort, such as eICU-CRD or a separate hospital dataset).

---

## III. Positioning Against Prior Reviews

Two existing reviews sit adjacent to this one but do not cover the same ground.

**Fleuren et al. (2020)**, a systematic review and meta-analysis of machine learning models for sepsis prediction, found that individual ML models can accurately predict sepsis onset ahead of time on retrospective data, but that substantial between-study heterogeneity limits pooled comparison. This review is exclusively about machine learning and does not examine classical statistical models as a distinct category, nor does it focus on MIMIC-IV specifically.
`DOI: 10.1007/s00134-019-05872-y`

**Wang et al. (2025)**, a methodological systematic review of 91 sepsis real-time prediction models (SRPMs), found that performance drops substantially under external and full-window validation (median AUROC falling from 0.886 internally to 0.783 under full external validation). This review evaluates SRPMs as a mixed category (statistical and ML models together) with a focus on validation methodology rather than on comparing statistical modeling families against one another.
`DOI: 10.1038/s41746-025-01587-1`

A targeted search for a review focused specifically on *purely statistical* (non-ML) sepsis prediction or prognosis modeling using MIMIC-IV did not return a matching result. This absence is itself a finding: the present review appears to be the first to synthesize the classical-statistics literature on MIMIC-IV sepsis prediction as a distinct category, separated from the much larger and more actively reviewed ML/DL literature. Where Fleuren et al. and Wang et al. converge on validation and generalizability as the central unresolved issue for ML-based models, this review extends that same concern to the statistical literature, and additionally surfaces a methodological issue specific to survival modeling (the proportional-hazards assumption, discussed in Section IV-A) that neither prior review addresses, since neither focuses on Cox-based methods specifically.

---

## IV. Results: Thematic Synthesis

### A. Theme 1: Survival & Hazard-Based Models (Static Cox)

**Henry et al. (2015)** fitted a **Cox proportional hazards model** on MIMIC-II vitals/labs to predict septic shock onset (*TREWScore*), achieving AUC 0.83 with a median 28-hour lead time. This remains the foundational statistical benchmark for real-time sepsis prediction, since it demonstrates that a hazard-based regression model, using only routinely collected variables, can anticipate shock well before clinical onset.
`DOI: 10.1126/scitranslmed.aab3719`

**Kasal et al. (2004)** directly compared a standard Cox model against **Gray's flexible survival model** in a large severe-sepsis cohort and found that hazards for death after sepsis are frequently **nonproportional**. This is an important methodological caution largely absent from later MIMIC-IV work: naive Cox modeling may misrepresent risk over time in sepsis populations.
`DOI: 10.1097/01.CCM.0000114819.37569.4B`

**Liaw et al. (2019)** proposed a **longitudinal, time-varying Cox extension** (a complementary log-log model) tracking daily mortality risk from six repeatedly measured biological indicators, producing an evolving risk profile rather than a single static score. This is the closest existing statistical precedent to a genuine real-time hazard model for sepsis.
`DOI: 10.1097/CCE.0000000000000032`

### B. Theme 2: Trajectory & Nonlinear Models (MIMIC-IV)

**Yang et al. (2022)** applied **Group-Based Trajectory Modeling (GBTM)** to 72-hour SOFA score trajectories in MIMIC-IV sepsis patients, then used Cox regression to link trajectory-group membership to mortality, modeling the evolving clinical course rather than a single snapshot.
`DOI: 10.1016/j.jointm.2021.11.001`

**Lou et al. (2025)** and **Yan et al. (2025)** independently examined the glucose-potassium ratio as a mortality biomarker in MIMIC-IV sepsis cohorts, using **Kaplan-Meier curves, Cox regression, and restricted cubic splines** to detect nonlinear dose-response relationships.
`DOI: 10.3389/fendo.2025.1555082` and `DOI: 10.1038/s41598-025-18798-x`

### C. Theme 3: Logistic Regression, Scoring Systems & Nomograms

**Wang et al. (2024)** compared **SIRS, qSOFA, and NEWS** against a **logistic regression** model enhanced with local variables (CETAT and MIMIC-IV data), with NEWS plus logistic regression outperforming the raw rule-based scores (AUC improved from 0.737 to 0.756).
`DOI: 10.17305/bb.2024.11134`

**Liu et al. (2025)** used **logistic regression and Cox regression** in parallel to evaluate SOFA and APSIII as 28-day mortality predictors in sepsis-induced myocardial injury, validated with ROC, Kaplan-Meier, and decision curve analysis.
`DOI: 10.3389/fcimb.2025.1574625`

**Mellhammar et al. (2020)** constructed a new **LASSO-derived** risk score (SHEWS) and formally validated the RETTS triage system, but found the statistically-derived score could not outperform the existing NEWS2 score, a valuable negative result showing that statistical construction alone does not guarantee improvement over an established score.
`DOI: 10.1371/journal.pone.0229210`

A recurring pattern across four further MIMIC-IV studies is **LASSO variable selection feeding a multivariable logistic regression, visualized as a nomogram**:
- Yang et al. (2025) — sepsis-induced coagulopathy risk. `DOI: 10.1186/s12879-025-10972-w`
- Chen et al. (2024) — in-hospital mortality in sepsis complicated by ARDS, externally validated. `DOI: 10.1016/j.heliyon.2024.e33337`
- Yuan et al. (2023) — hospital mortality in sepsis with cancer, validated on MIMIC-IV and eICU-CRD. `DOI: 10.1136/bmjopen-2023-072112`
- Xu et al. (2026) — 28-day mortality in cirrhosis-complicated sepsis, validated across MIMIC-III, MIMIC-IV, and eICU. `DOI: 10.1186/s12876-026-04620-z`

These four studies are methodologically consistent and reasonably well validated (three of the four include external validation), but all four are **prognostic**, predicting mortality after diagnosis rather than onset.

### D. Theme 4: Causal-Adjustment & Confounder Control

**Guo et al. (2025)** combined **propensity score matching, inverse probability weighting, doubly robust estimation, LASSO selection, logistic regression, and Cox regression** to disentangle confounding in a MIMIC-IV sepsis cohort, a strong template for covariate adjustment in observational statistical modeling.
`DOI: 10.3389/fmed.2025.1555103`

**Zou et al. (2022)** used **Cox regression with propensity score matching** to assess heparin's effect on sepsis mortality, a clean example of confounder-controlled survival analysis in the same database.
`DOI: 10.1093/burnst/tkac029`

### E. Theme 5: Real-Time Prediction Benchmarks (Broader Context)

**Reyna et al. (2019)**, the official paper of the PhysioNet/Computing in Cardiology Challenge 2019, established a shared benchmark and clinical-utility metric for early sepsis prediction across a large multi-team competition. Entries spanned both statistical and machine-learning approaches, so it is not itself a statistical-only method paper, but it remains the field's central real-time-prediction benchmark.
`DOI: 10.1097/CCM.0000000000004145`

**Morrill et al. (2020)** built on the same Challenge data with a **signature-based regression model**: a mathematically grounded feature-engineering method (the path signature transform) combined with regression rather than a deep neural network, placing it closer to statistical territory than most Challenge entries.
`DOI: 10.1097/CCM.0000000000004510`

This theme connects directly to the two reviews discussed in Section III: **Wang et al. (2025)**'s systematic review of 91 SRPMs found that performance drops substantially under external and full-window validation, a concern that applies equally to the statistical models discussed in Themes A through D above, almost none of which report external validation for their onset-prediction (as opposed to prognosis-prediction) components.
`DOI: 10.1038/s41746-025-01587-1`

### F. Summary Table

| Study | Method | Target | Validation | Data |
|---|---|---|---|---|
| Henry et al. 2015 | Cox PH | Onset (septic shock) | Internal | MIMIC-II |
| Kasal et al. 2004 | Cox vs Gray's model | Mortality (nonprop. hazards) | Internal | Severe sepsis cohort |
| Liaw et al. 2019 | Time-varying Cox | Daily mortality risk | Internal | Multi-site prospective |
| Yang et al. 2022 | GBTM + Cox | Mortality | Internal | MIMIC-IV |
| Lou / Yan 2025 | Cox + RCS + KM | Mortality | Internal | MIMIC-IV |
| Wang et al. 2024 | Logistic regression | Sepsis / high-risk sepsis | Internal | CETAT + MIMIC-IV |
| Liu et al. 2025 | Logistic + Cox + DCA | 28-day mortality | Internal | MIMIC-IV |
| Mellhammar et al. 2020 | LASSO-derived score | Risk stratification | Internal (2 cohorts) | Multicentre ED |
| Yang et al. 2025 | LASSO + logistic (nomogram) | SIC risk | Internal | MIMIC-IV |
| Chen et al. 2024 | LASSO + logistic | In-hospital mortality (ARDS) | **External** | MIMIC-IV + China cohort |
| Yuan et al. 2023 | LASSO + logistic (nomogram) | Hospital mortality (cancer) | **External** | MIMIC-IV + eICU-CRD |
| Xu et al. 2026 | LASSO + Boruta + logistic | 28-day mortality (cirrhosis) | **External** | MIMIC-III/IV + eICU |
| Guo et al. 2025 | PSM + IPW + doubly robust | SIMI prognosis | Internal | MIMIC-IV |
| Zou et al. 2022 | Cox + PSM | In-hospital mortality | Internal | MIMIC-IV |
| Reyna et al. 2019 | Mixed (benchmark) | Onset | External (Challenge) | PhysioNet Challenge |
| Morrill et al. 2020 | Signature-based regression | Onset | External (Challenge) | PhysioNet Challenge |
| Wang et al. 2025 (review) | Systematic review | SRPM performance | N/A | 91 studies |
| Fleuren et al. 2020 (review) | Systematic review + meta-analysis | ML sepsis prediction | N/A | Multiple |

---

## V. Discussion

**RQ1 (statistical approaches used).** The literature shows a consistent, well-established toolkit: static and time-varying Cox regression, logistic regression (frequently paired with LASSO selection and presented as a nomogram), group-based trajectory modeling, and restricted cubic splines for nonlinear effects. Causal-adjustment methods (propensity score matching, inverse probability weighting, doubly robust estimation) are used competently when the research question concerns a specific treatment or exposure (Guo et al.; Zou et al.). Methodologically, this is a mature and internally consistent body of work.

**RQ2 (real-time onset vs. post-diagnosis prognosis).** The evidence strongly favors prognosis over onset detection. Of the 18 studies reviewed, only three (Henry et al., Liaw et al., and the PhysioNet Challenge-derived papers) address prediction *ahead of* or *at* sepsis onset; the remaining 13 to 15 studies, including the entire LASSO-plus-nomogram cluster (Theme C) and the trajectory/nonlinear cluster (Theme B), predict mortality or complications *after* sepsis has already been diagnosed. Moreover, none of the genuine onset-prediction statistical papers (Henry et al.; Liaw et al.) use MIMIC-IV specifically; Henry et al. used MIMIC-II, and Liaw et al. used an independent prospective Canadian cohort. This is the central asymmetry this review identifies.

**RQ3 (assumption-testing and external validation).** Assumption-testing is rare: only Kasal et al. formally investigates whether the proportional-hazards assumption holds for sepsis mortality, finding that it frequently does not, yet none of the later MIMIC-IV Cox-regression papers reviewed here report having checked this assumption before fitting a static Cox model. External validation is present in three of the four LASSO-nomogram studies (Theme C), which is a genuine strength of that sub-literature, but is largely absent from the onset-prediction and trajectory-modeling studies (Themes A, B, and E), which is precisely where external validation matters most given Wang et al.'s (2025) finding that performance degrades substantially under external testing.

---

## VI. Research Gaps and Future Directions

Three consistent gaps emerge from the synthesis.

**Gap 1: Snapshot and prognosis bias.** Most MIMIC-IV statistical studies use a single baseline measurement or an aggregate score (SOFA, APSIII) and predict mortality after diagnosis, rather than modeling continuously updated, real-time risk of sepsis onset itself.

**Gap 2: Untested proportional-hazards assumption.** Kasal et al. (2004) showed that sepsis mortality hazards are frequently nonproportional, yet this assumption is not reported as tested in any of the MIMIC-IV Cox-regression papers reviewed here. This weakens confidence in hazard ratios reported across Themes B and D.

**Gap 3: Validation asymmetry.** External validation is reasonably common in the prognosis-focused nomogram literature (Theme C) but essentially absent from the real-time onset-prediction statistical literature (Theme A), despite Wang et al.'s (2025) finding that this is exactly where validation rigor most affects reported performance.

A coherent future direction is to unify these gaps within a single statistical framework: a **time-varying Cox model for real-time sepsis onset detection on MIMIC-IV**, with the proportional-hazards assumption explicitly tested (and a flexible alternative, such as Gray's model, applied if it fails), benchmarked against SIRS/qSOFA/NEWS, and validated both internally and on an external cohort (such as eICU-CRD). This forms the basis of the research question, objectives, and study plan below.

### Research Question

> Can a statistical (Cox proportional hazards / time-varying covariate) model, using routinely available real-time vitals and labs in MIMIC-IV, accurately predict impending sepsis onset ahead of clinical recognition, with performance comparable to or exceeding existing rule-based scores (SIRS, qSOFA, NEWS)?

### Research Objectives

**Primary Objective:** To develop and validate a statistical (Cox proportional hazards / time-varying covariate) model for real-time prediction of sepsis onset in ICU patients using MIMIC-IV data.

**Secondary Objectives:**
1. To identify statistically significant predictors of sepsis onset through multivariable logistic and Cox regression.
2. To determine whether modeling patient trajectories (GBTM or time-varying Cox) improves early detection lead time compared to static, single-time-point scoring.
3. To test the proportional-hazards assumption for the fitted Cox model and, where it fails, apply a time-varying or flexible alternative.
4. To benchmark the model's discriminative performance (AUC, sensitivity, specificity, lead time) against SIRS, qSOFA, and NEWS, under both internal and external validation.
5. To assess model robustness through sensitivity analyses, including subgroup performance and confounder adjustment via propensity score matching.
6. To quantify nonlinear relationships between key continuous predictors and sepsis risk using restricted cubic splines.

### Study Plan

**Phase 1: Data Preparation.** Extract a MIMIC-IV ICU cohort meeting Sepsis-3 criteria; define index time as sepsis onset versus matched non-septic controls; extract time-stamped vitals and labs in fixed windows prior to onset; handle missingness via outlier filtering and interpolation.

**Phase 2: Statistical Modeling.** Fit baseline logistic regression models; fit a Cox proportional hazards model with time-to-onset as outcome and formally test the proportional-hazards assumption (Schoenfeld residuals), following Kasal et al.'s caution; extend to a time-varying Cox or landmark model, following Liaw et al.; optionally apply GBTM for trajectory subgroups; check nonlinearity via restricted cubic splines; apply propensity score matching or doubly robust estimation where subgroup confounding is a concern.

**Phase 3: Validation.** Compare against SIRS, qSOFA, and NEWS on AUC-ROC and sensitivity/specificity; report Kaplan-Meier curves and log-rank tests; apply decision curve analysis; validate internally via train/test split and, where feasible, externally on a second cohort (e.g., eICU-CRD).

**Phase 4: Reporting.** Report hazard ratios and odds ratios with 95% CI; report lead time in hours before clinical recognition; conduct subgroup and E-value sensitivity analyses.

---

## VII. Conclusion

This review synthesizes 18 peer-reviewed statistical studies of sepsis prediction and prognosis on the MIMIC-IV database (and closely related predecessor datasets), organized around five methodological themes: static Cox/survival models, trajectory and nonlinear models, logistic regression and nomograms, causal-adjustment methods, and real-time prediction benchmarks. The overall picture is one of methodological maturity applied predominantly to the wrong half of the problem: statistical rigor is high for post-diagnosis mortality prognosis, but genuine pre-onset, real-time sepsis detection using purely statistical tools has not been meaningfully revisited on MIMIC-IV since Henry et al.'s 2015 work on the older MIMIC-II database. Two further specific weaknesses, an untested proportional-hazards assumption and a validation asymmetry between prognosis and onset-detection studies, sharpen this gap into an actionable research direction: a time-varying, assumption-tested, externally validated statistical model for real-time sepsis onset detection on MIMIC-IV. This statistical foundation is intended to serve as an interpretable baseline before the same problem is revisited with machine learning and deep learning methods in a later phase of this research program.

---

## VIII. Limitations of This Review

This review has several methodological limitations specific to its own search and screening process, distinct from limitations of the studies it reviews.

First, the search was not conducted as a single, formally reproducible query against one fixed-interface database (e.g., a single documented PubMed or Scopus query with a fixed date filter); instead it combined targeted web-based searches with a secondary candidate list from an AI-assisted discovery tool, each candidate individually re-verified. This is a departure from a strict PRISMA-style protocol and makes exact reproduction of the search more difficult than a single documented Boolean query would allow.

Second, screening and thematic classification were performed by a single reviewer (assisted by an AI tool for search execution and verification), introducing a risk of selection and classification bias that a dual-reviewer protocol would reduce.

Third, the search did not systematically query Scopus, Web of Science, or Embase directly; coverage relied on PubMed-indexed content and publisher sites surfaced through general web search, which may have missed relevant studies indexed only in those databases.

Fourth, one candidate study (a BMJ Open paper on sepsis-associated thrombocytopenia) could not be independently verified and was excluded; if a valid peer-reviewed version exists, this represents a false-negative exclusion.

Fifth, the review is restricted to English-language, peer-reviewed sources and to statistical (non-ML/DL) methods by design; this is a deliberate scope decision for this stage of the research program, and machine learning/deep learning approaches to the same problem are treated as future work rather than as a limitation to be corrected within this review.

These limitations concern the review process itself; substantive issues identified in the literature, such as the untested proportional-hazards assumption and the internal/external validation asymmetry, are treated as synthesis findings (Section VI) rather than as review-methodology constraints.

---

## References (DOI)

1. Henry KE, Hager DN, Pronovost PJ, Saria S. Sci Transl Med. 2015. `10.1126/scitranslmed.aab3719`
2. Kasal J, Jovanovic Z, Clermont G, et al. Crit Care Med. 2004. `10.1097/01.CCM.0000114819.37569.4B`
3. Liaw PC, Fox-Robichaud AE, Liaw KL, et al. Crit Care Explor. 2019. `10.1097/CCE.0000000000000032`
4. Yang R, et al. J Intensive Med. 2022. `10.1016/j.jointm.2021.11.001`
5. Lou J, et al. Front Endocrinol. 2025. `10.3389/fendo.2025.1555082`
6. Yan X, et al. Sci Rep. 2025. `10.1038/s41598-025-18798-x`
7. Wang W, et al. Biomol Biomed. 2024. `10.17305/bb.2024.11134`
8. Liu C, et al. Front Cell Infect Microbiol. 2025. `10.3389/fcimb.2025.1574625`
9. Mellhammar L, Linder A, Tverring J, et al. PLoS ONE. 2020. `10.1371/journal.pone.0229210`
10. Yang JY, et al. BMC Infect Dis. 2025. `10.1186/s12879-025-10972-w`
11. Chen Y, Zong C, Zou L, et al. Heliyon. 2024. `10.1016/j.heliyon.2024.e33337`
12. Yuan ZN, Xue YJ, Wang HJ, et al. BMJ Open. 2023. `10.1136/bmjopen-2023-072112`
13. Xu X, Li J, Yu H, et al. BMC Gastroenterol. 2026. `10.1186/s12876-026-04620-z`
14. Guo P, et al. Front Med. 2025. `10.3389/fmed.2025.1555103`
15. Zou ZY, et al. Burns Trauma. 2022. `10.1093/burnst/tkac029`
16. Reyna MA, Josef CS, Jeter R, et al. Crit Care Med. 2019. `10.1097/CCM.0000000000004145`
17. Morrill JH, Kormilitzin A, Nevado-Holgado AJ, et al. Crit Care Med. 2020. `10.1097/CCM.0000000000004510`
18. Wang Z, Wang W, Sun C, et al. npj Digit Med. 2025. `10.1038/s41746-025-01587-1`
19. Fleuren LM, Klausch TLT, Zwager CL, et al. Intensive Care Med. 2020. `10.1007/s00134-019-05872-y`
