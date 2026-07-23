"""
run_pipeline.py
===============
Cross-platform runner for scripts 01..22.
  .py  -> python
  .Rmd -> Rscript -e "rmarkdown::render(...)"  (produces PDF)

All stdout/stderr is saved to pipeline_run.log in this directory.
"""
from __future__ import annotations

import glob
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOG_FILE = HERE / "pipeline_run.log"

STEPS = list(range(1, 23))


def find_script(prefix: str) -> Path | None:
    pattern = str(HERE / f"{prefix}_*")
    hits = sorted(glob.glob(pattern))
    for h in hits:
        if h.endswith((".py", ".Rmd", ".rmd")):
            return Path(h)
    return None


def run(cmd: list[str], label: str, log) -> bool:
    header = f"\n{'='*60}\n[{label}]  {' '.join(cmd)}\n{'='*60}\n"
    print(header, end="", flush=True)
    log.write(header)
    log.flush()

    start = time.time()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=str(HERE),
        text=True,
    )
    for line in proc.stdout:
        sys.stdout.write(line)
        log.write(line)
    proc.wait()
    elapsed = time.time() - start

    footer = f"[{label}] exit {proc.returncode}  ({elapsed:.0f}s)\n"
    print(footer, flush=True)
    log.write(footer)
    log.flush()
    return proc.returncode == 0


def main():
    py = sys.executable

    with open(LOG_FILE, "w", encoding="utf-8") as log:
        log.write(f"Pipeline started: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        failed = []

        for i in STEPS:
            prefix = f"{i:02d}"
            script = find_script(prefix)
            if script is None:
                msg = f"---- No file for prefix {prefix} ----\n"
                print(msg, end="")
                log.write(msg)
                continue

            ext = script.suffix.lower()
            if ext == ".py":
                cmd = [py, "-u", str(script)]
            elif ext == ".rmd":
                render = f"rmarkdown::render('{script.name}')"
                cmd = ["Rscript", "-e", render]
            else:
                continue

            ok = run(cmd, prefix, log)
            if not ok:
                failed.append(prefix)

        log.write(f"\nPipeline finished: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        if failed:
            summary = f"FAILED steps: {', '.join(failed)}\n"
        else:
            summary = "All steps completed successfully.\n"
        print(summary)
        log.write(summary)

    print(f"Full log: {LOG_FILE}")


if __name__ == "__main__":
    main()
