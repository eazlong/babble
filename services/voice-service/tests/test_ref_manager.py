import pytest
from src.services.ref_manager import VoiceReferenceManager


def test_ref_manager_init():
    """Test manager initializes with voice paths."""
    manager = VoiceReferenceManager()
    assert "spirit" in manager.VOICE_PATHS
    assert "scholar" in manager.VOICE_PATHS


def test_parse_voice_id_preset():
    """Test parsing preset voice_id."""
    manager = VoiceReferenceManager()
    # Spirit is a preset - returns None if file doesn't exist
    ref = manager.get_reference("spirit")
    assert ref is None  # File doesn't exist yet


def test_parse_voice_id_base64():
    """Test parsing base64 voice_id."""
    manager = VoiceReferenceManager()
    ref = manager.get_reference("base64://SGVsbG8gV29ybGQ=")
    assert ref == b"Hello World"


def test_parse_voice_id_url():
    """Test parsing URL voice_id."""
    manager = VoiceReferenceManager()
    # URL type detection
    voice_id = manager._parse_voice_id("https://example.com/voice.wav")
    assert voice_id["type"] == "url"
    assert voice_id["value"] == "https://example.com/voice.wav"


def test_parse_voice_id_unknown():
    """Test unknown voice_id returns None."""
    manager = VoiceReferenceManager()
    ref = manager.get_reference("unknown_voice")
    assert ref is None
