# tools/test_harden_alpha.py
"""TDD checks for tools/harden_alpha.py (kill the low-alpha haze band)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from harden_alpha import harden_alpha  # noqa: E402


def _hazy_image() -> Image.Image:
    """Bimodal alpha: haze band (0.001-0.2) + solid subject (1.0) + soft edge."""
    alphas = [0, 3, 12, 51, 64, 128, 178, 200, 255]
    im = Image.new("RGBA", (len(alphas), 1), (200, 150, 120, 0))
    px = im.load()
    for x, a in enumerate(alphas):
        px[x, 0] = (200, 150, 120, a)
    return im


def test_haze_removed_and_subject_kept() -> None:
    out = harden_alpha(_hazy_image(), lo=0.25, hi=0.70)  # 0.25*255=64, 0.70*255=178
    a = [p[3] for p in out.convert("RGBA").getdata()]
    assert a[0] == 0, "fully transparent stays transparent"
    assert a[1] == 0 and a[2] == 0 and a[3] == 0, f"haze band must clear: {a}"
    assert a[4] <= 1, f"value at lo must map to ~0: {a[4]}"
    assert 130 <= a[5] <= 150, f"mid-ramp value should stay mid: {a[5]}"
    assert a[6] >= 254 and a[7] == 255 and a[8] == 255, f"subject must stay opaque: {a}"


def test_rgb_untouched() -> None:
    src = _hazy_image()
    out = harden_alpha(src, lo=0.25, hi=0.70)
    s = np.array(src.convert("RGB"))
    o = np.array(out.convert("RGB"))
    assert np.array_equal(s, o), "RGB must not change (color is decontaminate_alpha's job)"


def test_no_haze_band_survives_on_realistic_mask() -> None:
    """Realistic bimodal mask: 90% haze at 0.15, 10% subject at 1.0."""
    rng = np.random.default_rng(7)
    h = rng.random((64, 64)) < 0.9
    alpha = np.where(h, 38, 255).astype(np.uint8)  # 38/255 ~= 0.15
    im = Image.fromarray(np.dstack([np.full((64, 64), 210, np.uint8),
                                    np.full((64, 64), 160, np.uint8),
                                    np.full((64, 64), 130, np.uint8), alpha]), "RGBA")
    out = np.array(harden_alpha(im, lo=0.25, hi=0.70))
    vals = np.unique(out[:, :, 3])
    assert set(vals.tolist()) <= {0, 255}, f"expected binary mask, got {vals.tolist()[:6]}"


if __name__ == "__main__":
    test_haze_removed_and_subject_kept()
    test_rgb_untouched()
    test_no_haze_band_survives_on_realistic_mask()
    print("ALL HARDEN_ALPHA TESTS PASS")
