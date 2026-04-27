import pytest
from unittest.mock import patch, AsyncMock
from httpx import AsyncClient, ASGITransport
from src.main import app
from src.services.whisper import ASRResult


@pytest.mark.asyncio
async def test_asr_endpoint():
    with patch('src.api.routes.asr.whisper_service.transcribe', new_callable=AsyncMock) as mock_transcribe:
        mock_transcribe.return_value = ASRResult(text="Hello world", confidence=0.95, language="en")

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/voice/asr",
                files={"audio": ("test.wav", b"fake-audio-data", "audio/wav")},
                data={"language": "en"}
            )

        assert response.status_code == 200
        data = response.json()
        assert data["text"] == "Hello world"
        assert data["confidence"] == 0.95


@pytest.mark.asyncio
async def test_tts_endpoint():
    with patch('src.api.routes.tts.tts_service.synthesize_audio', new_callable=AsyncMock) as mock_synthesize:
        mock_synthesize.return_value = "base64encodedaudio"

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/voice/tts",
                json={"text": "Hello world", "voice_id": "spirit", "language": "en"}
            )

        assert response.status_code == 200
        data = response.json()
        assert "audio_data" in data
        assert data["duration_ms"] == 550
