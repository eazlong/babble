#!/usr/bin/env python3
"""把玩家答案录音写回各课的 scene_config。

`scripts/record_player_answers.py` 产出 `assets/test_audio/<pa_*.wav>` 与
`player_answers.json`；本脚本按 **步骤顺序** 把对应文件名写进
`assets/resources/scene_configs/<lesson>.json` 的 `test_asr_audio_names`，
课堂控制器在 test 模式下直接读它（见 ChangAnMarketController._configure_test_asr_audio）。

这样"录了什么"与"课里按什么顺序放"只有一个来源，避免再出现硬编码单文件导致卡课。

用法：
    .venv/bin/python scripts/sync_player_answers_to_configs.py --dry-run
    .venv/bin/python scripts/sync_player_answers_to_configs.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_ROOT = REPO_ROOT / "apps" / "godot-client"
ANSWERS_PATH = CLIENT_ROOT / "assets" / "test_audio" / "player_answers.json"
CONFIG_DIR = CLIENT_ROOT / "assets" / "resources" / "scene_configs"

#: 场景 id → (scene_config 文件名, 该课要用的答案 id 前缀)
LESSONS: dict[str, tuple[str, str]] = {
    "ChangAnMarket": ("chang_an_market_lesson_01.json", "lesson01_"),
    "ChangAnMarketLesson02": ("chang_an_market_lesson_02.json", "lesson02_"),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not ANSWERS_PATH.is_file():
        print(f"缺少 {ANSWERS_PATH}，先跑 scripts/record_player_answers.py", file=sys.stderr)
        return 2
    manifest = json.loads(ANSWERS_PATH.read_text(encoding="utf-8"))
    answers = manifest["answers"]

    changed = 0
    for scene_id, (config_name, prefix) in LESSONS.items():
        config_path = CONFIG_DIR / config_name
        config = json.loads(config_path.read_text(encoding="utf-8"))
        steps = [step["id"] for step in config.get("steps", []) if step.get("type") == "voice"]

        # 答案按 id 前缀归属本课，顺序必须与该课的 voice 步骤一致。
        lesson_answers = [a for a in answers if a["id"].startswith(prefix)]
        by_step = {a["step"]: a["file"] for a in lesson_answers}
        names = [by_step[step] for step in steps if step in by_step]
        missing_steps = [step for step in steps if step not in by_step]

        print(f"{scene_id} ({config_name})")
        for step in steps:
            mark = by_step.get(step, "—MISSING—")
            print(f"  {step:24s} -> {mark}")
        if missing_steps:
            print(f"  ⚠ 缺答案的步骤：{missing_steps}")

        if config.get("test_asr_audio_names") == names:
            print("  未变化")
            continue
        config["test_asr_audio_names"] = names
        config.setdefault("test_asr_audio_dir", "res://assets/test_audio/")
        if args.dry_run:
            print(f"  [dry-run] 将写入 {len(names)} 条")
        else:
            config_path.write_text(
                json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            print(f"  已写入 {len(names)} 条")
        changed += 1

    # 未归属任何课的答案（序章/客栈）仍由 project.godot 的全局顺序驱动。
    other = [
        a["file"]
        for a in answers
        if not any(a["id"].startswith(prefix) for _s, (_c, prefix) in LESSONS.items())
    ]
    print("不归属课程、仍走 project.godot 全局顺序的：")
    for name in other:
        print("  -", name)

    if not args.dry_run and changed:
        print(f"\n改动了 {changed} 个 config")
    return 0


if __name__ == "__main__":
    sys.exit(main())
