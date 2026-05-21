import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app
from src.services.tts import tts_service


@pytest.mark.asyncio
async def test_tts_endpoint_silent_fallback():
    """Test TTS endpoint returns silent WAV when no services available."""
    tts_service.fish_available = False
    tts_service.elevenlabs = None

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/voice/tts",
            json={"text": "Hello", "voice_id": "spirit"},
        )

    assert response.status_code == 200
    data = response.json()
    assert "audio_data" in data
    assert data["format"] == "wav"


@pytest.mark.asyncio
async def test_tts_with_custom_voice():
    """Test TTS endpoint handles custom voice_id in silent fallback."""
    tts_service.fish_available = False
    tts_service.elevenlabs = None

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.post(
            "/api/v1/voice/tts",
            json={
                "text": "Test",
                "voice_id": "scholar",
            },
        )

    assert response.status_code == 200
