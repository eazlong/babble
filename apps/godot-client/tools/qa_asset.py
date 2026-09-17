# tools/qa_asset.py
"""QA gate for generated assets. Exit 0 = PASS, 1 = FAIL. Always writes a 25% preview."""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def check_fringe(im: Image.Image) -> float:
    """Fraction of semi-transparent pixels that are near-black."""
    a = im.getchannel("A")
    hist = a.histogram()
    semi = sum(hist[1:254])
    if semi == 0:
        return 0.0
    px = im.load()
    dark = 0
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, al = px[x, y]
            if 0 < al < 255:
                if r < 32 and g < 32 and b < 32:
                    dark += 1
    return dark / semi


def fringe_contrast(im: Image.Image, max_iter: int = 64) -> tuple[float, float]:
    """Compare each semi-transparent pixel with the NEAREST opaque pixel's colour.

    Returns (mean luminance difference, fraction of semi pixels >20 darker).

    Why this exists: the raw near-black ratio alone false-positives on characters drawn
    with heavy black line art (all-dark edges). Two measured traps:
      * averaging the opaque colours in a ring around the pixel instead of taking the
        nearest one reports a phantom -35 on a clean frame — a dark outline sitting on a
        light background gets compared against a ring mean that includes the light
        background. The clerk's accepted frame measures +1.1 / median 0.0 against its
        true nearest neighbour, exactly like the already-accepted aling frames.
      * a genuine halo (matting against transparent black) leaves edge pixels far DARKER
        than the art they touch: the same clerk frame measures -23.8 BEFORE
        decontaminate_alpha and +1.1 after, so the metric tracks the real defect.
    The nearest opaque colour is propagated with the same 8-connected dilation
    decontaminate_alpha uses, so the two agree by construction.
    """
    arr = np.asarray(im.convert("RGBA"), dtype=np.int16)
    alpha = arr[..., 3]
    lum = arr[..., :3].mean(axis=2)
    semi = (alpha > 0) & (alpha < 255)
    if not semi.any():
        return 0.0, 0.0
    opaque = alpha >= 250
    if not opaque.any():
        return -255.0, 1.0
    nearest = np.where(opaque, lum, np.nan)
    known = opaque.copy()
    for _ in range(max_iter):
        if known[semi].all():
            break
        filled = known.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                sk = np.roll(np.roll(known, dy, axis=0), dx, axis=1)
                sv = np.roll(np.roll(nearest, dy, axis=0), dx, axis=1)
                take = ~filled & sk
                nearest[take] = sv[take]
                filled |= take
        known = filled
    reachable = ~np.isnan(nearest[semi])
    diffs = np.where(reachable, lum[semi] - np.nan_to_num(nearest[semi], nan=255.0), -255.0)
    return float(diffs.mean()), float((diffs < -20).mean())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--size", help="WxH, exact match required")
    ap.add_argument("--mode", choices=["RGB", "RGBA"])
    ap.add_argument("--fringe", action="store_true",
                    help="reject black alpha fringing (>5%% of semi-transparent pixels)")
    args = ap.parse_args()

    im = Image.open(args.path)
    errors = []
    if args.size:
        w, h = map(int, args.size.split("x"))
        if im.size != (w, h):
            errors.append(f"size {im.size[0]}x{im.size[1]} != expected {w}x{h}")
    if args.mode and im.mode != args.mode:
        errors.append(f"mode {im.mode} != expected {args.mode}")
    if args.fringe and im.mode == "RGBA":
        f = check_fringe(im)
        if f > 0.05:
            mean_diff, worse = fringe_contrast(im)
            if mean_diff < -8.0 or worse > 0.25:
                errors.append(
                    f"black alpha fringe ratio {f:.1%} > 5% and edge darker than its art "
                    f"(mean {mean_diff:+.1f}, {worse:.0%} >20 darker)")
            else:
                print(f"  note: fringe ratio {f:.1%} but edge pixels match their opaque "
                      f"neighbours (mean {mean_diff:+.1f}) — dark line art, not a halo")

    prev = Path(args.path).with_name(Path(args.path).stem + "_preview25.png")
    im.copy().resize((im.size[0] // 4, im.size[1] // 4), Image.LANCZOS).save(prev)

    if errors:
        print("FAIL " + "; ".join(errors))
        return 1
    print(f"PASS {args.path} ({im.size[0]}x{im.size[1]}, {im.mode})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
