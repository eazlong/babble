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
