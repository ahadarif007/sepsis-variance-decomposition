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
  section.toc ul { list-style: none; padding-left: 0; }
  section.toc li { margin-bottom: 6px; font-size: 22px; }
---

<!-- _class: lead -->

## Quantifying Model, Label, and Analyst Contributions to Variance in Real-Time Sepsis Onset Prediction

**Abdul Ahad**

M.Sc. in Computing
Department of Computer Science & Applied Physics
Atlantic Technological University (ATU), Galway

---

<!-- _class: toc -->

## Outline

- 1 &nbsp; Background & Research Question
- 2 &nbsp; Study Design & Methodology
- 3 &nbsp; Results — Hypothesis Tests (H1–H6)
- 4 &nbsp; Results — External Validation & Equity
- 5 &nbsp; Variance Decomposition Summary
- 6 &nbsp; Contributions, Limitations & Future Work

---

## 1 &ensp; Background

- **Sepsis** kills ~11 million people per year — nearly 1 in 5 deaths worldwide [1, 2].
- **90+ AI models** have been built to predict sepsis onset in real time [4].
- Wang et al. [4] reviewed 91 models and found:

| Metric               | Internal   | External   |
|----------------------|------------|------------|
| Median AUROC         | 0.811      | 0.783      |
| Median Utility Score | **+0.381** | **-0.164** |

AUROC looks stable externally, but Utility Score turns **negative** — alerts cause more harm than benefit.

**The conventional approach** — fix one label, one split, report AUROC — treats the label, data split, and metric as
minor technical choices. But each can shift results as much as the model itself [5, 6, 7].

---

## Research Question & Hypotheses

> How much of the performance variation comes from the **model** vs. the **researcher's decisions** (label, split,
> evaluation window, metric)?

| ID | Hypothesis                                                            | Threshold  |
|----|-----------------------------------------------------------------------|------------|
| H1 | Label choice affects AUROC ≥ model choice [5]                        | spread ≥   |
| H2 | Feature effects change across label definitions [11]                  | ≥1 sign Δ  |
| H3 | Removing post-treatment data lowers AUROC [7]                         | Δ ≥ 0.03   |
| H4 | Temporal split gives lower AUROC than random split [6]                | Δ ≥ 0.02   |
| H5 | Utility Score drops more than AUROC externally [4]                    | ratio      |
| H6 | Statistical model ≈ gradient-boosted trees [13]                       | |Δ| ≤ 0.02 |

---

## 2 &ensp; Study Design

- **MIMIC-IV v3.1** [14]: 65,078 adult ICU stays — **eICU-CRD v2.0** [15]: 7.9M person-hours (external)
- **Three Sepsis-3 label variants** (Cohen et al. [5]):

| Variant | ABX–Culture window | SOFA baseline         | Sepsis cases |
|---------|--------------------|-----------------------|--------------|
| A Strict   | ±24 h           | Admission SOFA        | 6,252 (9.6%) |
| B Standard | 72 h before / 24 h after | Admission SOFA | 6,447 (9.9%) |
| C Broad    | ±72 h           | Rolling 24 h minimum  | **12,581 (19.3%)** |

- **Primary model:** Dynamic discrete-time competing-risks hazard model (multinomial pooled logistic) [8]
- **Comparators:** GBT (XGBoost), Static Cox, NEWS2, qSOFA, SIRS
- **Validation:** Temporal split (primary), random patient-level split (H4), pre-treatment window (H3), frozen external

---

## 3 &ensp; H1 — Label vs. Model Spread

![w:550](output/09_label_variance_auroc.png)

- **Label spread:** 0.153 AUROC (across A/B/C, same model)
- **Model spread:** 0.145 AUROC (across models, same label B)
- The two spreads are **nearly equal** (Δ = 0.008), meaning the label choice produces comparable variation to model
  choice. H1 threshold met.

---

## H3 — Treatment Leakage

Pre-treatment window: only data **before** the first antibiotic or culture order [7].

- 179,003 patient-hours analysed → **0 sepsis onset events found**
- AUROC cannot be computed — there are no positive cases to discriminate.
- The pre-registered threshold (Δ ≥ 0.03) is not applicable: the finding is qualitatively stronger than expected.

**The Sepsis-3 label cannot exist before the clinical actions that define it.** Models trained on this label are
learning *when doctors act*, not *when patients deteriorate*.

---

## H4 — Split Optimism &ensp;|&ensp; H2 — Coefficient Instability

**H4: Random splits inflate performance (CONFIRMED)**

| Split    | Primary AUROC | GBT AUROC |
|----------|---------------|-----------|
| Temporal | 0.607         | 0.746     |
| Random   | **0.730**     | 0.720     |
| **Δ**    | **+0.123**    | −0.026    |

Random split inflated primary-model AUROC by **0.123** (threshold: 0.02). The GBT model showed a small reverse effect,
suggesting tree ensembles were more robust to temporal shift than the linear model.

**H2: 10 of 25 features** changed sign or magnitude across label variants — including MAP, temperature, bilirubin,
platelets, and vasopressors (CONFIRMED). Feature effects cannot be interpreted without specifying the label [11].

---

## H6 — Model-Class Null (REJECTED)

![w:550](output/09_model_class_auroc.png)

|                   | AUROC     | Utility Score |
|-------------------|-----------|---------------|
| **GBT**           | **0.746** | -4.849        |
| **Primary model** | 0.607     | **-1.004**    |

GBT wins on AUROC (Δ = 0.139, exceeds 0.02 threshold) but has **worse** Utility Score. The model ranking **reverses**
depending on the metric.

All models produced **93–359 false alerts per true alert** (benchmark: 1.4 [10]). Every model had a **negative
Utility Score**.

---

## 4 &ensp; External Validation on eICU-CRD [15]

| Variant | AUROC (MIMIC) | AUROC (eICU) | Drop      |
|---------|---------------|--------------|-----------|
| A Strict   | 0.760      | 0.736        | 0.024     |
| B Standard | 0.607      | **0.437**    | **0.170** |
| C Broad    | 0.759      | 0.725        | 0.034     |

- Variant B (most commonly used definition) showed the **largest external drop**.
- Only 63 sepsis events in eICU — external estimates should be interpreted with caution.
- H5 (utility drops more than AUROC externally) was **not fully tested** because external Utility Score was not
  computed due to differences in eICU event coding.

---

## Equity Analysis

![w:500](output/10_auroc_by_race.png)

- AUROC ranged from 0.56 to 0.71 across racial subgroups (primary model, Variant B).
- **Caution:** Several subgroups had very small event counts (13–58 sepsis cases), so individual AUROC estimates are
  unstable.
- Label sensitivity ranged **8.7–12.8 pp** across racial groups (excluding groups with < 30 stays).
- The label definition itself may affect which patients are identified as septic differently across subgroups [13].

---

## 5 &ensp; Variance Decomposition Summary

| Factor                          | AUROC Δ   | Hypothesis | Status               |
|---------------------------------|-----------|------------|----------------------|
| Sepsis label definition         | 0.153     | H1         | CONFIRMED            |
| Model choice                    | 0.145     | H6         | REJECTED             |
| Split method (temporal vs rand) | 0.123     | H4         | CONFIRMED            |
| Treatment anchoring             | N/A       | H3         | 0 events pre-treatment |
| Metric (AUROC vs Utility)       | —         | H5         | Not fully tested     |

Label, model, and split each produce AUROC shifts of **0.12–0.15**. Most studies vary only the model while holding the
other factors fixed — measuring one source of variation and ignoring others of comparable size.

---

## 6 &ensp; Contributions

| #  | What was done |
|----|---|
| C1 | Compared 3 Sepsis-3 label definitions on the same model and dataset, following Cohen et al. [5] |
| C2 | Showed 0 sepsis events exist before treatment actions, consistent with Kamran et al. [7] |
| C3 | Confirmed all models had negative Utility Scores on MIMIC-IV, consistent with Wang et al. [4] |
| C4 | Found 10 features changed sign/magnitude across labels, consistent with Lauritsen et al. [11] |
| C5 | Quantified split optimism (Δ = 0.123 AUROC, temporal vs random), consistent with Guo et al. [6] |
| C6 | Examined label sensitivity across racial subgroups alongside model performance [13] |
| C7 | Pre-registered, TRIPOD+AI-compliant pipeline with reproducible code [9] |

---

## Limitations & Future Work

**Limitations**
- Small external event count (63 sepsis cases in eICU) limits external metric reliability
- H5 not fully tested — external Utility Score not computed
- Deep learning comparator planned but not implemented
- No clinical notes, procedure codes, or ventilator settings used
- All findings specific to Sepsis-3 on MIMIC-IV/eICU

**Future Work**
1. Define sepsis from objective physiology (lactate, organ function) instead of treatment decisions
2. Prospective validation in real clinical settings
3. Optimise alert threshold for Utility Score rather than AUROC
4. Multi-hospital evaluation with larger external event counts

---

<!-- _class: refs -->

## References

[1] Singer et al., "Sepsis-3," *JAMA*, 2016. &ensp; [2] Rudd et al., "Global sepsis incidence," *Lancet*, 2020.
[3] Seymour et al., "Time to treatment," *NEJM*, 2017. &ensp; [4] Wang et al., "Sepsis prediction review," *npj Digit Med*, 2025.
[5] Cohen et al., "Sepsis-III definition variation," *Sci Rep*, 2024.
[6] Guo et al., "Temporal dataset shift," *Sci Rep*, 2022. &ensp; [7] Kamran et al., "Pre-treatment evaluation," *NEJM AI*, 2024.
[8] D'Agostino et al., "Pooled logistic regression," *Stat Med*, 1990.
[9] Collins et al., "TRIPOD+AI," *BMJ*, 2024. &ensp; [10] Moor et al., "Deep learning sepsis," *eClinMed*, 2023.
[11] Lauritsen et al., "Framing of ML risk models," *npj Digit Med*, 2021.
[12] Reyna et al., "PhysioNet Challenge 2019," *Crit Care Med*, 2020.
[13] Wang et al., "ML mortality + social determinants," *BMC Med Inform*, 2022.
[14] Johnson et al., "MIMIC-IV v3.1," PhysioNet, 2023. &ensp; [15] Pollard et al., "eICU-CRD," *Sci Data*, 2018.

---

<!-- _class: lead -->

# Thank You

### Questions & Discussion

**Abdul Ahad**
M.Sc. in Computing · Atlantic Technological University (ATU), Galway

*Pre-registered protocol. All extraction, modelling, and evaluation code released for reproducibility.*
