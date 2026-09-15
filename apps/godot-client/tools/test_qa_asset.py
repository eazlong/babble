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
