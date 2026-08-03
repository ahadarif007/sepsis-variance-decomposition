# RESEARCH — orientation

**Before exploring this repo, read `projects/v2/v2-GENAI/HANDOFF.md` in full.**
It is the single source of project knowledge: mission, layout, current results
with headline numbers inlined, known traps, and a map of which one result file
answers which question.

It is written so you can answer most questions with **no further file reads**.

Cost rules for this repo:

- Do **not** dump `v2-proj/output/processed_data/` — it is ~90 files. HANDOFF §5
  names the single file for each question, and CSV mirrors exist for `11_*`/`12_*`.
- Do **not** re-derive results that HANDOFF §3 already states.
- Read thesis `.tex` chapters only when editing them; `evaluation.tex` alone is
  ~1,450 lines and will not fit in one read.
- Active work is `projects/v2/` (`v2-proj` pipeline, `v2-thesis` LaTeX).
  Ignore `projects/v1/` and don't touch `v2-presentation*/` unless asked.
