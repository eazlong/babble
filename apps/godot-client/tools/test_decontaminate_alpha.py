# tools/test_decontaminate_alpha.py
"""TDD checks for tools/decontaminate_alpha.py (alpha edge decontamination).

Failing case this guards against: cutting a cel-shaded sprite with dark outlines
leaves NEAR-BLACK semi-transparent edge pixels, which render as dark halos on
light in-game backgrounds (qa_asset.py --fringe flags them above 5%).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from decontaminate_alpha import decontaminate  # noqa: E402


def _fringed_image() -> Image.Image:
    """Opaque red disc whose anti-aliased edge is black (the classic halo bug)."""
    s = 64
    yy, xx = np.mgrid[0:s, 0:s]
    dist = np.hypot(xx - s / 2 + 0.5, yy - s / 2 + 0.5)
    radius = 20.0
    alpha = np.clip((radius - dist + 0.5) * 255.0, 0, 255).astype(np.uint8)
    rgba = np.zeros((s, s, 4), dtype=np.uint8)
    rgba[..., 0:3] = (220, 60, 60)  # subject colour everywhere...
    edge = (alpha > 0) & (alpha < 255)
    rgba[edge, 0:3] = (0, 0, 0)  # ...except the anti-aliased ring: poisoned black
    rgba[..., 3] = alpha
    return Image.fromarray(rgba, "RGBA")


def _fringe_ratio(im: Image.Image) -> float:
    a = np.array(im.getchannel("A"))
    rgb = np.array(im.convert("RGB")).astype(np.int16)
    semi = (a > 0) & (a < 255)
    if semi.sum() == 0:
        return 0.0
    dark = semi & (rgb[..., 0] < 32) & (rgb[..., 1] < 32) & (rgb[..., 2] < 32)
    return float(dark.sum()) / float(semi.sum())


def test_fringe_removed() -> None:
    src = _fringed_image()
    assert _fringe_ratio(src) > 0.5, "fixture must start badly fringed"
    out = decontaminate(src)
    assert _fringe_ratio(out) == 0.0, f"fringe remains: {_fringe_ratio(out):.1%}"


def test_edge_takes_foreground_colour() -> None:
    out = np.array(decontaminate(_fringed_image()).convert("RGB")).astype(np.int16)
    assert abs(int(out[32, 12, 0]) - 220) < 25, out[32, 12]  # left edge -> red
    assert int(out[32, 12, 1]) < 120, out[32, 12]
    assert int(out[32, 12, 2]) < 120, out[32, 12]


def test_alpha_and_core_untouched() -> None:
    src = _fringed_image()
    out = decontaminate(src)
    assert np.array_equal(np.array(src.getchannel("A")), np.array(out.getchannel("A"))), \
        "alpha channel must not change"
    s = np.array(src)
    o = np.array(out)
    core = s[..., 3] == 255
    assert np.array_equal(s[core], o[core]), "opaque core pixels must not change"


if __name__ == "__main__":
    test_fringe_removed()
    test_edge_takes_foreground_colour()
    test_alpha_and_core_untouched()
    print("ALL DECONTAMINATE TESTS PASS")
