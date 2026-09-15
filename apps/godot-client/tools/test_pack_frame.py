# tools/test_pack_frame.py
"""TDD checks for tools/pack_frame.py.

Regression this guards: `canvas.paste(content, pos, content)` used the frame as its
own mask, which alpha-blended the semi-transparent edge against the transparent
black canvas and darkened edge RGB below 32 -> qa_asset.py --fringe FAIL (16%+).
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from pack_frame import pack_frame  # noqa: E402


def _decontaminated_frame(w: int = 200, h: int = 120) -> Image.Image:
    """Wide frame: opaque subject + soft top edge already carrying subject colour."""
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = im.load()
    for y in range(h):
        for x in range(w):
            alpha = 255 if y > 12 else int(255 * y / 12)
            px[x, y] = (222, 168, 140, alpha)  # subject colour, never black
    return im


def test_no_darkening_and_no_fringe() -> None:
    src = _decontaminated_frame()
    out = pack_frame(src, size=256, margin=4)
    a = np.array(out.getchannel("A"))
    rgb = np.array(out.convert("RGB")).astype(np.int16)
    semi = (a > 0) & (a < 255)
    assert semi.sum() > 0, "fixture must keep a soft edge"
    dark = semi & (rgb[..., 0] < 32) & (rgb[..., 1] < 32) & (rgb[..., 2] < 32)
    assert dark.sum() == 0, f"{dark.sum()} darkened semi-transparent pixels"


def test_aspect_preserved_and_bottom_anchored() -> None:
    src = _decontaminated_frame(200, 120)
    # pack_frame measures the SOLID box (alpha >= bbox_thresh), so derive the
    # expected aspect from the same measure instead of the raw canvas size.
    solid = src.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
    assert solid is not None
    sw, sh = solid[2] - solid[0], solid[3] - solid[1]
    out = pack_frame(src, size=256, margin=4)
    assert out.size == (256, 256) and out.mode == "RGBA"
    bbox = out.getchannel("A").getbbox()
    assert bbox is not None
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    assert abs(bw / bh - sw / sh) < 0.03, f"aspect distorted: {bw}x{bh} vs {sw}x{sh}"
    assert 256 - y1 == 4, f"bottom margin should be 4, got {256 - y1}"
    assert abs((x0 + x1) / 2 - 128) <= 1, "must be horizontally centred"


def test_bg_transparent_and_square() -> None:
    out = pack_frame(_decontaminated_frame(), size=128, margin=4)
    a = np.array(out.getchannel("A"))
    assert a[0, 0] == 0, "canvas corner must stay transparent"
    assert a.shape == (128, 128)


def test_fit_width_normalises_span_and_top_anchors() -> None:
    """Frames from panels with different forearm lengths must share one hand span."""
    tall = Image.new("RGBA", (100, 400), (222, 168, 140, 255))  # long forearm exposed
    wide = Image.new("RGBA", (200, 200), (222, 168, 140, 255))
    out_tall = pack_frame(tall, size=256, margin=8, anchor="top", fit_width=200)
    out_wide = pack_frame(wide, size=256, margin=8, anchor="top", fit_width=200)
    bt = out_tall.getchannel("A").getbbox()
    bw = out_wide.getchannel("A").getbbox()
    assert bt is not None and bw is not None
    assert bt[2] - bt[0] == 200 == bw[2] - bw[0], f"span mismatch: {bt} vs {bw}"
    assert bt[1] == 8 and bw[1] == 8, "fingertips must sit at the top margin"
    assert bt[3] == 256, "over-long forearm must be clipped by the canvas bottom"


def test_extend_bottom_removes_sawn_off_cut() -> None:
    """A frame whose content stops short of the bottom must reach the canvas edge."""
    short = Image.new("RGBA", (200, 150), (222, 168, 140, 255))
    plain = pack_frame(short, size=256, margin=8, anchor="top", fit_width=200)
    ext = pack_frame(short, size=256, margin=8, anchor="top", fit_width=200,
                     extend_bottom=True)
    bp = plain.getchannel("A").getbbox()
    be = ext.getchannel("A").getbbox()
    assert bp is not None and be is not None
    assert bp[3] == 158, f"fixture should stop short of the edge, got {bp}"
    assert be[3] == 256, f"extension must reach the canvas bottom, got {be}"
    assert np.array(ext)[255, 128, 3] == 255, "extension must be opaque arm colour"
    assert np.array(ext)[255, 128, 0] == 222, "extension must copy the arm colour"


def test_faint_stragglers_do_not_inflate_content_box() -> None:
    """A faint matting straggler far from the subject must not shrink the subject."""
    im = Image.new("RGBA", (400, 400), (0, 0, 0, 0))
    im.paste(Image.new("RGBA", (200, 100), (222, 168, 140, 255)), (100, 250))
    im.putpixel((5, 5), (222, 168, 140, 30))  # stray faint pixel near the corner
    out = pack_frame(im, size=256, margin=8, anchor="top", fit_width=200)
    bb = out.getchannel("A").getbbox()
    assert bb is not None
    assert bb[2] - bb[0] == 200, f"subject span must come from the solid block: {bb}"
    assert bb[3] - bb[1] == 100, f"subject height must come from the solid block: {bb}"


if __name__ == "__main__":
    test_no_darkening_and_no_fringe()
    test_aspect_preserved_and_bottom_anchored()
    test_bg_transparent_and_square()
    test_fit_width_normalises_span_and_top_anchors()
    test_extend_bottom_removes_sawn_off_cut()
    test_faint_stragglers_do_not_inflate_content_box()
    print("ALL PACK_FRAME TESTS PASS")
