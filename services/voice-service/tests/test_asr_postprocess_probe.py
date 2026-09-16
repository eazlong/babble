"""F6 后续：provider 探针（启动期 / 健康检查）与"非 completion 响应"的可读预览。

事故背景（`docs/plans/2026-09-15-intent-accuracy.md` §15）：
F6 的守卫把 provider 故障从"每个请求 500"变成"安静降级"，于是意图判定可以**整体失效**
而现场只有一行 WARNING，`docker ps` 还一直显示 healthy。这组用例钉住两件事：

1. 探针能在启动时把这类故障判定为 `error`，并给出**指向根因**的 reason（带响应预览）；
2. 探针自身绝不抛异常——它失败不能把服务带崩。
"""

from __future__ import annotations

import logging
from types import SimpleNamespace
from typing import Any

import pytest

from src.services.asr_postprocess import (
    ASRPostprocessor,
    describe_non_completion,
    resolve_provider_config,
)

HTML_LANDING_PAGE = (
    '<!doctype html>\n<html lang="en">\n  <head>\n    <meta charset="UTF-8" />\n'
    '    <title>Gateway Console</title>\n  </head>\n</html>'
)


class _ProbeCompletions:
    def __init__(self, payload: Any, raises: Exception | None = None):
        self._payload = payload
        self._raises = raises
        self.calls = 0

    async def create(self, **kwargs: Any) -> Any:
        self.calls += 1
        if self._raises is not None:
            raise self._raises
        return self._payload


class _ProbeClient:
    def __init__(self, payload: Any = None, raises: Exception | None = None):
        self.chat = SimpleNamespace(completions=_ProbeCompletions(payload, raises))


def _ok_completion() -> SimpleNamespace:
    return SimpleNamespace(
        choices=[
            SimpleNamespace(
                message=SimpleNamespace(content='{"ok": true}'),
                finish_reason="stop",
            )
        ],
        model_dump=lambda mode="json": {"model": "probe"},
    )


@pytest.fixture(autouse=True)
def _env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "true")
    monkeypatch.setenv("ASR_POSTPROCESS_API_KEY", "probe-key")
    monkeypatch.setenv("ASR_POSTPROCESS_BASE_URL", "https://gateway.example/v1")
    monkeypatch.setenv("ASR_POSTPROCESS_MODEL", "probe-model")
    monkeypatch.delenv("ASR_POSTPROCESS_PROBE_TIMEOUT_MS", raising=False)


# ────────────────────────────── 响应预览 ──────────────────────────────

def test_preview_flattens_and_truncates() -> None:
    preview = describe_non_completion(HTML_LANDING_PAGE)

    assert "<!doctype html>" in preview, "预览必须让现场一眼看出打到的是站点首页"
    assert "\n" not in preview, "预览必须压成一行，否则会淹掉日志"
    assert len(describe_non_completion("x" * 500)) <= 161, "预览必须截断"


def test_preview_handles_non_text_payloads() -> None:
    assert describe_non_completion(b"<html>bytes</html>") == "<html>bytes</html>"
    assert describe_non_completion(object()).startswith("<object")
    assert describe_non_completion("   ") == "<empty>"


# ────────────────────────────── 探针 ──────────────────────────────

async def test_probe_reports_ok_for_a_real_completion() -> None:
    postprocessor = ASRPostprocessor(client=_ProbeClient(_ok_completion()))  # type: ignore[arg-type]

    result = await postprocessor.check_provider()

    assert result["status"] == "ok"
    assert result["base_url"] == "https://gateway.example/v1"
    assert result["model"] == "probe-model"
    assert isinstance(result["latency_ms"], int)


async def test_probe_flags_html_landing_page_as_error_with_preview() -> None:
    """这就是 2026-09-15 事故的形态：BASE_URL 少 /v1 → 拿到 HTML → 必须判定为 error。"""
    postprocessor = ASRPostprocessor(client=_ProbeClient(HTML_LANDING_PAGE))  # type: ignore[arg-type]

    result = await postprocessor.check_provider()

    assert result["status"] == "error"
    assert "non-completion" in result["reason"]
    assert "doctype" in result["reason"], f"reason 必须带响应预览，实际：{result['reason']}"


async def test_probe_reports_missing_api_key_without_calling_provider(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("ASR_POSTPROCESS_API_KEY", raising=False)
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    completions = _ProbeCompletions(_ok_completion())
    postprocessor = ASRPostprocessor(  # type: ignore[arg-type]
        client=SimpleNamespace(chat=SimpleNamespace(completions=completions))
    )

    result = await postprocessor.check_provider()

    assert result["status"] == "missing_api_key"
    assert completions.calls == 0, "没有密钥就不该发出请求"


async def test_probe_is_disabled_by_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "false")
    completions = _ProbeCompletions(_ok_completion())
    postprocessor = ASRPostprocessor(  # type: ignore[arg-type]
        client=SimpleNamespace(chat=SimpleNamespace(completions=completions))
    )

    result = await postprocessor.check_provider()

    assert result["status"] == "disabled"
    assert completions.calls == 0


async def test_probe_never_raises_on_provider_failure() -> None:
    """探针失败不能把启动/健康检查带崩——它只负责描述。"""
    postprocessor = ASRPostprocessor(  # type: ignore[arg-type]
        client=_ProbeClient(raises=RuntimeError("upstream exploded"))
    )

    result = await postprocessor.check_provider()

    assert result["status"] == "error"
    assert "upstream exploded" in result["reason"]


async def test_probe_times_out_within_budget(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("ASR_POSTPROCESS_PROBE_TIMEOUT_MS", "150")

    class _Hanging:
        def __init__(self) -> None:
            self.chat = SimpleNamespace(completions=self)

        async def create(self, **kwargs: Any) -> Any:
            import asyncio

            await asyncio.sleep(30)

    postprocessor = ASRPostprocessor(client=_Hanging())  # type: ignore[arg-type]
    result = await postprocessor.check_provider()

    assert result["status"] == "error"
    assert "超时" in result["reason"]


async def test_probe_reuses_the_request_client_not_a_separate_one(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """探针必须用与真实请求相同的缓存键取客户端，否则会把连接池挤退休。"""
    created: list[dict[str, Any]] = []

    def factory(**kwargs: Any) -> Any:
        created.append(kwargs)
        return _ProbeClient(_ok_completion())

    import openai

    monkeypatch.setattr(openai, "AsyncOpenAI", factory)
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "30000")

    postprocessor = ASRPostprocessor()
    await postprocessor.check_provider()
    await postprocessor.check_provider()

    assert len(created) == 1, f"探针重复建连：{len(created)} 次"
    assert created[0]["timeout"] == 30.0, "探针要用真实请求的 timeout 建客户端（否则键不同）"
    await postprocessor.aclose()


def test_provider_config_resolution_is_shared(monkeypatch: pytest.MonkeyPatch) -> None:
    """探针与真实请求必须解析出同一份配置，否则探针会"报正常而请求照样挂"。"""
    monkeypatch.setenv("ASR_POSTPROCESS_BASE_URL", "https://a.example/v1")
    monkeypatch.setenv("ASR_POSTPROCESS_MODEL", "m1")
    assert resolve_provider_config() == ("probe-key", "https://a.example/v1", "m1")

    monkeypatch.delenv("ASR_POSTPROCESS_BASE_URL")
    monkeypatch.setenv("COACH_LLM_BASE_URL", "https://b.example/v1")
    monkeypatch.delenv("ASR_POSTPROCESS_MODEL")
    monkeypatch.setenv("COACH_LLM_MODEL", "m2")
    assert resolve_provider_config() == ("probe-key", "https://b.example/v1", "m2")


async def test_non_completion_warning_log_carries_the_preview(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """真实请求路径也要把预览写进日志——事故现场只有这行 WARNING 可看。"""
    postprocessor = ASRPostprocessor(client=_ProbeClient(HTML_LANDING_PAGE))  # type: ignore[arg-type]
    context = {
        "npc_question": "请跟老师读：Nice to meet you",
        "expected_slots": [{"key": "answer", "type": "keyword", "description": "课堂回答"}],
        "expected_answer_type": "keyword",
        "candidate_answers": ["Nice to meet you"],
        "recent_turns": [],
        "language": "en",
        "task_mode": "dialogue",
    }

    with caplog.at_level(logging.WARNING, logger="src.services.asr_postprocess"):
        result = await postprocessor.process(
            text="Nice to meet you", asr_confidence=0.9, language="en", context=context
        )

    assert result["fallback_reason"] == "provider_error"
    assert "<!doctype html>" in caplog.text, "日志里必须能直接看到站点首页内容"
