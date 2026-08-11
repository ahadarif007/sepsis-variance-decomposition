# Screencast plan — 5–10 minutes

Internal planning document. Not part of the thesis.

**Nothing is executed on camera. No pipeline stage runs. No terminal command is
typed. Every window is opened before recording starts and is already showing
what it needs to show.**

## Two rules before you build anything

**Rule 1: ignore both presentation decks.** `presentation/` and
`presentation-v2/` label H1, H2, H3 and H4 as CONFIRMED and H6 as REJECTED. The
thesis concludes close to the opposite. They were written before the inference
layer existed, so they report point estimates with nothing attached to them.
Lifting a slide from either one puts a wrong verdict on camera.

**Rule 2: two kinds of number, handled differently.**

Figures from prior work are safe to write into a slide and leave there. They are
fixed, they are cited, and the thesis types them by hand for the same reason.
Those are the ones in the Say lines below.

Your own results are macros. They are written into the thesis by
`thesis_constants.R` and they move if the pipeline is re-run. Every one of those
appears below as a slot like `‹label spread›`. Fill each slot from the built PDF
on the day you make the slide, and never from memory or from an old deck. The
previous version of this file hardcoded a results claim and it went stale inside
a week.

## What the recording has to do

A talk about an analysis pipeline fails in one of two ways.

It becomes a code tour that never says what was found, and the panel leaves
knowing you wrote twelve scripts and not knowing what the study concluded.

Or it becomes a results talk anyone could have given without writing a line of
code. Everything is asserted, nothing is shown. That is the easier trap when you
are not running anything, and it is the one to guard against here.

So the eight segments alternate. Research claim, then the machinery that makes
it checkable, then back. Segments 6 and 7 carry the submission; protect their
time and cut elsewhere.

You also lose any evidence that the thing runs. Say so once, plainly, in segment
8, and move on. Do not apologise for it twice.

---

## Segment 1 — The clinical problem (0:50)

**SHOW**

- Slide 1: title, your name, supervisor, ATU.
- Slide 2: four numbers, large. `AUROC 0.811 → 0.783` on one line.
  `Utility +0.381 → −0.164` on the line below, in a contrasting colour.

**SAY**

> Sepsis kills around eleven million people a year, close to one in five deaths
> worldwide. In intensive care every hour of delayed treatment raises the risk
> of death, so a model that warns before the clinician notices ought to save
> lives.
>
> Ninety-one real-time sepsis models have been published. Median internal AUROC
> is 0.811, which reads like a problem that is basically solved.
>
> Here is the other number from the same review. The clinical Utility Score
> falls from plus 0.381 internally to minus 0.164 externally. Negative means the
> alerts cost more than they are worth. And across that same transition AUROC
> moves from 0.811 to 0.783, which is almost nothing.
>
> So the measure the field reports cannot see the failure the field has. That is
> what this thesis is about.

**WATCH OUT.** Do not editorialise about how important sepsis is. The numbers do
that work. Thirty seconds of clinical background is plenty.

---

## Segment 2 — The question and the design (1:05)

**SHOW**

- Slide 3: the research question in full, one sentence, large type.
- Slide 4: the design grid. Three label variants down the side, six model
  specifications across the top, with "× 2 splits × 2 metrics" underneath.
- Slide 5: the six hypotheses, one line each, H1 to H6.

**SAY**

> The usual question is which model is best. That turns out to be the less
> interesting one.
>
> The question here is how much of a reported performance number comes from the
> model at all, and how much comes from decisions the analyst made along the
> way. How sepsis was defined. How the data was split. Which metric got
> reported.
>
> Most studies fix those three and vary the model. This study treats all four as
> variables and measures each contribution with an interval attached.
>
> Three readings of the Sepsis-3 definition, all of them defensible. Six model
> specifications. Two split designs, two metrics. Everything fitted and scored
> on the same test rows, so the comparisons are paired.
>
> Six hypotheses were pre-registered and locked before any modelling. Hold on to
> that, because three of them did not go the way I predicted, and the
> pre-registration is the reason I can say so cleanly.

**WATCH OUT.** Resist explaining all six hypotheses now. Name H1 and H6 only,
and say they were built in deliberate tension. The rest arrive in segment 7.

---

## Segment 3 — What is actually being estimated (1:20)

**SHOW**

- Slide 6: a person-hour strip. One stay drawn as a row of hourly boxes, with
  the four outcome codes marked underneath (0 at risk, 1 onset, 2 discharge,
  3 death).
- Then the editor: `05_primary_model.Rmd`, scrolled to the model formula.

**SAY**

> Every ICU stay is expanded into one row per hour at risk. Around forty-five
> rows per stay, and roughly 2.3 million rows in training.
>
> Each hour carries one of four outcomes. Nothing happened, sepsis onset,
> discharged alive without sepsis, or died without sepsis. Those last two are
> competing events, not censoring. If you treat a discharge as censoring you
> overstate how much sepsis there is.
>
> The model is a multinomial pooled logistic regression over those person-hours,
> with a flexible spline baseline in elapsed hours. D'Agostino showed that this
> is mathematically equivalent to time-dependent Cox regression when the
> intervals are short and the per-interval event rate is low. Hourly ICU data at
> well under one per cent satisfies both conditions comfortably.
>
> What you get for that is no proportional-hazards assumption. Which matters,
> because I tested that assumption on the static Cox comparator and it fails
> decisively on these data.
>
> One point I want to be exact about, because it governs every discrimination
> number I show later. The AUROC here scores the onset hour against the other
> at-risk hours. It is not the AUROC of a "sepsis within the next six hours"
> classifier, and it should not be read against published figures that are.

**WATCH OUT.** That last paragraph is the single most likely place for an
examiner to catch you out. Say it deliberately and do not rush it.

---

## Segment 4 — Pipeline architecture (1:00)

**SHOW**

- The stage DAG figure from Chapter 4, full screen.
- Editor: `run_pipeline.sh`, then `config.R` scrolled slowly through the label
  variant block and the covariate vector.

**SAY**

> Twelve numbered scripts, each with one job, each writing only to its own
> outputs. Nothing writes back to the source databases, so reproducing a run
> means deleting the output directory and starting again.
>
> `config.R` is the single source of truth. Every antibiotic-culture window,
> every threshold, every seed, the multiplicity family sizes, the event floors,
> and the covariate vector itself. No other file hard-codes a clinical constant.
>
> That sounds like ordinary tidiness. It is load-bearing here. This is a study
> about definitional sensitivity, so a constant that quietly diverged between
> two scripts would look exactly like a finding.
>
> The covariate vector is the case that matters most. It is read by both fitting
> stages and again by external validation, which rebuilds a stored model's
> column order from it. Two copies drifting apart would have produced a permuted
> design matrix and predictions that are wrong while looking perfectly
> well-formed.
>
> Stage 12 is the inference layer and it reads stored predictions only. It
> refits nothing. So the intervals and the multiplicity corrections can be
> recomputed and checked independently of the models that produced them.

---

## Segment 5 — Guards against silent failure (1:00)

**SHOW**

- Editor: `require_features()` in `utils.R`.
- Editor: the run-time assertions in `07_metrics_suite.Rmd`.
- Editor: the separation and ridge paragraph in `05_primary_model.Rmd`.

**SAY**

> A crash is the easy failure. The dangerous one is a stage that quietly does
> less than it was asked to.
>
> Here is the concrete case. If you select predictors by intersecting a declared
> feature list against the columns actually present, one typo drops a variable
> silently. The model still fits. The metrics still compute. Nothing anywhere in
> the output tells you a predictor went missing. So `require_features()` raises
> an error instead of proceeding.
>
> Same principle for the run-time invariants. A threshold set above every
> predicted probability has to score exactly zero, because it is the no-alert
> strategy. No operating point may exceed the optimum's score of one. And the
> three label variants have to produce three distinct sets of external onsets,
> because a label that was never varied would otherwise present as a label with
> no effect. Those are stops, not warnings. A warning in a sixty-minute batch
> run is a line in a log nobody reads.
>
> One more that is worth naming out loud. The unpenalised version of this model
> is completely separated on this design. The whole coefficient vector diverges
> together, order ten to the fifteen, under every label variant. And the
> standard diagnostic does not catch it: `nnet` returns convergence equals zero,
> because that flag only reports that the stopping rule fired. So the
> specification is ridge-penalised, and that is a precondition for comparing
> coefficients across labels at all.

**WATCH OUT.** Tempting to spend three minutes here. Do not. One guard
explained properly beats three mentioned.

---

## Segment 6 — From code to thesis (1:30) ★

The payoff segment. Four windows, opened and positioned before you hit record.
Cut or tile between them in this order.

**SHOW**

| Window | File | Positioned at |
|---|---|---|
| 1 | `08.Evaluation.tex` | the H1 sentence, with `\pcHOneEst` visible in the source |
| 2 | `generated/pipeline_constants.tex` | the `\newcommand{\pcHOneEst}{...}` line |
| 3 | `output/processed_data/12_confirmatory_tests.csv` | the H1 row |
| 4 | `index.pdf` | the rendered H1 sentence in Chapter 5 |
| 5 | `build.sh` | the `\pcMissing` guard block at the top |

**SAY**

> This is the part I most want to show you, and it is the reason the thesis and
> the code cannot disagree.
>
> *(window 1)* Here is the sentence in the results chapter that reports H1. Look
> at the source. There is no number in it. There is a macro called `pcHOneEst`.
>
> *(window 2)* Here is where that macro is defined, in a generated file.
> `thesis_constants.R` writes it. I never edit this file.
>
> *(window 3)* And here is where the value came from. This row of
> `12_confirmatory_tests.csv`, written by stage 12, the inference layer.
> Estimate, confidence interval, adjusted p-value.
>
> *(window 4)* And here is the same value on the page of the submitted PDF.
>
> So the chain runs from the model fit, to a result table, to a generated macro,
> to the sentence you read. No result number in this thesis was typed by hand.
>
> *(window 5)* And it is enforced rather than just intended. If a macro the
> thesis actually uses has no value behind it, `thesis_constants.R` emits a
> visible red marker instead of a plausible number, and the build script refuses
> to produce a PDF at all. That guard exists because an earlier version of this
> document went out with thirteen red markers in it and nothing stopped the
> build. Now something does.

**WATCH OUT.** Rehearse this until it takes ninety seconds. Hunting for a
window on camera undoes the point you are making. If the four-window tile is
cramped, record it as four clean cuts instead.

---

## Segment 7 — What was found (1:45) ★

**SHOW**

- Slide 7: the variance decomposition table from Chapter 5.
- Slide 8: the utility threshold sweep figure, with the zero line marked.
- Slide 9: Proposition 5.1, stated, with the pre-treatment onset counts beside
  it.

**SAY**

> Start with the result that inverts my own premise.
>
> I expected the label to dominate. It does not. Model class moves AUROC by
> ‹model-class spread›, against the label's ‹label spread›, and the interval on
> that difference excludes zero. H1 is not confirmed, and it fails in the
> direction opposite to the one I predicted.
>
> H4 goes the same way. I predicted a random split would flatter the model by at
> least 0.02 AUROC. The temporal split actually scored higher, and every model
> fitted under both splits shows the same sign.
>
> Now the part that matters more. The label being small in discrimination is not
> the label being unimportant. The two narrowest readings of Sepsis-3 agree on
> which patients are septic at only kappa equals ‹kappa A vs B›, at almost
> identical prevalence. So the label barely changes how learnable a cohort is,
> and it substantially changes which cohort exists. Every count, rate and
> denominator downstream sits on that choice, and AUROC is blind to all of it.
>
> *(sweep figure)* Clinical utility. This is every model, swept across sixty
> thresholds. The dashed line is the strategy of never alerting at all. Under
> the primary label nothing gets above ‹max utility› on a scale bounded by one,
> and reaching even that costs ‹alert burden› false alerts for every true one,
> against a published benchmark of 1.4. Four of the six models cannot be tuned
> above the line at any threshold.
>
> *(proposition slide)* And this is the finding I think is the most important
> one. Under the onset rule my pre-registered variants use, and much of the
> MIMIC-IV literature uses, the pre-treatment window is empty as a matter of
> arithmetic. Not empty because patients do not deteriorate before treatment.
> Empty because of how the timestamp is assigned. There is a proof in the
> thesis.
>
> Re-time the identical stays by the standard rule and ‹variant F pre-treatment
> onsets› onsets appear in that window, identified at ‹variant F AUROC› AUROC.
> The events were always there. The operationalisation removed them.
>
> So H6 is the one clearly positive result. An interpretable hazard model is not
> outperformed by gradient-boosted trees; the upper confidence limit sits inside
> the pre-registered margin. Whatever the boosted ensemble extracts from these
> features, a pooled logistic hazard model extracts as well, and that one gives
> you coefficients you can inspect.

**WATCH OUT.** Do not say H6 was "rejected" or that any hypothesis was
"confirmed" apart from H2's criterion being met. Check the wording against the
abstract the morning you record.

---

## Segment 8 — Limits and close (0:40)

**SHOW**

- Slide 10: three limitations, one line each.
- Slide 11: the repository URL, large, matching the thesis appendix.

**SAY**

> Three limits worth stating. External validation is bounded by documentation
> coverage in eICU-CRD rather than by cohort size, so the external estimates
> carry direction and not magnitude. No deep temporal model was built, so H6 is
> bounded to the comparator I actually fitted. And the subgroup analysis is
> underpowered, which is a statement about precision and not about fairness.
>
> I have not run anything during this recording. The repository is public, the
> full run is a single command, and the reproduction procedure is in the
> appendix.
>
> The finding I would leave you with is that the label is constituted by the
> clinical actions it is supposed to precede. That is not a failure of any
> model, and no amount of improving discrimination fixes it.

---

## Slides to build

Eleven, in this order. Nothing animates.

1. Title
2. The two-metric collapse (0.811→0.783, +0.381→−0.164)
3. Research question
4. Design grid
5. H1–H6, one line each
6. Person-hour strip with four outcome codes
7. Variance decomposition table
8. Utility threshold sweep figure
9. Proposition 5.1 with onset counts
10. Three limitations
11. Repository URL

## Before you record

- [ ] Rebuild `index.pdf` off camera so the values you show match the submitted
      document.
- [ ] Fill every `‹slot›` above from that build. Not from a deck, not from
      memory.
- [ ] Check H1, H4 and H6 wording against the abstract.
- [ ] Open all five segment-6 windows, size and position them, leave them open.
- [ ] Open `05_primary_model.Rmd`, `utils.R`, `07_metrics_suite.Rmd`,
      `config.R`, `run_pipeline.sh` at the right scroll positions.
- [ ] Raise editor font size. Assume the panel watches smaller than you record.
- [ ] Close anything showing row-level patient data. Aggregate tables are fine,
      individual records are not.
- [ ] Confirm the repository is public and the URL matches the appendix.
- [ ] Rehearse segment 6 alone, twice, with a timer.
- [ ] Hide notifications, mail, and any window title containing a patient
      identifier.

## Questions to expect

- **Why is H6 positive when the p-value is large?** The conclusion comes from
  inverting the interval, not from the test. The upper confidence limit falls
  inside the margin. Failing to reject could never have established it.
- **Isn't an empty pre-treatment window just a null result?** No. It is entailed
  by the onset rule, and the proof is in Chapter 5.
- **Why no deep temporal model?** Planned, not built. It is recorded as a
  limitation and it bounds H6 to the comparator fitted.
- **Why is external validation so imprecise?** The binding constraint is whether
  eICU-CRD documents the labelling inputs at all. Extra person-hours would grow
  the denominator without adding a single observable onset.
- **Eight post-hoc amendments is a lot.** All eight are disclosed and dated, and
  none changes an estimand or a threshold. The one whose result flatters the
  argument is flagged in the thesis as the one to treat most sceptically.
