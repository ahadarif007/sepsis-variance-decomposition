# Real-Time Sepsis Prediction Using Statistical Models on MIMIC-IV
### Literature Review, Research Gap, Research Question & Study Plan

---

## 1. Literature Review

Sepsis prediction research using ICU databases has evolved through several statistical modeling generations. This review focuses purely on classical/statistical approaches (no ML/DL), organized by methodology.

### 1.1 Survival & Hazard-Based Models
**Henry et al. (2015)** — *TREWScore* fitted a **Cox proportional hazards model** on MIMIC-II vitals/labs to predict septic shock onset, achieving AUC 0.83 with a median 28-hour lead time. This remains the foundational statistical benchmark for "real-time" sepsis prediction — it proved that a hazard-based regression model, using only routinely collected variables, could anticipate shock well before clinical onset.
`DOI: 10.1126/scitranslmed.aab3719`

**Yang et al. (2022)** applied **Group-Based Trajectory Modeling (GBTM)** to 72-hour SOFA score trajectories in MIMIC-IV sepsis patients, then used Cox regression to link trajectory-group membership to mortality. This is significant for "real-time" framing because it models the *evolving* clinical course rather than a single snapshot.
`DOI: 10.1016/j.jointm.2021.11.001`

**Lou et al. (2025)** and **Yan et al. (2025)** independently examined the glucose-potassium ratio (GPR) as a mortality biomarker in MIMIC-IV sepsis cohorts, using **Kaplan-Meier curves, Cox regression, and restricted cubic splines (RCS)** to detect nonlinear dose-response relationships between a lab biomarker and mortality risk.
`DOI: 10.3389/fendo.2025.1555082` · `DOI: 10.1038/s41598-025-18798-x`

### 1.2 Logistic Regression & Scoring Systems
**Wang et al. (2024)** directly compared **SIRS, qSOFA, and NEWS** scoring systems against a **logistic regression** model enhanced with local clinical variables, using CETAT and MIMIC-IV data. NEWS + logistic regression outperformed the raw rule-based scores (AUC improved from 0.737 to 0.756).
`DOI: 10.17305/bb.2024.11134`

**Liu et al. (2025)** used **logistic regression (for odds ratios) and Cox regression (for hazard ratios)** in parallel to evaluate SOFA and APSIII scores as 28-day mortality predictors in sepsis-induced myocardial injury, validated with ROC, Kaplan-Meier, and decision curve analysis (DCA).
`DOI: 10.3389/fcimb.2025.1574625`

### 1.3 Causal-Adjustment & Variable Selection Methods
**Guo et al. (2025)** combined **propensity score matching, inverse probability weighting, doubly robust estimation, LASSO variable selection, logistic regression, and Cox regression** to disentangle confounding in a MIMIC-IV sepsis cohort — a strong template for rigorous covariate adjustment in observational statistical modeling.
`DOI: 10.3389/fmed.2025.1555103`

**Zou et al. (2022)** used **Cox proportional hazards models with propensity score matching** to assess heparin's effect on sepsis mortality — a clean example of confounder-controlled survival analysis in the same database.
`DOI: 10.1093/burnst/tkac029`

### 1.4 Summary Table

| Study | Method | Outcome | Data |
|---|---|---|---|
| Henry et al. 2015 | Cox PH | Septic shock onset | MIMIC-II |
| Yang et al. 2022 | GBTM + Cox | Mortality | MIMIC-IV |
| Lou / Yan 2025 | Cox + RCS + KM | Mortality | MIMIC-IV |
| Wang et al. 2024 | Logistic regression | Sepsis / high-risk sepsis | CETAT + MIMIC-IV |
| Liu et al. 2025 | Logistic + Cox + DCA | 28-day mortality | MIMIC-IV |
| Guo et al. 2025 | PSM + IPW + doubly robust + LASSO | SIMI prognosis | MIMIC-IV |
| Zou et al. 2022 | Cox + PSM | In-hospital mortality | MIMIC-IV |

---

## 2. Research Gap

1. **Snapshot bias.** Most MIMIC-IV statistical studies (logistic/Cox regression) use a single baseline measurement or an aggregate score (SOFA, APSIII) rather than continuously updated, real-time trajectories.
2. **Outcome vs. early-detection asymmetry.** The majority of purely statistical MIMIC-IV papers predict **mortality/prognosis** *after* sepsis is already diagnosed — not the **onset** of sepsis itself in real time, unlike the Cox-based TREWScore approach (which used MIMIC-II, not IV).
3. **Limited trajectory-based statistical modeling.** Only a few studies (GBTM-based) model the *temporal evolution* of risk. None combine trajectory modeling with a formal real-time hazard framework (e.g., time-varying covariate Cox models or landmark analysis) specifically for **early sepsis detection** on MIMIC-IV.
4. **Confounding often addressed only for treatment-effect questions** (heparin, anticoagulation), not for a general real-time prediction pipeline.

**Gap statement:** There is no widely cited, purely statistical (non-ML) study that builds a **time-varying, real-time risk score for sepsis onset** on MIMIC-IV analogous to TREWScore's original design — most current MIMIC-IV statistical work is retrospective/prognostic rather than predictive/real-time.

---

## 3. Research Question

> **Can a statistical (Cox proportional hazards / time-varying covariate) model, using routinely available real-time vitals and labs in MIMIC-IV, accurately predict impending sepsis onset ahead of clinical recognition, with performance comparable to or exceeding existing rule-based scores (SIRS, qSOFA, NEWS)?**

**Sub-questions:**
- Which routinely measured variables (vitals, labs) are the strongest statistically significant predictors (via multivariable logistic/Cox regression) of sepsis onset in MIMIC-IV?
- Does modeling patient trajectories (GBTM or time-varying Cox) improve early detection lead time compared to static scoring at a single time point?
- How does a fitted statistical model compare against SIRS/qSOFA/NEWS on AUC, sensitivity/specificity, and lead time?

---

## 4. Planning

### Phase 1 — Data Preparation
- Extract MIMIC-IV cohort: ICU adults, Sepsis-3 criteria (documented/suspected infection + SOFA increase ≥2).
- Define index time: onset of sepsis criteria (event) vs. matched non-septic controls.
- Extract time-stamped vitals (HR, RR, Temp, SpO2, BP) and labs (WBC, lactate, creatinine) in fixed windows (e.g., every 1–4 hours) prior to onset.
- Handle missingness (as in prior MIMIC-IV papers — outlier filtering + interpolation).

### Phase 2 — Statistical Modeling
- **Baseline models:** Univariate & multivariable logistic regression (odds ratios, 95% CI) — replicate the approach in Wang et al. and Liu et al.
- **Survival framing:** Cox proportional hazards model with time-to-sepsis-onset as outcome, following Henry et al.'s design; test proportional-hazards assumption (Schoenfeld residuals).
- **Time-varying extension:** Time-dependent Cox model or landmark analysis to update risk as new vitals arrive (true "real-time" element).
- **Trajectory modeling (optional/exploratory):** GBTM on repeated vitals/labs, following Yang et al., to identify latent risk-trajectory subgroups.
- **Nonlinearity check:** Restricted cubic splines for key continuous predictors (as in Lou/Yan et al.).
- **Confounder control:** Propensity score matching / doubly robust estimation if comparing subgroups (e.g., comorbidities), following Guo et al. and Zou et al.

### Phase 3 — Validation & Comparison
- Compare against SIRS, qSOFA, NEWS using AUC-ROC, sensitivity/specificity at matched thresholds (as in Wang et al.).
- Report Kaplan-Meier curves and log-rank tests for risk-group separation.
- Decision curve analysis (DCA) for clinical net-benefit (as in Liu et al.).
- Internal validation via train/test split (e.g., 70/30, as used across most cited MIMIC-IV papers).

### Phase 4 — Reporting
- Present hazard ratios / odds ratios with 95% CI for each significant variable.
- Report lead time (hours before clinical recognition) as a key real-time performance metric, following TREWScore's precedent.
- Sensitivity analyses: subgroup performance (age, comorbidities), E-value for unmeasured confounding.

---

## 5. Conclusion

Purely statistical sepsis-prediction research on MIMIC-IV is currently dominated by **prognostic** studies (mortality after sepsis diagnosis) using logistic regression, Cox regression, GBTM, and RCS methods — while genuinely **real-time, pre-onset** statistical prediction (in the tradition of TREWScore) has not been revisited on the newer, larger MIMIC-IV database using purely classical statistical tools. This leaves a clear, well-motivated opening: applying time-varying Cox models (and optionally GBTM) to MIMIC-IV vitals/labs to build and validate a real-time statistical early-warning score, directly benchmarked against SIRS/qSOFA/NEWS. This statistical foundation will also serve as an interpretable baseline before extending the work to ML/DL approaches in a later phase of the project.

---

## References (DOI)

1. Henry KE, Hager DN, Pronovost PJ, Saria S. Sci Transl Med. 2015. `10.1126/scitranslmed.aab3719`
2. Yang R, et al. J Intensive Med. 2022. `10.1016/j.jointm.2021.11.001`
3. Lou J, et al. Front Endocrinol. 2025. `10.3389/fendo.2025.1555082`
4. Yan X, et al. Sci Rep. 2025. `10.1038/s41598-025-18798-x`
5. Wang W, et al. Biomol Biomed. 2024. `10.17305/bb.2024.11134`
6. Liu C, et al. Front Cell Infect Microbiol. 2025. `10.3389/fcimb.2025.1574625`
7. Guo P, et al. Front Med. 2025. `10.3389/fmed.2025.1555103`
8. Zou ZY, et al. Burns Trauma. 2022. `10.1093/burnst/tkac029`
