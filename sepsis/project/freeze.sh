#!/usr/bin/env bash
#
# freeze.sh — execute THE frozen run and prepare the release commit.
#
# Why this exists: the pipeline is not bit-stable (the GBT comparator refits
# differently each run), so every re-run moves GBT-derived numbers slightly.
# The thesis stays internally consistent, but anything built outside it — the
# presentation, the screencast, a number recalled in a viva — can silently
# disagree with the submitted PDF. Freezing pins one run and stamps its commit
# into the document.
#
#   ./freeze.sh --dry-run          check the preconditions only
#   FREEZE_TAG=frozen-2026-10-05 ./freeze.sh
#
# This script does NOT commit, tag, or push. It leaves a verified working tree
# and prints the exact commands to run. Releasing is a human decision.
set -uo pipefail
cd "$(dirname "$0")"
ROOT="$(git rev-parse --show-toplevel)"
THESIS="$(cd ../thesis && pwd)"
DRY=0; [[ "${1:-}" == "--dry-run" ]] && DRY=1

fail() { printf '\n  FAIL  %s\n' "$*" >&2; exit 1; }
step() { printf '\n=== %s ===\n' "$*"; }

step "Preconditions"

[[ -n "${FREEZE_TAG:-}" ]] || fail "FREEZE_TAG is not set.
        The tag name is stamped into the thesis as \\pcFrozenTag, so it must be
        chosen BEFORE the run, not after.
        e.g.  FREEZE_TAG=frozen-2026-10-05 ./freeze.sh"

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  git -C "$ROOT" status --short | sed 's/^/        /'
  fail "the working tree is dirty.
        Constants record the commit hash with a '-dirty' suffix when generated
        from uncommitted work, and a submitted thesis must not carry that.
        Commit or stash first, then re-run."
fi

command -v Rscript >/dev/null || fail "Rscript not found"
command -v pdflatex >/dev/null || fail "pdflatex not found"
[[ -f 00_preregistration.md ]] || fail "00_preregistration.md missing (G0 gate)"

# Captured HERE, while the tree is still verified clean, and exported so that
# every thesis_constants.R invocation below stamps this hash rather than looking
# it up live. The live lookup cannot be used during a freeze: pipeline_constants
# .tex is tracked, the run rewrites it, and setting FREEZE_TAG alone changes its
# contents, so by the time the stamp is verified the tree is dirty by this
# script's own action. Capturing it up front is what makes the stamp mean "the
# source state that produced these numbers", which is what Appendix A.2 claims.
FREEZE_COMMIT="$(git -C "$ROOT" describe --always --abbrev=12)"
export FREEZE_COMMIT FREEZE_TAG

echo "  ok    tree clean at $FREEZE_COMMIT"
echo "  ok    tag to be stamped: $FREEZE_TAG"
echo "  ok    toolchain present"

if [[ $DRY -eq 1 ]]; then
  printf '\n  Dry run only. Nothing was executed.\n'
  printf '  Full run takes roughly 2h30m; stage 05 alone is about 73 minutes.\n'
  exit 0
fi

step "Full pipeline (12 stages, ~2h30m)"
./run_pipeline.sh || fail "pipeline did not complete"

step "Regenerating thesis constants"
# thesis_constants.R exits non-zero on any unresolved macro. FREEZE_TAG and
# FREEZE_COMMIT are already exported, so this stamps the captured hash.
Rscript thesis_constants.R || fail "unresolved macros; the thesis would carry red ?? markers"

step "Consistency checkers"
Rscript check_consistency.R   || fail "check_consistency.R reported a failure"
Rscript check_thesis_numbers.R || fail "check_thesis_numbers.R reported a failure"

step "Building the thesis"
( cd "$THESIS" && ./build.sh ) || fail "thesis build failed"

step "Verifying the stamp"
STAMP=$(grep -o '\\newcommand{\\pcFrozenCommit}{[^}]*}' "$THESIS/generated/pipeline_constants.tex" | sed 's/.*{\(.*\)}/\1/')
case "$STAMP" in
  *-dirty) fail "constants recorded '$STAMP' — generated from a dirty tree" ;;
  "")      fail "no \\pcFrozenCommit was emitted" ;;
esac
[[ "$STAMP" == "$FREEZE_COMMIT" ]] || fail "stamp '$STAMP' is not the commit verified clean at the
        start of this run ('$FREEZE_COMMIT'). The export did not reach
        thesis_constants.R, so the document does not name the source that
        produced its numbers."
STAMPED_TAG=$(grep -o '\\newcommand{\\pcFrozenTag}{[^}]*}' "$THESIS/generated/pipeline_constants.tex" | sed 's/.*{\(.*\)}/\1/')
[[ "$STAMPED_TAG" == "$FREEZE_TAG" ]] || fail "the thesis names tag '$STAMPED_TAG', not '$FREEZE_TAG'"
echo "  ok    thesis stamped with commit $STAMP, tag $FREEZE_TAG"

cat <<DONE

=== Frozen run complete ===

  Pipeline commit : $STAMP
  Tag to apply    : $FREEZE_TAG

Nothing has been committed. To release:

  git add -A
  git commit -m "Frozen run $FREEZE_TAG"
  git tag -a $FREEZE_TAG -m "Frozen run: thesis and pipeline state as submitted"

After tagging, treat 00-12, config.R and utils.R as read-only. The
presentation, screencast and viva preparation all read from
thesis/generated/pipeline_constants.tex, never from a fresh run.
DONE
