---
marp: true
theme: default
paginate: true
size: 16:9
header: 'Model, Label, or Analyst? — Variance Decomposition of Real-Time Sepsis Onset Prediction'
footer: 'Abdul Ahad · M.Sc. Computing · Atlantic Technological University (ATU), Galway'
style: |
  section {
    font-size: 24px;
    color: #16302f;
  }
  h1 { color: #005b5e; }
  h2 { color: #005b5e; }
  section.lead h1 { font-size: 40px; }
  section.lead h2 { font-size: 28px; }
  table { font-size: 20px; }
  img { display: block; margin: 0 auto; }
  section.lead { text-align: center; }
  blockquote { border-left: 4px solid #005b5e; padding-left: 16px; font-style: italic; }
  strong { color: #005b5e; }
  section.refs { font-size: 15px; }
  section.refs h2 { font-size: 24px; }
---

<!-- _class: lead -->

## Quantifying Model, Label, and Analyst Contributions to Variance in Real-Time Sepsis Onset Prediction

**Abdul Ahad**

M.Sc. in Computing
Department of Computer Science & Applied Physics
Atlantic Technological University (ATU), Galway

---

## I. Introduction

- **Sepsis** is a life-threatening condition caused by the body's extreme response to an infection [1].
- It causes **about 11 million deaths every year**, nearly **1 in 5 deaths worldwide** [2].
- Delaying treatment by even a few hours increases the risk of death [3].
- **More than 90 AI models** have already been developed to predict sepsis [4].

**Existing models have improved prediction, but important methodological questions remain unanswered.**

---

## II. Background and Related Work

Wang et al. [4] reviewed 91 real-time sepsis prediction models and found:

| Metric               | Internal   | External   |
|----------------------|------------|------------|
| Median AUROC         | 0.811      | 0.783      |
| Median Utility Score | **+0.381** | **-0.164** |

**Four key limitations of the conventional approach:**

1. **The sepsis label can change.** Cohen et al. [5] showed that different ways of applying Sepsis-3 criteria to the same database can create very different patient groups (867–2,178 cases).
2. **The data split can give unrealistic results.** Guo et al. [6] found that performance drops significantly when tested on data from a different time period.
3. **AUROC does not show the full picture.** Wang et al. [4] showed that a model can maintain a good AUROC while its clinical usefulness decreases.
4. **The label may represent doctor decisions, not only patient deterioration.** Kamran et al. [7] suggested that models may learn patterns of medical actions instead of actual patient worsening.

---

## III. Research Question and Hypotheses

> In real-time sepsis prediction using MIMIC-IV [14], how much of the model's performance difference comes from:
>
> (a) the choice of AI model, and
> (b) the researcher's decisions, including how sepsis is defined, how data is split, when prediction is made, and how performance is measured?

| # | Hypothesis | Threshold |
|---|-----------|-----------|
| H1 | Label choice affects AUROC as much as or more than model choice [5] | label spread ≥ model spread |
| H2 | Feature importance changes across different label definitions [11] | ≥1 sign change |
| H3 | Removing post-treatment information lowers AUROC by ≥0.03 [7] | Δ ≥ 0.03 |
| H4 | Temporal testing gives lower AUROC than random testing by ≥0.02 [6] | Δ ≥ 0.02 |
| H5 | Utility Score drops more than AUROC under realistic testing [4] | ratio comparison |
| H6 | Statistical models perform close to gradient boosting models (within 0.02 AUROC) [13] | |Δ| ≤ 0.02 |

---

## IV. Materials

- **Development dataset:** MIMIC-IV v3.1 [14] (65,078 adult ICU stays)
- **External validation:** eICU-CRD v2.0 [15] (200+ US ICUs, 7.9 million person-hours)

**Three Sepsis-3 label variants [1]:**

| Variant | Meaning      | When infection is confirmed                                                                 | SOFA baseline                              |
|---------|--------------|---------------------------------------------------------------------------------------------|--------------------------------------------|
| A       | **Strict**   | Antibiotics and blood culture must happen within **24 hours** of each other.                | SOFA score at ICU admission                |
| B       | **Standard** | Antibiotics can come up to **72 hours before** the blood culture, or **24 hours after** it. | SOFA score at ICU admission                |
| C       | **Broad**    | Antibiotics and blood culture can happen within **72 hours** of each other.                 | Lowest SOFA score in the previous 24 hours |

**In all three definitions, a patient has sepsis if** there is **suspected infection** and the **SOFA score increases by at least 2 points**.

---

## V. Methods — Model Architecture

The main model is a **dynamic discrete-time competing-risks hazard model** using **multinomial pooled logistic regression** [8].

- Predicts the **risk of sepsis every hour** during a patient's ICU stay.
- Does not require the proportional hazards assumption.
- Accounts for patients who **leave the ICU or die before developing sepsis** (competing risks).

**Comparator models:** Gradient-Boosted Trees (GBT), Static Cox model, NEWS2, qSOFA, and SIRS.

---

## V. Methods — Validation Strategy

| Validation        | What was done                                                                      | Why?                                                                                              |
|-------------------|------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|
| **Internal**      | Trained on patients from **2008–2016** and tested on **2017–2019** data [6].       | To evaluate the model on newer, unseen patients.                                                  |
| **Random split**  | Trained on 75% of patients and tested on 25%, chosen randomly [6].                 | To quantify how much the data split inflates reported performance (H4).                           |
| **Pre-treatment** | Used only data collected **before the first antibiotic or blood culture** [7].      | To check whether the model is predicting sepsis or simply detecting when doctors start treatment. |
| **External**      | Tested the same trained model on the **eICU-CRD** [15] dataset without retraining. | To see whether the model works in other hospitals.                                                |

**Main evaluation metrics:** **Utility Score** [12] and **Calibration**. AUROC was reported only for comparison because it may not detect clinically important performance failures [4].

---

## V. Methods — Methodological Commitments

- **Pre-registered protocol:** The study plan was fixed before model development to reduce bias (following TRIPOD+AI guidelines [9]).
- **Leakage prevention:** The model only uses information available at each prediction time; missing values are handled using past information only.
- **Patient-level separation:** The same patient never appears in both training and testing data.
- **Frozen external validation:** The model trained on MIMIC-IV is directly tested on eICU-CRD without retraining.
- **Reproducible pipeline:** The complete workflow uses organised scripts, shared configurations, and publicly available code for replication.

---

## VI. Results — Cohort and Label Variance

| Variant | Name             | ICU Stays | Sepsis Cases | Percentage |
|---------|------------------|-----------|--------------|------------|
| A       | Narrow           | 65,078    | 6,252        | 9.6%       |
| B       | Seymour-Standard | 65,078    | 6,447        | 9.9%       |
| C       | Liberal          | 65,078    | **12,581**   | **19.3%**  |

The Liberal definition found almost **2 times more sepsis cases** than the other two definitions.

The patient data and database were the same. Only the way sepsis was defined was different.

---

## VI. Results — H1: Label Has More Impact Than Model (CONFIRMED)

![w:550](output/09_label_variance_auroc.png)

- **Label variation:** AUROC changed by **0.153** when the sepsis definition changed while using the same model.
- **Model variation:** AUROC changed by **0.145** when the model changed while using the same label.
- This confirms Cohen et al.'s [5] finding that sepsis label definition can strongly influence model performance.

**The way sepsis is defined can affect performance as much as, or more than, the AI model itself.**

---

## VI. Results — H2: Coefficient Instability (CONFIRMED)

- **10 out of 25 features** changed their effect or strength significantly across different sepsis label definitions.
- Affected features include: MAP, temperature, bilirubin, platelets, vasopressors, norepinephrine/epinephrine, respiratory rate change, platelet measurement, WBC measurement, and P/F ratio.

**Implication:** A published hazard ratio for MAP could show a positive, negative, or almost no association with sepsis risk depending only on how the antibiotic-culture time window is defined [11].

Feature effects cannot be reliably interpreted without knowing which sepsis label definition was used.

---

## VI. Results — H3: Treatment Leakage (CONFIRMED)

The treatment-anchored window [7] uses only information available **before the first antibiotic or blood culture**.

- **179,003 patient-hours** were analysed.
- **0 sepsis onset events** were found in this period.

No sepsis onset event is found before the clinical actions used to define the Sepsis-3 label.

This is not just a small drop in model performance (0.03 AUROC). The prediction target is completely missing in the clinically realistic time window.

**Most MIMIC-IV sepsis prediction models are learning when doctors suspect sepsis and start treatment, rather than detecting when a patient's health is starting to get worse.**

---

## VI. Results — H4: Split Optimism (CONFIRMED)

| Split    | Model   | AUROC | Utility Score |
|----------|---------|-------|---------------|
| Temporal | Primary | 0.607 | -1.004        |
| Random   | Primary | 0.730 | -1.000        |
| Temporal | GBT     | 0.746 | -4.849        |
| Random   | GBT     | 0.720 | -5.167        |

- **Primary model:** Random-split AUROC was **0.123 higher** than temporal-split AUROC (threshold: ≥ 0.02).
- The random split lets future patient patterns leak into training, inflating reported performance.
- This confirms Guo et al.'s [6] finding: **studies using random splits may overestimate real-world performance.**

---

## VI. Results — H5: External Validation on eICU-CRD [15]

| Variant | Model   | AUROC (eICU) | AUROC (MIMIC) | Drop      |
|---------|---------|--------------|---------------|-----------|
| A       | Primary | 0.736        | 0.760         | 0.024     |
| B       | Primary | **0.437**    | 0.607         | **0.170** |
| C       | Primary | 0.725        | 0.759         | 0.034     |
| —       | NEWS2   | 0.605        | 0.63          | 0.025     |

- Variants A and C showed similar performance on both datasets, with only small drops.
- **Variant B (Seymour-Standard) showed a large performance drop of 0.170 AUROC when tested on eICU-CRD.**
- The most commonly used sepsis label definition did not transfer well to a different hospital dataset.

---

## VI. Results — H6: Model-Class Difference (REJECTED)

![w:550](output/09_model_class_auroc.png)

- **GBT AUROC:** 0.746 — **Primary Model AUROC:** 0.607 — Difference: **0.139**
- **GBT Utility Score:** -4.849 — **Primary Model Utility Score:** -1.004

The model ranking changes depending on the evaluation metric. A model that looks better by AUROC may perform worse in real clinical use.

---

## VI. Results — Internal Performance (Temporal Test)

| Variant | Model   | AUROC     | Utility Score | Alert Burden |
|---------|---------|-----------|---------------|--------------|
| A       | Primary | 0.760     | **-1.000**    | ∞            |
| A       | GBT     | 0.742     | -4.667        | 203          |
| B       | Primary | 0.607     | -1.004        | ∞            |
| B       | **GBT** | **0.746** | -4.849        | 194          |
| C       | Primary | 0.759     | -1.000        | ∞            |
| C       | GBT     | 0.752     | -2.475        | 93           |
| —       | NEWS2   | 0.63–0.64 | -1.1 to -1.6  | 97–223       |

**All models had a negative Utility Score**, meaning they did not provide clinical benefit and performed worse than giving no alerts.

**Alert burden:** For every real sepsis alert, the system generated **93–359 false alerts** (benchmark: 1.4 [10]).

---

## VI. Results — Equity Analysis (Novel Finding)

![w:500](output/10_auroc_by_race.png)

- AUROC varied by up to **0.15** across racial subgroups (primary model, Variant B), from 0.56 (Other) to 0.71 (Asian-Chinese).
- The percentage of patients labelled as septic changed by **7.4–14.2 percentage points** across different label definitions within demographic subgroups.
- The **Unknown/Unable-to-obtain** race groups showed the largest changes (12.3–12.8 pp).
- This is the first study to examine both model performance disparities and label sensitivity across subgroups [13].

---

## VI. Results — Variance Decomposition Summary

| Factor                                     | AUROC Change | Related Hypothesis | Status    |
|--------------------------------------------|--------------|--------------------|-----------|
| Sepsis label definition                    | 0.153        | H1                 | CONFIRMED |
| Model choice                               | 0.145        | H6                 | REJECTED  |
| Split method (temporal vs random)          | 0.123        | H4                 | CONFIRMED |
| Evaluation metric (AUROC vs Utility Score) | 0.170        | H5                 | —         |

**All four analyst decisions create AUROC changes of 0.12–0.17.**

Most studies fix one sepsis label and compare models. This measures only one source of variation while ignoring three other sources of similar importance.

---

## VII. Discussion — Key Finding

The performance collapse reported by Wang et al. [4] is not only a model evaluation issue. This study shows that it is strongly related to how the sepsis label is constructed.

The Sepsis-3 label in MIMIC-IV has three important limitations:

1. **Depends on clinical actions** — No sepsis cases are identified before treatment starts [7].
2. **Sensitive to label definition** — Different reasonable interpretations can produce almost double the number of sepsis cases [5].
3. **Produces poor clinical utility** — All tested models show negative Utility Scores [4].

These findings suggest that improving model complexity alone cannot solve the problem. Better sepsis label design is required.

---

## VII. Discussion — Contributions

| #  | Contribution                                                                                                                        |
|----|-------------------------------------------------------------------------------------------------------------------------------------|
| C1 | Compared three different Sepsis-3 label definitions using the same prediction model on MIMIC-IV [5].                                |
| C2 | Showed that no sepsis cases exist before antibiotics or culture tests, highlighting that the label depends on clinical actions [7]. |
| C3 | Confirmed that all models had negative Utility Scores, extending the findings of Wang et al. [4].                                   |
| C4 | Found that 10 clinical features changed their effects across different label definitions, supporting Lauritsen et al. [11].         |
| C5 | Quantified split optimism: random splits inflated AUROC by 0.123 compared to temporal splits, confirming Guo et al. [6].           |
| C6 | First study to examine how different sepsis label definitions affect racial subgroup analysis [13].                                 |
| C7 | Used a pre-registered, TRIPOD+AI-compliant, fully reproducible research pipeline [9].                                               |

---

## VII. Discussion — Limitations

- **Small external event count:** The eICU dataset had only **63 sepsis cases**, making some evaluation metrics less reliable.
- **Deep learning comparison:** A deep survival model was planned but not implemented.
- **Limited features:** Clinical notes, procedure codes, and ventilator settings were not included.
- **Specific to Sepsis-3:** These findings apply to the Sepsis-3 label and may not apply to other sepsis definitions.

These limits are documented rather than hidden.

---

## VIII. Conclusion and Future Work

1. **Better sepsis labels:** Define sepsis using objective patient measurements (such as lactate levels and organ function) instead of treatment decisions.
2. **Prospective study:** Test the new label in real clinical settings using future patient data.
3. **Better alert threshold:** Choose the alert threshold that maximises clinical benefit (Utility Score) instead of only improving prediction accuracy.
4. **Multi-hospital evaluation:** Test the model in different hospitals and identify an acceptable number of false alerts for clinical use.

---

<!-- _class: refs -->

## References (1/2)

[1] M. Singer, C. S. Deutschman, C. W. Seymour et al., "The Third International Consensus Definitions for Sepsis and
Septic Shock (Sepsis-3)," *JAMA*, vol. 315, no. 8, pp. 801–810, 2016.

[2] K. E. Rudd, S. C. Johnson, K. M. Agesa et al., "Global, regional, and national sepsis incidence and mortality,
1990–2017: Analysis for the Global Burden of Disease Study 2017," *The Lancet*, vol. 395, no. 10219, pp. 200–211, 2020.

[3] C. W. Seymour, F. Gesten, H. C. Prescott et al., "Time to treatment and mortality during mandated emergency care for
sepsis," *New England Journal of Medicine*, vol. 376, no. 23, pp. 2235–2244, 2017.

[4] Z. Wang, W. Wang, C. Sun et al., "A methodological systematic review of validation and performance of sepsis
real-time prediction models," *npj Digital Medicine*, vol. 8, no. 1, p. 190, 2025.

[5] S. N. Cohen, J. Foster, P. Foster et al., "Subtle variation in Sepsis-III definitions markedly influences predictive
performance within and across methods," *Scientific Reports*, vol. 14, no. 1, p. 1920, 2024.

[6] L. L. Guo, S. R. Pfohl, J. Fries et al., "Evaluation of domain generalization and adaptation on improving model
robustness to temporal dataset shift in clinical medicine," *Scientific Reports*, vol. 12, no. 1, p. 2726, 2022.

[7] F. Kamran, D. Tjandra, A. Heiler et al., "Evaluation of sepsis prediction models before onset of treatment," *NEJM
AI*, vol. 1, no. 3, 2024.

[8] R. B. D'Agostino, M.-L. Lee, A. J. Belanger et al., "Relation of pooled logistic regression to time dependent Cox
regression analysis: The Framingham Heart Study," *Statistics in Medicine*, vol. 9, no. 12, pp. 1501–1515, 1990.

---

<!-- _class: refs -->

## References (2/2)

[9] G. S. Collins, K. G. M. Moons, P. Dhiman et al., "TRIPOD+AI statement: Updated guidance for reporting clinical
prediction models that use regression or machine learning methods," *BMJ*, vol. 385, e078378, 2024.

[10] M. Moor, N. Bennett, D. Plečko et al., "Predicting sepsis using deep learning across international sites: A
retrospective development and validation study," *eClinicalMedicine*, vol. 62, 102124, 2023.

[11] S. M. Lauritsen, B. Thiesson, M. J. Jørgensen et al., "The framing of machine learning risk prediction models
illustrated by evaluation of sepsis in general wards," *npj Digital Medicine*, vol. 4, no. 1, p. 158, 2021.

[12] M. A. Reyna, C. S. Josef, R. Jeter et al., "Early prediction of sepsis from clinical data: The PhysioNet/Computing
in Cardiology Challenge 2019," *Critical Care Medicine*, vol. 48, no. 2, pp. 210–217, 2020.

[13] H. Wang, Y. Li, A. Naidech, and Y. Luo, "Comparison between machine learning methods for mortality prediction for
sepsis patients with different social determinants," *BMC Medical Informatics and Decision Making*, vol. 22, Suppl 2, p.
156, 2022.

[14] A. Johnson, L. Bulgarelli, T. Pollard et al., "MIMIC-IV," PhysioNet, 2024. Version 3.1. doi: 10.13026/kpb9-mt58.

[15] T. J. Pollard, A. E. W. Johnson, J. D. Raffa et al., "The eICU Collaborative Research Database, a freely available
multi-centre database for critical care research," *Scientific Data*, vol. 5, 180178, 2018.
