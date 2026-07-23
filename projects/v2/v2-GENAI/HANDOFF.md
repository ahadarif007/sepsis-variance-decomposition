# GENAI Handoff — V2 Sepsis Variance Decomposition Pipeline

> Purpose: let another AI assistant (or a human) **continue this project cold**,
> with full context on what was built, why, the current state, and known pitfalls.

Last updated: 2026-07-19.
Author of work: Claude (Anthropic), working with **Abdul Ahad** (ATU Galway MSc).

---

## 1. Mission

**Research question:** In real-time sepsis onset prediction on MIMIC-IV, how is
predictive performance partitioned between (a) the choice of model class and (b)
the analyst's discretionary choices — label operationalisation, temporal vs random
split, prediction-time anchoring, and evaluation metric?

The pipeline implements a pre-registered variance decomposition with six hypotheses
(H1–H6), three Sepsis-3 label variants, and multiple model classes.

---

## 2. Project Structure

```
RESEARCH/projects/v2/
├── v2-GENAI/         ← this folder (AI handoff docs)
├── v2-lr-rp/         ← literature review + research proposal
├── v2-proj/          ← pipeline code + output
│   ├── config.R      ← single source of truth (paths, params, labels)
│   ├── utils.R       ← shared helpers (DuckDB streaming, LOCF, etc.)
│   ├── clinical_scores.R  ← NEWS2, qSOFA, SIRS scoring
│   ├── utility_score.py   ← PhysioNet Utility Score (called via reticulate)
│   ├── 00_preregistration.md  ← locked protocol (G0 gate)
│   ├── 01_setup.Rmd → 13_equity_analysis.Rmd  ← numbered pipeline scripts
│   ├── run_pipeline.R    ← R-based orchestrator
│   ├── run_pipeline.sh   ← shell orchestrator
│   └── output/       ← all pipeline outputs (parquet, csv, html, png)
└── v2-thesis/        ← LaTeX thesis document
    ├── index.tex     ← master document
    ├── *.tex         ← chapter files
    ├── images/       ← figures from pipeline output
    └── references.bib
```

---

## 3. Critical Environment Facts (caused real bugs in prior work)

| Fact | Detail |
|---|---|
| **Python** | `/Library/Frameworks/Python.framework/Versions/3.14/bin/python3` — pandas 3.0.4. Shell `python3` resolves here. |
| **System python (AVOID)** | `/usr/bin/python3` has NO pandas. |
| **pandas 3.0 Arrow strings** | CSV datetime columns load as `str`; `str - Timedelta` raises `ArrowNotImplementedError`. **Always `parse_dates=[...]` when loading CSV datetimes.** |
| **R** | `/usr/local/bin/Rscript` — R 4.5.2. `pdflatex` at `/Library/TeX/texbin/`. |
| **Data root** | `/Users/arif/Desktop/RESEARCH/data/mimic-iv-3.1/` with `hosp/` and `icu/` subdirs, all `*.csv.gz`. |
| **eICU** | `/Users/arif/Desktop/RESEARCH/data/eicu-collaborative-research-database-2.0/` |
| **Path auto-detection** | `config.R` walks up parents until it finds `data/mimic-iv-3.1`. Override with `MIMIC_RESEARCH_ROOT`. |
| **OUTPUT_DIR** | Resolves to `v2-proj/output/` (co-located with scripts). |
| **macOS case-insensitive FS** | `V2` and `v2` resolve to same dir. Stick to lowercase `v2`. |

---

## 4. Pipeline Scripts (all R-based)

| Script | Purpose | Key outputs |
|---|---|---|
| `01_setup.Rmd` | Verify data exists, report table sizes | `01_setup_file_report.csv` |
| `02_cohort_labels.Rmd` | Extract cohort + 3 label variants | `cohort_{A,B,C}.parquet` |
| `03_person_hours.Rmd` | Build person-hour tables (heavy: streams 6GB) | `person_hours_{A,B,C}.parquet` |
| `07_sample_size.Rmd` | Riley et al. sample size calculation | `07_sample_size.csv` |
| `08_primary_model.Rmd` | Fit multinomial discrete-time CR model | `model_primary_{A,B,C}.rds` |
| `09_comparators.Rmd` | Fit GBT, Cox, NEWS2/qSOFA/SIRS | `model_gbt_{A,B,C}.rds` |
| `10_metrics_suite.Rmd` | Full metric evaluation | `10_metric_results.csv` |
| `11_external_validation.Rmd` | Frozen-model on eICU | `11_external_validation_results.csv` |
| `12_variance_decomposition.Rmd` | Compute decomposition + test H1/H2/H6 | `12_hypothesis_verdicts.csv` |
| `13_equity_analysis.Rmd` | Subgroup performance + label sensitivity | `13_subgroup_performance.csv` |

---

## 5. Common Pitfalls & Lessons Learned

### Data handling

1. **Never assume CSV round-trips dtypes.** pandas 3.0 makes the failure loud.
   Always `parse_dates=` for datetime columns.

2. **DuckDB for large table reads.** `chartevents` is 3.5 GB, `labevents` 2.6 GB.
   Never load these into R memory wholesale. Use the DuckDB-backed streaming
   reader in `utils.R` (`read_large_csv_filtered()`).

3. **FiO2 stored as percent (median 40).** Must divide by 100, clip [0.21, 1.0].
   Temperature in both °F (223761) and °C (223762) — convert F→C.
   MAP has garbage outliers (max 117120) — clip [10, 250].

4. **PRROC + NAs crash.** `PRROC::pr.curve()` fails on NA subscripts. Always
   filter with `complete.cases()` before calling.

5. **eICU microbiology capture is ~1.5% of stays.** Suspected infection in eICU
   must trigger on antibiotics alone (culture refines timing when present). A
   culture requirement makes the *label* untransportable.

### Statistical modelling

6. **Per-patient random-intercept GLMM is degenerate** on rare outcomes (quasi-complete
   separation). Use GEE + cluster-robust SEs instead. Don't "fix" the GLMM.

7. **Proportional hazards is always rejected** on MIMIC-IV sepsis data (global
   Schoenfeld p < 10^-16). The discrete-time model dissolves this by construction.

8. **Informative missingness dominates.** Binary "test-ordered" indicators
   frequently outweigh the test values themselves. Don't drop missingness indicators.

### R-specific

9. **`nnet::multinom()` for the primary model.** Sandwich-robust SEs via
   `sandwich::vcovCL()` clustered on `stay_id`.

10. **XGBoost early stopping.** Use 15% internal validation from training rows,
    not the temporal test set. Column sampling 0.8, max depth 6, learning rate 0.1.

11. **Parquet for all intermediate data.** CSV only for small result tables
    (< 1,000 rows) for human readability.

### Pipeline execution

12. **Don't re-run `03_person_hours.Rmd` unless needed.** It streams ~6 GB and
    takes significant time. The downstream scripts (07–13) are cheap to iterate.

13. **Pre-registration gate.** The pipeline refuses to run if
    `00_preregistration.md` is missing. This is the G0 gate — don't bypass it.

14. **Temporal split by `anchor_year_group`.** Train: 2008–2016. Test: 2017–2019.
    Random split (seed 42, 75/25) is for optimism quantification only.

### Thesis document

15. **LaTeX builds require `biber` (not bibtex).** The document uses `biblatex`
    with `style=apa`. Build with: `pdflatex index && biber index && pdflatex index && pdflatex index`.

16. **ATU colour palette defined in `index.tex`.** Use `ATUGreen`, `ATUNavy`,
    `ATUOrange`, etc. in `mdframed` environments.

17. **Landscape tables.** Use `\begin{landscape}...\end{landscape}` with
    `longtable` for wide result tables. Requires `pdflscape` package.

---

## 6. Key Design Decisions

1. **Three label variants (A/B/C)** = the primary methodological innovation.
   Variance across them is reported as a primary result, not a sensitivity analysis.

2. **Treatment-anchored evaluation** reveals that the Sepsis-3 label contains zero
   pre-treatment predictable events. This is the study's strongest finding.

3. **PhysioNet Utility Score as primary metric.** AUROC is descriptive only. The
   Utility Score is negative across all models and labels — the central finding.

4. **Competing-risks formulation.** Discharge alive and death without sepsis are
   informative events, not censoring. Multinomial cause-specific model handles this.

5. **No case-control matching.** All at-risk person-hours contribute. The
   person-hour design dissolves the control-alignment problem.

6. **GBT is mandatory ML comparator** — not deferred to "future work." Cross-paper
   comparison under differing labels is uninterpretable (Cohen et al., 2024).

---

## 7. Current Status

**Pipeline fully executed.** All 10 Rmd scripts rendered to HTML. Key findings:
- H1 (label dominance): CONFIRMED (spread 0.153 vs model-class 0.140)
- H2 (coefficient instability): CONFIRMED (10/25 predictors affected)
- H3 (treatment leakage): STRUCTURAL — 0 events in pre-treatment window
- H5 (metric divergence): CONFIRMED qualitatively (Utility negative everywhere)
- H6 (model-class null): REJECTED (GBT beats primary by 0.133 AUROC under B)

**Thesis document compiled** (`index.pdf` exists). All chapters written.

---

## 8. Exact Run Order

```bash
cd /Users/arif/Desktop/RESEARCH/projects/v2/v2-proj

# Full pipeline (shell orchestrator)
./run_pipeline.sh

# Or R orchestrator
Rscript run_pipeline.R

# Or individual phases
Rscript run_pipeline.R --phase 2   # cohort + person-hours

# Thesis build
cd ../v2-thesis
pdflatex index && biber index && pdflatex index && pdflatex index
```

---

## 9. What NOT to Do

- Don't add causal-inference tools (PSM, IPW, AIPW, E-values) — they are category
  errors in a prediction study.
- Don't add GBTM — it produces no real-time score and requires post-hoc data.
- Don't use a random split as primary — temporal is primary (Guo et al., 2022).
- Don't report AUROC as primary metric — Utility Score is primary (Wang et al., 2025).
- Don't try to "fix" negative Utility Scores — they ARE the finding.
- Don't reference or depend on the v1 project files. This is a standalone study.
