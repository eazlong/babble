# tools/test_micro_motion.py
"""TDD checks for tools/micro_motion.py (procedural idle/talk/happy frames)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from micro_motion import CURVES, micro_motion  # noqa: E402


def _pose(w: int = 120, h: int = 200) -> Image.Image:
    """A stand-in character with realistic headroom (packed frames are not full-bleed).

    Head block y 20..60, body y 60..190, transparent 0..20 and 190..200.
    """
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y in range(60, 190):          # body
        for x in range(30, w - 30):
            im.putpixel((x, y), (180, 120, 90, 255))
    for y in range(20, 60):           # head
        for x in range(45, w - 45):
            im.putpixel((x, y), (90, 60, 40, 255))
    return im


def _opaque_rows(im: Image.Image, thresh: int = 32) -> tuple[int, int]:
    """First/last row containing SOLID pixels.

    Threshold matters: LANCZOS resampling bleeds a faint alpha halo a few px past
    the real edge, so an alpha>0 test reports feet that "moved" when they did not.
    """
    rows = np.where(np.asarray(im.getchannel("A")).max(axis=1) > thresh)[0]
    return int(rows.min()), int(rows.max())


def test_frame_counts_match_asset_spec() -> None:
    assert len(micro_motion(_pose(), "idle")) == 3   # idle >= 3
    assert len(micro_motion(_pose(), "talk")) == 3   # talk >= 3
    assert len(micro_motion(_pose(), "happy")) == 2  # happy >= 2


def test_idle_breath_keeps_feet_planted_and_moves_head() -> None:
    frames = micro_motion(_pose(), "idle")
    bottoms = [_opaque_rows(f)[1] for f in frames]
    tops = [_opaque_rows(f)[0] for f in frames]
    # feet stay put (bottom-anchored scale), head dips progressively
    assert max(bottoms) - min(bottoms) <= 1, bottoms
    assert tops[0] < tops[1] < tops[2], tops


def test_happy_bounce_lifts_the_whole_body() -> None:
    base, hop = micro_motion(_pose(), "happy")
    b_top, b_bottom = _opaque_rows(base)
    h_top, h_bottom = _opaque_rows(hop)
    assert b_bottom - h_bottom >= 8, (b_bottom, h_bottom)   # ground left behind
    assert b_top - h_top >= 8, (b_top, h_top)


def test_talk_sways_horizontally() -> None:
    frames = micro_motion(_pose(), "talk")
    cols = [np.where(np.asarray(f.getchannel("A")).max(axis=0) > 0)[0] for f in frames]
    assert cols[1].min() != cols[0].min(), "middle frame should sway 1 px"


def test_unknown_mode_rejected() -> None:
    try:
        micro_motion(_pose(), "walk")
    except ValueError:
        return
    raise AssertionError("expected ValueError for unknown mode")


def test_curves_documented_for_every_mode() -> None:
    assert set(CURVES) == {"idle", "talk", "happy"}
    for mode, curve in CURVES.items():
        assert len(curve) >= 2, mode
        assert all(len(step) == 3 for step in curve), mode
