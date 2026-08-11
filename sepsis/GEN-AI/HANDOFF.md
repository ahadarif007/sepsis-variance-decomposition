# GENAI Handoff — V2 Sepsis Variance Decomposition

> ### What this document is, for a reader who is not a maintainer
>
> This is an **engineering defect log and working handoff**, not part of the
> thesis and not written in its voice. It exists because the pipeline is large
> enough that a defect found once and not written down gets reintroduced, and
> because several defects in it materially changed reported results. It records
> them bluntly, including the observation that the ones found ran in the
> direction that flattered the study — that is the whole point of keeping the
> list, and it is why the amendments in `00_preregistration.md` can be checked
> against something rather than taken on trust.
>
> Three consequences for how to read it. Its tone is diagnostic and internal.
> Its numbers are resynced after a run but the thesis, not this file, is
> authoritative — every reported quantity in the thesis is written mechanically
> from the result tables by `thesis_constants.R`, and where the two disagree
> this file is the stale one. And it is deliberately retained in the repository
> rather than removed before submission: a defect log that disappears when the
> work is examined is worth nothing.

> **Read this file first and stop.** It is written so a cold thread can answer most
> questions with **zero further file reads**. Headline numbers are inlined below.
> Only open a data file when you need a number that is *not* here, and then open
> the single file named in §5 — never dump the whole `processed_data/` directory.

Last updated: **2026-08-10** — **feedback round 12 complete** (`feedback/v6.md`),
an external-examiner-style audit applied to the thesis text and the checks.
`pipeline_constants.tex` carries **1,398 macros, 0 missing**; `index.pdf` builds
at 0 errors / 0 undefined refs / 0 undefined citations / **164 pages**, with
**zero** placeholder markers. Nothing in rounds 10–12 moved a result, an
interval or a verdict.

Structural history, so the older text below reads correctly: round 7 gave the
thesis a **Discussion chapter** (7 chapters + appendix), rewrote Chapter 2 as a
critical review and added the 100-event interpretability floor; rounds 8–9 added
Chapter 4's design-principles section and Appendix B; the licence was decided in
round 7 (Apache-2.0, scoped — §7). The confirmatory canary has held through
every round: H1 −0.137549, H4 −0.016543, H6 −0.012931.

**Two stages are patched but not yet re-run** (§9, Still open): stage 08's
labelled-versus-scored instrumentation and stage 12's register de-duplication.
Both stages' code is newer than their outputs, which is why
`check_consistency.R` reports 4 failures. Neither refits GBT.

Work by Claude (Anthropic) with **Abdul Ahad** (ATU MSc, student ID G00486649).

> ## Where things stand
>
> **§3 below is current.** Run of 2026-08-06 23:17–00:42, 12/12 stages.
> The GBT canary held: every internal AUROC is bit-identical to the 2026-08-05
> run, so the only thing that moved is eICU — which is what should have moved.
>
> **H5 reversed again, and this time towards the hypothesis.** With per-variant
> external labels the internal→external AUROC gap is **+0.0630**
> [−0.0215, +0.1563] rather than −0.0033. Discrimination *does* degrade on
> transport; the study can establish the direction but not the magnitude, on 29
> external events. Full account: `feedback/v2.md` §23.
>
> Six headline reversals happened across feedback round 2, and all are now baked
> into §3 and the thesis. **Do not restate any of the old versions:**
>
> | Old claim | Status |
> |---|---|
> | "Label choice rivals model class as a variance source" (H1) | **Reversed.** Model class 0.1499 vs label 0.0123; the interval on the difference excludes zero. |
> | "No patient develops sepsis before doctors begin treatment" (H3) | **Withdrawn.** The zero is a theorem given the A–C onset rule (§6.14). Variant F records 71 pre-treatment onsets at 0.8081 AUROC. |
> | "Negative Utility Score for every model and every variant" (C3) | **Withdrawn.** Restated as a utility *ceiling*: max 0.039 (GBT/B) over the threshold sweep. |
> | "Sepsis-3 is harder to predict than either limb" (Amendment 2) | **Dead.** φ_anchor = 1.041 [0.990, 1.097], CI includes 1. |
> | "Random splits inflate AUROC" (H4) | **Reversed.** −0.0165 [−0.037, +0.004]; every model scores lower on the random split. |
> | "External AUROC collapses under Variant B" (H5) | **Dead — and so is its first replacement.** Two superseded versions, do not restate either: (i) "B collapses, A and C hold"; (ii) "discrimination transports intact" (the 2026-08-05 eICU 0.7623 vs 0.7590), which was an artefact of one label set shared across all three variants. **Current:** discrimination *degrades* — B 0.7590 → 0.6960, H5 = +0.0630 [−0.0215, +0.1563], Holm p 0.551. Direction established, magnitude not. §23. |
>
> **All four testable hypotheses are non-confirmations**, and H6's
> non-rejection (equivalence between an interpretable hazard model and GBT) is
> now the strongest positive result in the thesis.
>
> Read `feedback/v2.md` for the full write-up: §§0–10 point 1 (Variant B fit),
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
RESEARCH/sepsis/
├── GEN-AI/        ← this file
├── feedback/      ← supervisor feedback rounds: `v1.md` (see §7)
├── lr-rp/         ← companion literature review (NARRATIVE, not systematic — see §7)
├── project/       ← pipeline: config.R, utils.R, clinical_scores.R,
│                    thesis_constants.R, utility_score.py,
│                    00_preregistration.md,
│                    01..12_*.Rmd, run_pipeline.{R,sh}, output/,
│                    check_consistency.R, check_thesis_numbers.R (see §4a)
└── thesis/        ← LaTeX: index.tex + chapters, images/, build.sh,
                     pipeline_constants.tex + table_*.tex (GENERATED — see §4)
```

**Thesis chapter order (changed 2026-08-06, feedback round 7):**
`introduction` · `review` · `methodology` · `design` · `evaluation` (Results) ·
**`discussion`** · `conclusion`, then `\appendix` + `appendix.tex`.
The Discussion used to be a section at the end of `evaluation.tex`; it is now
its own chapter and also absorbed three interpretive passages that were embedded
in Results ("What the External Estimate Can Support", "What Variant D Does and
Does Not Establish", "What the Ablation Establishes"). **Results reports;
Discussion interprets.** Put new interpretation in `discussion.tex`.
`sec:limitations` and `sec:external_interpretability` now live there.

`README.md` at the repo root and `GEN-AI/SCREENCAST.md` are submission
deliverables, added in the same round. The screencast plan is internal.

Scripts are **01–12** (an older version of this file said 01–13; that was wrong).
`output/` holds `processed_data/`, `figures/`, `pdf/`, `logs/`.

| # | Script | Phase |
|---|---|---|
| 01 | setup (verify source tables) | 1 |
| 02 | cohort_labels (5 variants: A/B/C + D/E) | 2 |
| 03 | person_hours (heavy: streams ~6 GB) | 2 |
| 04 | sample_size (Riley) | 3 |
| 05 | primary_model (multinomial discrete-time CR) — **two arms**, see `V2_ARMS` | 4 |
| 06 | comparators (GBT, Cox+Schoenfeld, NEWS2/qSOFA/SIRS) — GBT also ablated | 4 |
| 07 | metrics_suite (+ ablation scoring) | 5 |
| 08 | external_validation (eICU, frozen models, **per-variant labels**, two anchor arms) | 6 |
| 09 | variance_decomposition + label-anchor attribution (Amendment 2) | 7 |
| 10 | equity_analysis | 7 |
| 11 | clinical_metrics (calibration curves, DCA, operating points, per-patient, lead time) | 8 |
| 12 | inference (cluster bootstrap, Holm + BH, analysis register) | 9 |

Run: `./run_pipeline.sh` (all) · `./run_pipeline.sh 10 11 12` (subset) ·
`Rscript run_pipeline.R --phase 4`. Thesis: `cd ../thesis && ./build.sh`.
Full run ≈ **2 h 30 m** end to end (measured on the run that produced the
reported results); stage 05 dominates at ≈73 min, stage 12 ≈19 min (bootstrap),
stages 03 and 08 ≈16 min each. `README.md` carries the per-stage table and is
the authoritative one.

`V2_VARIANTS=D,E ./run_pipeline.sh 02 03 05 06 07` restricts the per-variant
loops in 02–07 to a subset. **Use it whenever you add a variant** — it is the
only way to avoid an incidental XGBoost refit of A/B/C (see §4).

`V2_ARMS=ablated ./run_pipeline.sh 05 06` restricts the **fitting arm** the same
way (Protocol Amendment 5). `full` is the pre-registered specification;
`ablated` drops `ACTION_DERIVED_FEATURES` (vasopressors + the six order flags,
8 of 22). Unset runs both. With `V2_ARMS=ablated` stage 05 skips the main fits
*and* the random-split refit, and 06 skips the comparators *and* the
random-split comparators — so an ablation-only pass cannot touch a single H1,
H4 or H6 input. Ablated output goes to `*_ablated_*` files; the main files are
never overwritten.

---

## 3. Current status — **2026-08-10 full clean run, 12/12 stages, all variants**

The numbers below come from the full run of 2026-08-10 (the 2026-08-06 run they
first appeared in reproduced exactly; only the 15 Riley macros moved, when
`P_CANDIDATE_PREDICTORS` went 25 → 29). **Every AUROC, interval, verdict, equity
and external quantity is byte-identical across the two runs** — the GBT canary
held. The thesis is re-synced: `pipeline_constants.tex` carries **1,398 macros,
0 missing**, and `index.pdf` builds at 0 errors, 0 undefined references,
0 undefined citations, **164 pages**, zero placeholder markers.

### Confirmatory verdicts (Holm, m=6, FWER 0.05)

| H | Contrast | Est. | 95% CI | Holm p | Verdict |
|---|---|---|---|---|---|
| H1 | label spread − model spread | **−0.1375** | −0.162 – −0.109 | 1.000 | **NOT confirmed — reversed** |
| H2 | unstable covariates | **6 / 22** | — | — | Descriptive (2 sign, 5 magnitude) |
| H3 | pre-treatment onsets | **0** | — | — | **Definitional** (theorem, not finding — §6.14) |
| H4 | random − temporal AUROC | **−0.0165** | −0.037 – +0.004 | 1.000 | **NOT confirmed — reversed** |
| H5 | internal − external AUROC | **+0.0630** | −0.022 – +0.156 | 0.551 | **NOT confirmed — but the only near miss** |
| H6 | GBT − primary AUROC | **−0.0129** | −0.027 – +0.002 | 1.000 | **NOT rejected — equivalence holds** |

**All four testable hypotheses fail.** H1 and H4 fail directionally. H1, H4 and H6
carry adjusted p = 1.000, so multiplicity determines no verdict for them. **H5 is
the exception**: its estimate has the predicted sign, its raw p is 0.092 (the
only one below 0.10 in the family) and Holm takes it to 0.551. It fails on
precision — 29 external events — not on direction.

Decomposition (ΔAUROC): model class **0.1499** · **external transport 0.0630** ·
label **0.0123** · split **−0.0166**. **The ordering changed with the eICU fix.**
Model class still dominates, but transport is now second and moves AUROC ~5x more
than the label does. Split remains null. Transport carries by far the widest
interval (it is the only row not measured on the full test cohort), so it ranks
second on the point estimate without being established at that confidence.

### Key headline numbers

- Cohort: **65,078** stays. Sepsis: A 6,252 (9.6%) · B 6,447 (9.9%) · C 12,581 (19.3%).
- Variant B temporal test AUROC: primary **0.7590**, GBT **0.7460**, Cox 0.6444,
  NEWS2 0.6415, SIRS 0.6114, qSOFA 0.6091.
- Calibration is the primary model's strongest result: slope 1.013 / **1.055** /
  1.084 across A/B/C, scaled Brier positive throughout. GBT and Cox are
  miscalibrated by ~3 orders of magnitude (scaled Brier −97 for GBT/B).
- **Utility ceiling, scoped.** Under the *primary* label B no model exceeds
  **0.039** (GBT/B) at its best threshold. Across all variants the maximum is
  **0.1121** (GBT/C) — the unscoped version of this sentence ("no model exceeds
  0.039 at any threshold") was false and was corrected in `abstract.tex` in
  round 10; it survived here until round 11. At the fixed 0.5 cut-off the
  primary model scores exactly 0.000 because it never alerts there — that zero
  is a threshold artefact, not a result. Report `utility_max`, not
  `utility_normalised`, when quoting a ceiling, and always say which variant.
- External (eICU), **Sepsis-3 arm on the microbiology-covered sub-cohort**
  (2,824 of 181,589 stays = 1.55 %; 163,458 person-hours): primary AUROC
  **A 0.6913 / B 0.6960 / C 0.7370** on **27 / 29 / 73** events — all below the
  100-event interpretability floor. NEWS2 **0.5866 / 0.5259 / 0.5074**, i.e.
  near chance externally. Degradation is ordered by label exactly as internally
  (Narrow loses most, Liberal least). NNE 3,985 / 3,372 / 1,396;
  ~12–13 false-alert hours per patient-day.
- External **antibiotic-only sensitivity arm** (full cohort, 7.63 M
  person-hours): **5,589 / 6,140 / 9,886** events, primary AUROC
  **0.6488 / 0.6644 / 0.7209**. Well clear of the floor, same sign and ordering
  as the Sepsis-3 arm — this is the consistency check that lets the thesis
  assert a *direction*. Different target; never pool it with the Sepsis-3 arm.
- **Event rate now reconciles.** Events per 1,000 person-hours, Variant B:
  MIMIC 1.895 · eICU Sepsis-3 0.179 (ratio 0.094) · eICU antibiotic-only 0.805
  (ratio 0.425). Was ratio ≈0.004. Two orders of magnitude recovered, and the
  residual gap localises to the **culture limb**. **Coverage ladder, corrected
  round 8** — all four counts restricted to the 181,589-stay cohort: antibiotic
  limb documented **55,273 (30.44 %)**, culture limb **2,824 (1.555 %)**,
  **both limbs at any offset 232 (0.128 %)**, suspicion pair firing inside the
  variant window **186 / 196 / 211** (A/B/C), Sepsis-3 onsets **27 / 31 / 73**.
  **Reconciling 31 against the 29 in the AUROC bullet above:** an onset falling
  after a stay's last observed hour is right-censoring, not an event (the same
  horizon rule MIMIC applies at 72 h), so 2 of B's 31 are not scored. A and C
  lose none, which is why only B differs between the two counts. No onset is
  lost for any other reason — stage 08 now asserts that and logs it.
  The old "32.66 %" was a defect: `n_abx_stays` counted distinct stays in the
  antibiotic *tables* (59,304) against a *cohort* denominator. Fixed in stage
  08; the ladder is monotone, so the "240 vs 2,824" question is answered —
  they were different quantities, and 232 is the both-limbs count.
- Equity: **no** race contrast survives BH (smallest q in family E1 is 0.0660,
  the Private-insurance/GBT contrast; no *race* contrast is below q=0.16). Label-sensitivity
  contrasts do: race-Unknown +3.01 pp (q=0.006), Unable-to-obtain +3.49 pp
  (q=0.009), Spanish +2.61 pp (q=0.006), Private insurance −1.76 pp (q=0.006).
- **Sample size, on the correct unit (stage 04, rewritten round 7).** Riley
  assumes independent observations, so the criterion is parameterised on the
  **stay**: min-N **1,729 / 1,666 / 991** stays (A/B/C) at stay-level prevalence
  8.78 / 9.16 / 17.76 %, against **52,946** training stays — margins
  **30.6x / 31.8x / 53.4x**. The per-hour minima (60,553 / 59,174 / 27,920) are
  retained as a labelled reference only. **Updated round 10**: the parameter
  count supplied to `pmsampsize` was corrected from 25 to **29**, the number of
  terms the model actually estimates per outcome (22 covariates + 6 spline
  columns + intercept). Margins fall ~14 % and remain enormous. **Never compare a per-hour minimum
  against the 2.3 M row count.**
- **Equity, after the 100-event interpretability floor (round 7).** Family E1
  shrank from **30 contrasts to 6**, and **none survives BH** (was one: the
  Haitian-language contrast on 12 events, now below the floor and out of the
  family). Only **2 of 8 racial strata** clear the floor — White (597 events) and
  **Unknown (235)**, a missingness category — so *the study contains no
  sufficiently powered comparison between two racial strata that both record an
  actual demographic answer*. That sentence is in the thesis and should not be
  softened. Label-sensitivity contrasts are unaffected (stay-level proportions,
  no floor): race-Unknown +3.01 pp (q=0.006), Unable-to-obtain +3.49 pp
  (q=0.009), Spanish +2.61 pp (q=0.006), Private insurance -1.76 pp (q=0.006) —
  and **both significant racial strata are missingness categories**, which is why
  the thesis reads this as a finding about documentation, not race.
- **eICU GBT comparator now exists** (§9a fix took): external AUROC **0.6812**
  under Variant B, against the primary model's 0.6960.
- **Ablation (Amendment 5) landed on the strongest decision-table row.**
  Dropping the 8 action-derived covariates costs **-0.0076** AUROC (primary, B)
  and **-0.0063** (GBT, B) — under 0.01 everywhere — while the cross-label
  unstable count falls from **6 of 22 to 1 of 14** (27.3 % -> 7.1 %). By kind in
  the full fit: action-derived **4/8 = 50 %** unstable, physiological
  **2/14 = 14.3 %**. Reading, now written into the thesis: the features that
  record clinician behaviour contribute almost nothing to discrimination and
  carry most of the label sensitivity.

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

### A label built once and reused across the variant loop
Stage 08 opened with `v <- LABEL_VARIANTS[["B"]]`, built **one** `event` column
from it, and then looped `for (vid in names(LABEL_VARIANTS))` swapping only the
*model*. The three external variants were one label wearing three names. The
tell was there in the output for months: `pred_news2` scored **0.6058 under all
three variants** and `n_events` was **63 in all three rows**. NEWS2's predictor
is label-invariant, but its AUROC cannot be — AUROC is a property of the
predictor *and* the outcome. The thesis had explained the identity away as
"NEWS2 is label-invariant because it uses only physiological features", which is
a true sentence about the wrong object and it concealed the defect.

Generalise: **whenever a loop is supposed to vary factor X, find a quantity that
must move when X moves and assert that it does.** Stage 08 now hashes the three
onset sets and `stop()`s if they are identical. Do not weaken it to a warning.

Three further defects lived in the same chunk and are fixed together:
- **Negative `culturetakenoffset`** (pre-ICU cultures; the first rows of the
  file are −688 and −5481) made `t_susp_h < 0`, so `at_risk <- is.na(onset) |
  hour <= onset` was FALSE for every hour and `grid[at_risk == TRUE]` **deleted
  the whole stay**. Out-of-range onsets must make a stay *non-septic*, never
  absent — that is what MIMIC's `onset_time < intime → NA` rule does.
- **Only `medication.csv.gz` was read.** eICU splits drugs across `medication`
  (orders) and `infusionDrug` (infusions); vancomycin, pip-tazo and every
  vasopressor live largely in the latter. Both are read now, and vasopressors
  finally reach the SOFA cardiovascular component.
- **The SOFA gate was an absolute `sofa_total >= 2` evaluated per row**, not
  MIMIC's delta-vs-baseline inside the variant's window. Since `score_sofa()`
  substitutes assumed-normal values for missing components, an absolute
  threshold rejects on *missingness*, which biases hardest in the database with
  sparser labs. It also nulled a stay-level `onset_hour` row by row, corrupting
  the at-risk set.

### Documentation that contradicts the code — now three instances
This is the project's most repeated defect, and every instance ran in the
direction that flattered the study. Recorded together so the pattern is visible:

1. **`evaluation.tex` explained an identical eICU NEWS2 AUROC as "NEWS2 is
   label-invariant"** — a true sentence about the wrong object, which concealed
   a label that was never varied (§22.3).
2. **`evaluation.tex` and this file both said eICU "triggers infection on
   antibiotics alone"** while stage 08 did an *inner* merge requiring both limbs.
   The documented mitigation was never implemented (§4, eICU bullet).
3. **`design.tex` Stage 05 claimed "Standard errors are cluster-robust (grouped
   by stay)"** while `methodology.tex` correctly said no analytic variance
   exists for a `multinom` fit and all uncertainty comes from the bootstrap. The
   two chapters contradicted each other and the false one came first. Fixed in
   round 9 (`feedback/v2.md` §30.4).

**Generalise:** when a chapter states what the code does, check the code, not
another chapter. Chapter 4 §Design Principles now states this as an explicit
architectural principle — interfaces fail loudly or not at all — precisely
because the failures above were all silent.

### `news2()` scores a FALSE consciousness flag as 3, and NA as 0
`avpu_alert <- !is.na(gcs) & gcs >= 14` maps "unmeasured" to `FALSE`, which
`news2()` charges **3 points**. eICU has no GCS in `vitalPeriodic`, so every
external person-hour carried a spurious +3 — constant, therefore invisible in
AUROC, but it invalidates every threshold, specificity and alert-burden number
compared across cohorts. `avpu_alert_flag()` in `clinical_scores.R` is the
correct helper and stage 08 uses it. **MIMIC (`03`) deliberately still does
not**: 3.2 % of its person-hours have no GCS after LOCF, so switching would
move every NEWS2 number in the thesis and needs a full 03–12 re-run. That is
an open decision, flagged at the call site and in `feedback/v2.md` §22.

### `sandwich::vcovHC()` does not work on `multinom` — **fixed round 8**
`sandwich` ships a `bread` method for that class but **no `estfun`**, so the
stage-05 call failed, was caught as a warning, and `vcov_robust` was silently
`NULL`. Cluster-robust SEs for the primary model were never computed, though
the methodology claimed them.

`utils.R` now supplies `estfun.multinom` (score for row *i*, non-reference
category *k*, is `x_ij (y_ik − p_ik)`; `multinom` already stores that residual
matrix), registers it **into the `sandwich` namespace** — `registerS3method`
against the global env fails with "object 'estfun' not found" — and adds
`multinom_vcov_cluster()`, which returns `NULL` **with a logged reason** rather
than silently. Stage 05 fits with `Hess = TRUE` (bread needs it) and saves
`05_vcov_cluster[_arm]_<vid>.rds`.

Verified on synthetic data: scores sum to ~0 at the optimum and an unclustered
unadjusted sandwich reproduces `vcov(fit)`. **Not yet run on the real fits** —
needs `./run_pipeline.sh 05` then `07 12`. `Hess = TRUE` runs after the
optimiser stops, so coefficients should be bit-identical, but **check the canary
(H1 −0.13755, H4 −0.01654, H6 −0.01293) before trusting the run**. With
`decay > 0` this is the covariance of the *penalised* estimator; describe it as
a ridge-regularised sandwich. Full account: `feedback/v3.md` §5b.

### GBT drift + thesis sync — now automated, use it
**Fixed 2026-08-04.** `project/thesis_constants.R` reads the result tables and
writes `thesis/pipeline_constants.tex` (≈292 `\pc`-prefixed macros), then
copies `output/figures/*.png` → `thesis/images/`. `index.tex` `\input`s it.
It runs automatically at the tail of `run_pipeline.{sh,R}` **when every stage
succeeded**, and standalone via `Rscript thesis_constants.R`.

Rules:
- **Never hardcode a result number in a chapter.** Use the macro, e.g.
  `\pcAurocPrimaryB`, `\pcHOneEst`, `\pcKappaVsBA`, `\pcPhiAnchorPrimary`.
- **Never hand-edit `pipeline_constants.tex`** — it is overwritten every run.
  To add a quantity, add a `put()` call in `thesis_constants.R`.
- **Tables too large for one-macro-per-cell are generated whole.**
  `write_table()` in `thesis_constants.R` emits a complete `tabular` to
  `thesis/table_<name>.tex`; the chapter keeps only `\begin{table}`,
  `\input{table_<name>}`, caption and label. Currently `table_equitylabel` and
  `table_equitylabelcontrasts`. **Emit the whole environment, never just the
  rows** — `\input` of a partial alignment body fails with
  "Misplaced `\noalign`" at the `\bottomrule`, because TeX's alignment scanner
  needs the `&` and `\\` tokens in the same expansion context.
  **Four** such tables now exist: `table_equitylabel`,
  `table_equitylabelcontrasts`, and (added round 7) `table_equityperformance`,
  `table_equitycontrasts`. The last two *had* to be generated: with the
  subgroup event floor in force the row count is no longer fixed, so a
  one-macro-per-cell grid would either leave red `??` cells or silently drop a
  stratum. `table_*.tex` files are generated: never hand-edit, never commit a
  fix to them.
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

### A caption is prose, and prose is outside the macro guarantee
`thesis_constants.R` protects *values*: a missing quantity typesets as a red
`??`. It cannot protect a **qualitative claim**, and a number in a caption is
protected only if it is written as a `\pc` macro. That is how Figure 5.9 kept
"Both are of similar size" through the H1 reversal (round 8), and how
`discussion.tex` kept "two sources of variance of comparable size". No
mechanism could have caught either; only a read.

**When a headline reverses, grep the prose for the old claim's adjectives**,
not just for its numbers:

```bash
grep -niE "comparable|similar size|slightly exceeds|same order|label (dominates|rivals)|no patient develops|inflates? AUROC|transports intact|harder than either limb" thesis/*.tex
```

Legitimate hits describe prior work's claim, the study's stated expectation, or
an explicit negation. Anything asserting the reversed claim in the thesis's own
voice is a leak.

### TeX does not warn about an over-wide table
A `tabular` is typeset at its natural width, so there is no target width for it
to be overfull *against*: it silently runs past the right margin and `Overfull
\hbox` never fires. Round 8 found **seven tables and two TikZ diagrams** over
the margin (worst +125 pt) with **zero** LaTeX warnings, by measuring glyph
positions in the built PDF against the footer's right edge.

`adjustbox` is loaded in `index.tex`; wrap a wide table as
`\adjustbox{max width=\textwidth}{...}` — inert unless the natural width
exceeds the text block. The four generated equity tables are wrapped **at the
`\input` site**, so `write_table()` keeps emitting complete `tabular`
environments. Long `\texttt{}` file names have no break points and need
`\allowbreak` (`\emergencystretch` is set to 3 em; `hyphenat[htt]` was tried
and rejected — it fixes the overflow but adds 31 font-shape warnings).

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

Audit before any commit that touches `thesis/*.tex`:

```bash
grep -niE "reviewer|supervis|feedback|earlier draft|previous(ly)? (draft|version|reported)|revision history|was originally|is withdrawn|as suggested|in response to|an examiner" thesis/*.tex
```

**Eight hits are legitimate and expected** (was five before feedback round 7):
the supervisor acknowledgement; the clinical-staff-feedback future-work item;
**four** "no second reviewer screened independently" statements about the
*literature search* (`review.tex` ×2, `methodology.tex`, `discussion.tex`); one
"not previously reported" in `conclusion.tex` C1, which is a claim about prior
art rather than about this document; and one false positive on "unsupervised" in
`review.tex`. Anything else is a leak. `feedback/v2.md` §13.1a lists the six
passages already fixed this way, so the same phrasing is not reintroduced.

### Stray `.log` files in `project/` root
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
- eICU microbiology (`microLab.csv.gz`) covers **2,923 distinct unit stays**,
  ~1.4 % of the cohort. **Correction: the claim that "infection triggers on
  antibiotics alone" was never true of the code.** Stage 08 did an *inner*
  `merge()` of antibiotics and cultures, so it required both — and the thesis
  said the opposite. Documentation and implementation disagreed for the whole
  project. The rewrite makes the Sepsis-3 arm explicit (restricted to the
  micro-covered sub-cohort, so the denominator only holds person-hours in which
  an onset is observable) and adds a separate, clearly-labelled antibiotic-only
  arm on the full cohort. Never let those two arms be pooled or substituted.
- Per-patient random-intercept GLMM is degenerate on rare outcomes → cluster-robust
  SEs (`sandwich::vcovCL()` on `stay_id`). Don't "fix" the GLMM.
- Proportional hazards always rejected (global Schoenfeld p≈5e-31). **Six** of eleven
  covariates violate individually at α=0.05 (incl. MAP p=0.014) — an earlier draft
  said five.
- Missingness indicators often outweigh the values. Never drop them.
- **Calibration floor must be 1e-6, not 1e-3.** At a 0.2% hourly event rate the
  conventional clamp overwrites **46.8 / 39.6 / 8.8 %** of the primary model's
  predictions under A/B/C. (The old "45–72%" and the slope pair
  "1.169→1.029 / 0.318→0.209" are pre-Amendment-3 numbers — the current
  clamped-vs-floored contrast for A is **1.137 → 1.013**. Both figures are now
  generated as `\pcPctBelowClampPrimary*` and `\pcCalibSlopeClampedPrimary*`.)
- **DCA threshold grid must be 0.1×–10× prevalence**, not 0.01–0.20. The conventional
  grid sits 5–100× above prevalence and yields a trivially null result.
- Parquet for all intermediate data; CSV only for small result tables (user rule).

---

## 4a. The three checkers — all wired, none needs remembering

**All three now run automatically.** `run_pipeline.sh` calls
`check_consistency.R` and `check_thesis_numbers.R` at its tail after
`thesis_constants.R`; `build.sh` calls `check_thesis_margins.R` on the PDF it
just produced. Run them by hand only when you have edited the thesis without
re-running anything:

```bash
cd sepsis/project
Rscript check_consistency.R       # cross-file arithmetic + claim predicates
Rscript check_thesis_numbers.R    # literal provenance over the thesis sources
Rscript check_thesis_margins.R    # does anything actually pass the text block
```

`run_pipeline.sh` exit codes: **1** a stage failed · **2** a macro or table body
is unresolved · **3** a consistency check failed · **4** the thesis types a
result-shaped number with no recorded provenance. `build.sh` exits non-zero if
a page runs past the text block.

None of them executes the pipeline; all read files already on disk and take
seconds. They exist because `thesis_constants.R` guarantees that a number in
the thesis *is* the number the pipeline produced, and cannot check the three
things that actually went wrong repeatedly.

**`check_consistency.R`** asserts identities that must hold between tables
written by different stages: the decomposition row against its hypothesis
estimate, every printed rate against its own events/person-hours, the eICU
labelled count against the scored count, H2's counts across the three files
that report them, the cohort ladder's arithmetic, family sizes against row
counts, and (added round 12) that no analysis is registered twice. A failure is
a defect in the results or in how they are reported. **Fix the source, not the
check.**

**`check_thesis_numbers.R`** (added round 12) enforces the Declaration's claim
that no quantity this study estimates is typed by hand. It sorts every
result-shaped literal in `thesis/*.tex` into CITED (a citation in the same
paragraph), ALLOWED (an explicit list of design constants and source-data
facts, each with its reason written beside it) or REVIEW, and exits non-zero
while anything is in REVIEW. It is currently **0 review / 15 allowed / 51
cited**.

**`check_thesis_margins.R`** (added round 12) measures the built PDF. LaTeX
cannot answer this question at all: a `tabular` is set at its natural width, so
there is no target width for it to be overfull *against*, and it passes the
right margin in silence. The script infers the text block's right edge from the
document itself (the *mode* of per-page maxima, since pages ending mid-paragraph
drag an average left of the true edge) and reports any page beyond it. Page 1 is
exempt by design: the ATU title page sets its own `\newgeometry` for the green
bar. Regression-tested against the pre-fix PDF, where it correctly reports the
40 pt overrun.

### What is checked mechanically and what is not

`check_consistency.R` §9 holds the **claim predicates**: the sentences the
thesis states in words, written as assertions on the result tables. Currently
eight, among them "the two counts sum to seven across six covariates", "both
sign reversals fall below their own estimation noise", "model class moves AUROC
more than tenfold the label", and the abstract's scoped utility ceiling. **Add
one whenever a chapter asserts a relation rather than a value** — that is the
only way a re-run can tell you a sentence has become false.

What stays a human read: `check_thesis_numbers.R` prints an **advisory** list of
comparative claims ("an order of magnitude", "twice as many", "tenfold") that
carry no macro in their sentence. It does not gate on them, deliberately:
gating would need an allow-list of every idiom, and a checker people silence by
reflex is worse than none. Twenty-five is a scannable list, and it is the right
thing to re-read after a run that moved numbers.

Two design points, both learned the expensive way. Value-matching a literal
against `pipeline_constants.tex` does *not* work: with 1,398 macros a
three-decimal figure from the literature collides with one by chance often
enough that the match means nothing, so the classification is by **provenance**,
not arithmetic. And one- and two-decimal numbers are excluded on purpose: here
they are pre-registered thresholds, file sizes and TikZ geometry, and a checker
that fires on those is one people stop reading.

---

## 5. Ground truth — read ONE of these, not the directory

All under `project/output/processed_data/`. **CSV mirrors exist for 11_* and 12_*
— prefer them; they are small and need no arrow.**

| Question | File |
|---|---|
| Headline AUROC/AUPRC/Utility/alert burden | `07_metric_results.parquet` |
| Random-split arm (H4) | `07_metric_results_random.parquet` |
| eICU AUROC (Sepsis-3 arm, micro-covered sub-cohort) | `08_external_validation_results.csv` |
| eICU AUROC (antibiotic-only sensitivity arm) | `08_external_validation_results_abxonly.csv` |
| **eICU vs MIMIC event rates side by side** | `08_event_rate_reconciliation.csv` |
| eICU labelling-input coverage | `08_eicu_coverage.csv` |
| eICU onsets per variant × anchor | `08_eicu_label_summary.csv` |
| H5 internal vs external + interpretability flag | `08_h5_internal_external.csv` |
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
| **CONSORT cohort ladder (counts + exclusions)** | `02_cohort_flow.csv` |
| **H2 instability vs pooled SE (Amendment 7)** | `12_h2_stability_uncertainty.csv` |
| **Ablation ΔAUROC / ΔUtility (Amendment 5)** | `07_ablation_metrics.csv` |
| Ablated-arm coefficient stability | `05_h2_stability_ablated.csv` |
| H2 instability split by feature kind | `12_h2_stability_by_kind.csv` |

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
   the correction *stricter*). Exploratory = BH q=0.05 in families E1 (**6**
   AUROC contrasts — 30 were computed; Amendment 6's 100-event interpretability
   floor restricts the *inferential* family to 6, see rule 16) and E2 (18
   label-sensitivity contrasts).
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
15. **Protocol Amendment 5** (2026-08-06, post-hoc, same disclosure rule as
    1–4): the action-derived feature ablation. `ACTION_DERIVED_FEATURES` is the
    8 of 22 covariates that record clinician behaviour rather than the patient —
    `vaso_any`, `norepi_epi_any` and the six `*_measured` order flags. The
    ablated arm refits primary + GBT without them, everything else held fixed.
    **The boundary is deliberately conservative**: forward-filled lab *values*
    are retained even though a value exists only because someone ordered the
    test, because dropping them would confound the ablation with a loss of
    physiological signal. Do not "improve" the ablation by widening it — the
    conservative boundary is what makes the contrast interpretable, and the
    limitation is stated in the thesis. Exploratory: enters no hypothesis, no
    confirmatory family, no decomposition.
16. **Two subgroup thresholds, and the distinction is load-bearing**
    (2026-08-06, feedback round 7). `MIN_SUBGROUP_EVENTS = 5` decides whether a
    subgroup AUROC is **computed**; `MIN_SUBGROUP_EVENTS_INTERPRET = 100`
    (defined as `MIN_EXTERNAL_EVENTS`, not as a literal, so the two floors
    cannot drift) decides whether it is **interpreted**. Below-floor strata are
    still estimated and tabulated — flagged `†` — because the figure showing
    their intervals reaching the chance line *is* the argument for the floor;
    but they are excluded from every spread statement and **from exploratory
    family E1**, so BH corrects over the contrasts the study will read.
    Do not "simplify" this by raising the estimation floor: suppressing the
    small strata hides the cohort's composition, which is the thing the section
    is about.
17. **The subgroup range is never compared against the decomposition spreads**
    (same round). Three independent reasons, all stated in `evaluation.tex`
    §Equity: different estimands (whole-cohort contrast vs extreme order
    statistic over disjoint slices), different information, and the range of
    noisy estimates is upward-biased by construction. Do not reinstate "the
    subgroup spread is wider than the model-class spread" — it is not an effect
    size.
18. **MIMIC's equity strata are administrative, not populations** (same round).
    `race` is one registration code mixing broad and granular levels from the
    same population (`WHITE` vs `WHITE - OTHER EUROPEAN`, `ASIAN` vs
    `ASIAN - CHINESE`), so the reference level is a *residual* category and the
    strata are not disjoint populations; `UNKNOWN` and `UNABLE TO OBTAIN`
    record the absence of an answer. Stated up front in `sec:equity_strata`.
    **Consequence for C5:** both surviving label-sensitivity contrasts are
    missingness categories and no stratum recording an actual demographic
    answer differs from the reference, so the finding is read as one about
    **documentation completeness**, not about race. Do not restate it as a
    racial disparity.
19. **Riley's criterion is applied on the stay, not the person-hour** (same
    round). It assumes independent observations and person-hours are ~45
    correlated rows per stay. Stage 04 now runs `pmsampsize` twice — stay-level
    (the verdict) and per-hour (reference only, labelled as such). Never
    compare a per-hour minimum against the 2.3 M row count.
13. **κ(A,B) = 0.267** — the two pre-registered variants agree with each other
    *less* than post-hoc variant E agrees with B (κ = 0.432), despite nearly
    identical prevalence (9.6% vs 9.9%). This is in `09_label_agreement.csv` but
    was missing from this file and the thesis, which is why reviewers assume A
    and B are near-duplicates. Report it wherever the label variants are
    introduced.

---

## 7. Open items / known weaknesses

- **Licence: DECIDED (2026-08-06). Apache-2.0, deliberately scoped.**
  `LICENSE` (Apache-2.0 verbatim, copyright line set to Abdul Ahad 2026) and
  `NOTICE` now exist at the repo root, and the seven pipeline source files carry
  `SPDX-License-Identifier: Apache-2.0` headers.
  **The scoping is the point and must not be flattened.** `NOTICE` §1 covers
  `sepsis/project/` source; §2 *excludes* the ATU thesis template
  and brand assets (`index.tex` title page, `atu-logo-*.png`, `leftbar.png` ---
  ATU's rights, reproduced only so the thesis typesets) and excludes both
  databases absolutely; §3 lists the eight published methods implemented here
  from their definitions, attributing each and stating that no implementation was
  copied from third-party source; §4 puts the thesis prose, figures and the
  companion review *outside* Apache-2.0 as scholarly work available for citation
  with attribution, and notes ATU's student-IP policy may also apply; §5 is the
  not-a-medical-device disclaimer. If a future round touches licensing, keep the
  §2/§3 boundaries --- the author's instruction was Apache-2.0 "where it's my
  original work and not others' work".
- **Repo URL: `https://github.com/ahadarif007/RESEARCH`** (the tree's own
  `origin`), set in `index.tex` as `\repourl`. The repo-visibility position
  **reversed** in feedback round 7: it was private with the URL deliberately
  omitted, but the submission page penalises a missing repository link as a
  failure to submit, so `design.tex` §Code Availability and Appendix A now state
  a public repository. **The thesis asserts the repo is public --- it must
  actually be public before submission, or that sentence is false.** Code-only +
  PhysioNet DUA forbids data redistribution is unchanged. `.gitignore` verified:
  0 patient-data files tracked. **One hygiene item before going public:**
  `.claude/settings.local.json` is tracked (it predates the `.claude/` ignore
  rule) and exposes local paths under `/Users/arif/`; `git rm --cached` it.
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

## 7a. Deadlines, and the presentation freeze

| Item | Date / value |
|---|---|
| Thesis deadline | **17:00, 19 October** |
| Viva schedule published | 21 October |
| Vivas | **29–30 October** |
| Presentation | 15 min + 15 min questions |

**Untracked as of round 10.** The freeze was right while results were moving,
but it stopped being right once the repository became a submission deliverable:
both decks were tracked, `presentation-v2/index.pdf` was committed, and an
examiner browsing the repo the thesis points them at would have found a deck
tagging **H6 as REJECTED** — contradicting the thesis's headline positive
result — alongside primary AUROC 0.607 and the withdrawn "Variant B collapse"
claim. `git rm -r --cached` was applied and both directories added to
`.gitignore`. **The files are still on disk and nothing was deleted.** Before
either deck is shown or re-tracked it must be rebuilt against
`pipeline_constants.tex`.

**Do not work on `presentation*/`.** This is a standing instruction, not an
oversight: results moved in every feedback round, so any polish before the
results settled would have been discarded. The skeleton (11 section files, same
in both decks) is sound and is what October returns to. The current deck is
**32 slides ≈ 28 s each — not deliverable**, and spends **six slides on
background before any method**.

**Before either deck is ever shown, it must be wired to
`pipeline_constants.tex`.** Neither contains a single `\pc` macro and both
predate several rounds of fixes. The critical one:

> **The deck tags H6 as `\tagrejected`. H6 is NOT rejected** — its
> non-rejection is the thesis's strongest positive result. Presenting the deck
> as-is would contradict the headline finding in front of the panel.

Also stale on the slides: primary AUROC 0.607 (now 0.7590), primary Utility
−1.004, GBT Utility −4.849, model spread 0.145, and the withdrawn "Variant B
showed a large performance drop"; plus Strict/Broad in `05.materials.tex`
against Narrow/Seymour-Standard/Liberal in `07.results.tex`, and a deck title
that differs from the thesis title. A 15-minute slide budget (16–18 slides) is
drafted in `feedback/v2.md` §29.4.

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
- Don't reinstate "discrimination transports intact to eICU" or "Variant B
  collapses; A and C hold" (§4, the variant-loop trap). Both were artefacts of
  a single reused label.
- Don't pool the eICU antibiotic-only arm with the Sepsis-3 arm, and don't quote
  it when the Sepsis-3 arm is inconvenient. It labels a different target.
- Don't touch `presentation*/` unless asked. Don't depend on `v1/`.
- Don't leave LaTeX build junk in `thesis/` (keep sources, `images/`, `index.pdf`).

---

## 9. Runs — all complete

The three pieces of work that were patched-but-unexecuted at round 7
(9a eICU GBT comparator, 9b Protocol Amendment 5 ablation, 9c feedback round 7)
have all run, as has the full pipeline of 2026-08-10.
`thesis_constants.R` reports **1,398 macros, 0 missing**; `index.pdf` builds at
0 errors, 0 undefined references, 0 undefined citations, **164 pages**. Results
are folded into §3 above.

**Two stages are patched but not yet re-run** — see *Still open* at the end of
this section. Until they are, `check_consistency.R` reports 4 failures, all of
them the outputs being older than the code.

Verification checks that were specified in advance and passed:

| Check | Result |
|---|---|
| **Canary:** H1–H6 in `12_confirmatory_tests.csv` | **unchanged** — H1 −0.13755, H4 −0.01654, H6 −0.01293, bit-identical |
| eICU GBT row present in the external table | yes, AUROC 0.6812 (B) |
| `07_ablation_metrics.csv` | 6 rows, paired deltas, all \|ΔAUROC\| < 0.01 |
| `12_h2_stability_by_kind.csv` | action-derived 4/8, physiological 2/14 |
| `04_sample_size.parquet` | has `min_n_riley_stay` / `stay_prevalence` / `margin_stay`; `min_n_riley` gone |
| `12_subgroup_auroc_ci.csv` | 36 rows (unchanged), gains `interpretable` + `min_events_interpret` |
| `12_subgroup_auroc_contrasts.csv` | **6 rows** (was 30); every row `n_events >= 100` |

The command, recorded for the next time a stage needs re-running:

```bash
cd sepsis/project && V2_ARMS=ablated ./run_pipeline.sh 05 06 && ./run_pipeline.sh 04 07 08 11 12
```

```bash
cd sepsis/project && Rscript thesis_constants.R && cd ../thesis && ./build.sh
```

Why that order: `V2_ARMS=ablated` on 05/06 fits only the ablated arm, so no H1/H4/H6
input is touched and there is no GBT-drift exposure; 07 must run **unrestricted**
(it rewrites the alt-label table and scores the ablation); 08 picks up the GBT
fallback; 11 the resulting external operating points; 12 the inference layer; 04
is cheap and independent.

### Round 10 — examiner-audit remediation (text and config only; no results moved)

An external-examiner-style audit was run over the whole repository. Nothing it
found changed a result; what it found was claim-bearing text that had drifted
from the code, plus a pre-registration that had stopped being current. Applied:

| Fix | Where |
|---|---|
| **Amendments 5 and 6 written into the pre-registration** (§19 ablation, §20 subgroup interpretability floor). Amendment 5 existed only in the thesis and `methodology.tex` cited it as "§16", which is Amendment 2. Amendment 6 had never been recorded at all | `00_preregistration.md`; `methodology.tex`, `appendix.tex`, `README.md`, `declaration.tex` now say 1–6 |
| **H6 restated as non-inferiority.** The thesis said the interval "lies entirely inside the 0.02 equivalence margin". It does not: CI is [−0.0272, +0.0019] and −0.0272 is outside. Only the upper side is tested (`boot_pvalue(..., 0.02, "greater")`), so what holds is *GBT is not better by more than the margin*, not two-sided equivalence | `evaluation.tex` §H6 (+ new `\label{sec:h6}`), `conclusion.tex`, `discussion.tex` ×3, `README.md` |
| **H5's estimand substitution disclosed.** The tested contrast is internal−external AUROC, not the pre-registered utility-vs-AUROC proportional divergence, and it was not among Amendment 1's degenerate cases. Now recorded in §13.6 with three constraints, and flagged in the H5 box and in Limitations | `00_preregistration.md` §13.6; `evaluation.tex`, `discussion.tex` |
| **Prediction framing corrected.** Methodology claimed a 6-hour horizon; the models estimate the **current-hour cause-specific hazard** and every AUROC/AUPRC/calibration figure scores that. The 6 h window enters only via the Utility Score reward and the episode/lead metrics | `methodology.tex` §Prediction Framing; new Limitation |
| **Feature list corrected.** Methodology named a lactate slope (does not exist) and P/F ratio as a value predictor (only its order flag is one), and omitted the heart-rate slope. Counts reconciled: **22 covariates, 29 terms per outcome** | `methodology.tex` §Feature Construction; `evaluation.tex` |
| **`P_CANDIDATE_PREDICTORS` 25 → 29** with the binary-criterion-on-a-multinomial caveat stated. **Needs a stage-04 re-run** (cheap, independent, touches no hypothesis) | `config.R`, `methodology.tex` §Sample Size (now uses `\pcNCandidatePredictors`) |
| **Abstract's utility ceiling scoped.** "No model exceeds 0.039 at any threshold" was false — GBT/Variant C reaches 0.112 | `abstract.tex` |
| **`BASE_FEATURES`/`MISSINGNESS_FEATURES` consolidated into `config.R`.** They were declared three times (05, 06, 08). Stage 08's copy sets the stored GBT model's column order, so an order divergence would have produced permuted external predictions that are still well-formed numbers. `check_model_features()` now **errors** on a mismatch and logs loudly when falling back | `config.R`, `05`, `06`, `08`; `design.tex`, `README.md` |
| Introduction no longer claims everything outside H1–H6 is exploratory (the register marks nine more analyses confirmatory) | `introduction.tex` |
| Lead-time "compares favourably with the literature" removed — the next paragraph retracts it | `evaluation.tex` |
| C6's "reproduces every reported estimate exactly" now carries the XGBoost exception | `conclusion.tex` |
| Front matter: `\pagenumbering{arabic}` moved after a `\cleardoublepage`, so Acknowledgments no longer takes body page 1; `\today` on the title page replaced with `\submissiondate` | `index.tex` |
| `requirements.txt` **pinned** to the versions the results were produced under; `install_requirements.R` added (the old documented one-liner passed comment lines to `install.packages()`); `/Users/arif/...` fallback in `config.R` replaced with a `stop()` | `project/` |
| Presentation decks **untracked** (`git rm --cached`, added to `.gitignore`). Still on disk. They contradicted the thesis: H6 tagged REJECTED, primary AUROC 0.607, the withdrawn "Variant B collapse" claim | `.gitignore` |

**Nothing in `output/processed_data/` was touched, and no macro value changed.**
The one config change that alters a pipeline output is `P_CANDIDATE_PREDICTORS`.

### Round 12 — examiner audit of the thesis text (`feedback/v6.md`)

Nine defects, none of which moved a result, an interval or a verdict. All nine
are fixed. The three worth remembering, because each is a *class*:

| Defect | Class |
|---|---|
| The conclusion said two Utility Scores differ "by less than one hundredth"; 0.039 − 0.025 = 0.0142 | a qualitative comparison written beside two macros |
| A caption said the per-hour/per-patient views differ "20-fold in alarm count"; its own rows give 8–11 | a caption not re-derived from the table under it |
| **Both** of H2's sign reversals sit *below* their own estimation noise (ratios 0.61 and 0.75), yet three chapters led with the vasopressor reversal | an Amendment's consequence not propagated to the chapters that cite it |

The third is the one to keep in mind. Amendment 7 narrows H2 to three order
indicators, and the Introduction, Conclusion and C4 were still emphasising a
sign reversal the diagnostic does not support. All three now carry the
narrowing. **When an amendment qualifies a headline, grep for every place the
headline is stated, not just the section the amendment lives in.**

Also applied: fifty-two em dashes removed from the thesis prose (the three left
in the PDF are inside cited paper *titles* in the bibliography and must stay);
four hand-typed study quantities converted to macros, found by the new linter.

### Still open

- [ ] **PENDING RUN: stages 08 and 12.** Both stages' code is newer than their
      outputs, so `check_consistency.R` reports 4 failures that are staleness,
      not defects: three are round 11's stage-08 labelled-vs-scored
      instrumentation, one is a duplicated Amendment 7 row in
      `12_analysis_register` that stage 12 already removes in code. Neither
      stage refits GBT, so there is no drift exposure.

      ```bash
      cd sepsis/project && ./run_pipeline.sh 08 && ./run_pipeline.sh 12
      Rscript check_consistency.R && Rscript check_thesis_numbers.R
      Rscript thesis_constants.R && cd ../thesis && ./build.sh
      ```

      Canary to check afterwards: H1 −0.137549, H4 −0.016543, H6 −0.012931.

~~Re-run stage 04 for `P_CANDIDATE_PREDICTORS = 29`~~ — **DONE**, full run
  2026-08-10 10:47–13:20, 12/12 stages. The **only** macros that moved in the
  whole document were the 15 Riley ones; every AUROC, CI, verdict, equity and
  external quantity is byte-identical. Canary: H4 and H6 bit-identical, H1
  −0.137549186942963 vs −0.137549147378645 (Δ = 4e-8, eight orders below any
  reported precision — a summation-order artefact, not drift). Notably the GBT
  refit reproduced exactly despite xgboost's usual non-determinism.
- [ ] **`thesis/declaration.tex` must be read and amended by the author.**
      Added round 8. ATU's Academic Integrity Policy (AQAE022 §4) makes
      *undeclared* AI assistance misconduct, and the thesis previously carried
      **no statement of tooling at all** while the tracked repository visibly
      records the use of an AI assistant (`GEN-AI/HANDOFF.md` opens with "Work
      by Claude (Anthropic) with Abdul Ahad"; `feedback/` is tracked too). The
      declaration is drafted from what the repository record shows; only the
      author can confirm each clause is accurate. **Blocking for submission.**
- [ ] **Decide whether `GEN-AI/` and `feedback/` stay in the public repo.**
      Both are tracked and examiner-visible. `.claude/` and `CLAUDE.md` are
      *not* tracked (gitignored) but do exist in history — `ccb96b9` and
      `934ba03`.
~~Cluster-robust covariances are coded but not run~~ — **RUN, 2026-08-10.**
  `estfun.multinom` works: all nine fits produced a covariance with zero
  failures, **87 parameters** (29 terms × 3 non-reference outcomes) for the full
  arm and 63 (21 × 3) for the ablated arm, median SE 0.0105.
  `05_vcov_cluster[_ablated]_<vid>.rds` now exist for A/B/C/D/E/F. Coefficients
  were unaffected, as predicted — `Hess = TRUE` runs after the optimiser stops.
  Described in the thesis as a **ridge-regularised** sandwich, because
  `decay > 0` makes it the covariance of the penalised estimator.

- [x] ~~**PENDING RUN: `./run_pipeline.sh 05` then `./run_pipeline.sh 12`**~~ —
      **DONE, full pipeline run 2026-08-10, 12/12 stages.** Amendment 7 (§21)
      now has its producing outputs: `12_h2_stability_uncertainty` exists and
      `table_htwouncertainty.tex` carries six data rows, so the 8 red `??` are
      gone and `index.pdf` builds clean at **164 pages, 0 errors, 0 undefined
      references, 0 undefined citations, 1,397 macros, 0 missing**.
      **Canary held**: H4 −0.0165430069475656 and H6 −0.012930984123391
      bit-identical, H1 −0.137549147378645 (matching to 9 dp). The GBT refit
      reproduced exactly despite the full run touching stage 06.
      The dry-run prediction was exact: 6 flagged, 3 exceed noise, 3 do not,
      all 3 exceeders action-derived, z from 0.61 to 15.51 with a clean gap
      between 1.07 and 2.48.

- [x] ~~The covariance is computed but nothing consumes it~~ — **closed by
      Amendment 7.** The record of what it found: `05_coef_table_primary_*.parquet` still has no `se`
      column, no stage reads the `.rds`, and no thesis table shows a standard
      error — so the thesis now says a cluster-robust covariance is computed
      and then shows none. The obvious examiner follow-up is **"then does H2's
      instability exceed its standard error?"**, and that is answerable from
      files already on disk with no refit. Computed 2026-08-10 for the three
      A/B/C fits, sepsis outcome, max cross-variant coefficient difference over
      the pooled SE of the two extremes:

      | Covariate | β_A | β_B | β_C | max diff | pooled SE | \|d\|/SE |
      |---|---|---|---|---|---|---|
      | bilirubin_total | 0.0014 | −0.0016 | −0.0020 | 0.0034 | 0.0056 | **0.61** |
      | platelets | 0.0002 | 0.0001 | 0.0003 | 0.0002 | 0.0002 | **1.07** |
      | vaso_any | −0.0374 | 0.0271 | 0.0025 | 0.0645 | 0.0864 | **0.75** |
      | creatinine_measured | 0.2877 | 0.2303 | 0.0343 | 0.2534 | 0.1024 | 2.48 |
      | platelets_measured | −0.2563 | −0.5614 | −0.8173 | 0.5610 | 0.0529 | 10.60 |
      | wbc_measured | 0.0969 | 0.5374 | 0.8989 | 0.8020 | 0.0517 | 15.51 |

      **Three of H2's six "unstable" covariates move by less than their own
      estimation noise**, and the three that genuinely move are *all* order
      indicators — action-derived features. The pre-registered count of 6 of 22
      is therefore a loose **upper bound**: a threshold rule on point estimates
      cannot tell a coefficient that moved from one never estimated precisely
      enough for a doubling to mean anything.

      **Decided 2026-08-10: keep the pre-registered count, add the diagnostic
      beside it.** H2's headline stays 6 of 22 — restating it as 3 would swap a
      post-hoc estimand for a pre-registered one, which is exactly the move the
      thesis criticises elsewhere, and the swap would be *flattering*, which is
      a reason for more caution rather than less. §21.3 makes the ordering
      binding.

      Two cautions carried into the thesis text. The diagnostic is **not a
      test**: the three fits share stays, so the differenced estimates are
      correlated and the pooled SE assumes otherwise, and the sandwich is
      ridge-regularised. And its agreement with the Amendment 5 ablation is
      **not independent corroboration** — the ablation's by-kind split, the
      ablation arm and this diagnostic all come from the same three fits and
      share the flagged set. Three readings of one body of evidence, and the
      thesis says so (§21.4).
- [ ] **Variant D on the full eICU cohort** — the one cheap external
      experiment left. D needs no culture anchor, so it can run on all 181,589
      stays instead of the 2,824-stay sub-cohort, which would put the
      treatment-independent label's transport on a properly powered event
      count. **Not a config change**: stage 08 loops over `LABEL_VARIANTS`
      only, so it needs an external alt-label branch writing to a separate
      output and kept out of H5 the way D is kept out of H1. The frozen model
      already exists. `feedback/v3.md` §1.
- [ ] **MIMIC's `avpu_alert`** collapses unmeasured GCS to `FALSE`, which
      `news2()` charges 3 points. 3.2 % of MIMIC person-hours after LOCF (vs
      100 % in eICU, which is fixed). Needs a full 03–12 re-run. **Author's
      call.**
- [ ] **A matched MIMIC antibiotic-only arm** for the eICU sensitivity
      comparison — Variant G under a Protocol Amendment 6, `V2_VARIANTS=G`
      through 02/03/05/06 plus unrestricted 07, including the 6 GB stream.
- [ ] Carried forward: `tab:equity_label` macro conversion; cluster-robust SEs
      for the primary model; licence decision.
