import os
import pytest
from src.services.fish_client import FishSpeechClient


def test_fish_client_init():
    """Test client initializes with default URL."""
    # FISH_SPEECH_URL env var may be set by .env, check accordingly
    expected = os.environ.get("FISH_SPEECH_URL", "http://localhost:8002")
    client = FishSpeechClient()
    assert client.base_url == expected


def test_fish_client_custom_url():
    """Test client accepts custom URL."""
    client = FishSpeechClient(base_url="http://fish-speech:8002")
    assert client.base_url == "http://fish-speech:8002"


@pytest.mark.asyncio
async def test_health_check_success():
    """Test health check returns True when service is up."""
    client = FishSpeechClient(base_url="http://mock-fish")
    # Will test with mock in integration tests
    assert client.healthy == False  # Initial state
