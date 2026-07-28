import base64
import json
import logging
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from src.main import app
from src.services.whisper import ASRResult


FURNITURE_CONTEXT = {
    "npc_question": "这个家具是什么？",
    "expected_slots": [
        {"key": "answer", "type": "string", "description": "玩家对 NPC 问题的答案"}
    ],
    "expected_answer_type": "object_name",
    "candidate_answers": ["书架", "椅子", "桌子", "床"],
}


async def post_multipart(path: str, data: dict[str, str] | None = None):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.post(
            path,
            files={"audio": ("test.wav", b"fake-audio-data", "audio/wav")},
            data={"language": "cn_en", **(data or {})},
        )


async def post_json(context: dict | None = None):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        payload = {
            "audio_data": base64.b64encode(b"fake-audio-data").decode("utf-8"),
            "lang": "cn_en",
        }
        if context is not None:
            payload["context"] = context
        return await client.post("/api/v1/voice/asr/json", json=payload)


async def post_asr_endpoint(endpoint: str, context: dict | None = None):
    if endpoint == "/api/v1/voice/asr/json":
        return await post_json(context=context)
    data = None
    if context is not None:
        data = {"context": __import__("json").dumps(context, ensure_ascii=False)}
    return await post_multipart(endpoint, data=data)


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/api/v1/voice/asr", "/asr/recognize"])
async def test_multipart_asr_returns_postprocess_missing_context(path):
    with patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe:
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")

        response = await post_multipart(path)

    assert response.status_code == 200
    data = response.json()
    assert data["text"] == "暑假"
    assert data["confidence"] == 0.9
    assert data["language"] == "cn_en"
    assert data["postprocess"] == {
        "applied": False,
        "corrected_text": "暑假",
        "correction_reason": None,
        "extracted": {},
        "intent_matched": False,
        "intent": "off_topic",
        "guidance": {"npc_line": None},
        "confidence": 0.0,
        "fallback_reason": "missing_context",
        "model": None,
        "latency_ms": 0,
    }


@pytest.mark.asyncio
async def test_json_asr_returns_postprocess_missing_context():
    with patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe:
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")

        response = await post_json()

    assert response.status_code == 200
    assert response.json()["postprocess"]["fallback_reason"] == "missing_context"


@pytest.mark.asyncio
async def test_json_asr_uses_postprocessor_with_context():
    postprocess_result = {
        "applied": True,
        "corrected_text": "书架",
        "correction_reason": "家具题且候选答案书架与暑假音近。",
        "extracted": {"answer": "书架"},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.88,
        "fallback_reason": None,
        "model": "mock-model",
        "latency_ms": 12,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        response = await post_json(context=FURNITURE_CONTEXT)

    assert response.status_code == 200
    data = response.json()
    assert data["text"] == "暑假"
    assert data["postprocess"] == postprocess_result
    mock_process.assert_awaited_once_with(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=FURNITURE_CONTEXT,
    )


@pytest.mark.asyncio
async def test_multipart_asr_uses_postprocessor_with_context():
    postprocess_result = {
        "applied": True,
        "corrected_text": "书架",
        "correction_reason": "家具题且候选答案书架与暑假音近。",
        "extracted": {"answer": "书架"},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.88,
        "fallback_reason": None,
        "model": "mock-model",
        "latency_ms": 12,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        response = await post_multipart(
            "/api/v1/voice/asr",
            data={"context": __import__("json").dumps(FURNITURE_CONTEXT, ensure_ascii=False)},
        )

    assert response.status_code == 200
    data = response.json()
    assert data["text"] == "暑假"
    assert data["postprocess"] == postprocess_result
    mock_process.assert_awaited_once_with(
        text="暑假",
        asr_confidence=0.9,
        language="cn_en",
        context=FURNITURE_CONTEXT,
    )


@pytest.mark.asyncio
async def test_multipart_asr_logs_postprocess_context(caplog):
    postprocess_result = {
        "applied": False,
        "corrected_text": "暑假",
        "correction_reason": None,
        "extracted": {},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.0,
        "fallback_reason": "missing_context",
        "model": None,
        "latency_ms": 0,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        with caplog.at_level(logging.INFO, logger="src.api.routes.asr"):
            response = await post_multipart("/api/v1/voice/asr")

    assert response.status_code == 200
    assert "[ASR-POSTPROCESS] request endpoint=/api/v1/voice/asr" in caplog.text
    assert "context_present=False" in caplog.text
    assert "[ASR-POSTPROCESS] response text_len=2 applied=False fallback_reason=missing_context" in caplog.text


@pytest.mark.asyncio
async def test_json_asr_logs_postprocess_success(caplog):
    postprocess_result = {
        "applied": True,
        "corrected_text": "书架",
        "correction_reason": "家具题且候选答案书架与暑假音近。",
        "extracted": {"answer": "书架"},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.88,
        "fallback_reason": None,
        "model": "mock-model",
        "latency_ms": 12,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        with caplog.at_level(logging.INFO, logger="src.api.routes.asr"):
            response = await post_json(context=FURNITURE_CONTEXT)

    assert response.status_code == 200
    assert "[ASR-POSTPROCESS] request endpoint=/api/v1/voice/asr/json" in caplog.text
    assert "context_present=True" in caplog.text
    assert "context_keys=['candidate_answers', 'expected_answer_type', 'expected_slots', 'npc_question']" in caplog.text
    assert "[ASR-POSTPROCESS] response text_len=2 applied=True fallback_reason=None" in caplog.text


@pytest.mark.asyncio
async def test_json_asr_returns_200_when_postprocess_falls_back():
    postprocess_result = {
        "applied": False,
        "corrected_text": "暑假",
        "correction_reason": None,
        "extracted": {},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.0,
        "fallback_reason": "timeout",
        "model": None,
        "latency_ms": 1500,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        response = await post_json(context=FURNITURE_CONTEXT)

    assert response.status_code == 200
    data = response.json()
    assert data["text"] == "暑假"
    assert data["postprocess"] == postprocess_result


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["/api/v1/voice/asr", "/asr/recognize", "/api/v1/voice/asr/json"])
async def test_all_asr_endpoints_share_success_contract(endpoint):
    postprocess_result = {
        "applied": True,
        "corrected_text": "书架",
        "correction_reason": "家具题且候选答案书架与暑假音近。",
        "extracted": {"answer": "书架"},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.88,
        "fallback_reason": None,
        "model": "mock-model",
        "latency_ms": 12,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        response = await post_asr_endpoint(endpoint, context=FURNITURE_CONTEXT)

    assert response.status_code == 200
    data = response.json()
    assert set(data.keys()) == {"text", "confidence", "language", "postprocess"}
    assert data["text"] == "暑假"
    assert data["confidence"] == 0.9
    assert data["language"] == "cn_en"
    assert data["postprocess"] == postprocess_result


@pytest.mark.asyncio
@pytest.mark.parametrize("endpoint", ["/api/v1/voice/asr", "/asr/recognize", "/api/v1/voice/asr/json"])
async def test_all_asr_endpoints_share_fallback_contract(endpoint):
    postprocess_result = {
        "applied": False,
        "corrected_text": "暑假",
        "correction_reason": None,
        "extracted": {},
        "intent_matched": True,
        "guidance": {"npc_line": None},
        "confidence": 0.0,
        "fallback_reason": "timeout",
        "model": None,
        "latency_ms": 1500,
    }

    with (
        patch("src.api.routes.asr.service_manager.transcribe", new_callable=AsyncMock) as mock_transcribe,
        patch("src.api.routes.asr.asr_postprocessor.process", new_callable=AsyncMock) as mock_process,
    ):
        mock_transcribe.return_value = ASRResult(text="暑假", confidence=0.9, language="cn_en")
        mock_process.return_value = postprocess_result

        response = await post_asr_endpoint(endpoint, context=FURNITURE_CONTEXT)

    assert response.status_code == 200
    data = response.json()
    assert set(data.keys()) == {"text", "confidence", "language", "postprocess"}
    assert data["text"] == "暑假"
    assert data["postprocess"] == postprocess_result
