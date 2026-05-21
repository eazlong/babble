"""F5-TTS HTTP client for local TTS."""

import os
import httpx
import logging

logger = logging.getLogger(__name__)


class FishSpeechClient:
    """Client for F5-TTS / Fish Speech TTS HTTP server.

    Supports both F5-TTS (/v1/tts with voice_id) and
    Fish Speech (/v1/tts with reference_audio) API formats.
    """

    def __init__(self, base_url: str | None = None):
        self.base_url = base_url or os.environ.get(
            "FISH_SPEECH_URL", "http://localhost:8002"
        )
        self.client = httpx.AsyncClient(timeout=30.0)
        self.healthy = False
        self.is_f5 = False  # Detected after health check
        logger.info(f"FishSpeechClient initialized with base_url: {self.base_url}")

    async def health_check(self) -> bool:
        """Check if TTS server is available and detect type."""
        try:
            resp = await self.client.get(f"{self.base_url}/health")
            if resp.status_code == 200:
                body = resp.json()
                # F5-TTS server returns {"model": "f5-tts-mlx"}
                self.is_f5 = body.get("model", "").startswith("f5")
                self.healthy = True
                server_type = "F5-TTS" if self.is_f5 else "Fish Speech"
                logger.info(f"Health check passed ({server_type})")
            else:
                self.healthy = False
                logger.warning(f"Health check failed: {resp.status_code}")
        except Exception as e:
            self.healthy = False
            logger.warning(f"Health check error: {e}")
        return self.healthy

    async def synthesize(
        self, text: str, voice_id: str = "spirit"
    ) -> bytes:
        """Synthesize text to audio.

        Args:
            text: Text to synthesize
            voice_id: Voice identifier (resolved server-side via voices.json)

        Returns:
            Audio bytes
        """
        payload = {"text": text, "voice_id": voice_id}

        try:
            resp = await self.client.post(
                f"{self.base_url}/v1/tts",
                json=payload,
                timeout=60.0,
            )
            resp.raise_for_status()
            logger.info(f"Synthesized: {len(resp.content)} bytes")
            return resp.content
        except httpx.HTTPStatusError as e:
            logger.error(f"API error: {e.response.status_code} - {e.response.text}")
            raise
        except Exception as e:
            logger.error(f"Synthesis error: {e}")
            raise

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()
