# GENAI Handoff — V2 Sepsis Variance Decomposition

> **Read this file first and stop.** It is written so a cold thread can answer most
> questions with **zero further file reads**. Headline numbers are inlined below.
> Only open a data file when you need a number that is *not* here, and then open
> the single file named in §5 — never dump the whole `processed_data/` directory.

Last updated: **2026-08-05 05:00** — full clean pipeline run (12/12 stages, all
six variants) with Protocol Amendments 3 and 4 in force, thesis fully re-synced.
Prior state: Amendment 4 (variant F) source-patched but not yet run; Amendment 3
(fit identification + plausibility filter); Utility Score normalisation fix +
threshold sweep; feedback round 1 write-up `v2/feedback/v1.md`.
Work by Claude (Anthropic) with **Abdul Ahad** (ATU MSc, student ID G00486649).

> ## Where things stand
>
> **§3 below is current.** It describes the run of 2026-08-05 03:03–04:32 plus a
> stage-09 re-run at 04:51. No stale banner applies any more; four earlier
> "superseded" notices have been folded into §3 and §6.
>
> Three headline reversals happened across feedback round 2, and all three are
> now baked into §3 and the thesis. **Do not restate any of the old versions:**
>
> | Old claim | Status |
> |---|---|
> | "Label choice rivals model class as a variance source" (H1) | **Reversed.** Model class 0.1499 vs label 0.0123; the interval on the difference excludes zero. |
> | "No patient develops sepsis before doctors begin treatment" (H3) | **Withdrawn.** The zero is a theorem given the A–C onset rule (§6.14). Variant F records 71 pre-treatment onsets at 0.8081 AUROC. |
> | "Negative Utility Score for every model and every variant" (C3) | **Withdrawn.** Restated as a utility *ceiling*: max 0.039 (GBT/B) over the threshold sweep. |
> | "Sepsis-3 is harder to predict than either limb" (Amendment 2) | **Dead.** φ_anchor = 1.041 [0.990, 1.097], CI includes 1. |
> | "Random splits inflate AUROC" (H4) | **Reversed.** −0.0165 [−0.037, +0.004]; every model scores lower on the random split. |
> | "External AUROC collapses under Variant B" (H5) | **Reversed.** eICU 0.7623 vs internal 0.7590; discrimination transports intact. |
>
> **All four testable hypotheses are non-confirmations**, and H6's
> non-rejection (equivalence between an interpretable hazard model and GBT) is
> now the strongest positive result in the thesis.
>
> Read `v2/feedback/v2.md` for the full write-up: §§0–10 point 1 (Variant B fit),
> §§11–15 point 2 (H3 circularity / Amendment 4), §§16–20 point 3 (Utility),
> §21 the alignment pass.

---

## 1. Mission

**RQ:** In real-time sepsis onset prediction on MIMIC-IV, how is performance
partitioned between (a) model class and (b) the analyst's discretionary choices —
label operationalisation, temporal vs random split, prediction-time anchoring,
evaluation metric?

Pre-registered variance decomposition. Six hypotheses (H1–H6), three Sepsis-3
label variants (A Narrow / B Seymour-Standard / C Liberal), five model classes.
**Variant B is the primary analysis.**

**Protocol Amendment 2** adds two post-hoc, non-pre-registered variants that
split the Sepsis-3 conjunction into its limbs: **E (Anchor-Only)** = suspicion
of infection with the SOFA criterion removed; **D (Deterioration)** = acute
organ dysfunction with the infection anchor removed and vasopressor terms
stripped, so it contains no treatment timestamp.

**Protocol Amendment 4** adds a third: **F (Sepsis-3 Early-Onset)** = Variant
B's membership *exactly*, with the onset re-timed to `min(t_susp, t_SOFA)`. It
isolates onset *timing*, which A–C hold fixed at `t_susp` and never examine.

All three live in `ALT_LABEL_VARIANTS`, never in `LABEL_VARIANTS`, and their
metrics go to separate files — H1 and the decomposition are computed from
unchanged inputs. Their contrasts share exploratory family **E3**, which
Amendment 4 enlarges (so its BH adjustments are stricter than before).

---

## 2. Layout

```
RESEARCH/projects/v2/
├── v2-GENAI/      ← this file
├── feedback/      ← supervisor feedback rounds: `v1.md` (see §7)
├── v2-lr-rp/      ← companion literature review (NARRATIVE, not systematic — see §7)
├── v2-proj/       ← pipeline: config.R, utils.R, clinical_scores.R,
│                    thesis_constants.R, utility_score.py,
│                    00_preregistration.md,
│                    01..12_*.Rmd, run_pipeline.{R,sh}, output/
└── v2-thesis/     ← LaTeX: index.tex + 7 chapter .tex, images/, build.sh,
                     pipeline_constants.tex (GENERATED — see §4)
```

Scripts are **01–12** (an older version of this file said 01–13; that was wrong).
`output/` holds `processed_data/`, `figures/`, `pdf/`, `logs/`.

| # | Script | Phase |
|---|---|---|
| 01 | setup (verify source tables) | 1 |
| 02 | cohort_labels (5 variants: A/B/C + D/E) | 2 |
| 03 | person_hours (heavy: streams ~6 GB) | 2 |
| 04 | sample_size (Riley) | 3 |
| 05 | primary_model (multinomial discrete-time CR) | 4 |
| 06 | comparators (GBT, Cox+Schoenfeld, NEWS2/qSOFA/SIRS) | 4 |
| 07 | metrics_suite | 5 |
| 08 | external_validation (eICU, frozen models) | 6 |
| 09 | variance_decomposition + label-anchor attribution (Amendment 2) | 7 |
| 10 | equity_analysis | 7 |
| 11 | clinical_metrics (calibration curves, DCA, operating points, per-patient, lead time) | 8 |
| 12 | inference (cluster bootstrap, Holm + BH, analysis register) | 9 |

Run: `./run_pipeline.sh` (all) · `./run_pipeline.sh 10 11 12` (subset) ·
`Rscript run_pipeline.R --phase 4`. Thesis: `cd ../v2-thesis && ./build.sh`.
Full run ≈ **60 min** (≈85 min with D/E); stage 05 dominates. Stage 12 alone
≈ 14 min (bootstrap).

`V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07` restricts the per-variant
loops in 02–07 to a subset. **Use it whenever you add a variant** — it is the
only way to avoid an incidental XGBoost refit of A/B/C (see §4).

---

## 3. Current status — **2026-08-05 full clean run, 12/12 stages, all variants**

Everything below is the run of 2026-08-05 03:03–04:32 with Amendments 3 and 4 in
force. Stage 06 ran unrestricted, so **every GBT number moved** — that is
expected and correct here, because the whole run is internally consistent for
the first time. The thesis is fully re-synced: `pipeline_constants.tex` carries
**1,197 macros, 0 missing**, and `index.pdf` builds at 0 errors, 0 undefined
references, 0 undefined citations, 114 pages.

### Confirmatory verdicts (Holm, m=6, FWER 0.05)

| H | Contrast | Est. | 95% CI | Holm p | Verdict |
|---|---|---|---|---|---|
| H1 | label spread − model spread | **−0.1375** | −0.162 – −0.109 | 1.000 | **NOT confirmed — reversed** |
| H2 | unstable covariates | **6 / 22** | — | — | Descriptive (2 sign, 5 magnitude) |
| H3 | pre-treatment onsets | **0** | — | — | **Definitional** (theorem, not finding — §6.14) |
| H4 | random − temporal AUROC | **−0.0165** | −0.037 – +0.004 | 1.000 | **NOT confirmed — reversed** |
| H5 | internal − external AUROC | **−0.0033** | −0.066 – +0.068 | 1.000 | **NOT confirmed** |
| H6 | GBT − primary AUROC | **−0.0129** | −0.027 – +0.002 | 1.000 | **NOT rejected — equivalence holds** |

**All four testable hypotheses fail, two of them directionally.** Every adjusted
p-value is 1.000, so multiplicity control determines no verdict.

Decomposition (ΔAUROC): model class **0.1499** · label **0.0123** · split
**−0.0166** · external transport **−0.0033**. **Model class dominates the label
by more than tenfold**; split and transport are indistinguishable from zero.

### Key headline numbers

- Cohort: **65,078** stays. Sepsis: A 6,252 (9.6%) · B 6,447 (9.9%) · C 12,581 (19.3%).
- Variant B temporal test AUROC: primary **0.7590**, GBT **0.7460**, Cox 0.6444,
  NEWS2 0.6415, SIRS 0.6114, qSOFA 0.6091.
- Calibration is the primary model's strongest result: slope 1.013 / **1.055** /
  1.084 across A/B/C, scaled Brier positive throughout. GBT and Cox are
  miscalibrated by ~3 orders of magnitude (scaled Brier −97 for GBT/B).
- **Utility: no model exceeds 0.039 (GBT/B) at its best threshold.** At the
  fixed 0.5 cut-off the primary model scores exactly 0.000 because it never
  alerts there — that zero is a threshold artefact, not a result. Report
  `utility_max`, not `utility_normalised`, when quoting a ceiling.
- External (eICU): 63 events / 7.87 M person-hours. **AUROC transports intact**
  — B primary 0.7623 external vs 0.7590 internal; A 0.7466, C 0.7489. Operating
  characteristics do not transport (NNE ~75,000).
- Equity: **no** race contrast survives BH (smallest q=0.347). Label-sensitivity
  contrasts do: race-Unknown +3.01 pp (q=0.006), Unable-to-obtain +3.49 pp
  (q=0.009), Spanish +2.61 pp (q=0.006), Private insurance −1.76 pp (q=0.006).

### Amendment 2 — label-anchor attribution

| Variant | What it is | Onsets ≤72 h | κ vs B | Exact onset match | primary AUROC | GBT AUROC |
|---|---|---|---|---|---|---|
| E Anchor-Only | suspicion time, no SOFA gate | 17,251 (26.5%) | 0.432 | **100%** | 0.7697 | 0.7667 |
| B Seymour-Std | both limbs | 5,887 (9.0%) | — | — | 0.7590 | 0.7460 |
| F Sepsis-3 Early | B's membership, min(t_susp, t_SOFA) | 6,074 (9.3%) | **0.983** | **73.7%** | **0.7951** | 0.7632 |
| D Deterioration | physiology-only SOFA ≥2, no treatment timestamp | 27,209 (41.8%) | **0.057** | **6.5%** | 0.8493 | 0.9145 |

**φ_anchor = 1.041 [0.990, 1.097] primary — the CI includes 1**, and E-vs-B is
not significant for the primary model (Δ +0.0107, p_BH = 0.116). GBT's
φ = 1.084 [1.020, 1.146] survives. **"Sepsis-3 is harder than either limb" is
dead** — do not restate it. What survives: D separates (Δ +0.0904, significant)
and F separates (Δ +0.0361, significant). Family E3 is now m=6.

### Amendment 4 — the pre-treatment window

| Variant | Pre-treatment person-h | Onsets | primary AUROC |
|---|---|---|---|
| A / B / C / E | 179,003 | **0** (theorem) | undefined |
| **F** | 178,303 | **71** | **0.8081** |
| D | 147,299 | 1,362 | 0.8498 |

Variant F moved **1,738 of 6,447** onsets earlier (27%, median −14 h, max −48 h);
**419 fall before the treatment anchor** cohort-wide, 71 in the temporal test
set. F also pulls **187 stays into the 72 h horizon** whose `t_susp` fell at
hours 73–120 — so F ⊇ B within the panel and κ(F,B) = 0.983 rather than 1. The
onset rule governs how many events a real-time model can see at all.

## 4. Traps that have actually bitten (do not relearn these)

### The biggest one: silent `intersect()` feature drops
Every stage selected predictors with `intersect(FEATURES, names(dt))`. `CHART_ITEMIDS`
calls the column `heart_rate`; every feature list asks for `"hr"`. Result, undetected
for the whole project: **heart rate was absent from the primary model, the GBT and
the Cox model**; `hr_slope6h` was never computed; `news2_hr` was constant 0 and
`sirs_score` capped at 3 of 4; and eICU (which builds `hr`) was **not** feature-matched
to MIMIC. `03` now renames `heart_rate` → `hr`, and `require_features()` in `utils.R`
**errors** on any declared-but-absent feature. Never widen that to a warning.

### `nnet::multinom` reports `convergence = 0` on a separated likelihood
It means "BFGS's stopping rule fired", not "the fit is identified". The unpenalised
primary spec is completely separated (IRLS at tight tolerance sends all 27
coefficients to |b| ~ 1e15 under **every** variant), so the stopping point is
arbitrary — that is the whole Variant B story. `PRIMARY_MODEL_DECAY = 1e-4` restores
a unique maximum and `check_multinom_fit()` logs convergence + max|coef|, warning
above 20. **If you ever see max|coef| > 20 in the stage-05 log, the fit is not
trustworthy no matter what the convergence flag says.**

### A metric normalised against one reference strategy instead of two
The Utility Score was `U_total / U_max`, so a model that never alerts scored
**−1.000** rather than 0 — and the primary model never alerts at a 0.5 cut-off,
because its largest predicted hourly probability is 0.0988. Reyna et al. (2020)
normalise as `(U − U_inaction)/(U_optimal − U_inaction)`; the inaction baseline
must appear in **both** numerator and denominator. Stage 07 now asserts the two
bounds at run time and **stops** rather than warns: a threshold above every
prediction must score exactly 0, and nothing may exceed 1. The same function
also paid the true-positive reward backwards (`1 − lead/6`, so alerting *at*
onset scored best in a timeliness metric).

Generalise the lesson: **any metric with a "0 means no better than X" reading
needs X computed and subtracted, and a unit test that constructs X.** And never
report a threshold-dependent metric at one cut-off — at a 0.19 % event rate the
0.5 cut-off ranks models by calibration, not by clinical value.

### `sandwich::vcovHC()` does not work on `multinom`
No `estfun` method exists for that class, so the stage-05 call fails, is caught as a
warning, and `vcov_robust` is silently `NULL`. **Cluster-robust SEs for the primary
model were never actually computed**, though the methodology claims them. Unresolved —
see `feedback/v2.md` §6.3.

### GBT drift + thesis sync — now automated, use it
**Fixed 2026-08-04.** `v2-proj/thesis_constants.R` reads the result tables and
writes `v2-thesis/pipeline_constants.tex` (≈292 `\pc`-prefixed macros), then
copies `output/figures/*.png` → `v2-thesis/images/`. `index.tex` `\input`s it.
It runs automatically at the tail of `run_pipeline.{sh,R}` **when every stage
succeeded**, and standalone via `Rscript thesis_constants.R`.

Rules:
- **Never hardcode a result number in a chapter.** Use the macro, e.g.
  `\pcAurocPrimaryB`, `\pcHOneEst`, `\pcKappaVsBA`, `\pcPhiAnchorPrimary`.
- **Never hand-edit `pipeline_constants.tex`** — it is overwritten every run.
  To add a quantity, add a `put()` call in `thesis_constants.R`.
- A quantity the pipeline did not produce renders as a **red ??**
  (`\pcMissing`); one undefined by design (H2's test statistic, H3's p-value)
  renders as an em dash (`\pcNotApplicable`). The generator prints the missing
  list — it is a precise diagnostic of which stage did not run.
- Macro names are letters only (LaTeX forbids digits/underscores): variants
  `A`..`E`, models `Primary/Gbt/News/Cox/Qsofa/Sirs`, hypotheses
  `HOne`..`HSix`.

The old hazard was: the thesis hardcoded every number and kept its own copy of
the figures, so on 2026-07-30 a re-run moved every GBT number and the document
silently kept the stale ones. **Chapters not yet converted to macros still carry
that risk** — the conversion is in progress, so until it is finished also
re-check the hardcoded tables against §5.

On 2026-07-30 a re-run refit GBT slightly differently. **Every non-GBT number still
matched; every GBT number was stale**, cascading into H1, H6, the decomposition,
abstract and conclusion. **Use the GBT rows as the canary** — if they match, the
rest almost certainly does.

### The thesis must never expose its own review history
`feedback/` and this file are **internal implementation records**. The thesis is
not. It must read as a single, self-contained document written in its final form:
no "as suggested", no "an earlier draft", no "previously reported", no
"withdrawn", no reference to reviewers, supervisors or revision history. State a
position analytically instead of narrating a change of position — e.g. C2 is
"deliberately *not* the proposition that…", not "that claim is withdrawn".

**Do keep** the Protocol Amendment 1–4 disclosures. A pre-registration amendment
*must* be declared post-hoc; that is research integrity, not revision history.
Keep the analysis register's [C]/[E]/[D] labels for the same reason.

Audit before any commit that touches `v2-thesis/*.tex`:

```bash
grep -niE "reviewer|supervis|feedback|earlier draft|previous(ly)? (draft|version|reported)|revision history|was originally|is withdrawn|as suggested|in response to|an examiner" v2-thesis/*.tex
```

Exactly five hits are legitimate and expected: the supervisor acknowledgement,
the clinical-staff-feedback future-work item, and three "no second reviewer
screened independently" statements about the *literature search*. Anything else
is a leak. `feedback/v2.md` §13.1a lists the six passages already fixed this way,
so the same phrasing is not reintroduced.

### Stray `.log` files in `v2-proj/` root
Those are **xelatex** logs, not R logs (R logs live in `output/logs/`). xelatex
writes `.log` to the working dir and tinytex keeps it **only when LaTeX warned**.
Root cause is always a real defect. Two seen and fixed:
- **Two captioned `kable()` calls in one chunk** → both get `tab:<chunk-name>` →
  "multiply defined" → cross-refs can resolve to the wrong table. Split the chunks.
- **Long table in a float** → "Float too large for page". Use `longtable = TRUE`.

`run_pipeline.sh` now cleans stray `.log/.tex/.aux/.toc/.out/.knit.md` (it previously
did not; `run_pipeline.R` always did). Fix the warning, don't just delete the log.

### Environment
| Fact | Detail |
|---|---|
| R | `/usr/local/bin/Rscript`, R 4.5.2. LaTeX: `/Library/TeX/texbin/`, **xelatex** for Rmd, **pdflatex+biber** for thesis |
| Python | `/Library/Frameworks/Python.framework/Versions/3.14/bin/python3` (pandas 3.0.4). `/usr/bin/python3` has **no pandas** |
| pandas 3.0 | CSV datetimes load as Arrow `str`; `str − Timedelta` raises. Always `parse_dates=[...]` |
| Data | `RESEARCH/data/mimic-iv-3.1/{hosp,icu}/*.csv.gz`; `data/eicu-collaborative-research-database-2.0/` |
| Paths | `config.R` walks up to find `data/mimic-iv-3.1`; override `MIMIC_RESEARCH_ROOT` |
| FS | macOS case-insensitive — always lowercase `v2` |

### Data / stats
- DuckDB streaming for `chartevents` (3.5 GB) / `labevents` (2.6 GB). Never load whole.
- FiO2 stored as percent → ÷100. Temp in °F **and** °C → convert.
  **Correction (Amendment 3): the clipping this line used to claim was never
  implemented.** Until 2026-08-03 no plausibility filter existed anywhere in the
  pipeline; the panel held HR 5,113,280, RR 7,000,400, SpO2 9,765,430, MAP
  −9,806 to 8,999,090, temp −17.8 to 2,686 °C. `PLAUSIBLE_RANGES` +
  `apply_plausibility()` in `config.R` now do it, applied in 03 and 08 **before**
  the forward-fill. Don't re-trust this bullet's old wording.
- `PRROC::pr.curve()` crashes on NA → `complete.cases()` first.
- eICU microbiology covers ~1.5% of stays → infection triggers on **antibiotics alone**.
  This is why eICU yields only 63 events; it is a *label transport* failure, not a
  population difference. Always state that caveat with external results.
- Per-patient random-intercept GLMM is degenerate on rare outcomes → cluster-robust
  SEs (`sandwich::vcovCL()` on `stay_id`). Don't "fix" the GLMM.
- Proportional hazards always rejected (global Schoenfeld p≈5e-31). **Six** of eleven
  covariates violate individually at α=0.05 (incl. MAP p=0.014) — an earlier draft
  said five.
- Missingness indicators often outweigh the values. Never drop them.
- **Calibration floor must be 1e-6, not 1e-3.** At a 0.2% hourly event rate the
  conventional clamp overwrites 45–72% of predictions. This changed A's slope
  1.169→1.029 and B's 0.318→0.209.
- **DCA threshold grid must be 0.1×–10× prevalence**, not 0.01–0.20. The conventional
  grid sits 5–100× above prevalence and yields a trivially null result.
- Parquet for all intermediate data; CSV only for small result tables (user rule).

---

## 5. Ground truth — read ONE of these, not the directory

All under `v2-proj/output/processed_data/`. **CSV mirrors exist for 11_* and 12_*
— prefer them; they are small and need no arrow.**

| Question | File |
|---|---|
| Headline AUROC/AUPRC/Utility/alert burden | `07_metric_results.parquet` |
| Random-split arm (H4) | `07_metric_results_random.parquet` |
| eICU AUROC | `08_external_validation_results.parquet` |
| Decomposition / verdicts | `09_variance_decomposition_table.parquet`, `09_hypothesis_verdicts.parquet` |
| Calibration (ICI, E50/E90, Brier) | `11_calibration_summary.csv` |
| PPV / NNE / FA-per-patient-day @80% sens | `11_operating_points.csv` |
| Net benefit @prevalence | `11_net_benefit_at_prevalence.csv` |
| Per-patient detection, lead time | `11_patient_level_metrics.csv`, `11_lead_time_summary.csv` |
| Per-hour vs per-patient side by side | `11_hour_vs_patient.csv` |
| eICU operating points | `11_external_operating_points.csv`, `11_external_patient_level.csv` |
| **Alt-label (D/E/F) metrics** | `07_metric_results_altlabel.csv` |
| **Utility across the threshold grid** | `07_utility_sweep.csv` |
| **Max achievable utility + attaining operating point** | `07_utility_max.csv` |
| Anchor attribution + agreement | `09_label_anchor_attribution.csv`, `09_label_agreement.csv` |
| **Pre-treatment window, all variants (H3)** | `09_pretreatment_onsets.csv` |
| **Variant F onset shift** | `03_early_onset_shift.csv` |
| Alt-label CIs + E3 contrasts | `12_altlabel_auroc_ci.csv`, `12_altlabel_contrasts.csv`, `12_anchor_attribution_ci.csv` |
| **H1–H6 with CIs + Holm** | `12_confirmatory_tests.csv` |
| Variant-B CIs, all models | `12_internal_ci.csv` |
| H2 sign/magnitude flags | `12_h2_coefficient_stability.csv` |
| Subgroup AUROC + BH contrasts | `12_subgroup_auroc_ci.csv`, `12_subgroup_auroc_contrasts.csv` |
| Subgroup label sensitivity | `12_subgroup_labelsens_ci.csv`, `12_subgroup_labelsens_contrasts.csv` |
| Confirmatory/exploratory register | `12_analysis_register.csv` |

Equity variables: `config.R` declares four (race, ethnicity, language, insurance) but
MIMIC-IV v3.1 merges race/ethnicity, so **three carry data**: race, language,
insurance. Top 8 levels each.

---

## 6. Design decisions (settled — do not relitigate)

1. Three label variants are the **primary** result, not a sensitivity analysis.
2. Treatment-anchored evaluation → 0 pre-treatment events = the strongest finding.
3. Utility Score is primary; AUROC descriptive. **Amended 2026-08-05:** the
   finding is the *ceiling*, not the sign. Report the score at the 0.5 cut-off
   **and** at its swept maximum, and never make a clinical claim from the
   cut-off alone — at a 0.19 % event rate it separates models by calibration,
   not by clinical value.
4. Competing risks (discharge/death are informative, not censoring) via multinomial.
5. No case-control matching — all at-risk person-hours contribute.
6. GBT is a mandatory comparator, not future work.
7. Temporal split (train 2008–2016 / test 2017–2019) is primary; random 75/25
   seed 42 exists only to quantify optimism (H4).
8. Confirmatory family = Holm m=6 (H2/H3 reserve slots without p-values, which makes
   the correction *stricter*). Exploratory = BH q=0.05 in families E1 (30 AUROC
   contrasts) and E2 (18 label-sensitivity contrasts).
9. The inference layer (stage 12) is **Protocol Amendment 1** and is disclosed as
   post-hoc. Don't present it as pre-specified.
10. Variants D/E are **Protocol Amendment 2**, also post-hoc. Same rule: never
    present as pre-specified, never fold into H1/decomposition/E1/E2. Their
    contrasts are exploratory family **E3** (BH); φ_anchor is a ratio with no
    null at zero and is reported as an interval only, outside the family.
11. Onset time under A/B/C is always `t_susp` — the SOFA delta gates membership,
    not timing. Don't "fix" this in A/B/C; it is the mechanism behind the
    Amendment 2 result. **But do not present it as Sepsis-3 either** — it is a
    non-standard reading, and it is what made H3's zero a tautology. Variant F
    (Amendment 4) carries the standard `min(t_susp, t_SOFA)` timing.
14. **Protocol Amendment 4** (2026-08-05, post-hoc): variant F. H3's zero is
    **entailed** by the A/B/C onset rule — `t_susp = pmax(abx, culture) ≥
    t_anchor` — so it is a proposition with a proof, not a result. The thesis
    states it as Proposition 7.1 and reports F's pre-treatment onset count as
    the empirical counterpart. The absolute claim "no patient develops sepsis
    before doctors begin treatment" is **withdrawn everywhere**; do not
    reinstate it. Kamran et al. is confirmed for label *membership* only.
12. **Protocol Amendment 3** (2026-08-03, post-hoc, same disclosure rule as 1
    and 2): plausibility filter, `hr` naming fix, ridge penalty on the primary
    model, and fit guards. The penalty value `1e-4` is **not** tuned — test
    AUROC moves <0.02 across a 20-point ridge path for every variant, and that
    insensitivity is the justification. Never present it as optimised.
13. **κ(A,B) = 0.267** — the two pre-registered variants agree with each other
    *less* than post-hoc variant E agrees with B (κ = 0.432), despite nearly
    identical prevalence (9.6% vs 9.9%). This is in `09_label_agreement.csv` but
    was missing from this file and the thesis, which is why reviewers assume A
    and B are near-duplicates. Report it wherever the label variants are
    introduced.

---

## 7. Open items / known weaknesses

- **Licence: UNDECIDED.** No `LICENSE` file exists → code is currently *all rights
  reserved*. Thesis claims of "permissive open-source licence" were **removed**
  2026-07-30. Recommendation on the table: **Apache-2.0** (patent grant, stronger
  warranty disclaimer for clinical-adjacent code, NOTICE for citation); CC BY 4.0
  for prose. Must check ATU student-IP policy first.
- **Repo private**, URL deliberately **omitted** from the thesis by the author's
  choice. `design.tex` §Code Availability says "available from the author on
  request" + code-only + PhysioNet DUA forbids data redistribution.
  `.gitignore` verified: 0 patient-data files tracked.
- **The literature review is narrative, not PRISMA-conformant.** The companion doc
  states this explicitly. The thesis previously carried a PRISMA flow diagram full
  of `TODO` placeholders and cited a nonexistent `search_strategy_queries.xlsx`;
  both were replaced with an honest search-and-verification flow (35 searches,
  50 sources, 46 verified, 4 excluded, 33 cited). **Do not reinstate a PRISMA
  diagram unless real screening counts exist.** Novelty claims are "to the best of
  our knowledge" and bounded by a stated limitation.
- **Supervisor feedback round 1 — all five points closed.** Full write-up with
  numbers, file locations and design rationale is `v2/feedback/v1.md`; read it
  instead of re-deriving the mapping. Audited against source 2026-08-03, not
  just against this file. Summary: (1) novelty — hedged in 6 places + documented
  search protocol in `review.tex` §Search Strategy; (2) label circularity —
  Protocol Amendment 2, variants D/E; (3) metrics — new stage 11; (4)
  multiplicity/CIs — Protocol Amendment 1, new stage 12; (5) limitations/ethics
  — CONSORT figure, full ethics section, limitations 4 → 13 (nine of the
  thirteen exist because of this round).
  Two consequences worth remembering: **Amendment 1 reversed H1** (confirmed on
  point estimates, NOT confirmed with intervals), and **Amendment 2 answered
  point 2 by measurement rather than the discussion the feedback would have
  accepted** — the 1,362-vs-0 pre-treatment onset count is now the load-bearing
  evidence for C2 and C7.
  PhysioNet/CinC 2019, SEP-1 and CDC ASE were considered and **rejected as the
  treatment-independent comparator** — all three key on treatment timing, so
  none breaks the circularity. Implementing them for cohort-level comparison
  remains genuine future work.
  `feedback/v1.md` §7 lists what is still exposed at viva; keep it current if a
  later round changes any of it.
- No deep survival comparator. Limited features (no notes/procedures/vent settings).

---

## 8. What NOT to do

- Don't add causal-inference tooling (PSM/IPW/AIPW/E-values) — category error in a
  prediction study. Don't add GBTM.
- Don't make the random split primary. Don't report AUROC as primary.
- Don't "fix" a low Utility Score by tuning the model — the ceiling is the
  result. Do always report the swept maximum alongside it; a single cut-off is
  not evidence about clinical value (superseded rule: "negative utility is the
  result").
- Don't bypass the `00_preregistration.md` G0 gate.
- Don't re-run `03_person_hours.Rmd` casually (~6 GB stream). Stages 07–12 are cheap.
- Don't create new pipeline stages. The author has explicitly ruled this out.
- Don't put variants D/E/F into `LABEL_VARIANTS`, and don't pool their metrics
  with A/B/C. They are post-hoc; H1 and the decomposition must stay on A/B/C alone.
- Don't re-run 05/06 for A/B/C when you only need another variant — use
  `V2_VARIANTS=<ids>`. XGBoost is not bit-stable, so an incidental refit drifts
  every GBT number in the thesis (see the GBT canary above).
- **Don't run stage 07 under `V2_VARIANTS=<subset>`.** It rewrites
  `07_metric_results_altlabel` from whatever ran, so an F-only pass silently
  deletes D's and E's rows. 07 is cheap — always run it unrestricted.
- Don't reinstate "no patient develops sepsis before treatment" (§6 rule 14).
- Don't touch `v2-presentation*/` unless asked. Don't depend on `v1/`.
- Don't leave LaTeX build junk in `v2-thesis/` (keep sources, `images/`, `index.pdf`).
