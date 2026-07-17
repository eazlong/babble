import json
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
async def test_postprocessor_provider_error_does_not_retry(monkeypatch):
    calls = 0

    async def fake_create(**_kwargs):
        nonlocal calls
        calls += 1
        request = httpx.Request("POST", "https://llm.test/v1/chat/completions")
        response = httpx.Response(500, request=request, json={"error": "provider down"})
        raise openai.APIStatusError("provider down", response=response, body={"error": "provider down"})

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

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["fallback_reason"] == "provider_error"
    assert calls == 1


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
    assert result["intent_matched"] is True
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
        text="暑假",
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
        text="暑假",
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
    assert "Be conservative" in system_prompt
    assert "Extract only the slots listed in expected_slots" in system_prompt
    assert "candidate_answers" in system_prompt
    assert "Decide whether the player's answer satisfies target_intent" in system_prompt
    assert user_prompt["context"]["expected_slots"][0]["key"] == "name"
    assert user_prompt["return_shape"] == {
        "corrected_text": "string",
        "correction_applied": "boolean",
        "correction_reason": "string|null",
        "extracted": "object containing only expected_slots keys",
        "intent_matched": "boolean",
        "guidance": {"npc_line": "string|null"},
        "confidence": "number 0..1",
    }


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
async def test_postprocessor_falls_back_on_invalid_json(monkeypatch):
    async def create(**_kwargs):
        return openai_completion("not-json", "mock-model")

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
    assert result["fallback_reason"] == "invalid_json"
