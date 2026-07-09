#!/usr/bin/env zsh
# run_01_to_22.zsh
# Execute the first matching file for prefixes 01..22 in numeric order.
# Dispatches by extension: .py -> python3, .R -> Rscript, .Rmd -> rmarkdown::render,
# .sh -> bash, .zsh -> zsh. Unknown extensions are skipped.
# Set BASE_DIR to override the working directory (defaults to script directory).

set -u
set -o pipefail

# Defaults (can be overridden by env vars or CLI flags)
DRY_RUN="${DRY_RUN:-0}"             # 1 -> print commands instead of running
CONTINUE_ON_ERROR="${CONTINUE_ON_ERROR:-0}"  # 1 -> continue on error
RENDER_RMD="${RENDER_RMD:-1}"       # 1 -> render .Rmd files

print_usage() {
  cat <<EOF
Usage: $0 [options]
Options:
  -n, --dry-run       Print commands instead of executing
  -c, --continue      Continue on error instead of exiting
  -r, --no-render     Do not render .Rmd files for this run
  -h, --help          Show this help

Defaults: render .Rmd files, exit on first failure.
EOF
}

# CLI flags override environment variables
while (( "$#" )); do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=1
      shift
      ;;
    -c|--continue)
      CONTINUE_ON_ERROR=1
      shift
      ;;
    -r|--no-render)
      RENDER_RMD=0
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Unknown option: $1"
      print_usage
      exit 2
      ;;
  esac
done

# Apply continue-on-error behavior
if [[ "$CONTINUE_ON_ERROR" == "1" ]]; then
  set +e
else
  set -e
fi

# Base directory containing the numbered files. Default: this script's directory.
BASE_DIR="${BASE_DIR:-$(cd "$(dirname "$0")" && pwd)}"
BASE="$BASE_DIR"

# Dry-run handling: EXEC_CMD prints or executes
if [[ "$DRY_RUN" != "0" ]]; then
  echo "DRY_RUN=1 -> printing commands (no execution)"
  function EXEC_CMD() {
    echo "+ $*"
  }
else
  function EXEC_CMD() {
    # Direct exec avoids zsh glob-qualifying parentheses in rmarkdown::render().
    "$@"
  }
fi

echo "Running 01..22 in: $BASE"

for i in {01..22}; do
  # use zsh nullglob (N) to get empty array if no match
  matches=($BASE/${i}_*.*(N))
  if (( ${#matches} )); then
    file=${matches[1]}
    echo "==== [$i] -> $file ===="
    ext=${file##*.}
    case "$ext" in
      py)
        EXEC_CMD python3 -u "$file"
        ;;
      sh)
        EXEC_CMD bash "$file"
        ;;
      zsh)
        EXEC_CMD zsh "$file"
        ;;
      R)
        EXEC_CMD Rscript "$file"
        ;;
      Rmd|rmd)
        if [[ "$RENDER_RMD" != "0" ]]; then
          EXEC_CMD Rscript -e "rmarkdown::render('$file')"
        else
          echo "Skipping $file (.Rmd) because RENDER_RMD=0"
        fi
        ;;
      *)
        echo "Skipping $file (unknown extension .$ext)"
        ;;
    esac
  else
    echo "---- No file found for prefix $i ----"
  fi
done

echo "All done."

