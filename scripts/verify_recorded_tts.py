#!/usr/bin/env python3
"""校验客户端查表键是否都能命中录音。

复刻客户端 HybridAPI._recorded_tts_key 的算法（md5("voice|lang|text")[:16]），
对两部分文本逐条检查 <voice>_<lang>_<key>.wav 是否存在：
  1. dialogue_flows/*.json 里每条 flow 的台词（占位符按录制脚本的取值解析）；
  2. 场景控制 `_loc()` 表里的**运行时**台词（提议英语名、教练提示…）。

用法：
    .venv/bin/python scripts/verify_recorded_tts.py
"""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_ROOT = REPO_ROOT / "apps" / "godot-client"
FLOW_DIR = CLIENT_ROOT / "assets" / "resources" / "dialogue_flows"
TTS_DIR = CLIENT_ROOT / "assets" / "test_audio" / "tts"

PLACEHOLDER_VALUES = {
    "player_source_name": "卡卡",
    "player_display_name": "Carl",
    "special_language_name": "英语",
    "source_language_name": "中文",
}

#: 客户端会把这两类语言传给 TTS：序章/客栈用 zh，英语名等目标语言句子用 en。
LANGUAGES = ("zh", "en")

LOC_PATTERN = re.compile(
    r'"([a-z0-9_]+)"\s*:\s*\{\s*"zh"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"en"\s*:\s*"((?:[^"\\]|\\.)*)"\s*\}'
)


def key(voice: str, language: str, text: str) -> str:
    return hashlib.md5(f"{voice}|{language}|{text}".encode("utf-8")).hexdigest()[:16]


def resolve(text: str) -> str:
    for name, value in PLACEHOLDER_VALUES.items():
        text = text.replace("{%s}" % name, value)
    return text


def main() -> int:
    if not TTS_DIR.is_dir():
        print(f"录音目录不存在：{TTS_DIR}", file=sys.stderr)
        return 2

    on_disk = {path.name for path in TTS_DIR.glob("*.wav")}
    print(f"录音文件：{len(on_disk)}")

    missing: list[str] = []
    checked = 0
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
                    text = resolve(str(raw).strip())
                    checked += 1
                    name = f"{voice}_{language}_{key(voice, language, text)}.wav"
                    if name not in on_disk:
                        missing.append(
                            f"{path.name} {flow.get('flow_id')}/{line.get('key')} "
                            f"[{voice}/{language}] {name}"
                        )

    # 运行时台词（_loc 表）：提议英语名等由客户端拼值，漏录会卡在实时 TTS 上。
    runtime_checked = 0
    for path in sorted((CLIENT_ROOT / "assets" / "scripts").rglob("*.gd")):
        for loc_key, zh_raw, en_raw in LOC_PATTERN.findall(path.read_text(encoding="utf-8")):
            for language, raw in (("zh", zh_raw), ("en", en_raw)):
                text = raw.replace('\\"', '"').replace("\\n", " ").strip()
                if not text:
                    continue
                if "%s" in text:
                    value = "Carl" if loc_key.startswith("special_name_proposal") else "英语"
                    text = text % value
                if "%d" in text:
                    text = text % 3
                runtime_checked += 1
                name = f"spirit_{language}_{key('spirit', language, text)}.wav"
                if name not in on_disk:
                    missing.append(
                        f"{path.name} _loc(\"{loc_key}\") [spirit/{language}] {text[:32]!r} {name}"
                    )

    print(f"已检查台词：flow {checked} 条 + 运行时 {runtime_checked} 条")
    if missing:
        print(f"未命中 {len(missing)} 条（这些台词运行时会回退实时 TTS）：")
        for item in missing[:40]:
            print("  -", item)
        return 1
    print("全部命中 ✅")
    return 0

if __name__ == "__main__":
    sys.exit(main())
