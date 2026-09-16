"""§14.4 有界重试的回归测试。

背景：网关实测对 13.5% 的请求返回 HTTP 500，而 `provider_error` 走"容错放行"，
含义是约 1/8 的对话轮次**完全跳过意图判定**（客户端退回 corrected_text，既不纠错
也不判 off_topic）。裁定为 `provider_error` 增加**一次**有界重试。

这组用例钉住四件事：
1. 瞬时故障（5xx / 连接错误）重试一次就能把这一轮救回来；
2. 重试是**有界**的（至多 1 次），不会变成重试风暴；
3. 重试**永远不延长孩子等待的上限** —— 它花的是同一个总时长预算；
4. 不该重试的绝不重试：4xx（配置/鉴权错误，重试只会掩盖它）与响应形状漂移（F6）。
"""

from __future__ import annotations

import asyncio
import json
import time
from types import SimpleNamespace
from typing import Any

import httpx
import openai
import pytest

from src.services.asr_postprocess import ASRPostprocessor

CONTEXT = {
    "npc_question": "请跟老师读：Nice to meet you",
    "expected_slots": [{"key": "answer", "type": "keyword", "description": "课堂回答"}],
    "expected_answer_type": "keyword",
    "candidate_answers": ["Nice to meet you"],
    "recent_turns": [],
    "language": "en",
    "task_mode": "dialogue",
}

OK_PAYLOAD = json.dumps(
    {
        "corrected_text": "Nice to meet you",
        "correction_applied": False,
        "correction_reason": None,
        "extracted": {"answer": "Nice to meet you"},
        "intent_matched": True,
        "intent": "provide",
        "guidance": {"npc_line": None},
        "confidence": 0.9,
    },
    ensure_ascii=False,
)


def _status_error(status: int) -> openai.APIStatusError:
    request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
    response = httpx.Response(status, request=request, json={"error": f"status {status}"})
    return openai.APIStatusError(f"status {status}", response=response, body={"error": status})


def _ok_completion() -> Any:
    return SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=SimpleNamespace(content=OK_PAYLOAD),
                finish_reason="stop",
            )
        ],
        model_dump=lambda mode="json": {"model": "stub"},
    )


class _ScriptedClient:
    """按脚本依次产出：抛异常、延迟后返回、直接返回。"""

    def __init__(self, script: list[Any]):
        self._script = list(script)
        self.call_times: list[float] = []
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    async def _create(self, **_kwargs: Any) -> Any:
        self.call_times.append(time.monotonic())
        if not self._script:
            raise AssertionError("脚本用尽：重试次数超出了测试预期")
        step = self._script.pop(0)
        if isinstance(step, BaseException):
            raise step
        if isinstance(step, tuple):  # (延迟秒, 返回值/异常)
            delay, outcome = step
            await asyncio.sleep(delay)
            if isinstance(outcome, BaseException):
                raise outcome
            return outcome
        return step


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "true")
    monkeypatch.setenv("ASR_POSTPROCESS_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "5000")
    monkeypatch.setenv("ASR_POSTPROCESS_RETRY_BACKOFF_MS", "0")


async def _process(client: _ScriptedClient) -> dict[str, Any]:
    postprocessor = ASRPostprocessor(client=client)  # type: ignore[arg-type]
    return await postprocessor.process(
        text="Nice to meet you", asr_confidence=0.9, language="en", context=CONTEXT
    )


async def test_5xx_then_success_recovers_the_turn() -> None:
    """这是本改动的全部价值：一次重试把"跳过意图判定"的那一轮救回来。"""
    client = _ScriptedClient([_status_error(500), _ok_completion()])

    result = await _process(client)

    assert result["applied"] is True
    assert result["intent"] == "provide"
    assert result["retry_count"] == 1
    assert len(client.call_times) == 2


async def test_retry_is_bounded_to_exactly_one() -> None:
    client = _ScriptedClient([_status_error(503), _status_error(503)])

    result = await _process(client)

    assert result["fallback_reason"] == "provider_error"
    assert result["retry_count"] == 1
    assert len(client.call_times) == 2, "只允许一次重试，不得继续尝试"
    assert result["intent_matched"] is True, "系统故障仍走容错放行"


async def test_retry_can_be_disabled_by_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_MAX_RETRIES", "0")
    client = _ScriptedClient([_status_error(500)])

    result = await _process(client)

    assert result["retry_count"] == 0
    assert len(client.call_times) == 1


async def test_connection_error_is_retried() -> None:
    request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
    client = _ScriptedClient([openai.APIConnectionError(request=request), _ok_completion()])

    result = await _process(client)

    assert result["applied"] is True
    assert result["retry_count"] == 1


@pytest.mark.parametrize("status", [400, 401, 403, 404, 422, 429])
async def test_client_errors_are_not_retried(status: int) -> None:
    """4xx 是配置/鉴权/请求错误——重试只会掩盖问题（F6 就是这样被掩盖过一次）。"""
    client = _ScriptedClient([_status_error(status)])

    result = await _process(client)

    assert result["fallback_reason"] == "provider_error"
    assert result["retry_count"] == 0
    assert len(client.call_times) == 1


async def test_response_shape_drift_is_not_retried() -> None:
    """F6：provider 返回非 completion（如缺 /v1 时的首页 HTML）→ 配置问题，不重试。"""
    client = _ScriptedClient(["<!doctype html><html>gateway home</html>"])

    result = await _process(client)

    assert result["fallback_reason"] == "provider_error"
    assert result["retry_count"] == 0
    assert len(client.call_times) == 1


async def test_retry_cannot_extend_the_total_budget(monkeypatch: pytest.MonkeyPatch) -> None:
    """核心安全性质：重试花的是同一个总时长预算，不会把孩子的等待翻倍。

    第一次立刻 503，第二次挂住 5s。预算 400ms → 必须在预算内收手，
    而不是等满 5s（否则"重试"就等于把 30s 预算悄悄变成 60s）。
    """
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "400")
    client = _ScriptedClient([_status_error(503), (5.0, _ok_completion())])

    started = time.monotonic()
    result = await _process(client)
    elapsed = time.monotonic() - started

    assert result["fallback_reason"] == "timeout"
    assert elapsed < 2.0, f"重试突破了总预算：耗时 {elapsed:.2f}s"
    assert result["retry_count"] == 1
    assert len(client.call_times) == 2, "第二次尝试应当已被预算切断"


async def test_backoff_is_applied_between_attempts(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_RETRY_BACKOFF_MS", "200")
    client = _ScriptedClient([_status_error(500), _ok_completion()])

    result = await _process(client)

    assert result["applied"] is True
    gap = client.call_times[1] - client.call_times[0]
    assert gap >= 0.15, f"退避未生效：两次尝试间隔仅 {gap * 1000:.0f}ms"


async def test_backoff_is_clamped_by_remaining_budget(monkeypatch: pytest.MonkeyPatch) -> None:
    """退避不能睡过截止时间——否则预算形同虚设。"""
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "300")
    monkeypatch.setenv("ASR_POSTPROCESS_RETRY_BACKOFF_MS", "10000")
    client = _ScriptedClient([_status_error(503), _ok_completion()])

    started = time.monotonic()
    result = await _process(client)
    elapsed = time.monotonic() - started

    assert elapsed < 2.0, f"退避睡过了预算：耗时 {elapsed:.2f}s"
    assert result["fallback_reason"] == "timeout"
    assert result["retry_count"] == 1
