# Screencast plan — 5–10 minutes

Internal planning document. Not part of the thesis.

## The problem this has to solve

The submission expects a demonstration. This project is an **analysis
pipeline**, not an application: there is no UI to click through, and the honest
demonstration is that the pipeline runs, produces outputs, and that those
outputs are the numbers in the thesis.

Two traps to avoid.

**A full run takes ~60 minutes.** Nothing can be recorded live end-to-end.

**Recording a terminal that prints log lines for six minutes is not a
demonstration.** The panel needs to see the *link* between code and claim: that
a number in the thesis came out of a specific file produced by a specific stage,
and that nothing in between was typed by hand. That link is this project's real
engineering contribution, and it is demonstrable in a way most analysis projects
are not, because `thesis_constants.R` makes it mechanical.

## Recommended structure (8 minutes)

| # | Segment | Time | What is on screen |
|---|---|---|---|
| 1 | The question | 0:45 | Title slide, then one slide: the field varies the model and fixes everything else; this study does the opposite. State the RQ. |
| 2 | Architecture | 1:15 | `run_pipeline.sh` and the twelve stage files in the editor. Walk the stage table. Point at `config.R` and say once, clearly, that every constant lives there and nowhere else. |
| 3 | **Live partial run** | 2:00 | Terminal: `./run_pipeline.sh 12`. Stage 12 is the right one to show live — it is self-contained, reads existing predictions, prints the bootstrap progress and the Holm/BH tables, and finishes in a bounded time. Let the log scroll; narrate what it is doing. |
| 4 | Outputs appearing | 1:00 | Split screen: `output/processed_data/` before and after. Open `12_confirmatory_tests.csv` and read the H1 row aloud — estimate, interval, adjusted *p*. |
| 5 | **Code to thesis** | 1:45 | The payoff. Run `Rscript thesis_constants.R`; show `pipeline_constants.tex` being rewritten; grep the H1 macro; then open `evaluation.tex` and show the macro *in the source sentence*, not a typed number. Then `./build.sh` and the same value in the PDF. Say explicitly: no result number in the thesis is typed by hand. |
| 6 | A result | 0:45 | One figure — the utility threshold sweep or the subgroup AUROC intervals. One sentence on what it shows. |
| 7 | Close | 0:30 | The headline finding, the repository URL on screen, done. |

Segments 3–5 are the demonstration. Segments 1, 2, 6 and 7 are framing and
should be cut first if the recording runs long.

## Preparation checklist

- [ ] Complete a full pipeline run beforehand, so `output/processed_data/` is
      populated and stage 12 has its inputs.
- [ ] Delete only the stage-12 outputs immediately before recording, so segment
      4 genuinely shows files appearing.
- [ ] Time a rehearsal of `./run_pipeline.sh 12` and confirm it fits segment 3.
      If it does not, run it with a reduced bootstrap count for the recording
      **and say on camera that the replicate count was reduced for the demo** —
      never present a reduced run as the reported one.
- [ ] Increase terminal font size. Log lines must be readable at whatever
      resolution the panel watches at.
- [ ] Close anything showing patient-level data. Nothing from `data/` or
      `processed_data/` containing a patient record may appear on screen —
      results tables and aggregate counts are fine, row-level data is not.
- [ ] Check the repository is public and the URL on the closing slide matches
      the one in the thesis appendix.
- [ ] Record audio separately if the machine is audible under load; stage 12's
      bootstrap will spin the fans.

## Points worth making out loud

These are the things a panel is likely to probe, and each is cheap to state
while something relevant is on screen.

- The label, the split and the metric are treated as variables. That is the
  design, not a robustness check.
- `require_features()` errors rather than dropping a declared predictor — a
  guard against a defect class that is invisible by construction.
- The pipeline halts rather than warns when an invariant fails: a threshold
  above every prediction must score exactly zero; three label variants must
  produce three distinct onset sets.
- Every interval is a stay-level cluster bootstrap, because person-hours are
  not independent.
- Findings that did not survive scrutiny are reported as non-confirmations. Four
  of four testable hypotheses failed, and the thesis says so.
