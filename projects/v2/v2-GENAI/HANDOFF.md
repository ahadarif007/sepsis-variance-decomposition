# GENAI Handoff — V2 Sepsis Variance Decomposition

> **Read this file first and stop.** It is written so a cold thread can answer most
> questions with **zero further file reads**. Headline numbers are inlined below.
> Only open a data file when you need a number that is *not* here, and then open
> the single file named in §5 — never dump the whole `processed_data/` directory.

Last updated: **2026-08-03** (supervisor-feedback response written up in
`v2/feedback/v1.md`; no code or results changed).
Prior state: 2026-08-02 Protocol Amendment 2 (non-Sepsis-3 label variants D/E);
2026-07-30 full pipeline re-run + thesis alignment pass.
Work by Claude (Anthropic) with **Abdul Ahad** (ATU MSc, student ID G00486649).

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
stripped, so it contains no treatment timestamp. They live in
`ALT_LABEL_VARIANTS`, never in `LABEL_VARIANTS`, and their metrics go to
separate files — H1 and the decomposition are computed from unchanged inputs.

---

## 2. Layout

```
RESEARCH/projects/v2/
├── v2-GENAI/      ← this file
├── feedback/      ← supervisor feedback rounds: `v1.md` (see §7)
├── v2-lr-rp/      ← companion literature review (NARRATIVE, not systematic — see §7)
├── v2-proj/       ← pipeline: config.R, utils.R, clinical_scores.R,
│                    utility_score.py, 00_preregistration.md,
│                    01..12_*.Rmd, run_pipeline.{R,sh}, output/
└── v2-thesis/     ← LaTeX: index.tex + 7 chapter .tex, images/, build.sh
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

## 3. Current status (2026-08-02)

Pipeline **fully executed, 12/12 succeeded, 0 LaTeX warnings**. Thesis compiles
clean (0 errors, 0 undefined citations/refs). Reproduces **bit-for-bit** on re-run
with seed 42 — verified.

### Confirmatory verdicts (Holm, m=6, FWER 0.05)

| H | Contrast | Est. | 95% CI | p | Holm | Verdict |
|---|---|---|---|---|---|---|
| H1 | label spread − model spread | 0.011 | −0.017–0.034 | 0.211 | 0.634 | **NOT confirmed** |
| H2 | unstable covariates | 18/20 | — | — | — | Descriptive (10 sign flips, 17 mag ≥2×) |
| H3 | pre-treatment onsets | **0** | — | — | — | Structural (0 in 179,003 person-h) |
| H4 | random − temporal AUROC | 0.123 | 0.100–0.147 | 5e-4 | 0.003 | **Confirmed** |
| H5 | internal − external AUROC | 0.170 | 0.102–0.242 | 1e-3 | 0.004 | **Confirmed** |
| H6 | GBT − primary AUROC | 0.135 | 0.113–0.156 | 5e-4 | 0.003 | **Rejected** (non-equivalence) |

Decomposition (ΔAUROC): model class **0.142** [0.130–0.161] · label **0.153**
[0.136–0.177] · split **0.123** · metric **0.170**. All overlap — no factor ranks.

### Key headline numbers

- Cohort: **65,078** stays. Sepsis: A 6,252 (9.6%) · B 6,447 (9.9%) · C 12,581 (19.3%).
- Variant B temporal test AUROC: primary **0.607**, GBT **0.742**, NEWS2 0.635,
  Cox 0.623, qSOFA 0.609, SIRS 0.600.
- **Utility Score negative for every model × every variant.** Best alert burden 91:1
  (GBT/C) vs 1.4 benchmark.
- External (eICU): 63 events / 7.87 M person-hours. B primary AUROC **0.436** (collapse);
  A 0.736, C 0.725 hold.
- Equity: **no** race contrast survives BH (smallest q=0.310). Label-sensitivity
  contrasts **do** survive: race-Unknown +3.01 pp (q=0.006), Unable-to-obtain +3.49 pp
  (q=0.009), Spanish +2.61 pp, Private insurance −1.76 pp.

### Protocol Amendment 2 — label-anchor attribution (2026-08-02)

Splits Sepsis-3 (= anchor **AND** organ dysfunction) into its limbs. B/D/E all
on the same 65,078 stays and the same temporal split.

| Variant | What it is | Onsets ≤72 h | κ vs B | Exact onset match | primary AUROC | GBT AUROC |
|---|---|---|---|---|---|---|
| E Anchor-Only | suspicion time, no SOFA gate | 17,251 (26.5%) | 0.432 | **100%** | **0.756** | 0.766 |
| B Seymour-Std | both limbs | 5,887 (9.0%) | — | — | 0.607 | 0.742 |
| D Deterioration | physiology-only SOFA ≥2 over admission baseline, **no treatment timestamp** | 27,195 (41.8%) | **0.057** | **6.4%** | **0.842** | 0.915 |

Two structural facts, not estimates:
- **E ⊇ B exactly, onset times identical in 100% of B's stays.** Onset time under
  A/B/C *is* `t_susp`; the SOFA gate only filters *which* stays. So 100% of
  Sepsis-3 onset timing is treatment timing. A vs B exact-onset match 97.5%,
  C vs B 98.6% — the pre-registered label variance is entirely about *which
  patients*, never *when*.
- **D vs B κ=0.057** (near chance), 6.4% exact onset match, median |shift| 9 h
  (IQR −11 to +7). A treatment-independent label is a *different construct*, so
  the label-sensitivity finding is **not** purely tautological.

**Sepsis-3 is harder than either limb.** φ_anchor = (AUROC_E−0.5)/(AUROC_B−0.5)
= **2.40** [2.06–2.89] primary, **1.10** [1.04–1.17] GBT — both CIs entirely
above 1, and φ>1 for all six models. The anchor is the predictable part; the
SOFA gate discards two thirds of anchor-positive stays and takes the separable
signal with it. Utility stays negative under D and E (best −0.218, GBT/D);
D's best alert burden 17.7:1 vs B's 201.7:1 — still ≫1.4.

Family **E3** (m=4, BH): all four ΔAUROC-vs-B contrasts significant at the
smallest reportable p. primary D +0.235 [0.216–0.255] · primary E +0.149
[0.131–0.168] · GBT D +0.173 [0.155–0.189] · GBT E +0.024 [0.009–0.038].
**H1–H6, E1 and E2 outputs are byte-identical to the pre-amendment run** —
verified by diff.

**The H3 zero is a property of the label, not the patients.** In the
treatment-anchored (pre-treatment) window: B **0** onsets / 179,003 person-h,
E **0** / 179,003 (structural tautology — E's onset *is* the anchor, and B ⊆ E),
but D **1,362** onsets / 147,357 person-h at AUROC 0.840 primary / 0.937 GBT.
Patients *do* deteriorate before clinicians act; Sepsis-3 simply cannot place an
onset there. This sharpens C2/H3 rather than weakening it.

Caveat to state every time: D's label is a threshold function of recorded
physiology and 5 of its 6 SOFA components are model inputs, so its *level* is
partly self-fulfilling and not comparable to B's. The κ / onset-shift
disagreement and the 1,362-vs-0 event count are the parts that carry weight —
those are label properties, not model results.

---

## 4. Traps that have actually bitten (do not relearn these)

### The big one: GBT drift + thesis sync
The thesis **hardcodes every number** and keeps its **own copy** of figures in
`v2-thesis/images/`. Nothing auto-reads pipeline output. After any re-run:
1. `cp v2-proj/output/figures/*.png v2-thesis/images/`
2. Re-check hardcoded tables against §5 files.
3. `./build.sh`.

On 2026-07-30 a re-run refit GBT slightly differently. **Every non-GBT number still
matched; every GBT number was stale**, cascading into H1, H6, the decomposition,
abstract and conclusion. **Use the GBT rows as the canary** — if they match, the
rest almost certainly does.

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
- FiO2 stored as percent → ÷100, clip [0.21, 1.0]. Temp in °F **and** °C → convert.
  MAP outliers to 117120 → clip [10, 250].
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
| **Alt-label (D/E) metrics** | `07_metric_results_altlabel.csv` |
| Anchor attribution + agreement | `09_label_anchor_attribution.csv`, `09_label_agreement.csv` |
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
3. Utility Score is primary; AUROC descriptive. Negative utility **is** the finding.
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
    not timing. Don't "fix" this; it is the mechanism behind the Amendment 2
    result.

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
- Don't "fix" negative Utility Scores — they are the result.
- Don't bypass the `00_preregistration.md` G0 gate.
- Don't re-run `03_person_hours.Rmd` casually (~6 GB stream). Stages 07–12 are cheap.
- Don't create new pipeline stages. The author has explicitly ruled this out.
- Don't put variants D/E into `LABEL_VARIANTS`, and don't pool their metrics with
  A/B/C. They are post-hoc; H1 and the decomposition must stay on A/B/C alone.
- Don't re-run 05/06 for A/B/C when you only need another variant — use
  `V2_VARIANTS=<ids>`. XGBoost is not bit-stable, so an incidental refit drifts
  every GBT number in the thesis (see the GBT canary above).
- Don't touch `v2-presentation*/` unless asked. Don't depend on `v1/`.
- Don't leave LaTeX build junk in `v2-thesis/` (keep sources, `images/`, `index.pdf`).
