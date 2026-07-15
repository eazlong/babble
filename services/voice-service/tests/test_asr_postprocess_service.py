import json
from unittest.mock import AsyncMock

import httpx
import pytest

from src.services.asr_postprocess import ASRPostprocessor


CONTEXT = {
    "npc_question": "这个家具是什么？",
    "expected_slots": [{"key": "answer", "type": "string"}],
    "expected_answer_type": "object_name",
    "candidate_answers": ["书架", "椅子", "桌子", "床"],
}


@pytest.mark.asyncio
async def test_postprocessor_returns_missing_context_without_llm(monkeypatch):
    process = AsyncMock()
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    postprocessor = ASRPostprocessor(client=type("Client", (), {"post": process})())

    result = await postprocessor.process(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=None,
    )

    assert result["applied"] is False
    assert result["corrected_text"] == "暑假"
    assert result["extracted"] == {}
    assert result["fallback_reason"] == "missing_context"
    process.assert_not_awaited()


@pytest.mark.asyncio
async def test_postprocessor_maps_valid_llm_output(monkeypatch):
    async def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content.decode("utf-8"))
        assert body["response_format"] == {"type": "json_object"}
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "corrected_text": "书架",
                                    "correction_applied": True,
                                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                                    "extracted": {"answer": "书架"},
                                    "confidence": 0.88,
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            },
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    monkeypatch.setenv("ASR_POSTPROCESS_MODEL", "mock-model")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://llm.test") as client:
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
    assert result["confidence"] == 0.88
    assert result["fallback_reason"] is None
    assert result["model"] == "mock-model"


@pytest.mark.asyncio
async def test_postprocessor_drops_extracted_keys_not_declared_in_expected_slots(monkeypatch):
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "corrected_text": "书架",
                                    "correction_applied": True,
                                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                                    "extracted": {"answer": "书架", "extra": "不要透传"},
                                    "confidence": 0.88,
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            },
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://llm.test") as client:
        postprocessor = ASRPostprocessor(client=client)

        result = await postprocessor.process(
            text="暑假",
            asr_confidence=0.9,
            language="cn_en",
            context=CONTEXT,
        )

    assert result["applied"] is True
    assert result["extracted"] == {"answer": "书架"}


@pytest.mark.asyncio
async def test_postprocessor_prompt_contains_conservative_schema_rules(monkeypatch):
    captured_body = {}

    async def handler(request: httpx.Request) -> httpx.Response:
        captured_body.update(json.loads(request.content.decode("utf-8")))
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "corrected_text": "我叫大飞，大小的大，飞行的飞",
                                    "correction_applied": False,
                                    "correction_reason": None,
                                    "extracted": {"name": "大飞"},
                                    "confidence": 0.93,
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            },
        )

    name_context = {
        "npc_question": "你叫什么名字？",
        "expected_slots": [{"key": "name", "type": "person_name"}],
        "expected_answer_type": "player_name",
    }
    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://llm.test") as client:
        postprocessor = ASRPostprocessor(client=client)

        await postprocessor.process(
            text="我叫大飞，大小的大，飞行的飞",
            asr_confidence=0.9,
            language="cn_en",
            context=name_context,
        )

    system_prompt = captured_body["messages"][0]["content"]
    user_prompt = json.loads(captured_body["messages"][1]["content"])
    assert "Be conservative" in system_prompt
    assert "Extract only the slots listed in expected_slots" in system_prompt
    assert "candidate_answers" in system_prompt
    assert user_prompt["context"]["expected_slots"][0]["key"] == "name"
    assert user_prompt["return_shape"] == {
        "corrected_text": "string",
        "correction_applied": "boolean",
        "correction_reason": "string|null",
        "extracted": "object containing only expected_slots keys",
        "confidence": "number 0..1",
    }


@pytest.mark.asyncio
async def test_postprocessor_falls_back_on_schema_extra_fields(monkeypatch):
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "choices": [
                    {
                        "message": {
                            "content": json.dumps(
                                {
                                    "corrected_text": "书架",
                                    "correction_applied": True,
                                    "correction_reason": "家具题且候选答案书架与暑假音近。",
                                    "extracted": {"answer": "书架"},
                                    "confidence": 0.88,
                                    "unexpected": "不要透传",
                                },
                                ensure_ascii=False,
                            )
                        }
                    }
                ]
            },
        )

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://llm.test") as client:
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
    async def handler(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, json={"choices": [{"message": {"content": "not-json"}}]})

    monkeypatch.setenv("OPENAI_API_KEY", "test-key")
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler), base_url="https://llm.test") as client:
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
