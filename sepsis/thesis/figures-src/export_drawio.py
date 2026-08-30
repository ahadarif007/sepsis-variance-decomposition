#!/usr/bin/env python3
"""Export the .drawio sources to PDF (and PNG) with the draw.io desktop CLI.

This is the other half of build_figures.py. That one compiles the .tex sources;
this one renders the .drawio sources, so both representations can be compared
before the thesis is switched from one to the other.

    python3 figures-src/export_drawio.py                 # -> figures-img/drawio/
    python3 figures-src/export_drawio.py --into-figures  # -> figures-img/  (THE SWAP)

--into-figures overwrites the TikZ-compiled images. Only use it when the
chapters are actually being switched to \\includegraphics; until then
figures-img/ must match what index.pdf is built from, which is the .tex.
"""
import os, glob, shutil, subprocess, sys

SRC  = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SRC)
APP  = "/Applications/draw.io.app/Contents/MacOS/draw.io"

def main():
    if not os.path.exists(APP):
        raise SystemExit(
            "draw.io desktop not found at %s\n"
            "Install with:  brew install --cask drawio" % APP)
    into = "--into-figures" in sys.argv
    out  = os.path.join(ROOT, "figures-img") if into else \
           os.path.join(ROOT, "figures-img", "drawio")
    os.makedirs(out, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SRC, "*.drawio")))
    if not files:
        raise SystemExit("no .drawio files in figures-src/")
    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        pdf  = os.path.join(out, name + ".pdf")
        r = subprocess.run([APP, "--export", "--format", "pdf",
                            "--crop", "--border", "6", "--output", pdf, f],
                           capture_output=True, text=True)
        if not os.path.exists(pdf):
            print("  FAIL %s\n%s" % (name, r.stderr.strip()[:400])); continue
        subprocess.run(["pdftoppm", "-r", "300", "-png", "-singlefile",
                        pdf, os.path.join(out, name)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("  ok   %s.pdf + .png" % name)
    print("\nwrote to %s" % os.path.relpath(out, ROOT))
    if not into:
        print("figures-img/ itself is untouched and still matches index.pdf.")

if __name__ == "__main__":
    main()
