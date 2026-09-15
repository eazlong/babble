# tools/test_synth_sfx.py
import subprocess, sys
from pathlib import Path
from wave import open as wav_open

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tmp/asset-gen/b1/sfx"

def synth(name):
    OUT.mkdir(parents=True, exist_ok=True)
    r = subprocess.run([sys.executable, str(ROOT / "tools/synth_sfx.py"), name,
                        "-o", str(OUT / (name + ".wav"))], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    with wav_open(str(OUT / (name + ".wav"))) as w:
        return w.getnframes() / w.getframerate()

def test_durations_in_spec():
    specs = {  # name: (min_s, max_s)  来自 master §7
        "magic_sparkle": (1, 3), "badge_unlock": (5, 8),
        "bookshelf_awake": (1, 2), "library_enter": (2, 4),
        "word_spirit_clear": (1, 2), "guest_distant_hello": (1, 3),
        "changan_mist_surge": (3, 5), "ui_spirit_stone_listen": (0.5, 1),
        "ui_spirit_stone_success": (1, 1.5), "ui_spirit_stone_hint": (0.5, 1),
        "celebration": (2, 3), "area_unlock": (2, 3), "changan_bell_ring": (2, 4),
    }
    for name, (lo, hi) in specs.items():
        d = synth(name)
        assert lo - 0.05 <= d <= hi + 0.05, f"{name}: {d:.2f}s outside [{lo},{hi}]"
