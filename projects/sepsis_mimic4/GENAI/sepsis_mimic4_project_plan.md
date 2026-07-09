# Time-Varying Statistical Modeling for Real-Time Sepsis Onset Prediction: A Survival Analysis Approach Using MIMIC-IV

---

## Abstract

Sepsis remains a leading cause of ICU mortality, and early recognition materially improves outcomes. While machine learning has come to dominate recent sepsis-prediction research, purely statistical models, particularly Cox proportional hazards regression, remain the interpretable foundation of the field and are directly comparable to established clinical scores (SIRS, qSOFA, NEWS). A companion literature review identified that existing statistical work on the MIMIC-IV database is dominated by post-diagnosis prognostic modeling (mortality prediction) rather than pre-onset early detection, that the proportional-hazards assumption is rarely tested before fitting a Cox model, and that external validation is largely absent from the real-time onset-prediction literature specifically. This project proposes a quantitative, Design-Science-informed study to address these gaps directly. A time-varying Cox proportional hazards model will be developed for real-time sepsis onset prediction using MIMIC-IV vitals and labs, with the proportional-hazards assumption formally tested and a flexible alternative applied if it fails. The model will be benchmarked against SIRS, qSOFA, and NEWS using AUC-ROC, sensitivity/specificity, and lead time, and validated internally and externally on the eICU Collaborative Research Database. Expected outcomes include a reproducible, open statistical modeling pipeline, a direct empirical test of the proportional-hazards assumption in this setting, and an assessment of whether time-varying statistical modeling closes the internal/external validation gap identified in the literature. The project is designed for completion within a five-to-six-month MSc timeline, with machine learning and deep learning extensions explicitly reserved for future work.

---

## I. Introduction

Sepsis is defined by the Sepsis-3 consensus as life-threatening organ dysfunction caused by a dysregulated host response to infection, and this remains the current clinical and research standard used for ICU dataset labeling. Sepsis is a major cause of global mortality, and because early treatment materially improves survival, real-time prediction of its onset is of direct clinical significance. Recent studies using the MIMIC-IV electronic health record database have shown that both machine learning and classical statistical models can be used for sepsis-related prediction tasks, though the two traditions have not developed evenly: machine learning research has grown rapidly around post-diagnosis mortality prediction, while the statistical tradition, exemplified by Henry et al.'s 2015 TREWScore (a Cox proportional hazards model for septic shock onset on the older MIMIC-II database), has not been substantially revisited on MIMIC-IV specifically.

A companion literature review (statistical sepsis prediction on MIMIC-IV) identified three consistent limitations in the current statistical literature. First, most MIMIC-IV statistical studies predict mortality or complications *after* sepsis is diagnosed rather than *onset* itself. Second, the proportional-hazards assumption that underlies Cox regression, shown by Kasal et al. (2004) to often fail in sepsis populations, is rarely tested in the reviewed MIMIC-IV papers. Third, external validation, while present in a subset of the prognosis-focused nomogram literature, is essentially absent from the real-time onset-prediction statistical literature, despite evidence that model performance degrades substantially under external testing.

This project addresses these limitations within a single statistical modeling framework, focused on adult ICU sepsis onset prediction using MIMIC-IV, with external validation on eICU-CRD. The study is non-interventional and uses only de-identified secondary data; prospective deployment and real-time clinical decision-making are outside the scope of this work. Machine learning and deep learning approaches to the same problem are explicitly deferred to a later phase of this research program and are not part of the present scope.

The remainder of this document is organized as follows. Section II presents the research questions and objectives. Section III summarizes the relevant literature review findings. Section IV describes the research methodology, modeling framework, and ethical considerations. Section V outlines the project timeline, work breakdown structure, risks, and resource requirements. Section VI concludes.

---

## II. Research Questions and Objectives

The primary research question is:

> **RQ.** Can a statistical (Cox proportional hazards / time-varying covariate) model, using routinely available real-time vitals and labs in MIMIC-IV, accurately predict impending sepsis onset ahead of clinical recognition, with performance comparable to or exceeding existing rule-based scores (SIRS, qSOFA, NEWS)?

This question is divided into three sub-questions:

- **SQ1.** Which routinely measured variables (vitals, labs) are the strongest statistically significant predictors of sepsis onset in MIMIC-IV, via multivariable logistic and Cox regression, and does the proportional-hazards assumption hold for the fitted Cox model?
- **SQ2.** Does modeling patient trajectories through a time-varying Cox extension (or, exploratorily, group-based trajectory modeling) improve early detection lead time compared to a static, single-time-point Cox or logistic model?
- **SQ3.** How does the developed statistical model's discriminative performance (AUC, sensitivity, specificity, lead time) compare with SIRS, qSOFA, and NEWS, and does this performance hold up under external validation on eICU-CRD rather than only internal MIMIC-IV validation?

The corresponding research objectives are:

- **O1.** Construct a reproducible ICU sepsis cohort from MIMIC-IV using Sepsis-3 criteria, with matched non-septic controls and time-windowed vitals/labs preceding sepsis onset.
- **O2.** Fit and compare a static Cox proportional hazards model and a static multivariable logistic regression model as baselines, replicating the general approach used in the reviewed MIMIC-IV literature.
- **O3.** Formally test the proportional-hazards assumption (Schoenfeld residuals) for the fitted Cox model and, where it fails, fit a time-varying covariate or flexible alternative (following Liaw et al.'s longitudinal Cox approach and Kasal et al.'s comparison of Cox and Gray's model).
- **O4.** Benchmark the best-performing statistical model against SIRS, qSOFA, and NEWS using AUC-ROC, sensitivity/specificity at matched thresholds, Kaplan-Meier survival curves, log-rank tests, and decision curve analysis.
- **O5.** Externally validate the final model on the eICU Collaborative Research Database and directly compare internal versus external performance, addressing the validation gap identified in the literature review.
- **O6.** Release the cohort-extraction scripts, modeling code, and evaluation notebooks under an open-source licence to support reproducibility.

The null hypothesis for SQ1 states that the proportional-hazards assumption will hold for at least half of the included covariates in the fitted Cox model (i.e., that a fully time-varying reformulation is not required for the majority of predictors); rejection of this null motivates Objective O3's time-varying extension as a primary rather than secondary contribution.

---

## III. Brief Literature Summary

The detailed thematic synthesis is provided in the companion literature review. This section summarizes only the findings relevant to the present methodological design.

Statistical sepsis-prediction research on MIMIC-IV is methodologically mature but concentrated on the wrong half of the clinical problem. A recurring pattern of studies (using LASSO variable selection feeding a multivariable logistic regression, presented as a nomogram) reliably predicts mortality after sepsis diagnosis, with three of four such studies including external validation, a genuine strength of that sub-literature. By contrast, genuine real-time, pre-onset sepsis detection using purely statistical tools is represented by only a small number of studies, none of which use MIMIC-IV: Henry et al. (2015) fitted a Cox model on the older MIMIC-II database, and Liaw et al. (2019) used an independent prospective Canadian cohort with a time-varying Cox extension. Kasal et al. (2004) demonstrated, in a separate severe-sepsis cohort, that the proportional-hazards assumption central to Cox regression is frequently violated, yet none of the MIMIC-IV Cox-regression papers reviewed report testing this assumption. Finally, a systematic review of 91 real-time sepsis prediction models (statistical and machine learning combined) found that performance drops substantially under external and full-window validation compared to internal validation, a concern that applies with particular force to the onset-prediction statistical literature, where external validation is essentially absent.

The theoretical basis of this project combines two components. First, the Sepsis-3 definition provides the clinical target for prediction. Second, classical survival analysis theory, specifically the Cox proportional hazards model, its underlying proportional-hazards assumption, and time-varying-covariate extensions, provides the statistical framework for the proposed artefact.

---

## IV. Methodology

### A. Research Methodology

**1) Research paradigm:** The project follows a quantitative, hypothesis-driven statistical modeling methodology with an embedded artefact-development component: the primary output is a validated, reproducible statistical risk-scoring pipeline (a "real-time sepsis onset score"), assessed against measurable, pre-specified criteria (AUC-ROC, sensitivity/specificity, lead time, external validation performance). This framing supports controlled benchmarking against existing rule-based clinical scores, making the study both artefact-oriented and hypothesis-testable, while remaining strictly within classical statistical methods (no machine learning or deep learning components at this stage).

**2) Data sources:** The primary dataset is MIMIC-IV, containing electronic health records from ICU admissions at Beth Israel Deaconess Medical Center. External validation is performed using the eICU Collaborative Research Database, a separate multi-hospital ICU dataset. Both datasets are de-identified and accessed through PhysioNet under credentialed research access, supporting external validation consistent with the recommendations arising from the companion literature review.

**3) Cohort and feature engineering:** The sepsis cohort is defined using Sepsis-3 criteria (documented or suspected infection with an increase in SOFA score of at least 2). Only adult ICU patients are included. Index time is defined as sepsis onset; matched non-septic ICU patients serve as controls. Vitals (heart rate, respiratory rate, temperature, SpO2, blood pressure) and labs (WBC, lactate, creatinine) are extracted at hourly resolution from the raw electronic health record. Missing data are handled using forward-fill (carrying the last known value forward, which mirrors what the clinician currently knows) and informative-missingness indicators (binary flags marking whether each lab was measured in a given hour, which capture clinical suspicion patterns).

**3a) Temporal resolution and prediction mechanism:** ICU data in MIMIC-IV is irregularly sampled, not a uniform real-time stream: vitals are charted every 1–5 minutes (nurse entries or monitor snapshots), temperature and GCS every 1–4 hours, and labs every 4–12 hours on clinical suspicion. Hourly aggregation is the natural resolution that balances signal density against computational tractability, and matches the PhysioNet/CinC 2019 Challenge benchmark used for evaluation.

The prediction mechanism uses an *expanding window* with dynamic landmarking, not a fixed-width sliding window. At each hour *h* (starting from *h* = 6, when enough post-admission data has accumulated), the model sees all available data from admission up to hour *h* and predicts onset within the next 12 hours:

- Hour 6: features from [0, 6] → P(onset in 6–18 h)
- Hour 7: features from [0, 7] → P(onset in 7–19 h)
- Hour 8: features from [0, 8] → P(onset in 8–20 h)
- …continuing hourly until the end of the stay.

Within this expanding window, slope features (e.g., heart-rate trend over the preceding 6 hours) act as a *local sliding window* that captures recent deterioration. The supermodel includes interaction terms between features and landmark time (*s*, *s*²) so that the coefficient surface adapts as the stay progresses. This means a patient whose vitals are stable at hour 6 but deteriorate at hour 12 will see a rising risk score without manual threshold adjustment.

Per-second or per-minute prediction is not pursued because (a) the raw data does not support it — labs arrive hours apart and even vitals are only charted at minute-level intervals, (b) clinical treatment decisions (antibiotics, fluids, vasopressors) operate on 30-minute to multi-hour timescales, making sub-hourly resolution clinically redundant, and (c) per-second prediction would require continuous waveform data and a streaming model architecture (e.g., RNN or streaming transformer), which constitutes a fundamentally different system from the interpretable statistical early-warning tool developed here.

**4) Models and analytical framework:** Three groups of methods are evaluated. Clinical scores include SIRS, qSOFA, and NEWS, computed directly from the extracted vitals. Baseline statistical models include univariate and multivariable logistic regression (odds ratios, 95% CI) and a static Cox proportional hazards model (time-to-sepsis-onset as outcome). The primary modeling contribution is a time-varying Cox extension (time-dependent covariates or landmark analysis), applied once the proportional-hazards assumption has been tested via Schoenfeld residuals; where the assumption fails, a flexible alternative such as Gray's model is considered, following Kasal et al.'s methodological precedent. Group-based trajectory modeling (GBTM) is included as an exploratory extension to identify latent risk-trajectory subgroups, following Yang et al.'s approach to SOFA-score trajectories. Restricted cubic splines are used to check for nonlinearity in key continuous predictors. Where subgroup confounding is a concern, propensity score matching or doubly robust estimation is applied.

**5) Evaluation strategy:** Performance is measured using AUC-ROC as the primary discrimination metric, with sensitivity and specificity at matched thresholds as secondary measures, directly comparable to the SIRS/qSOFA/NEWS baselines. Lead time (hours before clinical recognition) is reported as the key real-time performance metric, following TREWScore's and Liaw et al.'s precedent. Kaplan-Meier curves and log-rank tests assess risk-group separation; decision curve analysis assesses clinical net benefit. Internal validation uses a train/test split within MIMIC-IV; external validation repeats the full evaluation on eICU-CRD, directly testing whether the internal/external performance gap identified in the literature review persists for this statistical model. Sensitivity analyses include subgroup performance (age, comorbidities) and E-value assessment for unmeasured confounding.

### B. Development Methodology

**1) Process model:** Development follows a phased cycle, with each phase producing a verifiable, testable output (cohort extraction, baseline models, assumption-tested Cox model, time-varying extension, benchmarking, external validation) before proceeding to the next. Each phase is validated on a held-out subset before integration into the full pipeline, reducing the risk of compounding errors across a multi-stage statistical workflow.

**2) Tools and technologies:** The system is implemented in Python and/or R, using established survival-analysis libraries (`lifelines` or the R `survival` package for Cox modeling and Schoenfeld residual testing, `rms` for restricted cubic splines, `lcmm` or `traj` for group-based trajectory modeling, `MatchIt` or equivalent for propensity score matching). Data extraction uses SQL against the MIMIC-IV and eICU-CRD PostgreSQL builds on PhysioNet. Git and GitHub manage version control; results and figures are produced in reproducible notebooks.

**3) System architecture:** The pipeline consists of four layers: data extraction (SQL queries against MIMIC-IV/eICU-CRD), preprocessing (cohort selection, time-windowed feature extraction, missing-data handling), modeling (clinical scores, baseline regression, time-varying Cox, optional GBTM), and evaluation/reporting (AUC-ROC and lead-time comparison, assumption testing, internal/external validation, final report generation).

### C. Ethical Considerations

The study uses only de-identified secondary data accessed through PhysioNet under a credentialed agreement. No new data is collected and no human participants are involved; ethical approval for primary data collection is therefore not required. Data handling follows PhysioNet's data use agreement, with no attempt at re-identification and processing restricted to secure environments. All results are reported transparently, including internal and external validation performance side by side, to avoid overstating generalizability from internal results alone. The system is a research artefact only, not intended for clinical deployment, and will be released with a clear non-clinical disclaimer.

---

## V. Project Plan and Timeline

### A. Work Breakdown Structure

The project is divided into eight phases, each producing a verifiable output.

1. **Setup and access (Week 1–2):** CITI training, PhysioNet credentialing for MIMIC-IV and eICU-CRD, environment configuration, and repository setup.
2. **Cohort and feature engineering (Week 3–5):** SQL extraction, Sepsis-3 labeling, time-windowed feature extraction, and missing-data handling.
3. **Baseline statistical models (Week 6–8):** Implementation of SIRS, qSOFA, NEWS, univariate/multivariable logistic regression, and a static Cox model, with finalized baseline results.
4. **Assumption testing and time-varying extension (Week 9–12):** Schoenfeld residual testing of the static Cox model; development of the time-varying Cox extension (or flexible alternative if proportional hazards fails); exploratory GBTM.
5. **Nonlinearity and causal adjustment (Week 13–14):** Restricted cubic spline analysis for key continuous predictors; propensity score matching or doubly robust estimation for subgroup comparisons where relevant.
6. **Internal validation and benchmarking (Week 15–16):** AUC-ROC, sensitivity/specificity, Kaplan-Meier curves, log-rank tests, and decision curve analysis, benchmarked against SIRS/qSOFA/NEWS.
7. **External validation (Week 17–18):** Full evaluation repeated on eICU-CRD; direct internal-versus-external performance comparison.
8. **Writing and submission (Week 19–22):** Dissertation writing, results reporting, and release of code and analysis notebooks.

### B. Timeline

The project schedule spans 22 weeks, with writing beginning during the later analytical phases to reduce risk in the final integration stage.

```
Project timeline (weeks)
      1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22
P1 Setup and credentialing        [==]
P2 Cohort and features                [======]
P3 Baseline models                          [======]
M1 Baselines locked                               *
P4 Assumption test + time-varying                    [==========]
M2 Time-varying model locked                                   *
P5 Nonlinearity + causal adjustment                                [====]
P6 Internal validation                                                  [====]
P7 External validation                                                       [====]
M3 Validation complete                                                            *
P8 Writing and submission                                                          [========]
M4 Submission                                                                              *
```

### C. Risk Assessment

| # | Risk | L | I | Mitigation |
|---|---|---|---|---|
| R1 | Delay in PhysioNet credentialing | Med | High | Early submission of CITI training; parallel development using a demo/synthetic subset. |
| R2 | Proportional-hazards assumption fails for most covariates | Med | Med | Pre-registered as a testable hypothesis (SQ1); Gray's model or a fully time-varying reformulation is the planned fallback, not a project-ending failure. |
| R3 | Time-varying Cox model does not outperform static baseline | Med | Med | Retain the assumption-testing and validation-rigor contributions regardless of discrimination outcome; report both models transparently. |
| R4 | Class imbalance (sepsis vs. non-septic controls) destabilizes model fitting | High | Med | Matched-control sampling design; report calibration alongside discrimination metrics. |
| R5 | Small subgroup sizes limit external validation power | Med | Med | Bootstrap confidence intervals; explicit reporting of uncertainty rather than point estimates alone. |
| R6 | Schema mismatch between MIMIC-IV and eICU-CRD variable definitions | Med | High | Build an explicit variable-mapping/adapter step; fall back to MIMIC-IV-only evaluation if mapping is infeasible for a given variable. |
| R7 | GBTM or RCS extensions consume disproportionate time relative to core Cox contribution | Med | Low | Treat both as optional/exploratory (clearly scoped as secondary objectives), core deliverable is the assumption-tested time-varying Cox model and its validation. |
| R8 | Personal or supervisor availability issues | Low | Med | Built-in buffer in the final writing phase; regular check-ins. |

### D. Resource Requirements

The project requires PhysioNet access to MIMIC-IV and eICU-CRD, standard CPU compute (no GPU is required, since all modeling is classical statistical regression rather than deep learning), and modest secure storage for extracted cohort tables and processed features. The software stack includes Python and/or R with established survival-analysis packages, SQL for data extraction, and Git/GitHub for version control. No paid tools or human participant data are required.

---

## VI. Conclusion

This project proposes a quantitative statistical modeling study that develops a time-varying Cox proportional hazards model for real-time sepsis onset prediction on the MIMIC-IV database, with the proportional-hazards assumption explicitly tested and a flexible alternative applied where it fails. The study responds directly to the limitations identified in the companion literature review: the near-total absence of real-time (as opposed to post-diagnosis prognostic) statistical modeling on MIMIC-IV, the widespread failure to test the proportional-hazards assumption before fitting Cox models, and the lack of external validation in the onset-prediction statistical literature specifically. The planned 22-week schedule, phased development process, and defined risk-mitigation strategy are designed to keep the scope realistic for an MSc-level project. Independent of the final discrimination performance achieved, the open release of the cohort-extraction and modeling pipeline is intended to support reproducibility and provide an interpretable statistical baseline against which machine learning and deep learning approaches can later be compared in a subsequent phase of this research program.

---

## References (DOI)

1. Singer M, Deutschman CS, Seymour CW, et al. The Third International Consensus Definitions for Sepsis and Septic Shock (Sepsis-3). JAMA. 2016. `10.1001/jama.2016.0287`
2. Henry KE, Hager DN, Pronovost PJ, Saria S. Sci Transl Med. 2015. `10.1126/scitranslmed.aab3719`
3. Kasal J, Jovanovic Z, Clermont G, et al. Crit Care Med. 2004. `10.1097/01.CCM.0000114819.37569.4B`
4. Liaw PC, Fox-Robichaud AE, Liaw KL, et al. Crit Care Explor. 2019. `10.1097/CCE.0000000000000032`
5. Yang R, et al. J Intensive Med. 2022. `10.1016/j.jointm.2021.11.001`
6. Lou J, et al. Front Endocrinol. 2025. `10.3389/fendo.2025.1555082`
7. Yan X, et al. Sci Rep. 2025. `10.1038/s41598-025-18798-x`
8. Wang W, et al. Biomol Biomed. 2024. `10.17305/bb.2024.11134`
9. Liu C, et al. Front Cell Infect Microbiol. 2025. `10.3389/fcimb.2025.1574625`
10. Mellhammar L, Linder A, Tverring J, et al. PLoS ONE. 2020. `10.1371/journal.pone.0229210`
11. Yang JY, et al. BMC Infect Dis. 2025. `10.1186/s12879-025-10972-w`
12. Chen Y, Zong C, Zou L, et al. Heliyon. 2024. `10.1016/j.heliyon.2024.e33337`
13. Yuan ZN, Xue YJ, Wang HJ, et al. BMJ Open. 2023. `10.1136/bmjopen-2023-072112`
14. Xu X, Li J, Yu H, et al. BMC Gastroenterol. 2026. `10.1186/s12876-026-04620-z`
15. Guo P, et al. Front Med. 2025. `10.3389/fmed.2025.1555103`
16. Zou ZY, et al. Burns Trauma. 2022. `10.1093/burnst/tkac029`
17. Reyna MA, Josef CS, Jeter R, et al. Crit Care Med. 2019. `10.1097/CCM.0000000000004145`
18. Morrill JH, Kormilitzin A, Nevado-Holgado AJ, et al. Crit Care Med. 2020. `10.1097/CCM.0000000000004510`
19. Wang Z, Wang W, Sun C, et al. npj Digit Med. 2025. `10.1038/s41746-025-01587-1`
20. Fleuren LM, Klausch TLT, Zwager CL, et al. Intensive Care Med. 2020. `10.1007/s00134-019-05872-y`
21. Johnson AEW, Bulgarelli L, Shen L, et al. MIMIC-IV, a freely accessible electronic health record dataset. Sci Data. 2023. `10.1038/s41597-022-01899-x`
22. Pollard TJ, Johnson AEW, Raffa JD, et al. The eICU Collaborative Research Database. Sci Data. 2018. `10.1038/sdata.2018.178`
