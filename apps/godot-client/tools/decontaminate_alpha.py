# tools/decontaminate_alpha.py
"""Alpha edge decontamination (colour bleed) for cut-out sprites.

Why: color-matting a cel-shaded sprite leaves NEAR-BLACK semi-transparent pixels
along the anti-aliased silhouette (dark outline + soft matte). Rendered on a light
in-game background they read as a dark halo; `qa_asset.py --fringe` rejects >5%.

Fix: keep the alpha channel exactly as-is, but replace the RGB of every
non-opaque pixel with the colour of the nearest fully-opaque pixel (8-connected
dilation). Fully transparent pixels are filled too, so mipmaps/filters never
sample black.

Usage:
    python tools/decontaminate_alpha.py <in.png>            # writes <in>_dc.png
    python tools/decontaminate_alpha.py <in.png> -o <out.png>
    python tools/decontaminate_alpha.py --batch <dir> -o <out_dir>

SOP: run AFTER rembg_matting.py, BEFORE the final LANCZOS downsample.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def decontaminate(im: Image.Image) -> Image.Image:
    """Return a copy of `im` with edge RGB replaced by nearest opaque colour."""
    im = im.convert("RGBA")
    alpha = np.array(im.getchannel("A"), dtype=np.uint8)
    out = np.array(im.convert("RGB"), dtype=np.uint8).copy()

    known = alpha == 255
    if not known.any():
        return im.copy()

    unknown = ~known
    guard = 0
    while unknown.any():
        guard += 1
        if guard > 4096:  # pathological: bail out rather than spin
            break
        filled = known.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                shifted_known = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
                take = unknown & shifted_known & ~filled
                if not take.any():
                    continue
                shifted_rgb = np.roll(np.roll(out, dy, axis=0), dx, axis=1)
                out[take] = shifted_rgb[take]
                filled |= take
        if np.array_equal(filled, known):
            break
        known = filled
        unknown = ~known

    return Image.fromarray(np.dstack([out, alpha]), "RGBA")


def _output_path(src: Path, out: Path | None) -> Path:
    if out is None:
        return src.with_name(src.stem + "_dc.png")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Alpha edge decontamination for sprites")
    ap.add_argument("input", nargs="?", help="input PNG")
    ap.add_argument("-o", "--output", help="output PNG (or directory with --batch)")
    ap.add_argument("--batch", help="process every PNG in this directory")
    args = ap.parse_args()

    if args.batch:
        src_dir = Path(args.batch)
        out_dir = Path(args.output) if args.output else src_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        files = sorted(src_dir.glob("*.png"))
        if not files:
            print(f"no PNGs in {src_dir}", file=sys.stderr)
            return 1
        for f in files:
            dst = _output_path(f, None) if args.output is None else out_dir / f.name
            decontaminate(Image.open(f)).save(dst)
            print(f"decontaminated {dst.name}")
        return 0

    if not args.input:
        ap.error("input or --batch required")
    src = Path(args.input)
    dst = _output_path(src, Path(args.output) if args.output else None)
    decontaminate(Image.open(src)).save(dst)
    print(f"Saved: {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
