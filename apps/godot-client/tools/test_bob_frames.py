# tools/test_bob_frames.py
"""TDD checks for tools/bob_frames.py (synthetic walk/idle bob)."""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from bob_frames import bob_frame, sine_offsets  # noqa: E402


def _frame() -> Image.Image:
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    im.paste(Image.new("RGBA", (100, 100), (222, 168, 140, 255)), (78, 100))
    return im


def _centroid_y(im: Image.Image) -> float:
    a = np.array(im.getchannel("A")).astype(float)
    m = a > 200
    ys = np.mgrid[0:a.shape[0], 0:a.shape[1]][0]
    return float(ys[m].mean())


def test_offset_moves_content() -> None:
    base = _centroid_y(bob_frame(_frame(), 0, extend_bottom=False))
    up = _centroid_y(bob_frame(_frame(), -3, extend_bottom=False))
    down = _centroid_y(bob_frame(_frame(), 3, extend_bottom=False))
    assert abs((base - up) - 3) < 0.6, f"up shift wrong: {base} -> {up}"
    assert abs((down - base) - 3) < 0.6, f"down shift wrong: {base} -> {down}"


def test_bottom_stays_covered_after_upward_shift() -> None:
    """An upward shift must not leave a gap at the canvas bottom."""
    f = _frame()  # content ends at y=200, i.e. already short of the edge
    out = bob_frame(f, -5)
    a = np.array(out.getchannel("A"))
    bottom = a[255][a[255] > 200]
    assert bottom.size > 0, "bottom row must stay covered by the extended arm"
    assert a[255, 128] > 200, "centre of the bottom row should be opaque arm"


def test_sine_offsets_form_a_cycle() -> None:
    offs = sine_offsets(6, 3)
    assert len(offs) == 6
    assert max(offs) - min(offs) >= 5, f"too little travel: {offs}"
    assert abs(sum(offs)) <= 2, f"cycle should be balanced: {offs}"


if __name__ == "__main__":
    test_offset_moves_content()
    test_bottom_stays_covered_after_upward_shift()
    test_sine_offsets_form_a_cycle()
    print("ALL BOB_FRAMES TESTS PASS")
