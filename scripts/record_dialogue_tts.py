#!/usr/bin/env python3
"""按对话流程批量录制 TTS：把游戏会念的每一句台词预生成为 wav，供客户端在
"录制回放模式"下按文本查表播放（不再实时打 TTS 接口）。

用法：
    # 先看清单与估算（不发请求）
    .venv/bin/python scripts/record_dialogue_tts.py --dry-run

    # 实际录制到 Godot 客户端资源目录
    .venv/bin/python scripts/record_dialogue_tts.py --jobs 4

产物：
    apps/godot-client/assets/test_audio/tts/<voice>_<md5[:16]>.wav
    apps/godot-client/assets/test_audio/tts/manifest.json

键 = (voice, language, text)：客户端 HybridAPI._recorded_tts_stream() 用同一算法定位文件。
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import sys
import time
import urllib.error
import urllib.request
import wave
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_ROOT = REPO_ROOT / "apps" / "godot-client"
FLOW_DIR = CLIENT_ROOT / "assets" / "resources" / "dialogue_flows"
OUT_DIR = CLIENT_ROOT / "assets" / "test_audio" / "tts"
TTS_URL = "http://localhost:8301/tts/synthesize"

#: 主角身份。占位符按这套值解析并录制（客户端在回放模式下也会用同一套值）。
PLAYER_SOURCE_NAME = "卡卡"
PLAYER_DISPLAY_NAME = "Carl"
SPECIAL_LANGUAGE_NAME = "英语"
SOURCE_LANGUAGE_NAME = "中文"
PLACEHOLDER_VALUES = {
    "player_source_name": PLAYER_SOURCE_NAME,
    "player_display_name": PLAYER_DISPLAY_NAME,
    "special_language_name": SPECIAL_LANGUAGE_NAME,
    "source_language_name": SOURCE_LANGUAGE_NAME,
}

#: TTS 侧没有真实音色的 voice_id（实测返回静音占位 wav），录制时回落到有效音色。
VOICE_FALLBACK = {
    "elder": "spirit",
    "young_female": "spirit",
    "young_male": "young_male",
}

#: 序章英语名的本地值池（与 BeginningFPController.SPECIAL_NAME_POOL 保持一致）。
SPECIAL_NAME_POOL = ("Carl", "Wendy", "Leo", "Mia", "Luna")

LANGUAGES = ("zh", "en")


def record_key(voice: str, language: str, text: str) -> str:
    payload = f"{voice}|{language}|{text}".encode("utf-8")
    return hashlib.md5(payload).hexdigest()[:16]


def file_name(voice: str, language: str, text: str) -> str:
    return f"{voice}_{language}_{record_key(voice, language, text)}.wav"


def find_placeholders(text: str) -> set[str]:
    import re

    return set(re.findall(r"\{([A-Za-z_][A-Za-z0-9_]*)\}", text))


def resolve(text: str, values: dict[str, str]) -> str:
    for name, value in values.items():
        text = text.replace("{%s}" % name, value)
    return text


def collect_runtime_lines() -> list[tuple[str, str, str]]:
    """收集对话 flow 之外的**运行时**台词。

    这部分文本不走 dialogue_flows，而是散在场景控制的 `_loc()` 表里
    （如 `special_name_proposal` = '那就叫%s，你觉得怎么样？'）。漏了它们，
    玩家一旦触发（提议英语名、教练干预…）就会回退实时 TTS，录制就没意义了。
    做法是扫描控制器源码里的 `"key": {"zh": "...", "en": "..."}` 条目 + `%s` 参数表，
    宁可多录几条 HUD 文案，也不要漏掉一句台词。
    """
    import re

    entries: dict[str, tuple[str, str, str]] = {}
    loc_pattern = re.compile(
        r'"([a-z0-9_]+)"\s*:\s*\{\s*"zh"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"en"\s*:\s*"((?:[^"\\]|\\.)*)"\s*\}'
    )
    for path in sorted((CLIENT_ROOT / "assets" / "scripts").rglob("*.gd")):
        source = path.read_text(encoding="utf-8")
        for key, zh_raw, en_raw in loc_pattern.findall(source):
            for language, raw in (("zh", zh_raw), ("en", en_raw)):
                text = raw.replace('\\"', '"').replace("\\n", " ").strip()
                if not text:
                    continue
                # 带参数的模板解析成具体值（录制的是玩家真正会听到的那一句）。
                if "%s" in text:
                    value = (
                        PLACEHOLDER_VALUES["player_display_name"]
                        if key.startswith(("special_name_proposal", "name_celebrate"))
                        else PLACEHOLDER_VALUES["special_language_name"]
                    )
                    text = text % value
                if "%d" in text:
                    text = text % 3
                for voice in ("spirit", "elder"):
                    entries[record_key(voice, language, text)] = (voice, language, text)

    # 提议英语名是序章唯一"运行时拼值"的台词（player_display_name 由本地值池挑出），
    # 池里 5 个候选都要有录音，否则玩家说「帮我起一个吧」时会卡在实时 TTS 上。
    template_map = {
        "special_name_proposal": "那就叫%s，你觉得怎么样？",
        "special_name_proposal_en": "How about %s? Do you like it?",
    }
    for candidate in SPECIAL_NAME_POOL:
        entries[record_key("spirit", "zh", template_map["special_name_proposal"] % candidate)] = (
            "spirit",
            "zh",
            template_map["special_name_proposal"] % candidate,
        )
        entries[record_key("spirit", "en", template_map["special_name_proposal_en"] % candidate)] = (
            "spirit",
            "en",
            template_map["special_name_proposal_en"] % candidate,
        )
    return list(entries.values())


def collect_lines() -> list[tuple[str, str, str]]:
    """返回去重后的 (voice, language, text) 列表。"""
    entries: dict[str, tuple[str, str, str]] = {}
    if not FLOW_DIR.is_dir():
        raise SystemExit(f"dialogue flow dir not found: {FLOW_DIR}")

    for path in sorted(FLOW_DIR.glob("*.json")):
        root = json.loads(path.read_text(encoding="utf-8"))
        for flow in root.get("flows", []):
            flow_voice = str(flow.get("voice", "spirit"))
            for line in flow.get("lines", []):
                voice = str(line.get("voice", flow_voice))
                text_map = line.get("text", {})
                for language in LANGUAGES:
                    raw = text_map.get(language)
                    if not raw:
                        continue
                    raw = str(raw).strip()
                    if not raw:
                        continue
                    templates = [resolve(raw, PLACEHOLDER_VALUES)]
                    if find_placeholders(raw):
                        # 占位符本身也留一份：万一某处没带参数，客户端不会静音。
                        templates.append(raw)
                    for text in templates:
                        entries[record_key(voice, language, text)] = (voice, language, text)
    for entry in collect_runtime_lines():
        entries[record_key(*entry)] = entry
    return list(entries.values())


def to_wav(raw: bytes, fmt: str) -> bytes:
    """把 provider 返回的音频统一成 16-bit PCM WAV。

    voice-service 正常情况下给 wav；偶发会走 ElevenLabs 回退给 mp3
    （实测：provider 侧对同一段文本的输出格式并不稳定）。录音文件
    必须统一格式，客户端 `AudioManager.create_wav_stream_from_bytes` 只解 wav。
    """
    if fmt == "wav" and raw[:4] == b"RIFF":
        return raw
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "in.bin"
        dst = Path(tmp) / "out.wav"
        src.write_bytes(raw)
        result = subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-ac", "1", "-ar", "16000", str(dst)],
            capture_output=True,
        )
        if result.returncode != 0 or not dst.is_file():
            raise RuntimeError("ffmpeg transcode failed: %s" % result.stderr.decode()[:200])
        return dst.read_bytes()


def synth(voice: str, language: str, text: str, retries: int = 3) -> bytes:
    mapped = VOICE_FALLBACK.get(voice, voice)
    body = json.dumps({"text": text, "voice_id": mapped, "language": language}).encode("utf-8")
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            request = urllib.request.Request(
                TTS_URL, data=body, headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(request, timeout=120) as response:
                payload = json.loads(response.read().decode("utf-8"))
            raw = base64.b64decode(payload.get("audio_data") or "")
            if not raw:
                raise RuntimeError("empty audio_data")
            raw = to_wav(raw, str(payload.get("format") or ""))
            with wave.open(io.BytesIO(raw)) as handle:
                frames = np.frombuffer(
                    handle.readframes(handle.getnframes()), dtype=np.int16
                ).astype(np.float32) / 32768.0
            rms = float(np.sqrt((frames ** 2).mean())) if frames.size else 0.0
            if rms < 0.01:
                raise RuntimeError("silent audio (rms=%.5f)" % rms)
            return raw
        except Exception as exc:  # noqa: BLE001 - 网络/内容问题都要重试
            last_error = exc
            time.sleep(1.0 + attempt)
    raise RuntimeError(f"synth failed for {voice}/{language}/{text[:24]!r}: {last_error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="只打印清单，不发请求")
    parser.add_argument("--jobs", type=int, default=4, help="并发请求数")
    parser.add_argument("--limit", type=int, default=0, help="只录前 N 条（调试用）")
    parser.add_argument(
        "--force",
        action="store_true",
        help="覆盖已存在的录音（默认增量：只补缺失的，改文案后只重录那几条）",
    )
    args = parser.parse_args()

    lines = collect_lines()
    if not args.force:
        lines = [
            entry
            for entry in lines
            if not (OUT_DIR / file_name(*entry)).is_file()
        ]
    if args.limit:
        lines = lines[: args.limit]

    by_voice: dict[str, int] = {}
    for voice, _language, _text in lines:
        by_voice[voice] = by_voice.get(voice, 0) + 1

    print(f"待录制台词：{len(lines)} 条")
    for voice, count in sorted(by_voice.items()):
        mapped = VOICE_FALLBACK.get(voice)
        note = f" -> {mapped}" if mapped else ""
        print(f"  voice={voice:14s} {count:4d}{note}")

    if args.dry_run:
        total_chars = sum(len(text) for _v, _l, text in lines)
        print(f"总字数：{total_chars}（粗略估算 ≈ {total_chars / 4.5:.0f}s 音频）")
        print("示例：")
        for voice, language, text in lines[:5]:
            print(f"  [{voice}/{language}] {text[:60]}")
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT_DIR / "manifest.json"
    manifest: dict[str, dict[str, str]] = {}
    # 增量录制时合并已有清单，避免 manifest 只剩最后一次跑的那几条。
    if manifest_path.is_file():
        try:
            manifest = dict(json.loads(manifest_path.read_text(encoding="utf-8")).get("entries", {}))
        except Exception:  # noqa: BLE001 - 清单损坏不该挡住录制
            manifest = {}
    failures: list[str] = []
    started = time.time()

    def worker(entry: tuple[str, str, str]) -> tuple[tuple[str, str, str], bytes]:
        voice, language, text = entry
        return entry, synth(voice, language, text)

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(worker, entry): entry for entry in lines}
        done = 0
        for future in as_completed(futures):
            voice, language, text = futures[future]
            done += 1
            try:
                _entry, raw = future.result()
            except Exception as exc:  # noqa: BLE001
                failures.append(f"{voice}/{language}/{text[:32]!r}: {exc}")
                print(f"[{done}/{len(lines)}] FAIL {voice}/{language} {text[:32]!r}")
                continue
            name = file_name(voice, language, text)
            (OUT_DIR / name).write_bytes(raw)
            manifest[record_key(voice, language, text)] = {
                "voice": voice,
                "language": language,
                "text": text,
                "file": name,
            }
            if done % 20 == 0 or done == len(lines):
                print(f"[{done}/{len(lines)}] ok ({time.time() - started:.0f}s)")

    # 未命中的条目（未录制/失败）不写进清单，保证清单 = 磁盘上真实存在的录音。
    rebuilt: dict[str, dict[str, str]] = {}
    for entry in collect_lines():
        voice, language, text = entry
        name = file_name(*entry)
        if not (OUT_DIR / name).is_file():
            continue
        key = record_key(voice, language, text)
        rebuilt[key] = manifest.get(
            key, {"voice": voice, "language": language, "text": text, "file": name}
        )
    manifest = rebuilt

    manifest_path.write_text(
        json.dumps(
            {
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "tts_url": TTS_URL,
                "voice_fallback": VOICE_FALLBACK,
                "placeholder_values": PLACEHOLDER_VALUES,
                "entries": manifest,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"完成：{len(manifest)} 条写入 {OUT_DIR}，耗时 {time.time() - started:.0f}s")
    if failures:
        print(f"失败 {len(failures)} 条：")
        for item in failures[:20]:
            print("  -", item)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
