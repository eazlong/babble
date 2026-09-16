# tools/micro_motion.py
"""Expand ONE rendered pose into N animation frames by micro-motion.

Why this exists: the image model will not produce a consistent multi-pose
character sheet — "3 poses of the same character side by side" reliably comes
back as a front/side/back TURNAROUND (three prompt strategies failed), and
image-to-video drifts slowly instead of looping (61 frames, content width
304 -> 472 px). One front-view render per state plus procedural micro-motion
gives frames that are guaranteed consistent and still read as breathing /
bouncing at the size these sprites are actually shown (180 px NPC cards).

Modes (frame counts match the asset spec: idle >= 3, talk >= 3, happy >= 2):
    idle  : 3 frames — breathing: vertical scale about the BOTTOM edge so the
            feet stay planted while the head dips.
    talk  : 3 frames — talking bob (gentle vertical scale) + 1 px sway.
    happy : 2 frames — cheerful hop: the whole body lifts off the ground.

Usage:
    python tools/micro_motion.py <pose.png> -o <out_dir> --mode idle
    python tools/micro_motion.py --batch <dir> -o <out_dir> --mode talk
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

# (scale_y, offset_x, offset_y) per frame. scale_y is applied about the bottom edge.
CURVES: dict[str, list[tuple[float, int, int]]] = {
    "idle": [(1.000, 0, 0), (0.985, 0, 0), (0.972, 0, 0)],
    "talk": [(1.000, 0, 0), (0.992, 1, 0), (0.984, 0, 0)],
    "happy": [(1.000, 0, 0), (1.000, 0, -10)],
}


def micro_motion(im: Image.Image, mode: str = "idle") -> list[Image.Image]:
    """Return the frame list for `mode` derived from a single pose render."""
    if mode not in CURVES:
        raise ValueError(f"unknown mode {mode!r}; expected one of {sorted(CURVES)}")
    im = im.convert("RGBA")
    w, h = im.size
    frames: list[Image.Image] = []
    for scale_y, dx, dy in CURVES[mode]:
        nh = max(1, round(h * scale_y))
        scaled = im.resize((w, nh), Image.LANCZOS) if nh != h else im
        # Uniform canvas for every frame (a sprite set must not change size).
        # Bottom-anchored paste: the feet keep their y, the head moves. `dy < 0`
        # lifts the whole body (hop) and needs headroom in the source packing.
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        # NOTE: a negative y is intentional — a hop pastes the body higher and the
        # source frame must carry transparent headroom (pack with a smaller
        # fit-height) or the top of the head gets clipped.
        canvas.paste(scaled, (dx, h - nh + dy))
        frames.append(canvas)
    return frames


def main() -> int:
    ap = argparse.ArgumentParser(description="Expand a pose render into micro-motion frames")
    ap.add_argument("input", nargs="?")
    ap.add_argument("-o", "--output")
    ap.add_argument("--batch")
    ap.add_argument("--mode", choices=sorted(CURVES), default="idle")
    args = ap.parse_args()

    def emit(src: Path, out_dir: Path) -> None:
        frames = micro_motion(Image.open(src), args.mode)
        out_dir.mkdir(parents=True, exist_ok=True)
        stem = src.stem
        for i, f in enumerate(frames, 1):
            f.save(out_dir / f"{stem}_{i:02d}.png")
        print(f"{args.mode}: {src.name} -> {len(frames)} frames")

    if args.batch:
        src_dir = Path(args.batch)
        out_dir = Path(args.output) if args.output else src_dir
        files = [f for f in sorted(src_dir.glob("*.png")) if "_preview" not in f.name]
        if not files:
            print(f"no PNGs in {src_dir}", file=sys.stderr)
            return 1
        for f in files:
            emit(f, out_dir)
        return 0

    if not args.input:
        ap.error("input or --batch required")
    src = Path(args.input)
    emit(src, Path(args.output) if args.output else src.parent)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
