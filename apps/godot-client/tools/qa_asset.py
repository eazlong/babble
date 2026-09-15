# tools/qa_asset.py
"""QA gate for generated assets. Exit 0 = PASS, 1 = FAIL. Always writes a 25% preview."""
import argparse
import sys
from pathlib import Path

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
            errors.append(f"black alpha fringe ratio {f:.1%} > 5%")

    prev = Path(args.path).with_name(Path(args.path).stem + "_preview25.png")
    im.copy().resize((im.size[0] // 4, im.size[1] // 4), Image.LANCZOS).save(prev)

    if errors:
        print("FAIL " + "; ".join(errors))
        return 1
    print(f"PASS {args.path} ({im.size[0]}x{im.size[1]}, {im.mode})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
