#!/usr/bin/env python3
"""Pixel comparison of a render against a reference screenshot (overlay, amplified diff, per-component metrics).

usage: compare.py REFERENCE.png OUR.png OUTDIR [x0 y0]
REFERENCE is cropped to the opaque window (alpha==255 area) unless x0/y0 are given.
Writes overlay (50 %), diff (amplified) and per-component metrics to OUTDIR/report.md.
"""
import sys, os
import numpy as np
from PIL import Image

ref_path, our_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
ref = Image.open(ref_path).convert("RGBA")
a = np.asarray(ref)
op = a[:, :, 3] == 255
ys, xs = np.where(op.mean(1) > .5)[0], np.where(op.mean(0) > .5)[0]
x0, y0 = (int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) > 5 else (xs.min(), ys.min())
our = Image.open(our_path).convert("RGB")
W, H = our.size
R = np.asarray(ref.crop((x0, y0, x0 + W, y0 + H)).convert("RGB")).astype(int)
O = np.asarray(our).astype(int)
D = np.abs(R - O).max(2)

# components (x0, y0, x1, y1) in window pixels; sidebar differs in content (reference shows other accounts), reported separately
comp = {
    "Leather header (0-40)": (0, 0, W, 40),
    "Rule + paper edge (40-62)": (0, 40, W, 62),
    "Toolbar controls (centre)": (560, 20, 830, 50),
    "Search field": (1170, 20, 1386, 50),
    "Title text": (200, 64, 440, 100),
    "Day header row": (218, 104, W, 126),
    "Grid body (events excluded: whole grid)": (218, 150, W, H - 20),
    "Hour labels": (165, 160, 218, H - 20),
    "Sidebar (content differs)": (0, 62, 164, H),
}
lines = ["# Pixel comparison", "", f"Reference `{os.path.basename(ref_path)}` window origin ({x0},{y0}), size {W}x{H}.", "",
         "| Component | pixels | > 8/255 | share | mean abs diff |", "|---|---|---|---|---|"]
tot_bad = 0
for name, (a0, b0, a1, b1) in comp.items():
    d = D[b0:b1, a0:a1]
    bad = (d > 8).sum(); n = d.size
    lines.append(f"| {name} | {n} | {bad} | {bad / n * 100:.1f} % | {d.mean():.1f} |")
allbad = (D > 8).sum()
lines += ["", f"**Whole window:** {allbad} of {D.size} pixels differ by more than 8/255 ({allbad / D.size * 100:.1f} %). Identical pixels (0 difference): {(D == 0).sum() / D.size * 100:.1f} %.",
          "", "Rule of thumb: ≤ 1 % per unmasked component; 0 differing pixels only for 'pixel-identical'."]
open(os.path.join(out, "report.md"), "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
Image.blend(Image.fromarray(R.astype("uint8")), our, .5).save(os.path.join(out, "overlay.png"))
Image.fromarray(np.clip(D * 4, 0, 255).astype("uint8")).save(os.path.join(out, "diff.png"))
side = Image.new("RGB", (W * 2, H)); side.paste(Image.fromarray(R.astype("uint8")), (0, 0)); side.paste(our, (W, 0)); side.save(os.path.join(out, "side_by_side.png"))
