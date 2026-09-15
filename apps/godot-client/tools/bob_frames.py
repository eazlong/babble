# tools/bob_frames.py
"""Apply a vertical bob cycle to a frame set (walk/idle HUD hand animation).

Why: image-to-video of a still anchor often returns near-static motion (measured
0.65px and 1.93px centroid travel over a whole clip), so the frames carry the right
art but no readable movement. Offsetting each frame on a sine cycle gives the
vertical oscillation a walk cycle needs.

Each frame is shifted by `offsets[i]` px (positive = down) and the bottom rows are
repeated down to the canvas edge so the arms still run off-screen after the shift.

    python tools/bob_frames.py --batch <dir> -o <out_dir> --offsets "2,3,2,-2,-3,-2"
    python tools/bob_frames.py <in.png> -o <out.png> --offset -3
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image


def bob_frame(im: Image.Image, offset: int, extend_bottom: bool = True) -> Image.Image:
    """Shift `im` vertically by `offset` px, keeping the bottom edge covered."""
    im = im.convert("RGBA")
    size = im.size
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.paste(im, (0, offset))
    if not extend_bottom:
        return canvas

    # After an upward shift the content can stop above the bottom edge; repeat its
    # last row(s) down to the edge so the arm keeps running off-screen.
    alpha = canvas.getchannel("A")
    last = None
    for y in range(size[1] - 1, -1, -1):
        if alpha.crop((0, y, size[0], y + 1)).getbbox() is not None:
            last = y
            break
    if last is None or last == size[1] - 1:
        return canvas
    band_h = min(8, last + 1)
    band = canvas.crop((0, last - band_h + 1, size[0], last + 1))
    ext_h = size[1] - (last + 1)
    ext = band.resize((size[0], band_h + ext_h), Image.NEAREST)
    canvas.paste(ext, (0, last + 1))
    return canvas


def sine_offsets(count: int, amplitude: int = 3) -> list[int]:
    import math
    return [round(amplitude * math.sin(2 * math.pi * (i + 0.5) / count))
            for i in range(count)]


def main() -> int:
    ap = argparse.ArgumentParser(description="Apply a vertical bob to sprite frames")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--batch")
    ap.add_argument("--offset", type=int, default=0, help="single-frame mode offset")
    ap.add_argument("--offsets", help="comma-separated per-frame offsets (batch)")
    ap.add_argument("--sine", type=int, metavar="AMPLITUDE",
                    help="generate offsets from a sine of this amplitude")
    ap.add_argument("--no-extend", action="store_true")
    args = ap.parse_args()
    extend = not args.no_extend

    if args.batch:
        src_dir = Path(args.batch)
        out_dir = Path(args.output) if args.output else src_dir
        out_dir.mkdir(parents=True, exist_ok=True)
        files = [f for f in sorted(src_dir.glob("*.png")) if "_preview" not in f.name]
        if not files:
            print(f"no PNGs in {src_dir}", file=sys.stderr)
            return 1
        if args.offsets:
            offsets = [int(v) for v in args.offsets.split(",")]
        elif args.sine is not None:
            offsets = sine_offsets(len(files), args.sine)
        else:
            offsets = sine_offsets(len(files), 3)
        if len(offsets) != len(files):
            print(f"{len(offsets)} offsets for {len(files)} frames", file=sys.stderr)
            return 1
        for f, off in zip(files, offsets):
            bob_frame(Image.open(f), off, extend).save(out_dir / f.name)
            print(f"bobbed {f.name} by {off:+d}px")
        return 0

    if not args.input:
        ap.error("input or --batch required")
    src = Path(args.input)
    dst = Path(args.output) if args.output else src.with_name(src.stem + "_bob.png")
    bob_frame(Image.open(src), args.offset, extend).save(dst)
    print(f"Saved: {dst}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
