"""Voice reference audio manager for TTS."""

import base64
import logging
from pathlib import Path

logger = logging.getLogger(__name__)


class VoiceReferenceManager:
    """Manage preset and dynamic reference audio for voice cloning."""

    VOICE_PATHS = {
        "scholar": "assets/voices/scholar.wav",
        "merchant": "assets/voices/merchant.wav",
        "storyteller": "assets/voices/storyteller.wav",
        "receptionist": "assets/voices/receptionist.wav",
        "street_child": "assets/voices/street_child.wav",
        "spirit": "assets/voices/spirit.wav",
    }

    def __init__(self, base_path: str | None = None):
        self.base_path = Path(base_path) if base_path else Path.cwd()

    def get_reference(self, voice_id: str) -> bytes | None:
        """Get reference audio bytes by voice_id.

        Supports:
        - Preset names (spirit, scholar, etc.)
        - base64://... (inline base64 audio)
        - https://... (URL to download)

        Args:
            voice_id: Voice identifier

        Returns:
            Reference audio bytes or None
        """
        parsed = self._parse_voice_id(voice_id)

        if parsed["type"] == "preset":
            return self._load_preset(parsed["value"])
        elif parsed["type"] == "base64":
            return parsed["data"]
        elif parsed["type"] == "url":
            return self._download(parsed["value"])
        else:
            return None

    def _parse_voice_id(self, voice_id: str) -> dict:
        """Parse voice_id into type and value."""
        if voice_id.startswith("base64://"):
            return {
                "type": "base64",
                "value": voice_id,
                "data": base64.b64decode(voice_id[9:]),
            }
        elif voice_id.startswith("http://") or voice_id.startswith("https://"):
            return {"type": "url", "value": voice_id}
        elif voice_id in self.VOICE_PATHS:
            return {"type": "preset", "value": voice_id}
        else:
            return {"type": "unknown", "value": voice_id}

    def _load_preset(self, voice_name: str) -> bytes | None:
        """Load preset reference audio from file."""
        path = self.base_path / self.VOICE_PATHS[voice_name]
        if path.exists():
            logger.info(f"Loaded preset reference: {voice_name}")
            return path.read_bytes()
        logger.warning(f"Preset reference file not found: {path}")
        return None

    def _download(self, url: str) -> bytes | None:
        """Download reference audio from URL."""
        import httpx

        try:
            resp = httpx.get(url, timeout=10.0, follow_redirects=True)
            resp.raise_for_status()
            logger.info(f"Downloaded reference audio from: {url}")
            return resp.content
        except Exception as e:
            logger.error(f"Failed to download reference audio: {e}")
            return None
