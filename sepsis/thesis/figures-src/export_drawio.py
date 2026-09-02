#!/usr/bin/env python3
"""Export the .drawio sources to PDF (and PNG) with the draw.io desktop CLI.

This is the other half of build_figures.py. That one compiles the .tex sources;
this one renders the .drawio sources, so both representations can be compared
before the thesis is switched from one to the other.

    python3 figures-src/export_drawio.py --into-figures   # THE NORMAL ONE
    python3 figures-src/export_drawio.py                  # preview -> figures-img/drawio/

**Use --into-figures.** The chapters \\includegraphics from figures-img/, so a
render written anywhere else does not reach the thesis. Without the flag this
script writes to figures-img/drawio/, which is a preview directory nothing
includes: the build then succeeds, the page still typesets, and the figure is
silently the old one. That has cost a round already.

(The bare form dates from the TikZ-to-draw.io migration, when figures-img/ still
held TikZ-compiled images and had to keep matching what index.pdf was built
from. The migration is finished and the TikZ is deleted, so that caution is
obsolete; the preview mode is kept only for eyeballing a render before it
replaces the live one.)
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
    if not into:
        # Silence here is the whole failure mode: the export succeeds, the
        # thesis builds, and the figure in the PDF is still the old one.
        print("NOTE: writing PREVIEW renders to figures-img/drawio/.\n"
              "      The chapters include figures-img/, so nothing you see\n"
              "      here will appear in index.pdf. Re-run with --into-figures\n"
              "      when the render is what you want.\n")
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
