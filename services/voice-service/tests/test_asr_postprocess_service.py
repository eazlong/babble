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
    assert captured["max_tokens"] == 800
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
