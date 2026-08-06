# GENAI Handoff — V2 Sepsis Variance Decomposition

> **Read this file first and stop.** It is written so a cold thread can answer most
> questions with **zero further file reads**. Headline numbers are inlined below.
> Only open a data file when you need a number that is *not* here, and then open
> the single file named in §5 — never dump the whole `processed_data/` directory.

Last updated: **2026-08-06** — feedback round 7 patched into source and thesis,
**nothing executed**. Structural changes: the thesis gained a **Discussion
chapter** (now 7 chapters + an appendix), Chapter 2 was rewritten as a critical
review, and the subgroup analysis gained a 100-event interpretability floor that
**changes family E1's size**. Three runs are now pending (§9). Results in §3 are
unchanged and current — the run of 2026-08-06 00:42, 12/12 stages.
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
└── v2-thesis/     ← LaTeX: index.tex + chapters, images/, build.sh,
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

`README.md` at the repo root and `v2-GENAI/SCREENCAST.md` are submission
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
`Rscript run_pipeline.R --phase 4`. Thesis: `cd ../v2-thesis && ./build.sh`.
Full run ≈ **60 min** (≈85 min with D/E); stage 05 dominates. Stage 12 alone
≈ 14 min (bootstrap).

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

## 3. Current status — **2026-08-06 full clean run, 12/12 stages, all variants**

Everything below is the run of 2026-08-06 23:17–00:42 with Amendments 3 and 4 in
force and the stage-08 eICU rewrite. **Every internal number is bit-identical to
the 2026-08-05 run** — the GBT canary held, so the run reproduced and the only
movement is external, which is where the fix was. The thesis is re-synced:
`pipeline_constants.tex` carries **1,240 macros, 3 missing** (the eICU GBT
comparator, §9), and `index.pdf` builds at 0 errors, 0 undefined references,
0 undefined citations, 119 pages.

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
- **Utility: no model exceeds 0.039 (GBT/B) at its best threshold.** At the
  fixed 0.5 cut-off the primary model scores exactly 0.000 because it never
  alerts there — that zero is a threshold artefact, not a result. Report
  `utility_max`, not `utility_normalised`, when quoting a ceiling.
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
  residual gap localises to the **culture limb**: eICU documents antibiotics
  for 32.66 % of stays and cultures for 1.55 %.
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
- **Tables too large for one-macro-per-cell are generated whole.**
  `write_table()` in `thesis_constants.R` emits a complete `tabular` to
  `v2-thesis/table_<name>.tex`; the chapter keeps only `\begin{table}`,
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

**Eight hits are legitimate and expected** (was five before feedback round 7):
the supervisor acknowledgement; the clinical-staff-feedback future-work item;
**four** "no second reviewer screened independently" statements about the
*literature search* (`review.tex` ×2, `methodology.tex`, `discussion.tex`); one
"not previously reported" in `conclusion.tex` C1, which is a claim about prior
art rather than about this document; and one false positive on "unsupervised" in
`review.tex`. Anything else is a leak. `feedback/v2.md` §13.1a lists the six
passages already fixed this way, so the same phrasing is not reintroduced.

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

- **Licence: STILL UNDECIDED, and the thesis now names one.** No `LICENSE` file
  exists → code is currently *all rights reserved*. `index.tex` sets
  `\repolicence` to **Apache-2.0** on the strength of the standing
  recommendation (patent grant, stronger warranty disclaimer for
  clinical-adjacent code, NOTICE for citation; CC BY 4.0 for prose), and the
  appendix and `design.tex` both print it. **Confirm against ATU student-IP
  policy and add a `LICENSE` file** — `README.md` points at one that does not
  exist yet.
- **The repo-visibility position REVERSED in feedback round 7.** It was private
  with the URL deliberately omitted; the submission page penalises a missing
  repository link as a failure to submit, so `design.tex` §Code Availability and
  the new Appendix A now state a **public** repository at `\repourl`. Two
  consequences: (1) `\repourl` in `index.tex` is a **placeholder**
  (`https://github.com/REPLACE-ME`) because the author is supplying a URL that
  is not this tree's `origin` — one line to set; (2) **the thesis asserts the
  repo is public, so it must actually be public before submission or that
  sentence is false.** Code-only + PhysioNet DUA forbids data redistribution is
  unchanged. `.gitignore` verified: 0 patient-data files tracked.
- **Feedback round 7 — all eight items closed in source; two runs pending.**
  Full write-up in `feedback/v2.md` §26. Summary: appendix + README + screencast
  plan; Chapter 2 rewritten as a critical review around four disputes (14 sources
  drawn in from the companion); Figure 2.1's invented AUROCs replaced with Cohen
  et al.'s own reported numbers; **nine miscited references corrected and every
  DOI in the bibliography verified to resolve** (the feedback named four; five
  more were found, including one paper that does not exist); Riley applied on the
  stay; subgroup event floor + non-disjoint-strata statement; novelty claims made
  precise about *what* is new; Discussion promoted to its own chapter.
  Two positions were **reversed** and both are recorded above: repo visibility,
  and the equity reading (documentation, not race).
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
- Don't reinstate "discrimination transports intact to eICU" or "Variant B
  collapses; A and C hold" (§4, the variant-loop trap). Both were artefacts of
  a single reused label.
- Don't pool the eICU antibiotic-only arm with the Sepsis-3 arm, and don't quote
  it when the Sepsis-3 arm is inconvenient. It labels a different target.
- Don't touch `v2-presentation*/` unless asked. Don't depend on `v1/`.
- Don't leave LaTeX build junk in `v2-thesis/` (keep sources, `images/`, `index.pdf`).

---

## 9. Pending runs

**Three** independent pieces of work are patched in source and **not executed**:
9a and 9b from feedback round 5, and 9c from round 7. Together they account for
72 missing macros. Unlike the earlier rounds, `index.pdf` currently **will not
compile** — 9c's 21 macros do not exist at all yet, so they are undefined
control sequences rather than red `??`. That is the loud-failure design working.

### 9a. eICU GBT comparator — 3 macros

`readRDS()` returns the stage-06 booster with an **empty** `feature_names`
under this xgboost build. `lapply()` over an empty vector produced a
zero-column DMatrix, `predict()` returned all-NA, and the metric loop discarded
it as "fewer than 50 valid rows" — so the GBT row silently vanished from the
external results. It had been absent for the whole project; it only became
visible when the corrected external table asked for the number.

Fixed by falling back to `BASE_FEATURES`, which is exact: stage 06 sets
`gbt_feats <- intersect(BASE_FEATURES, names(ph))` with `require_features()`
guaranteeing all 22 present, so the intersect is the declared vector unchanged.
**Verified** against `06_predictions_comparators_B`: max absolute difference
**0** across all 548,827 test rows. Guards added — `stop()` on a zero-column
design matrix and on an all-NA prediction vector.

### 9b. Protocol Amendment 5, the feature ablation — 48 macros

New arm in 05/06, scored in 07, stability split in 12. See §6 rule 15.

### 9c. Feedback round 7 — 21 macros, stages 04 and 12

Two independent changes, both cheap and neither refitting anything.

**Stage 04 — Riley on the independent unit.** `04_sample_size.Rmd` now calls
`pmsampsize` twice, at the stay-level prevalence (the adequacy verdict) and at
the per-hour prevalence (reference only). New columns `stay_prevalence`,
`min_n_riley_stay`, `sufficient_stay`, `margin_stay`, `min_n_riley_perhour`;
the old `min_n_riley` / `sufficient` are gone. Reads three columns of each
`03_person_hours_*.parquet` — cheap, no 6 GB stream.

**Stage 12 — the subgroup interpretability floor.** `elig` gains an
`interpretable` flag; a contrast enters family E1 only if both the level and the
reference clear `MIN_SUBGROUP_EVENTS_INTERPRET`. **This shrinks E1 and therefore
moves every BH-adjusted q-value in it.** The confirmatory arm is untouched.

Both are covered by `./run_pipeline.sh 04 12`, which can simply be folded into
the command below by appending `04` to the stage list.

### The run

```bash
cd projects/v2/v2-proj && V2_ARMS=ablated ./run_pipeline.sh 05 06 && ./run_pipeline.sh 04 07 08 11 12
```

```bash
cd projects/v2/v2-proj && Rscript thesis_constants.R && cd ../v2-thesis && ./build.sh
```

Roughly 40–45 min. Why this order and these stages:

- `V2_ARMS=ablated` on **05 06** fits only the ablated arm. The main fits and
  both random-split refits are skipped, so **no H1/H4/H6 input is touched** and
  there is no GBT-drift exposure at all.
- **07** must run unrestricted (it scores the ablation and rewrites the
  alt-label table; see §8). It refits nothing — it re-scores existing
  predictions, deterministically.
- **08** picks up the GBT fallback of 9a; **11** picks up the resulting GBT
  external operating points.
- **12** is needed only for `12_h2_stability_by_kind`. Its bootstraps are
  seeded and read unchanged prediction files, so its output should be identical
  apart from the new table — which is a useful check in itself.

### What to verify afterwards

| Check | Expect |
|---|---|
| `Arms in this run: ablated` in the 05 and 06 logs | present |
| `Ablated arm: 8 action-derived features dropped, 14 remain` | present |
| `Full arm not selected; keeping the existing random-split fit.` | present in both 05 and 06 |
| `GBT model carries no feature_names; reconstructing from BASE_FEATURES` | present in the 08 log |
| **Canary:** internal AUROCs in `07_metric_results.csv` | unchanged (primary 0.7713 / 0.7590 / 0.7695, GBT 0.7448 / 0.7460 / 0.7559) |
| `12_h2_coefficient_stability.csv` | unchanged, 22 rows, 6 unstable |
| `[PRIMARY] Minimum independent observations (Riley, stay-level)` in the 04 log | present, three variants |
| `04_sample_size.parquet` | has `min_n_riley_stay` / `stay_prevalence` / `margin_stay`; `min_n_riley` gone |
| `N levels estimated, M above the 100-event interpretability floor` in the 12 log | present for race, language, insurance |
| `12_subgroup_auroc_ci.csv` | gains `interpretable` + `min_events_interpret`; **row count unchanged** |
| `12_subgroup_auroc_contrasts.csv` | **row count falls**; every surviving row has `n_events >= 100` |
| `12_confirmatory_tests.csv` | **H1–H6 unchanged** — round 7 touches no confirmatory input |
| `thesis_constants.R` | **0 missing macros**; writes real rows into `table_equityperformance.tex` and `table_equitycontrasts.tex` (currently `\pcMissing` placeholders) |

If any internal AUROC moves, an ablation-only pass overwrote a main fit — stop
and check the `V2_ARMS` guards before trusting anything downstream. If any
H1–H6 value moves, the subgroup edit leaked into the shared bootstrap
machinery — also stop.

### Then align the thesis

`feedback/v2.md` §24.5 holds the decision table. The ablation's *direction* is
unknown until it runs, and the thesis text is written to survive either
outcome; what changes with the numbers is the strength of the reading, not
its direction.

### Still open

- [ ] **MIMIC's `avpu_alert`** collapses unmeasured GCS to `FALSE`, which
      `news2()` charges 3 points. 3.2 % of MIMIC person-hours after LOCF (vs
      100 % in eICU, which is fixed). Needs a full 03–12 re-run. **Author's
      call.**
- [ ] **A matched MIMIC antibiotic-only arm** for the eICU sensitivity
      comparison — Variant G under a Protocol Amendment 6, `V2_VARIANTS=G`
      through 02/03/05/06 plus unrestricted 07, including the 6 GB stream.
- [ ] Carried forward: `tab:equity_label` macro conversion; cluster-robust SEs
      for the primary model; licence decision.
