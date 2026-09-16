import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import httpx
import openai
import pytest

from src.services.asr_postprocess import ASRPostprocessor


CONTEXT = {
    "npc_question": "这个家具是什么？",
    "expected_slots": [{"key": "answer", "type": "string"}],
    "expected_answer_type": "object_name",
    "candidate_answers": ["书架", "椅子", "桌子", "床"],
}


@pytest.mark.asyncio
async def test_postprocessor_preserves_already_correct_answer(monkeypatch):
    captured_kwargs = {}

    async def fake_create(**kwargs):
        captured_kwargs.update(kwargs)
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "书架",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {"answer": "书架"},
                                "intent_matched": True,
                                "guidance": {"npc_line": None},
                                "confidence": 0.95,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="书架",
        asr_confidence=0.95,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is True
    assert result["corrected_text"] == "书架"
    assert result["correction_reason"] is None
    assert result["extracted"] == {"answer": "书架"}
    assert result["intent_matched"] is True
    assert result["guidance"] == {"npc_line": None}
    assert result["confidence"] == 0.95
    assert captured_kwargs["response_format"] == {"type": "json_object"}


@pytest.mark.asyncio
async def test_postprocessor_surfaces_delegate_intent(monkeypatch):
    """Delegate intent: player hands the slot back to the NPC.

    voice-service must surface the LLM's `intent: "delegate"` label without
    inventing a slot value or a proposal line — completion is the client's job.
    """

    async def fake_create(**kwargs):
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "你帮我起一个吧",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {},
                                "intent_matched": False,
                                "intent": "delegate",
                                "guidance": {"npc_line": None},
                                "confidence": 0.9,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="你帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            # delegatable: rule_005 的门控——未声明可委托时 delegate 会被降级为 off_topic，
            # 这三个用例要验证的是 delegate 的**透传**，所以必须显式声明可委托。
            "expected_slots": [{"key": "english_name", "type": "person_name", "delegatable": True}],
            "expected_answer_type": "player_name",
        },
    )

    assert result["applied"] is True
    assert result["intent"] == "delegate"
    assert result["intent_matched"] is False
    assert result["extracted"] == {}
    assert result["guidance"] == {"npc_line": None}


@pytest.mark.asyncio
async def test_postprocessor_sanitizes_delegate_payload(monkeypatch):
    """Delegate intent never carries invented values or proposal lines."""

    async def fake_create(**kwargs):
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "你帮我起一个吧",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {"english_name": "Wendy"},
                                "intent_matched": True,
                                "intent": "delegate",
                                "guidance": {"npc_line": "那就叫 Wendy，你觉得怎么样？"},
                                "confidence": 0.9,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="你帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            # delegatable: rule_005 的门控——未声明可委托时 delegate 会被降级为 off_topic，
            # 这三个用例要验证的是 delegate 的**透传**，所以必须显式声明可委托。
            "expected_slots": [{"key": "english_name", "type": "person_name", "delegatable": True}],
            "expected_answer_type": "player_name",
        },
    )

    assert result["intent"] == "delegate"
    assert result["intent_matched"] is False
    assert result["extracted"] == {}
    assert result["guidance"] == {"npc_line": None}


@pytest.mark.asyncio
async def test_postprocessor_derive_intent_matched_from_intent(monkeypatch):
    """`intent_matched` remains equivalent to `intent == "provide"`."""

    async def fake_create(**kwargs):
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "不是这个",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {"answer": "书架"},
                                "intent_matched": True,
                                "intent": "off_topic",
                                "guidance": {"npc_line": "我们先回答这个家具是什么，好吗？"},
                                "confidence": 0.7,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="不是这个",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["intent"] == "off_topic"
    assert result["intent_matched"] is False
    assert result["extracted"] == {}
    assert result["guidance"] == {"npc_line": "我们先回答这个家具是什么，好吗？"}


@pytest.mark.asyncio
async def test_postprocessor_preserves_expected_slot_extensions_in_prompt(monkeypatch):
    captured = {}

    async def fake_create(**kwargs):
        captured["messages"] = kwargs["messages"]
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "你帮我起一个吧",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {},
                                "intent_matched": False,
                                "intent": "delegate",
                                "guidance": {"npc_line": None},
                                "confidence": 0.9,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    await postprocessor.process(
        text="你帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            "expected_slots": [
                {
                    "key": "english_name",
                    "type": "person_name",
                    "delegateable": True,
                    "value_pool": ["Wendy", "Tom"],
                    "pick_strategy": "sequential",
                    "exclude_recent": 1,
                }
            ],
            "expected_answer_type": "player_name",
        },
    )

    user_payload = json.loads(captured["messages"][1]["content"])
    expected_slot = user_payload["expected_slots"][0]
    assert expected_slot["delegateable"] is True
    assert expected_slot["value_pool"] == ["Wendy", "Tom"]
    assert expected_slot["pick_strategy"] == "sequential"
    assert expected_slot["exclude_recent"] == 1


@pytest.mark.asyncio
async def test_postprocessor_defaults_intent_to_provide_when_absent(monkeypatch):
    """Legacy LLM payloads without an `intent` key stay backward compatible."""

    async def fake_create(**kwargs):
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "书架",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {"answer": "书架"},
                                "intent_matched": True,
                                "guidance": {"npc_line": None},
                                "confidence": 0.95,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="书架",
        asr_confidence=0.95,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["intent"] == "provide"
    assert result["intent_matched"] is True


@pytest.mark.asyncio
async def test_postprocessor_system_prompt_instructs_delegate_recognition(monkeypatch):
    captured = {}

    async def fake_create(**kwargs):
        captured["messages"] = kwargs["messages"]
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "x",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {},
                                "intent_matched": False,
                                "intent": "delegate",
                                "guidance": {"npc_line": None},
                                "confidence": 0.5,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    await postprocessor.process(
        text="你帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            "expected_slots": [{"key": "english_name", "type": "person_name"}],
            "expected_answer_type": "player_name",
        },
    )

    system_content = captured["messages"][0]["content"]
    assert "delegate" in system_content.lower()
    assert "provide" in system_content.lower()


@pytest.mark.asyncio
async def test_postprocessor_disabled_does_not_call_llm(monkeypatch):
    create = AsyncMock()
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_ENABLED", "false")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": create})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["extracted"] == {}
    assert result["intent_matched"] is True
    assert result["guidance"] == {"npc_line": None}
    assert result["fallback_reason"] == "disabled"
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_postprocessor_missing_api_key_does_not_call_llm(monkeypatch):
    create = AsyncMock()
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    monkeypatch.delenv("ASR_POSTPROCESS_API_KEY", raising=False)
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": create})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "missing_api_key"
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_postprocessor_provider_5xx_retries_once_then_degrades(monkeypatch):
    """网关 5xx 属瞬时故障：重试一次（§14.4 裁定），仍失败才降级。

    这条取代了旧的 `test_postprocessor_provider_error_does_not_retry`
    （当时的口径是"provider_error 一律不重试"）。裁定改为"一次有界重试"后，
    原来的保护性意图由两条用例承接：4xx 不重试（下一条）与超时不重试
    （`test_postprocessor_timeout_does_not_retry`）。
    """
    calls = 0

    async def fake_create(**_kwargs):
        nonlocal calls
        calls += 1
        request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
        response = httpx.Response(500, request=request, json={"error": "provider down"})
        raise openai.APIStatusError("provider down", response=response, body={"error": "provider down"})

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_RETRY_BACKOFF_MS", "0")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "provider_error"
    assert calls == 2, "5xx 应重试一次，且**只**重试一次（有界）"
    assert result["retry_count"] == 1


@pytest.mark.asyncio
async def test_postprocessor_provider_4xx_does_not_retry(monkeypatch):
    """4xx 是配置/鉴权错误，重试只会掩盖它（例如 F6 那种 BASE_URL 写错）。"""
    calls = 0

    async def fake_create(**_kwargs):
        nonlocal calls
        calls += 1
        request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
        response = httpx.Response(401, request=request, json={"error": "invalid api key"})
        raise openai.APIStatusError("invalid api key", response=response, body={"error": "invalid api key"})

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["fallback_reason"] == "provider_error"
    assert calls == 1
    assert result["retry_count"] == 0


@pytest.mark.asyncio
async def test_postprocessor_timeout_does_not_retry(monkeypatch):
    calls = 0

    async def fake_create(**_kwargs):
        nonlocal calls
        calls += 1
        request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
        raise openai.APITimeoutError(request=request)

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "1")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "timeout"
    assert result["latency_ms"] == 1
    assert calls == 1


@pytest.mark.asyncio
async def test_postprocessor_retries_when_llm_truncated_by_length(monkeypatch):
    """Reasoning models can exhaust max_tokens on reasoning and return finish_reason=length.

    The postprocessor must retry with a larger budget instead of falling back to a
    wrong `provide` result from truncated JSON.
    """
    calls = []

    async def fake_create(**kwargs):
        calls.append(kwargs.get("max_tokens"))
        if len(calls) == 1:
            return openai.types.chat.ChatCompletion(
                id="chatcmpl-test",
                model=kwargs["model"],
                object="chat.completion",
                created=0,
                choices=[
                    openai.types.chat.chat_completion.Choice(
                        index=0,
                        finish_reason="length",
                        message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                            role="assistant",
                            content='{"corrected_text": "帮我起一个吧',
                        ),
                    )
                ],
            )
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model=kwargs["model"],
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="stop",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content=json.dumps(
                            {
                                "corrected_text": "帮我起一个吧",
                                "correction_applied": False,
                                "correction_reason": None,
                                "extracted": {},
                                "intent_matched": False,
                                "intent": "delegate",
                                "guidance": {"npc_line": None},
                                "confidence": 0.9,
                            },
                            ensure_ascii=False,
                        ),
                    ),
                )
            ],
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            # delegatable: rule_005 的门控——未声明可委托时 delegate 会被降级为 off_topic，
            # 这三个用例要验证的是 delegate 的**透传**，所以必须显式声明可委托。
            "expected_slots": [{"key": "english_name", "type": "person_name", "delegatable": True}],
            "expected_answer_type": "player_name",
        },
    )

    assert result["applied"] is True
    assert result["intent"] == "delegate"
    assert result["intent_matched"] is False
    assert len(calls) == 2
    assert calls[1] >= calls[0]
    assert calls[1] >= 2048


@pytest.mark.asyncio
async def test_postprocessor_returns_missing_context_without_llm(monkeypatch):
    create = AsyncMock()
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": create})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=None,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["extracted"] == {}
    assert result["intent_matched"] is False
    assert result["intent"] == "off_topic"
    assert result["guidance"] == {"npc_line": None}
    assert result["fallback_reason"] == "missing_context"
    create.assert_not_awaited()


def openai_completion(content: str, model: str) -> openai.types.chat.ChatCompletion:
    return openai.types.chat.ChatCompletion(
        id="chatcmpl-test",
        model=model,
        object="chat.completion",
        created=0,
        choices=[
            openai.types.chat.chat_completion.Choice(
                index=0,
                finish_reason="stop",
                message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                    role="assistant",
                    content=content,
                ),
            )
        ],
    )


@pytest.mark.asyncio
async def test_postprocessor_maps_valid_llm_output(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": True,
                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                    "extracted": {"answer": "书架"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.88,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_MODEL", "mock-model")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        # 原始文本必须自身可确认命中：规则层的**决策**跑在原始 ASR 文本上（见 apply_rules 的
        # "两个文本"说明），若这里写「暑假」，同音改写会因拼音维尚未实现而弃权（见边界用例
        # test_postprocessor_abstains_on_homophone_it_cannot_verify）。本用例考的是字段映射。
        text="书架吧",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is True
    assert result["corrected_text"] == "书架"
    assert result["correction_reason"] == "家具题且候选答案书架与暑假音近。"
    assert result["extracted"] == {"answer": "书架"}
    assert result["intent_matched"] is True
    assert result["guidance"] == {"npc_line": None}
    assert result["confidence"] == 0.88
    assert result["fallback_reason"] is None
    assert result["model"] == "mock-model"
    assert captured["response_format"] == {"type": "json_object"}
    assert captured["max_tokens"] == 2048
    assert isinstance(captured["messages"], list)
    assert isinstance(captured["messages"][0], dict)
    assert captured["messages"][0]["role"] == "system"
    assert captured["messages"][1]["role"] == "user"


@pytest.mark.asyncio
async def test_postprocessor_sends_flat_message_list(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {"answer": "书架"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.95,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    await postprocessor.process(
        text="书架",
        asr_confidence=0.95,
        language="cn_en",
        context=CONTEXT,
    )

    messages = captured["messages"]
    assert isinstance(messages, list)
    assert all(isinstance(message, dict) for message in messages)


@pytest.mark.asyncio
async def test_postprocessor_uses_configured_max_tokens(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {"answer": "书架"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.95,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_MAX_TOKENS", "1200")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    await postprocessor.process(
        text="书架",
        asr_confidence=0.95,
        language="cn_en",
        context=CONTEXT,
    )

    assert captured["max_tokens"] == 1200


@pytest.mark.asyncio
async def test_postprocessor_drops_extracted_keys_not_declared_in_expected_slots(monkeypatch):
    async def create(**_kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": True,
                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                    "extracted": {"answer": "书架", "extra": "不要透传"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.88,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="书架吧",  # 同上：原始文本需自身可确认命中（本用例考的是键过滤）
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is True
    assert result["extracted"] == {"answer": "书架"}
    assert result["intent_matched"] is True
    assert result["guidance"] == {"npc_line": None}


@pytest.mark.asyncio
async def test_postprocessor_maps_intent_guidance_when_not_matched(monkeypatch):
    async def create(**_kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "我不知道",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {},
                    "intent_matched": False,
                    "guidance": {"npc_line": "你可以告诉我你的名字，比如：我叫小明。"},
                    "confidence": 0.72,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "你叫什么名字？",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_source_name",
        "intent_description": "玩家需要告诉腓腓自己的中文名。",
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="我不知道",
        asr_confidence=0.9,
        language="cn_en",
        context=name_context,
    )

    assert result["applied"] is True
    assert result["intent_matched"] is False
    assert result["guidance"] == {"npc_line": "你可以告诉我你的名字，比如：我叫小明。"}
    assert result["extracted"] == {}


@pytest.mark.asyncio
async def test_postprocessor_prompt_contains_conservative_schema_rules(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "我叫大飞，大小的大，飞行的飞",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {"name": "大飞"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.93,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "你叫什么名字？",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    await postprocessor.process(
        text="我叫大飞，大小的大，飞行的飞",
        asr_confidence=0.9,
        language="cn_en",
        context=name_context,
    )

    system_prompt = captured["messages"][0]["content"]
    user_prompt = json.loads(captured["messages"][1]["content"])
    assert "No reasoning" in system_prompt
    assert "Required keys" in system_prompt
    assert "Extract only expected_slots keys" in system_prompt
    assert "candidate_answers" in system_prompt
    assert "target_intent and intent_description" in system_prompt
    assert user_prompt["expected_slots"][0]["key"] == "name"
    assert "context" not in user_prompt
    assert "return_shape" not in user_prompt


@pytest.mark.asyncio
async def test_postprocessor_falls_back_on_schema_extra_fields(monkeypatch):
    async def create(**_kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": True,
                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                    "extracted": {"answer": "书架"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.88,
                    "unexpected": "不要透传",
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "schema_error"


@pytest.mark.asyncio
async def test_postprocessor_falls_back_on_non_object_json(monkeypatch):
    async def create(**_kwargs):
        return openai_completion(
            json.dumps(["not", "object"], ensure_ascii=False),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "schema_error"




@pytest.mark.asyncio
async def test_postprocessor_falls_back_to_local_name_when_llm_returns_empty_content(monkeypatch):
    async def create(**_kwargs):
        return openai.types.chat.ChatCompletion(
            id="chatcmpl-test",
            model="mock-model",
            object="chat.completion",
            created=0,
            choices=[
                openai.types.chat.chat_completion.Choice(
                    index=0,
                    finish_reason="length",
                    message=openai.types.chat.chat_completion_message.ChatCompletionMessage(
                        role="assistant",
                        content="",
                    ),
                )
            ],
        )

    name_context = {
        "npc_question": "请告诉我你的中文名。",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_source_name",
        "intent_description": "玩家需要告诉腓腓自己的中文名。",
        "recent_turns": [
            {"speaker": "npc", "text": "我有点没听明白，能再说一次你的中文名吗？"},
        ],
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="我叫大飞大小的大飞飞。",
        asr_confidence=0.9,
        language="cn_en",
        context=name_context,
    )

    assert result["applied"] is True
    assert result["corrected_text"] == "我叫大飞"
    assert result["extracted"] == {"name": "大飞"}
    assert result["intent_matched"] is True
    assert result["guidance"] == {"npc_line": None}
    assert result["confidence"] == 0.75
    assert result["fallback_reason"] is None


@pytest.mark.asyncio
async def test_postprocessor_falls_back_to_local_name_before_extra_question(monkeypatch):
    async def create(**_kwargs):
        return openai_completion("", "mock-model")

    name_context = {
        "npc_question": "告诉腓腓你的中文名就可以。",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_source_name",
        "intent_description": "玩家需要告诉腓腓自己的中文名。",
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="我叫小北，你是谁？",
        asr_confidence=0.9,
        language="cn_en",
        context=name_context,
    )

    assert result["corrected_text"] == "我叫小北"
    assert result["extracted"] == {"name": "小北"}
    assert result["intent_matched"] is True


@pytest.mark.asyncio
async def test_postprocessor_falls_back_on_empty_llm_content_without_local_match(monkeypatch):
    async def create(**_kwargs):
        return openai_completion("", "mock-model")

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="不知道",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["applied"] is False
    assert result["fallback_reason"] == "provider_error"


@pytest.mark.asyncio
async def test_postprocessor_prompt_allows_one_confirmation_for_implausible_name(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "Google",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {},
                    "intent_matched": False,
                    "guidance": {"npc_line": "我有点没听明白，是 Google 吗？怎么拼写呢？"},
                    "confidence": 0.55,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "What is your English name?",
        "expected_slots": [{"key": "english_name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_english_name",
        "intent_description": "玩家需要告诉 NPC 自己的英文名。",
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="Google",
        asr_confidence=0.62,
        language="cn_en",
        context=name_context,
    )

    assert result["guidance"] == {"npc_line": "我有点没听明白，是 Google 吗？怎么拼写呢？"}
    system_prompt = captured["messages"][0]["content"]
    user_prompt = json.loads(captured["messages"][1]["content"])
    assert "If confidence is low or the answer is implausible" in system_prompt
    assert "Ask at most one confirmation question" in system_prompt
    assert "Google" in system_prompt
    assert user_prompt["confirmation_already_asked"] is False


@pytest.mark.asyncio
async def test_postprocessor_does_not_treat_npc_self_intro_as_confirmation(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "我叫小北，你是谁？",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {"name": "小北"},
                    "intent_matched": True,
                    "guidance": {"npc_line": None},
                    "confidence": 0.92,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "告诉腓腓你的中文名就可以。",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_source_name",
        "intent_description": "玩家需要告诉腓腓自己的中文名。",
        "recent_turns": [
            {"speaker": "npc", "text": "你好啊，太好了，你醒了啊，外来人。我是腓腓。对了，你叫什么名字呀？"},
        ],
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="我叫小北，你是谁？",
        asr_confidence=0.9,
        language="cn_en",
        context=name_context,
    )

    user_prompt = json.loads(captured["messages"][1]["content"])
    assert user_prompt["confirmation_already_asked"] is False
    assert result["extracted"] == {"name": "小北"}
    assert result["intent_matched"] is True


@pytest.mark.asyncio
async def test_postprocessor_recognizes_specific_confirmation_prompt(monkeypatch):
    captured = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "Google",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {},
                    "intent_matched": False,
                    "guidance": {"npc_line": "我有点没听明白，是 Google 吗？怎么拼写呢？"},
                    "confidence": 0.55,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "What is your English name?",
        "expected_slots": [{"key": "english_name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_english_name",
        "intent_description": "玩家需要告诉 NPC 自己的英文名。",
        "recent_turns": [
            {"speaker": "npc", "text": "我有点没听明白，是 Google 吗？怎么拼写呢？"},
        ],
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="Google",
        asr_confidence=0.62,
        language="cn_en",
        context=name_context,
    )

    user_prompt = json.loads(captured["messages"][1]["content"])
    assert user_prompt["confirmation_already_asked"] is True
    assert result["guidance"] == {"npc_line": None}


@pytest.mark.asyncio
async def test_postprocessor_suppresses_repeated_confirmation_guidance(monkeypatch):
    async def create(**_kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "Google",
                    "correction_applied": False,
                    "correction_reason": None,
                    "extracted": {},
                    "intent_matched": False,
                    "guidance": {"npc_line": "我有点没听明白，是 Google 吗？怎么拼写呢？"},
                    "confidence": 0.55,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    name_context = {
        "npc_question": "What is your English name?",
        "expected_slots": [{"key": "english_name", "type": "person_name"}],
        "expected_answer_type": "player_name",
        "target_intent": "provide_english_name",
        "intent_description": "玩家需要告诉 NPC 自己的英文名。",
        "recent_turns": [
            {"speaker": "npc", "text": "我有点没听明白，是 Google 吗？怎么拼写呢？"},
            {"speaker": "player", "text": "Google"},
        ],
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text="Google",
        asr_confidence=0.62,
        language="cn_en",
        context=name_context,
    )

    assert result["intent_matched"] is False
    assert result["guidance"] == {"npc_line": None}


# ── 单字母 / 封闭题上下文回归（issue: asr 只有一个字母时纠错与意图识别结果不对）──


def _candidate_only_context() -> dict:
    """归卷厅字母精灵场景：客户端只传 candidate_answers + expected_answer_type，
    没有 npc_question / expected_slots。"""
    return {
        "scene_id": "word_spirit_library_archive_hall",
        "npc_id": "archive_guardian",
        "player_level": "grade4",
        "language": "en",
        "expected_answer_type": "letter_name",
        "candidate_answers": ["A"],
    }


@pytest.mark.asyncio
async def test_candidate_answers_without_npc_question_or_slots_goes_to_llm(monkeypatch):
    """H1: 有 candidate_answers（封闭题）即使缺 npc_question/expected_slots，
    也不该走 missing_context fallback，应进入 LLM 路径并应用纠错。"""

    async def create(**kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "A",
                    "correction_applied": True,
                    "correction_reason": "候选答案 A 与原始文本匹配，清洗噪声。",
                    "extracted": {},
                    "intent_matched": True,
                    "intent": "provide",
                    "guidance": {"npc_line": None},
                    "confidence": 0.9,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text=" A....",
        asr_confidence=0.9,
        language="en",
        context=_candidate_only_context(),
    )

    assert result["applied"] is True
    assert result["fallback_reason"] is None
    assert result["corrected_text"] == "A"
    assert result["intent"] == "provide"
    assert result["intent_matched"] is True


@pytest.mark.asyncio
async def test_missing_context_fallback_does_not_claim_provide(monkeypatch):
    """H2: 上下文不充分导致的 missing_context fallback 不应声称玩家提供了槽位值。
    系统 intent 应为 off_topic / intent_matched=False，与 'applied=False, confidence=0.0' 一致。"""
    create = AsyncMock()
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": create})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text=" A....",
        asr_confidence=0.9,
        language="en",
        context=None,
    )

    assert result["applied"] is False
    assert result["fallback_reason"] == "missing_context"
    assert result["intent"] == "off_topic"
    assert result["intent_matched"] is False
    assert result["confidence"] == 0.0
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_system_failure_fallback_still_tolerates_provide(monkeypatch):
    """H2 回归: 系统故障类 fallback（timeout/provider_error 等）保持容错放行，
    不因 H2 改动而把网络抖动误判为玩家未作答。"""
    calls = 0

    async def fake_create(**_kwargs):
        nonlocal calls
        calls += 1
        request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
        raise openai.APITimeoutError(request=request)

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_TIMEOUT_MS", "1")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=fake_create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text=" A....",
        asr_confidence=0.9,
        language="en",
        context=_candidate_only_context(),
    )

    assert result["fallback_reason"] == "timeout"
    # 系统故障时保持容错: 客户端可用原始文本继续, 不误判为 off_topic
    assert result["intent"] == "provide"
    assert result["intent_matched"] is True


# ── 非对话任务跳过 postprocess（归卷厅：字母识别/朗读/回放自评/指令）──


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "task_mode",
    ["open_greeting", "letter_recognition", "word_pronunciation", "playback_self_eval", "exit_command"],
)
async def test_non_dialogue_task_mode_skips_postprocess(monkeypatch, task_mode):
    """归卷厅非对话任务由场景声明 task_mode，voice-service 跳过 LLM postprocess，
    原样透传文本供客户端本地分类。不判 missing_context/off_topic，不调 LLM。"""
    create = AsyncMock()
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": create})()})()
    postprocessor = ASRPostprocessor(client=client)

    result = await postprocessor.process(
        text=" A.",
        asr_confidence=0.9,
        language="en",
        context={
            "scene_id": "word_spirit_library_archive_hall",
            "task_mode": task_mode,
            "expected_answer_type": "letter_name",
            "candidate_answers": [],
        },
    )

    assert result["applied"] is False
    assert result["fallback_reason"] == "non_dialogue_task"
    assert result["corrected_text"] == " A."
    # 非对话任务 voice-service 不做意图判定，中性放行让客户端用原始文本分类
    assert result["intent"] == "provide"
    assert result["intent_matched"] is True
    create.assert_not_awaited()


@pytest.mark.asyncio
async def test_dialogue_task_mode_still_uses_llm(monkeypatch):
    """显式 task_mode=dialogue 或缺省仍走对话 postprocess（不跳过）。"""

    async def create(**kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "A",
                    "correction_applied": True,
                    "correction_reason": "候选匹配。",
                    "extracted": {},
                    "intent_matched": True,
                    "intent": "provide",
                    "guidance": {"npc_line": None},
                    "confidence": 0.9,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()
    postprocessor = ASRPostprocessor(client=client)

    ctx = _candidate_only_context()
    ctx["task_mode"] = "dialogue"
    result = await postprocessor.process(
        text=" A....",
        asr_confidence=0.9,
        language="en",
        context=ctx,
    )

    assert result["applied"] is True
    assert result["fallback_reason"] is None


# ────────────────── 规则层接入生产路径（ADR-0009 §4，2026-09-16）──────────────────
# 此前规则层只有两层证据：单元测试（tests/test_intent_rules.py）与离线回放
# （scripts/replay_intent_rules.py，跑在存量模型输出上）。下面把**生产路径**钉住：
# 判据字段要真的发出去、两处合法性归一要真的生效、且规则层不得覆盖模型的好值。


def _stub_client(payload: dict) -> tuple[openai.AsyncOpenAI, dict]:
    """构造只回一段固定 JSON 的 provider 客户端。"""
    captured: dict = {}

    async def create(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(
            choices=[
                SimpleNamespace(
                    message=SimpleNamespace(content=json.dumps(payload, ensure_ascii=False)),
                    finish_reason="stop",
                )
            ],
            model_dump=lambda mode="json": {"model": "stub"},
        )

    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = SimpleNamespace(completions=SimpleNamespace(create=create))
    return client, captured


def _payload(**overrides) -> dict:
    base = {
        "corrected_text": "书架",
        "correction_applied": False,
        "correction_reason": None,
        "extracted": {"answer": "书架"},
        "intent_matched": True,
        "intent": "provide",
        "guidance": {"npc_line": None},
        "confidence": 0.9,
    }
    base.update(overrides)
    return base


@pytest.mark.asyncio
async def test_postprocessor_surfaces_rule_verdict_fields(monkeypatch):
    """规则层确认命中时，判决来源与判据必须随响应发出去（客户端据此复核）。"""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client, _ = _stub_client(_payload())

    result = await ASRPostprocessor(client=client).process(
        text="书架",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["intent"] == "provide"
    assert result["extracted"] == {"answer": "书架"}
    assert result["verdict_source"] == "rule", "命中候选应由规则层给出取值"
    assert result["matched_candidate"] == "书架"
    assert result["matched_rule"] is not None, "判决必须带可复核的规则名"


@pytest.mark.asyncio
async def test_postprocessor_clears_value_when_candidate_unconfirmed_but_keeps_intent(monkeypatch):
    """确认不了命中 → 弃权清空取值，但**绝不改判意图**（rule_003 情形 2）。

    把"答对了的孩子"判成没作答（F2）比留下一个可疑取值更糟，所以意图必须保持 provide。
    """
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client, _ = _stub_client(
        _payload(corrected_text="这个我不知道", extracted={"answer": "这个我不知道"})
    )

    result = await ASRPostprocessor(client=client).process(
        text="这个我不知道",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["intent"] == "provide", "规则层不得把 provide 改判成 off_topic"
    assert result["extracted"] == {}, "确认不了命中时应清空取值，让客户端退回 corrected_text"
    assert result["verdict_source"] == "llm", "弃权后判决仍归模型"


@pytest.mark.asyncio
async def test_postprocessor_downgrades_delegate_on_non_delegatable_slot(monkeypatch):
    """rule_005 合法性归一：槽位没声明 delegatable 时 delegate 没有完成器 → off_topic。"""
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client, _ = _stub_client(
        _payload(intent="delegate", intent_matched=False, extracted={})
    )

    result = await ASRPostprocessor(client=client).process(
        text="你帮我起一个吧",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "你的英文名是什么？",
            # 注意：这里**故意**不写 delegatable，与上面三个透传用例形成对照
            "expected_slots": [{"key": "english_name", "type": "person_name"}],
            "expected_answer_type": "player_name",
        },
    )

    assert result["intent"] == "off_topic"
    assert result["intent_matched"] is False
    assert result["matched_rule"] == "delegate_requires_delegatable"
    assert result["guidance"] == {"npc_line": None}, "降级后不得留下没有消费者的代选建议"


@pytest.mark.asyncio
async def test_postprocessor_downgrades_retraction_after_target(monkeypatch):
    """rule_010 合法性归一：命中口令后紧跟撤回 → off_topic。

    这是客户端 `_is_retraction_downgrade`（续行门控）赖以生效的前置条件：
    缺少 `matched_rule` 时客户端只能放行，玩家会在"出发…等一下"时被切场景。
    """
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client, _ = _stub_client(
        _payload(corrected_text="出发，等一下", extracted={"answer": "出发"})
    )

    result = await ASRPostprocessor(client=client).process(
        text="出发，等一下",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "准备好了就说出发。",
            "expected_slots": [{"key": "answer", "type": "keyword"}],
            "expected_answer_type": "keyword",
            "candidate_answers": ["出发", "走吧", "继续"],
        },
    )

    assert result["intent"] == "off_topic"
    assert result["matched_rule"] == "retraction_after_target"
    assert result["extracted"] == {}


@pytest.mark.asyncio
async def test_postprocessor_keeps_clean_free_slot_value_from_model(monkeypatch):
    """回归：自由槽的好值不该被规则层重算覆盖（生产接入时由集成测试发现的缺陷）。

    实测：文本「我叫小北，你是谁？」时模型正确给出「小北」，而规则层按壳与标点重算会得到
    「小北你是谁」——把 NPC 的问句粘进了名字。规则层只该修坏值，不该覆盖好值。
    """
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    client, _ = _stub_client(
        _payload(corrected_text="我叫小北，你是谁？", extracted={"name": "小北"})
    )

    result = await ASRPostprocessor(client=client).process(
        text="我叫小北，你是谁？",
        asr_confidence=0.9,
        language="cn_en",
        context={
            "npc_question": "告诉腓腓你的中文名就可以。",
            "expected_slots": [{"key": "name", "type": "person_name"}],
            "expected_answer_type": "player_name",
        },
    )

    assert result["extracted"] == {"name": "小北"}, "模型给出的更紧取值必须被采纳"
    # 判决仍归模型（值也是模型给的），但"采纳"这个动作由 rule_013 做，故记规则名供复核
    assert result["verdict_source"] == "llm", "采纳模型值不等于规则层做了判决"
    assert result["matched_rule"] == "free_slot_model_value_tighter"


@pytest.mark.asyncio
async def test_postprocessor_abstains_on_homophone_it_cannot_verify(monkeypatch):
    """**已知边界**：ADR-0009 §9 声明的"拼音/近音"匹配维**尚未实现**。

    规则层里只有 `RuleOptions.phonetic` 这个配置项，没有任何实现（需 pypinyin 依赖）。
    因此当模型的 corrected_text 与玩家原话之间是**同音改写**（暑假→书架）时，规则层在
    **原始文本**上确认不了命中 → 弃权清空 extracted。后果是安全的：

    - `corrected_text` 原样透出，客户端 `_asr_answer_text` 在 extracted 为空时回退到它 →
      玩家看到的仍然是「书架」；
    - 只是这条取值**没有**规则层背书（verdict_source=llm、extracted={}），客户端按"待确认"处理，
      不会直接落定槽位。

    这个边界是被"决策跑原始 ASR 文本"这条正确改动**暴露**出来的：此前决策跑在 corrected_text 上，
    模型的纠正被当成了玩家原话，同音维的缺失因此被掩盖——同时也掩盖了 rule_004 最怕的那种误判
    （模型把学习错误纠成满分答案后，规则层在纠正后的文本上"确认"它）。
    """
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")

    async def create(**kwargs):
        return openai_completion(
            json.dumps(
                {
                    "corrected_text": "书架",
                    "correction_applied": True,
                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                    "extracted": {"answer": "书架"},
                    "intent_matched": True,
                    "intent": "provide",
                    "guidance": {"npc_line": None},
                    "confidence": 0.88,
                },
                ensure_ascii=False,
            ),
            "mock-model",
        )

    client = openai.AsyncOpenAI(api_key="test-key", base_url="https://llm.test/v1")
    client.chat = type("Chat", (), {"completions": type("Completions", (), {"create": AsyncMock(side_effect=create)})()})()

    result = await ASRPostprocessor(client=client).process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=CONTEXT,
    )

    assert result["intent"] == "provide", "意图仍归模型，规则层弃权不改判"
    assert result["extracted"] == {}, "确认不了命中 → 弃权清空（而不是照抄模型的值）"
    assert result["corrected_text"] == "书架", "模型的纠错文本原样透出，客户端据此回退"
    assert result["verdict_source"] == "llm"
