# tools/harden_alpha.py
"""Collapse a soft/hazy alpha mask onto its true silhouette (flat-background cutouts).

Why: for flat-colour source art the matting alpha is bimodal — a real subject band
(~1.0) plus a wide low-alpha haze from a weak soft mask. The haze is invisible in a
preview but is a faint veil in game (and inflates the sprite's effective area).

Fix: remap alpha linearly so values <= lo become fully transparent and values
>= hi become fully opaque, keeping a soft ramp in between for true anti-aliased
edges. RGB is never touched (run decontaminate_alpha.py afterwards for edge colour).

    python tools/harden_alpha.py <in.png> -o <out.png> --lo 0.25 --hi 0.70
    python tools/harden_alpha.py --batch <dir> -o <out_dir> --lo 0.25 --hi 0.70

SOP order: rembg_matting.py -> harden_alpha.py -> pack_frame.py -> decontaminate_alpha.py
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def harden_alpha(im: Image.Image, lo: float = 0.25, hi: float = 0.70) -> Image.Image:
    if not 0.0 <= lo < hi <= 1.0:
        raise ValueError(f"need 0 <= lo < hi <= 1, got lo={lo} hi={hi}")
    im = im.convert("RGBA")
    arr = np.array(im, dtype=np.uint8)
    a = arr[:, :, 3].astype(np.float64) / 255.0
    remapped = np.clip((a - lo) / (hi - lo), 0.0, 1.0)
    arr[:, :, 3] = np.rint(remapped * 255.0).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def main() -> int:
    ap = argparse.ArgumentParser(description="Harden a hazy alpha mask")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--batch")
    ap.add_argument("--lo", type=float, default=0.25)
    ap.add_argument("--hi", type=float, default=0.70)
    args = ap.parse_args()

    if args.batch:
        src_dir = Path(args.batch)
        out_dir = Path(args.output) if args.output else src_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        files = [f for f in sorted(src_dir.glob("*.png")) if "_preview" not in f.name]
        if not files:
            print(f"no PNGs in {src_dir}", file=sys.stderr)
            return 1
        for f in files:
            harden_alpha(Image.open(f), args.lo, args.hi).save(out_dir / f.name)
            print(f"hardened {f.name}")
        return 0

    if not args.input:
        ap.error("input or --batch required")
    src = Path(args.input)
    dst = Path(args.output) if args.output else src.with_name(src.stem + "_hard.png")
    harden_alpha(Image.open(src), args.lo, args.hi).save(dst)
    print(f"Saved: {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
