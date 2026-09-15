"""F6 回归测试：provider 形状漂移不得把 ASR 端点打成 500。

背景（`docs/plans/2026-09-15-intent-accuracy.md` §11.3）：
本仓库 `.env` 的 `ASR_POSTPROCESS_BASE_URL` 曾少写 `/v1`，请求于是打到网关站点首页、
拿到 HTML 且 HTTP 200，OpenAI SDK 因此返回 `str`；`_complete_json` 接着取 `.choices`
抛 `AttributeError`——而 `process()` 只捕获 `APITimeoutError` / `APIStatusError` /
`APIError` / `RuntimeError`，异常冒泡到路由，**ASR 端点 500**（不是既有的容错降级）。

修复方式是一行守卫：非 completion 对象 → `RuntimeError` → 复用 `provider_error` 降级。
这组用例钉住"降级而不是 500"，以及对降级语义的约定（容错放行，不是判玩家没作答）。
"""

from __future__ import annotations

import json
from types import SimpleNamespace
from typing import Any

import pytest

from src.services.asr_postprocess import ASRPostprocessor


class _CannedCompletions:
    """返回固定对象的假 chat.completions，用来模拟各种 provider 形状漂移。"""

    def __init__(self, payload: Any):
        self._payload = payload

    async def create(self, **kwargs: Any) -> Any:
        return self._payload


class _CannedClient:
    def __init__(self, payload: Any):
        self.chat = SimpleNamespace(completions=_CannedCompletions(payload))


CONTEXT = {
    "npc_question": "请告诉腓腓你的中文名。",
    "expected_slots": [{"key": "name", "type": "person_name", "description": "玩家的中文名"}],
    "expected_answer_type": "player_name",
    "target_intent": "provide_source_name",
    "intent_description": "The player should tell Feifei their name.",
    "candidate_answers": [],
    "recent_turns": [],
    "language": "zh",
    "task_mode": "dialogue",
}


@pytest.fixture(autouse=True)
def _postprocess_enabled(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "true")
    monkeypatch.setenv("ASR_POSTPROCESS_API_KEY", "test-key")


async def _process_with(payload: Any) -> dict[str, Any]:
    postprocessor = ASRPostprocessor(client=_CannedClient(payload))  # type: ignore[arg-type]
    return await postprocessor.process(
        text="我叫小明",
        asr_confidence=0.9,
        language="zh",
        context=CONTEXT,
    )


async def test_html_page_response_degrades_instead_of_raising() -> None:
    """缺 /v1 时的真实症状：HTTP 200 的站点首页 HTML，SDK 返回 str。"""
    result = await _process_with("<!doctype html>\n<html lang=\"en\">...</html>")

    assert result["applied"] is False
    assert result["fallback_reason"] == "provider_error"
    assert result["corrected_text"] == "我叫小明", "降级必须原样透传文本"


async def test_provider_shape_drift_is_tolerated_not_treated_as_no_answer() -> None:
    """降级语义：系统故障容错放行（intent_matched=True），不得误判成玩家没作答。

    这条与 missing_context 的语义相反（后者 intent=off_topic），是既有契约，
    见 asr_postprocess.py `_fallback()`。
    """
    result = await _process_with("not a completion")

    assert result["intent_matched"] is True
    assert result["intent"] == "provide"
    assert result["confidence"] == 0.0
    assert result["model"] is None


@pytest.mark.parametrize("payload", ["plain string", b"bytes payload", ["a", "list"]])
async def test_non_completion_shapes_all_degrade(payload: Any) -> None:
    result = await _process_with(payload)

    assert result["fallback_reason"] == "provider_error", f"{type(payload).__name__} 未被守卫接住"


async def test_empty_choices_with_player_name_uses_local_recovery() -> None:
    """有 choices 但为空 → 不是形状漂移，走原有的空响应处理，不应被守卫误伤。

    对 `player_name` 上下文，原有代码会先用本地正则从"我叫X"里恢复名字
    （`_local_empty_content_fallback`），所以这里是 applied=True、confidence=0.75，
    **不是** provider_error。这条分支比通用降级更好，值得钉住别被守卫连坐。
    """
    payload = SimpleNamespace(choices=[], model_dump=lambda mode="json": {"model": "x"})

    result = await _process_with(payload)

    assert result["applied"] is True
    assert result["intent"] == "provide"
    assert result["extracted"] == {"name": "小明"}
    assert result["confidence"] == 0.75


async def test_empty_choices_without_local_recovery_degrades_to_provider_error() -> None:
    """本地恢复不适用时（非 player_name），空响应才落到 provider_error。"""
    payload = SimpleNamespace(choices=[], model_dump=lambda mode="json": {"model": "x"})
    keyword_context = {
        "npc_question": "请跟老师读：Nice to meet you",
        "expected_slots": [{"key": "answer", "type": "keyword", "description": "课堂回答"}],
        "expected_answer_type": "keyword",
        "candidate_answers": ["Nice to meet you"],
        "recent_turns": [],
        "language": "en",
        "task_mode": "dialogue",
    }
    postprocessor = ASRPostprocessor(client=_CannedClient(payload))  # type: ignore[arg-type]

    result = await postprocessor.process(
        text="Nice to meet you", asr_confidence=0.9, language="en", context=keyword_context
    )

    assert result["applied"] is False
    assert result["fallback_reason"] == "provider_error"
    assert result["intent_matched"] is True, "系统故障仍走容错放行"


async def test_normal_completion_is_unaffected_by_the_guard() -> None:
    content = json.dumps(
        {
            "corrected_text": "我叫小明",
            "correction_applied": False,
            "correction_reason": None,
            "extracted": {"name": "小明"},
            "intent_matched": True,
            "intent": "provide",
            "guidance": {"npc_line": None},
            "confidence": 0.9,
        },
        ensure_ascii=False,
    )
    payload = SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=SimpleNamespace(content=content),
                finish_reason="stop",
            )
        ],
        model_dump=lambda mode="json": {"model": "stub"},
    )

    result = await _process_with(payload)

    assert result["applied"] is True
    assert result["intent"] == "provide"
    assert result["extracted"] == {"name": "小明"}
