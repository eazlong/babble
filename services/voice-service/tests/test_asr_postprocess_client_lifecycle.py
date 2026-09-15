"""F7 回归测试：LLM 客户端复用（连接池）与总时长预算。

背景（`docs/plans/2026-09-15-intent-accuracy.md` §11.3 F7）：
`ASRPostprocessor` 是模块级单例但原先 `client=None`，于是**每次** `_call_llm` 都新建一个
`AsyncOpenAI` 再关闭——没有连接复用，实测单次最慢 37.8s，且超过配置的
`ASR_POSTPROCESS_TIMEOUT_MS=30000`（httpx 超时是分阶段读超时，不是总时长上限）。

这组用例钉住三件事：
1. 同配置的多次调用复用同一个客户端；配置变化才换新的；
2. 注入的客户端不被缓存也不被关闭（调用方持有生命周期）；
3. `timeout_ms` 是**总时长预算**：超时降级为 provider timeout，而不是把请求挂死。
"""

from __future__ import annotations

import asyncio
import json
from types import SimpleNamespace
from typing import Any

import pytest

import openai
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

PAYLOAD = json.dumps(
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


class _RecordingCompletions:
    def __init__(self, parent: "_RecordingClient"):
        self._parent = parent

    async def create(self, **kwargs: Any) -> Any:
        self._parent.calls += 1
        if self._parent.delay_s:
            await asyncio.sleep(self._parent.delay_s)
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=self._parent.content),
                    finish_reason="stop",
                )
            ],
            model_dump=lambda mode="json": {"model": "stub"},
        )


class _RecordingClient:
    """形状与 openai.AsyncOpenAI 足够像，用于注入测试。"""

    def __init__(self, content: str = PAYLOAD, delay_s: float = 0.0):
        self.content = content
        self.delay_s = delay_s
        self.calls = 0
        self.closed = False
        self.chat = SimpleNamespace(completions=_RecordingCompletions(self))

    async def close(self) -> None:
        self.closed = True


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "true")
    monkeypatch.setenv("ASR_POSTPROCESS_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_BASE_URL", "https://example.invalid/v1")
    monkeypatch.setenv("ASR_POSTPROCESS_MODEL", "test-model")


def _count_constructed(monkeypatch: pytest.MonkeyPatch) -> list[dict[str, Any]]:
    """拦截 openai.AsyncOpenAI 的构造：记录参数并返回**离线**假客户端。

    注意必须返回假客户端：真 AsyncOpenAI 会真的发请求，测试既慢又会依赖网络。
    """
    created: list[dict[str, Any]] = []

    def factory(**kwargs: Any) -> Any:
        created.append(kwargs)
        return _RecordingClient()

    monkeypatch.setattr(openai, "AsyncOpenAI", factory)
    return created


async def _process(postprocessor: ASRPostprocessor, *, text: str = "Nice to meet you") -> dict[str, Any]:
    return await postprocessor.process(
        text=text, asr_confidence=0.9, language="en", context=CONTEXT
    )


async def test_client_is_reused_across_calls(monkeypatch: pytest.MonkeyPatch) -> None:
    created = _count_constructed(monkeypatch)
    postprocessor = ASRPostprocessor()

    for _ in range(5):
        await _process(postprocessor)

    assert len(created) == 1, "同配置下必须复用同一个客户端（连接池），而不是每次新建"
    await postprocessor.aclose()


async def test_concurrent_calls_create_exactly_one_client(monkeypatch: pytest.MonkeyPatch) -> None:
    """并发下也不得多建：_resolve_client 全是同步操作，在事件循环里天然原子。"""
    created = _count_constructed(monkeypatch)
    postprocessor = ASRPostprocessor()

    await asyncio.gather(*(_process(postprocessor) for _ in range(8)))

    assert len(created) == 1, f"并发建连泄漏：创建了 {len(created)} 个客户端"
    await postprocessor.aclose()


async def test_client_is_rebuilt_when_config_changes(monkeypatch: pytest.MonkeyPatch) -> None:
    created = _count_constructed(monkeypatch)
    postprocessor = ASRPostprocessor()

    await _process(postprocessor)  # 用 env 里的 base_url
    monkeypatch.setenv("ASR_POSTPROCESS_BASE_URL", "https://other.invalid/v1")
    await _process(postprocessor)

    assert len(created) == 2, "配置变化必须换客户端（缓存键含 base_url/api_key/timeout）"
    await postprocessor.aclose()


async def test_aclose_releases_cached_and_retired_clients(monkeypatch: pytest.MonkeyPatch) -> None:
    created = _count_constructed(monkeypatch)
    postprocessor = ASRPostprocessor()

    await _process(postprocessor)
    monkeypatch.setenv("ASR_POSTPROCESS_BASE_URL", "https://other.invalid/v1")
    await _process(postprocessor)  # 旧客户端进入 retired

    assert len(created) == 2
    await postprocessor.aclose()

    assert postprocessor._cached_client is None
    assert postprocessor._retired_clients == []

    # 关停后再用会重新建连，且不报错
    await _process(postprocessor)
    assert len(created) == 3
    await postprocessor.aclose()


async def test_injected_client_is_used_and_never_closed() -> None:
    """注入路径不变：调用方持有生命周期，post-processor 不缓存也不关闭它。"""
    injected = _RecordingClient()
    postprocessor = ASRPostprocessor(client=injected)  # type: ignore[arg-type]

    result = await _process(postprocessor)
    await postprocessor.aclose()

    assert result["applied"] is True
    assert injected.calls == 1
    assert injected.closed is False, "注入的客户端不得被 aclose() 关闭"
    assert postprocessor._cached_client is None, "注入路径不得顺手缓存"


async def test_total_budget_cuts_a_hanging_request(monkeypatch: pytest.MonkeyPatch) -> None:
    """timeout_ms 是总时长预算：挂住的请求必须在预算内降级，而不是一直等。

    （httpx 的分阶段读超时挡不住"慢速但持续有响应"的请求，实测曾到 37.8s。）
    """
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "200")
    slow = _RecordingClient(delay_s=30.0)
    postprocessor = ASRPostprocessor(client=slow)  # type: ignore[arg-type]

    result = await asyncio.wait_for(_process(postprocessor), timeout=10)

    assert result["applied"] is False
    assert result["fallback_reason"] == "timeout"
    assert result["latency_ms"] == 200, "超时分支的 latency_ms 记为预算值"
    assert result["corrected_text"] == "Nice to meet you", "超时也必须原样透传文本"


async def test_fast_request_is_not_affected_by_the_budget(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "5000")
    postprocessor = ASRPostprocessor(client=_RecordingClient(delay_s=0.01))  # type: ignore[arg-type]

    result = await _process(postprocessor)

    assert result["applied"] is True
    assert result["extracted"] == {"answer": "Nice to meet you"}
