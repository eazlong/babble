# tools/test_qa_asset.py
import subprocess, sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
TMP = ROOT / "tmp/asset-gen/_smoke/qa"

def _mk(name, size, mode, fringe=False):
    TMP.mkdir(parents=True, exist_ok=True)
    p = TMP / name
    im = Image.new(mode, size)
    if mode == "RGBA" and fringe:
        px = im.load()
        for x in range(size[0]):
            px[x, 0] = (0, 0, 0, 128)  # 黑边行
    im.save(p)
    return p

def run(*args):
    return subprocess.run([sys.executable, str(ROOT / "tools/qa_asset.py"), *map(str, args)],
                          capture_output=True, text=True)

def test_ok_rgba_exact():
    p = _mk("ok.png", (256, 256), "RGBA")
    r = run(p, "--size", "256x256", "--mode", "RGBA")
    assert r.returncode == 0 and "PASS" in r.stdout, r.stdout + r.stderr

def test_wrong_size_fails():
    p = _mk("bad.png", (256, 256), "RGBA")
    r = run(p, "--size", "512x512", "--mode", "RGBA")
    assert r.returncode != 0 and "FAIL" in r.stdout

def test_fringe_fails():
    p = _mk("fringe.png", (256, 256), "RGBA", fringe=True)
    r = run(p, "--size", "256x256", "--mode", "RGBA", "--fringe")
    assert r.returncode != 0 and "fringe" in r.stdout.lower()

def _mk_edge(name, fill, edge, size=(64, 64)):
    """Opaque block of `fill` with a semi-transparent ring of `edge` colour."""
    TMP.mkdir(parents=True, exist_ok=True)
    p = TMP / name
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    px = im.load()
    for y in range(10, size[1] - 10):
        for x in range(10, size[0] - 10):
            px[x, y] = (*fill, 255)
    for y in range(8, size[1] - 8):
        for x in range(8, size[0] - 8):
            if px[x, y][3] == 0:
                px[x, y] = (*edge, 128)   # one-pixel semi-transparent ring
    im.save(p)
    return p


def test_fringe_dark_line_art_passes():
    """Near-black edge pixels that MATCH dark opaque art are line art, not a halo."""
    p = _mk_edge("dark_art.png", fill=(12, 12, 12), edge=(12, 12, 12))
    r = run(p, "--size", "64x64", "--mode", "RGBA", "--fringe")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "fringe" in r.stdout.lower(), r.stdout


def test_fringe_real_halo_fails():
    """Semi-transparent BLACK around LIGHT art is the classic matting halo -> must fail."""
    p = _mk_edge("halo.png", fill=(210, 200, 190), edge=(0, 0, 0))
    r = run(p, "--size", "64x64", "--mode", "RGBA", "--fringe")
    assert r.returncode != 0 and "fringe" in r.stdout.lower(), r.stdout
