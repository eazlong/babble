# tools/synth_sfx.py
"""Synthesize LinguaQuest SFX with the Python stdlib (no numpy).
Usage: synth_sfx.py <name> -o out.wav
Durations follow design/art/asset-requirements-master.md §7.
"""
import argparse
import math
import random
import struct
import wave

SR = 44100

def tone(freq, dur, vol=0.5, decay=4.0, harmonics=(), sr=SR):
    n = int(dur * sr)
    out = []
    for i in range(n):
        t = i / sr
        env = vol * math.exp(-decay * t) * min(1.0, t * 200.0)  # fast attack
        s = math.sin(2 * math.pi * freq * t)
        for h, hv in harmonics:
            s += hv * math.sin(2 * math.pi * freq * h * t)
        out.append(int(max(-1.0, min(1.0, env * s)) * 32767))
    return out

def noise(dur, vol=0.3, lp=0.1, sr=SR):
    n = int(dur * sr)
    out, prev = [], 0.0
    rnd = random.Random(42)
    for i in range(n):
        t = i / n
        env = vol * math.sin(math.pi * t)  # swell in/out
        x = rnd.uniform(-1.0, 1.0)
        prev = lp * x + (1 - lp) * prev
        out.append(int(max(-1.0, min(1.0, env * prev * 3.0)) * 32767))
    return out

def bell(freq=196.0, dur=3.5, strikes=1, strike_gap=0.8, sr=SR):
    """Temple bell: inharmonic partials."""
    partials = [(1.0, 1.0), (2.01, 0.5), (2.94, 0.35), (4.16, 0.2), (5.43, 0.12)]
    n = int(dur * sr)
    out = [0.0] * n
    for s in range(strikes):
        off = int(s * strike_gap * sr)
        for i in range(min(n - off, int(2.5 * sr))):
            t = i / sr
            env = 0.6 * math.exp(-1.2 * t)
            v = sum(hv * math.sin(2 * math.pi * freq * h * t) for h, hv in partials)
            out[off + i] += env * v
    return [int(max(-1.0, min(1.0, v)) * 32767) for v in out]

def _add(base, seg, start):
    needed = start + len(seg)
    if needed > len(base):
        base.extend([0] * (needed - len(base)))
    for i, v in enumerate(seg):
        base[start + i] = int(max(-32767, min(32767, base[start + i] + v)))
    return base

def _ambience(dur_s, seed, pad_mix=0.5):
    """Seamless ambient: integer-period sine breathing + filtered noise bed + pad."""
    n = int(dur_s * SR)
    out = []
    rnd = random.Random(seed)
    prev = 0.0
    for i in range(n):
        t = i / SR
        ph = math.sin(2 * math.pi * (2 * SR) / n * i)      # whole periods -> seamless loop
        prev = 0.02 * rnd.uniform(-1, 1) + 0.98 * prev
        base = 0.10 * prev * 3.0
        pad = 0.05 * math.sin(2 * math.pi * 110 * t) * (0.5 + 0.5 * ph) * (2.0 - pad_mix)
        pad += 0.03 * math.sin(2 * math.pi * 164.81 * t) * (0.5 - 0.5 * ph) * (2.0 - pad_mix)
        out.append(int(max(-1.0, min(1.0, base + pad)) * 32767))
    return out

def build(name):
    if name == "magic_sparkle":
        s = noise(0.35, vol=0.25, lp=0.02)
        return _add(s, tone(2400, 1.2, vol=0.18, decay=5.0), 0)
    if name == "badge_unlock":  # 5s: 低涌起 + 五音上行琶音
        s = noise(5.0, vol=0.06, lp=0.05)
        for k, f in enumerate([392.0, 523.25, 659.25, 783.99, 1046.5]):
            s = _add(s, tone(f, 1.6, vol=0.25, decay=2.2), int((0.6 + k * 0.55) * SR))
        return s
    if name == "bookshelf_awake":  # 闷响 + 吱呀
        thud = tone(70, 0.4, vol=0.7, decay=8.0)
        return _add(thud, tone(180, 1.0, vol=0.15, decay=1.5, harmonics=((2.7, 0.4),)), len(thud) - int(0.4 * SR))
    if name == "library_enter":
        s = noise(3.0, vol=0.15, lp=0.08)
        return _add(s, tone(261.6, 3.0, vol=0.12, decay=0.4), 0)
    if name == "word_spirit_clear":  # 880 -> 1318 两音上行
        s = tone(880, 0.55, vol=0.3, decay=6.0)
        return _add(s, tone(1318.5, 0.8, vol=0.25, decay=4.0), int(0.15 * SR))
    if name == "guest_distant_hello":  # 低通闷铃
        return _add(noise(0.2, vol=0.1, lp=0.4), tone(660, 1.6, vol=0.12, decay=2.5), 0)
    if name == "changan_mist_surge":  # 噪声涌起 + 55Hz 低频
        s = noise(4.0, vol=0.35, lp=0.15)
        return _add(s, tone(55, 4.0, vol=0.2, decay=0.3), 0)
    if name == "ui_spirit_stone_listen":
        return tone(660, 0.6, vol=0.3, decay=3.0)
    if name == "ui_spirit_stone_success":  # 1.0s 两音
        a = tone(784, 0.3, vol=0.3, decay=5.0)
        return _add(a, tone(1174.7, 0.7, vol=0.28, decay=4.0), len(a))
    if name == "ui_spirit_stone_hint":
        return tone(523.25, 0.55, vol=0.25, decay=4.0)
    if name == "celebration":  # 五音快速琶音
        s = [0] * int(2.4 * SR)
        for k, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.5]):
            s = _add(s, tone(f, 1.5, vol=0.25, decay=3.0), int(k * 0.2 * SR))
        return s
    if name == "area_unlock":  # 低频涌起 + 收尾钟音
        s = tone(98, 2.0, vol=0.4, decay=1.2)
        return _add(s, tone(880, 1.2, vol=0.2, decay=3.0), int(1.6 * SR))
    if name == "changan_bell_ring":  # 东华钟：一记浑厚长鸣（八响 = 游戏内连播 1-8 次，见 T35）
        return bell(freq=174.6, dur=3.5, strikes=1)
    if name == "ambience":  # 90s 无缝环境床
        return _ambience(90, 7)
    if name == "inn_ambience":
        return _ambience(90, 9)
    if name == "formation_room_hum":  # 45s 无缝（1 个整周期呼吸）
        n = int(45 * SR)
        out = []
        rnd = random.Random(11)
        prev = 0.0
        for i in range(n):
            t = i / SR
            ph = math.sin(2 * math.pi * (1 * SR) / n * i)      # 1 whole period over 45s
            prev = 0.02 * rnd.uniform(-1, 1) + 0.98 * prev
            base = 0.10 * prev * 3.0
            pad = 0.06 * math.sin(2 * math.pi * 55 * t) * (0.5 + 0.5 * ph)
            pad += 0.04 * math.sin(2 * math.pi * 82.41 * t) * (0.5 - 0.5 * ph)
            out.append(int(max(-1.0, min(1.0, base + pad)) * 32767))
        return out
    if name == "market_ambience":  # ambience + 0.5Hz 幅值摆动模拟人群嗡嗡（无语言）
        base = build("ambience")
        return [int(v * (0.75 + 0.25 * math.sin(2 * math.pi * 0.5 * i / SR))) for i, v in enumerate(base)]
    raise SystemExit(f"unknown sfx: {name}")

def write_wav(path, samples, sr=SR):
    with wave.open(str(path), "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % len(samples), *samples))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("-o", required=True)
    a = ap.parse_args()
    write_wav(a.o, build(a.name))
    print(f"OK {a.name} -> {a.o}")

if __name__ == "__main__":
    main()
