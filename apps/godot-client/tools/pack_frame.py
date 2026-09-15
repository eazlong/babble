# tools/pack_frame.py
"""Pack a cut-out sprite frame into a fixed square canvas without distortion.

Problem it solves: sheet cells are not square (a 1x3 strip gives ~437x736 panels).
Resizing those straight to 256x256 stretches the art. This tool instead:
  1. crops to the alpha bounding box (drops dead padding),
  2. scales UNIFORMLY (LANCZOS) to fit inside `size - 2*margin`,
  3. pastes onto a transparent square canvas, centred horizontally and anchored
     to the bottom (default) so first-person hands keep their bottom entry edge.

Usage:
    python tools/pack_frame.py <in.png> -o <out.png> [--size 256] [--margin 4]
    python tools/pack_frame.py --batch <dir> -o <out_dir> [--size 256]

SOP: run AFTER rembg_matting.py + decontaminate_alpha.py (decontaminate at full
resolution, then pack).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def pack_frame(im: Image.Image, size: int = 256, margin: int = 4,
               anchor: str = "bottom", fit_width: int | None = None,
               extend_bottom: bool = False, bbox_thresh: int = 128) -> Image.Image:
    """Pack a cut-out frame into a square canvas.

    anchor="bottom"  : scale to fit inside (size - 2*margin), bottom-anchored.
    anchor="top"     : own the TOP edge (first-person: fingertips at `margin`),
                       forearm may overflow the bottom and is clipped by the canvas.
    fit_width=N      : scale by WIDTH to exactly N px (normalises hand span across
                       frames whose source panels expose different forearm lengths),
                       ignoring the height budget.
    extend_bottom    : continue the last rows straight down to the canvas bottom when
                       the content stops short of it (no sawn-off arms).
    bbox_thresh      : alpha level that counts as "solid" when measuring the content
                       box. Stray faint pixels (matting stragglers) elsewhere in the
                       cell must not inflate the box, or width-normalisation shrinks
                       the real subject and the crop can cut it.
    """
    im = im.convert("RGBA")
    solid = im.getchannel("A").point(lambda v: 255 if v >= bbox_thresh else 0)
    bbox = solid.getbbox()
    if bbox is None:
        raise ValueError(f"frame has no pixels with alpha >= {bbox_thresh}")
    content = im.crop(bbox)
    cw, ch = content.size

    if fit_width:
        ratio = fit_width / cw
    else:
        fit = max(1, size - 2 * margin)
        ratio = min(fit / cw, fit / ch)
    nw, nh = max(1, round(cw * ratio)), max(1, round(ch * ratio))
    content = content.resize((nw, nh), Image.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - nw) // 2
    if anchor == "bottom":
        y = size - nh - margin
    else:
        y = margin
    # NOTE: plain paste (no mask). Passing `content` as its own mask would blend the
    # semi-transparent edge against the transparent-black canvas, darkening edge RGB
    # (decontaminated peach/outline colours drop below 32 -> qa_asset --fringe FAIL).
    canvas.paste(content, (x, y))

    if extend_bottom and y + nh < size:
        # First-person arms must run OFF the canvas bottom. When a square sheet cell
        # ends above the bottom edge the arms look sawn off mid-air, so continue the
        # last rows of the cut cross-section straight down to the edge.
        band_h = min(8, nh)
        band = content.crop((0, nh - band_h, nw, nh))
        ext_h = size - (y + nh)
        band = band.resize((nw, band_h + ext_h), Image.NEAREST)
        canvas.paste(band, (x, y + nh))

    return canvas


def main() -> int:
    ap = argparse.ArgumentParser(description="Pack cut-out frames into square canvases")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--batch")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--margin", type=int, default=4)
    ap.add_argument("--anchor", choices=["bottom", "top", "center"], default="bottom")
    ap.add_argument("--fit-width", type=int, default=None,
                    help="scale by width to exactly N px (normalises hand span)")
    ap.add_argument("--extend-bottom", action="store_true",
                    help="continue the last rows down to the canvas bottom (no sawn-off arms)")
    ap.add_argument("--bbox-thresh", type=int, default=128,
                    help="alpha level counted as solid when measuring the content box")
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
            dst = (out_dir / f.name) if args.output is None else (out_dir / f.name)
            pack_frame(Image.open(f), args.size, args.margin, args.anchor,
                       args.fit_width, args.extend_bottom,
                       args.bbox_thresh).save(dst)
            print(f"packed {dst.name}")
        return 0

    if not args.input:
        ap.error("input or --batch required")
    src = Path(args.input)
    dst = Path(args.output) if args.output else src.with_name(src.stem + f"_{args.size}.png")
    pack_frame(Image.open(src), args.size, args.margin, args.anchor,
               args.fit_width, args.extend_bottom, args.bbox_thresh).save(dst)
    print(f"Saved: {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
