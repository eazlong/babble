#!/usr/bin/env python3
"""录制"玩家的发音"：给 test 模式的流程测试准备每一轮该说的话。

为什么要单独录一套：
  - `assets/test_audio/tts/` 录的是**NPC 台词**（腓腓/执事/掌柜）；
  - 这里录的是**玩家台词**，VoicePipeline 在 test 模式下把它们当作麦克风输入，
    经真实 whisper + voice-service postprocess 再进课堂判定，用来端到端跑通
    「序章 → 蜃影客栈 → 长安西市 Lesson01/02」。

顺序即轮换顺序：VoicePipeline 按 `hybrid_api/asr_test_audio_names` 里给定的顺序
一轮取一个文件，所以本文件里的 ANSWERS 顺序必须与游戏实际的提问顺序一致。

用法：
    .venv/bin/python scripts/record_player_answers.py --dry-run     # 只看清单
    .venv/bin/python scripts/record_player_answers.py               # 合成 + 校验
    .venv/bin/python scripts/record_player_answers.py --synth-only  # 只合成，不跑 ASR 校验

产物：
    apps/godot-client/assets/test_audio/pa_<NN>_<slug>.wav
    apps/godot-client/assets/test_audio/player_answers.json（台词/期望判定/ASR 实测）
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.request
import wave
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
CLIENT_ROOT = REPO_ROOT / "apps" / "godot-client"
OUT_DIR = CLIENT_ROOT / "assets" / "test_audio"
MANIFEST = OUT_DIR / "player_answers.json"
API_BASE = "http://localhost:8301"

#: macOS `say` 音色：中文用 Tingting，英文用 Junior（童声，和玩家小孩身份相称）。
VOICE_ZH = "Tingting"
VOICE_EN = "Junior"

#: 玩家身份（与序章录音 scripts/record_dialogue_tts.py 的取值保持一致）。
PLAYER_SOURCE_NAME = "卡卡"
PLAYER_EN_NAME = "Leo"

#: 课堂判定档位（LessonResponseMatcher）。
TIER_CLEAR = "clear"
TIER_OK = "understandable"

#: 每轮：场景步骤 → 玩家该说的话 → 期望的判定结果。
#: `check` 说明这一轮由谁判定：
#:   lesson  —— LessonResponseMatcher.evaluate()，要求 clear/understandable
#:   prologue—— 序章 controller：provide 且 extracted.name 非空
#:   hub     —— 客栈 controller：命中出发/画卷候选
ANSWERS: list[dict] = [
    {
        "id": "prologue_source_name",
        "scene": "BeginningFP",
        "step": "AWAIT_SOURCE_NAME",
        "lang": "zh",
        "text": f"我的名字是{PLAYER_SOURCE_NAME}。",
        "check": "prologue",
        "note": "腓腓问「你叫什么名字」；中文名带 CJK，会顺势进入英语名那一步",
    },
    {
        "id": "prologue_special_name",
        "scene": "BeginningFP",
        "step": "AWAIT_SPECIAL_NAME",
        "lang": "en",
        "text": f"My name is {PLAYER_EN_NAME}.",
        "check": "prologue",
        "note": "腓腓问英语名；这里自己报名字（不委托），一步落定",
    },
    {
        "id": "intro_scroll_call",
        "scene": "MirageInnIntroduction",
        "step": "AWAIT_SCROLL_CALL",
        "lang": "zh",
        "text": "画中小世界，请回答。",
        "check": "marker",
        "markers": ["画中小世界", "little world", "painting"],
        "note": (
            "客栈导览第一步：对墙上画卷说口令。**不要只录孤立的口令**——实测 whisper 把单独的"
            "口令稳定误听（「书架」就被听成「输家」），只能靠 postprocess 纠回来；而一旦前面失败过一轮，"
            "recent_turns 里多了一条错答案，模型就不再纠（案发现场：卡在这一步出不去）。"
            "口令补足成「画中小世界，请回答。」之后，whisper 转出的是完整句子，"
            "归一繁体即命中，首轮/重问都稳。"
        ),
    },
    {
        "id": "hub_depart",
        "scene": "MirageInnHub",
        "step": "HUB_AWAIT_CHOICE",
        "lang": "zh",
        "text": "出发！",
        "check": "marker",
        "markers": ["出发", "走吧", "启程", "继续", "lets go", "let's go", "next lesson"],
        "note": (
            "hub 入口是二选一（继续主线 / 去词灵阁小游戏），这盘录的是'出发'那一支；"
            "说出发才会切到长安西市。也是续行（resume）那一步用的口令"
        ),
    },
    {
        "id": "lesson01_name_register",
        "scene": "ChangAnMarket",
        "step": "name_register",
        "lang": "en",
        "text": f"My name is {PLAYER_EN_NAME}.",
        "check": "lesson",
        "note": "天机阁执事登记名字；clear_phrases 含 'my name is'",
    },
    {
        "id": "lesson01_where_live",
        "scene": "ChangAnMarket",
        "step": "ask_where_live",
        "lang": "en",
        "text": "I live in the city.",
        "check": "lesson",
        "note": "clear_phrases 'i live in'",
    },
    {
        "id": "lesson01_restore_city",
        "scene": "ChangAnMarket",
        "step": "restore_city",
        "lang": "en",
        "text": "It is a city.",
        "check": "lesson",
        "note": "目标词 city",
    },
    {
        "id": "lesson01_restore_street",
        "scene": "ChangAnMarket",
        "step": "restore_street",
        "lang": "en",
        "text": "It is a street.",
        "check": "lesson",
        "note": "目标词 street",
    },
    {
        "id": "lesson01_restore_building",
        "scene": "ChangAnMarket",
        "step": "restore_building",
        "lang": "en",
        "text": "It is a building.",
        "check": "lesson",
        "note": "目标词 building",
    },
    {
        "id": "lesson01_restore_house",
        "scene": "ChangAnMarket",
        "step": "restore_house",
        "lang": "en",
        "text": "It is a house.",
        "check": "lesson",
        "note": "目标词 house",
    },
    {
        "id": "lesson01_where_is_home",
        "scene": "ChangAnMarket",
        "step": "where_is_your_home",
        "lang": "en",
        "text": "My home is in the city.",
        "check": "lesson",
        "note": "clear_phrases 'my home is in'",
    },
    {
        "id": "lesson02_where_is_eagle",
        "scene": "ChangAnMarketLesson02",
        "step": "where_is_eagle",
        "lang": "en",
        "text": "Where's the eagle?",
        "check": "lesson",
        "note": "目标词 eagle；confused_keywords 是 owl/bees，不能带",
    },
    {
        "id": "lesson02_tell_eagle_home",
        "scene": "ChangAnMarketLesson02",
        "step": "tell_eagle_home",
        "lang": "en",
        "text": "It's in the nest.",
        "check": "lesson",
        "note": "目标词 nest",
    },
    {
        "id": "lesson02_where_is_owl",
        "scene": "ChangAnMarketLesson02",
        "step": "where_is_owl",
        "lang": "en",
        "text": "Where's the owl?",
        "check": "lesson",
        "note": "目标词 owl",
    },
    {
        "id": "lesson02_tell_owl_home",
        "scene": "ChangAnMarketLesson02",
        "step": "tell_owl_home",
        "lang": "en",
        "text": "It's in the wall.",
        "check": "lesson",
        "note": "目标词 wall",
    },
    {
        "id": "lesson02_where_are_bees",
        "scene": "ChangAnMarketLesson02",
        "step": "where_are_bees",
        "lang": "en",
        "text": "Where are the honeybees?",
        "check": "lesson",
        "note": "目标词 bees",
    },
    {
        "id": "lesson02_tell_bees_home",
        "scene": "ChangAnMarketLesson02",
        "step": "tell_bees_home",
        "lang": "en",
        "text": "They're in the flowers.",
        "check": "lesson",
        "note": "目标词 flower",
    },
    {
        "id": "lesson02_all_home",
        "scene": "ChangAnMarketLesson02",
        "step": "all_home",
        "lang": "en",
        "text": "They're all home.",
        "check": "lesson",
        "note": "目标词 home",
    },
    # ── 客栈 hub 二选一的**另一支** ────────────────────────────────────────
    # hub 是二选一：说「出发」（pa_04_hub_depart）走主线去长安西市；
    # 说「词灵阁」（本条）进归卷厅玩复习小游戏。两条都留着，靠
    # MirageInnIntroductionController.TEST_ASR_HUB_ANSWERS 选择 test 模式跑哪一支
    # —— 别再改 pa_04 的文案：主人房「续行」那一步只认 StoryContinueMarkers
    # （出发/走吧/继续…），把 pa_04 改成词灵阁会让续行直接卡死在主人房。
    #
    # 编号追加在末尾而不是插在 pa_04 后面：插队会让后面 14 条全部改名，而它们的
    # 文件名被 3 处 .gd 常量 + 2 份 scene_config JSON 按名引用，还有各自的 .import
    # 边车要重生成（跑项目不会导入新资源，见 scripts/godot-test.sh 的 NOTE）。
    # 轮换顺序只是个标签，per-scene 的 TEST_ASR_* 才是真正决定放哪条的。
    {
        "id": "hub_library",
        "scene": "MirageInnHub",
        "step": "HUB_AWAIT_CHOICE",
        "lang": "zh",
        "text": "我要去词灵阁玩小游戏。",
        "check": "marker",
        "markers": [
            "词灵阁", "书阁", "词灵书阁", "充能",
            "library", "archive", "word spirit",
        ],
        "note": (
            "hub 二选一的「去词灵阁玩」那一支，对应 LIBRARY_ENTRY_MARKERS。"
            "按 README 的教训**不要只录孤立口令**（单个「书架」被 whisper 稳定误听成「输家」），"
            "所以补足上下文录成完整句。"
        ),
    },
]


def slug(text: str) -> str:
    return text.replace("'", "_").replace(" ", "_").lower()


def file_name(index: int, answer: dict) -> str:
    return f"pa_{index:02d}_{answer['id']}.wav"


def say_to_wav(text: str, voice: str, destination: Path) -> None:
    """用 macOS `say` 合成，再统一成 16kHz 单声道 16-bit PCM WAV。"""
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "say.aiff"
        subprocess.run(
            ["say", "-v", voice, "-o", str(raw), text],
            check=True,
            capture_output=True,
        )
        subprocess.run(
            [
                "ffmpeg", "-y", "-loglevel", "error",
                "-i", str(raw), "-ac", "1", "-ar", "16000", "-acodec", "pcm_s16le",
                str(destination),
            ],
            check=True,
            capture_output=True,
        )


def audio_stats(path: Path) -> tuple[float, float]:
    with wave.open(str(path)) as handle:
        frames = np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16)
        duration = handle.getnframes() / handle.getframerate()
    if frames.size == 0:
        return duration, 0.0
    rms = float(np.sqrt((frames.astype(np.float32) ** 2).mean()) / 32768.0)
    return duration, rms


def asr_roundtrip(path: Path, language: str, context: dict) -> dict:
    """把录好的音频按客户端的方式送给 voice-service，拿回 postprocess 结果。"""
    payload = {
        "audio_data": base64.b64encode(path.read_bytes()).decode("ascii"),
        "lang": language,
        "context": context,
    }
    request = urllib.request.Request(
        f"{API_BASE}/api/v1/voice/asr/json",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=180) as response:
        return json.loads(response.read().decode("utf-8"))


# ─────────────────────────── 判定（与客户端同源） ───────────────────────────

#: 复刻 StoryContinueMarkers.TRADITIONAL_VARIANTS：Whisper 常把普通话口令输出成繁体。
TRADITIONAL_VARIANTS = {
    "發": "发", "啟": "启", "繼": "继", "續": "续", "課": "课",
    "書": "书", "閣": "阁", "詞": "词", "靈": "灵", "著": "着",
    "畫": "画",
}


def normalize_variants(text: str) -> str:
    for traditional, simplified in TRADITIONAL_VARIANTS.items():
        text = text.replace(traditional, simplified)
    return text

def _normalize(text: str) -> str:
    """复刻 LessonResponseMatcher.normalize_text()。"""
    lower = text.lower().strip()
    out = []
    for ch in lower:
        if ch.isidentifier() or ch.isdigit() or ch == " " or ("\u4e00" <= ch <= "\u9fff"):
            out.append(ch)
        else:
            out.append(" ")
    while "  " in "".join(out):
        out = "".join(out).replace("  ", " ").split(" ")
    return "".join(out).strip()


def lesson_tier(text: str, rule: dict) -> str:
    """复刻 LessonResponseMatcher.evaluate() 的档位判定（只取 tier）。"""
    normalized = _normalize(text)

    def matches_any(phrases: list[str]) -> bool:
        return any(_normalize(p) and _normalize(p) in normalized for p in phrases)

    def matched(keywords: list[str]) -> list[str]:
        return [k for k in keywords if _normalize(k) and _normalize(k) in normalized]

    if not normalized:
        return "needs_help"
    if matches_any(rule.get("clear_phrases", [])):
        return TIER_CLEAR
    if matches_any(rule.get("acceptable_phrases", [])):
        return TIER_OK
    required = rule.get("required_keywords", [])
    optional = rule.get("optional_keywords", [])
    if required and len(matched(required)) == len(required):
        return TIER_OK
    if not required and matched(optional):
        return TIER_OK
    return "needs_help"


def scene_config(scene_id: str) -> dict:
    names = {
        "ChangAnMarket": "chang_an_market_lesson_01",
        "ChangAnMarketLesson02": "chang_an_market_lesson_02",
    }
    path = CLIENT_ROOT / "assets" / "resources" / "scene_configs" / f"{names[scene_id]}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def lesson_rule(scene_id: str, step_id: str) -> dict:
    for step in scene_config(scene_id).get("steps", []):
        if step.get("id") == step_id:
            return step.get("asr", {})
    raise SystemExit(f"step not found: {scene_id}/{step_id}")


def lesson_context(scene_id: str, step_id: str, lang: str) -> dict:
    rule = lesson_rule(scene_id, step_id)
    phrases = list(rule.get("clear_phrases", [])) + list(rule.get("acceptable_phrases", []))
    config = scene_config(scene_id)
    return {
        "scene_id": config["scene_id"],
        "npc_id": "changan_clerk",
        "npc_question": step_id,
        "expected_slots": [
            {
                "key": "answer",
                "type": "keyword",
                "description": f"课堂步骤 {step_id} 的关键词作答",
            }
        ],
        "expected_answer_type": "keyword",
        "candidate_answers": phrases,
        "recent_turns": [],
        "player_level": "A1",
        "language": lang,
    }


#: 非课堂轮次的 ASR 上下文：必须与客户端实际发送的一致，
#: 否则服务端 postprocess 的纠错/取值会和真实运行时不一样（校验就白做了）。
NON_LESSON_CONTEXTS: dict[str, dict] = {
    "prologue_source_name": {
        "scene_id": "beginning",
        "npc_id": "feifei_beginning",
        "npc_question": "告诉腓腓你的中文名。",
        "expected_slots": [{"key": "name", "type": "person_name", "description": "玩家告诉腓腓的中文名"}],
        "expected_answer_type": "player_name",
        "candidate_answers": [],
    },
    "prologue_special_name": {
        "scene_id": "beginning",
        "npc_id": "feifei_beginning",
        "npc_question": "告诉腓腓你的英语名，或者说“你帮我取一个”。",
        "expected_slots": [
            {
                "key": "name",
                "type": "person_name",
                "description": "玩家告诉腓腓的英语名",
                "delegatable": True,
                "value_pool": ["Carl", "Wendy", "Leo", "Mia", "Luna"],
                "pick_strategy": "exclude_recent",
                "slot_state": "awaiting",
            }
        ],
        "expected_answer_type": "player_name",
        "target_intent": "provide_special_language_name_or_request_default",
        "candidate_answers": [],
    },
    "intro_scroll_call": {
        "scene_id": "mirage_inn_introduction",
        "npc_id": "feifei_mirage_inn",
        "npc_question": "对着墙上的画卷说“画中小世界”，它就会听见你。",
        "expected_slots": [
            {"key": "answer", "type": "keyword", "description": "玩家对墙上画卷说出的口令：画中小世界/painting"}
        ],
        "expected_answer_type": "keyword",
        "candidate_answers": ["画中小世界", "little world in the painting", "little world", "painting"],
    },
    "hub_depart": {
        "scene_id": "mirage_inn_owner_room",
        "npc_id": "feifei_beginning",
        "npc_question": "准备好出发，就对腓腓说：“Let's go!” 或者“出发”。",
        "expected_slots": [
            {"key": "answer", "type": "keyword", "description": "玩家对腓腓说出的出发意图：Let's go / 出发 / 下一课"}
        ],
        "expected_answer_type": "keyword",
        "candidate_answers": [
            "let's go", "lets go", "出发", "走吧", "启程", "继续", "接着", "下一课", "next lesson",
        ],
    },
    # 与 MirageInnIntroductionController._build_hub_choice_asr_context() 对齐：
    # hub 二选一是**封闭题**，两条路的候选都喂给 postprocess（hub_choice_candidates(true)
    # = StoryContinueMarkers.MARKERS + LIBRARY_ENTRY_MARKERS），所以 context 里两份都要有，
    # 只放词灵阁会让"出发"那一支被纠错带偏。
    "hub_library": {
        "scene_id": "mirage_inn_hub",
        "npc_id": "feifei_mirage_inn",
        "npc_question": "想去词灵阁玩小游戏，就对腓腓说：“词灵阁”。",
        "expected_slots": [
            {
                "key": "answer",
                "type": "keyword",
                "description": "玩家对腓腓说的二选一：Let's go/出发 继续主线，或 词灵阁/书阁/充能 去复习",
            }
        ],
        "expected_answer_type": "keyword",
        "candidate_answers": [
            "let's go", "lets go", "出发", "走吧", "启程", "继续", "接着", "下一课", "next lesson",
            "词灵阁", "书阁", "词灵书阁", "充能", "library", "archive", "word spirit",
        ],
    },
}


def build_context(answer: dict) -> dict:
    if answer["check"] == "lesson":
        return lesson_context(answer["scene"], answer["step"], answer["lang"])
    context = dict(NON_LESSON_CONTEXTS[answer["id"]])
    context["recent_turns"] = []
    context["player_level"] = "A1"
    context["language"] = answer["lang"]
    return context


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--synth-only", action="store_true", help="只合成，不跑 ASR 校验")
    parser.add_argument("--force", action="store_true", help="覆盖已存在的音频")
    parser.add_argument(
        "--sync-project-settings",
        action="store_true",
        help="把轮换顺序写回 project.godot 的 asr_test_audio_names（默认只打印）",
    )
    args = parser.parse_args()

    if args.dry_run:
        print(f"共 {len(ANSWERS)} 轮玩家台词：")
        for index, answer in enumerate(ANSWERS, start=1):
            print(
                f"  {index:2d}. [{answer['scene']}/{answer['step']}] "
                f"({answer['lang']}) {answer['text']}"
            )
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest: list[dict] = []
    failures: list[str] = []

    for index, answer in enumerate(ANSWERS, start=1):
        path = OUT_DIR / file_name(index, answer)
        voice = VOICE_ZH if answer["lang"] == "zh" else VOICE_EN

        if args.force or not path.is_file():
            say_to_wav(answer["text"], voice, path)
        duration, rms = audio_stats(path)
        record = {
            **answer,
            "index": index,
            "voice": voice,
            "file": path.name,
            "duration_s": round(duration, 2),
            "rms": round(rms, 4),
        }
        status = "ok"
        if rms < 0.005 or duration < 0.3:
            status = "BAD_AUDIO"
            failures.append(f"{path.name}: 音频异常 (dur={duration:.2f}s rms={rms:.4f})")

        if not args.synth_only and status == "ok":
            context = build_context(answer)
            result = asr_roundtrip(path, answer["lang"], context)
            post = result.get("postprocess") or {}
            heard = str(post.get("extracted", {}).get("answer") or post.get("corrected_text") or "")
            record["asr_text"] = result.get("text")
            record["asr_corrected"] = post.get("corrected_text")
            record["asr_extracted"] = post.get("extracted")
            record["asr_intent"] = post.get("intent")
            record["asr_matched"] = post.get("intent_matched")

            if answer["check"] == "lesson":
                tier = lesson_tier(heard, lesson_rule(answer["scene"], answer["step"]))
                record["tier"] = tier
                if tier not in (TIER_CLEAR, TIER_OK):
                    status = f"TIER={tier}"
                    failures.append(f"{path.name}: 识别为 {heard!r} → {tier}")
            elif answer["check"] == "marker":
                # 与客户端同源：优先用 extracted（服务端已纠错/归一），才退回 corrected_text。
                # 注意 key 不一定是 "answer"——客栈唤醒词的槽位 key 就是 "wake_word"。
                extracted_map = post.get("extracted") or {}
                extracted = str(
                    extracted_map.get("answer")
                    or next(iter(extracted_map.values()), "")
                    or ""
                )
                heard_for_match = extracted or str(post.get("corrected_text") or result.get("text") or "")
                record["marker_input"] = heard_for_match
                # 复刻客户端的繁体归一（StoryContinueMarkers.normalize_variants）。
                haystack = normalize_variants(heard_for_match).lower()
                hit = [m for m in answer["markers"] if m.lower() in haystack]
                record["marker_hit"] = hit
                if not hit:
                    status = "NO_MARKER"
                    failures.append(
                        f"{path.name}: 没命中口令 {answer['markers']}（判定输入 {heard_for_match!r}）"
                    )
            else:
                extracted = str((post.get("extracted") or {}).get("name") or "")
                ok = extracted != ""
                record["extracted_name"] = extracted
                if not ok:
                    status = "NO_NAME"
                    failures.append(f"{path.name}: 没取到名字 (heard={heard!r})")

        print(f"[{index:02d}/{len(ANSWERS)}] {status:10s} {path.name}  {answer['text']}")
        manifest.append(record)

    MANIFEST.write_text(
        json.dumps(
            {
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "player": {"source_name": PLAYER_SOURCE_NAME, "en_name": PLAYER_EN_NAME},
                "voices": {"zh": VOICE_ZH, "en": VOICE_EN},
                "rotation_order": [entry["file"] for entry in manifest],
                "answers": manifest,
            },
            ensure_ascii=False,
            indent=1,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\n清单写入 {MANIFEST}")

    # project.godot 的轮换表以前是"打印出来让人手抄"，结果漏抄了第 3、4 条 → 轮到说「书架」时
    # 实际播放的是英语名那条，孩子怎么说都过不去。这里直接写进去，杜绝手抄漂移。
    rotation = [entry["file"] for entry in manifest]
    if args.sync_project_settings and not failures:
        sync_project_settings(rotation)
    else:
        print("project.godot 的轮换顺序（未写入）：")
        print("asr_test_audio_names=" + json.dumps(rotation))

    if failures:
        print(f"\n有 {len(failures)} 条没通过校验：")
        for item in failures:
            print("  -", item)
        return 1
    print("\n全部通过 ✅")
    return 0


def sync_project_settings(rotation: list[str]) -> None:
    """把非课程轮次的答案顺序写进 project.godot 的 asr_test_audio_names。

    课程场景自己有 scene_config 的 test_asr_audio_names（见
    scripts/sync_player_answers_to_configs.py），这里只管序章/客栈/hub 那几条。
    """
    import re

    path = CLIENT_ROOT / "project.godot"
    source = path.read_text(encoding="utf-8")
    packed = "PackedStringArray(%s)" % ", ".join(json.dumps(name) for name in rotation)
    pattern = re.compile(r"^asr_test_audio_names=PackedStringArray\(.*\)$", re.MULTILINE)
    if not pattern.search(source):
        print("⚠ project.godot 里没找到 asr_test_audio_names，跳过写入")
        return
    updated = pattern.sub("asr_test_audio_names=" + packed, source, count=1)
    if updated == source:
        print("project.godot 轮换表已是最新")
        return
    path.write_text(updated, encoding="utf-8")
    print(f"已更新 project.godot 轮换表（{len(rotation)} 条）")


if __name__ == "__main__":
    sys.exit(main())
