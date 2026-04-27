"""Fish Speech HTTP client for local TTS."""

import os
import httpx
import base64
import logging

logger = logging.getLogger(__name__)


class FishSpeechClient:
    """Client for Fish Speech TTS HTTP server."""

    def __init__(self, base_url: str | None = None):
        self.base_url = base_url or os.environ.get(
            "FISH_SPEECH_URL", "http://localhost:8002"
        )
        self.client = httpx.AsyncClient(timeout=30.0)
        self.healthy = False
        logger.info(f"FishSpeechClient initialized with base_url: {self.base_url}")

    async def health_check(self) -> bool:
        """Check if Fish Speech server is available."""
        try:
            resp = await self.client.get(f"{self.base_url}/health")
            self.healthy = resp.status_code == 200
            if self.healthy:
                logger.info("Fish Speech health check passed")
            else:
                logger.warning(f"Fish Speech health check failed: {resp.status_code}")
        except Exception as e:
            self.healthy = False
            logger.warning(f"Fish Speech health check error: {e}")
        return self.healthy

    async def synthesize(
        self, text: str, ref_audio: bytes | None = None, output_format: str = "wav"
    ) -> bytes:
        """Synthesize text to audio using Fish Speech API.

        Args:
            text: Text to synthesize
            ref_audio: Optional reference audio for voice cloning
            output_format: Output format (wav or mp3)

        Returns:
            Audio bytes
        """
        payload = {
            "text": text,
            "output_format": output_format,
            "latency": "balanced",
        }

        if ref_audio:
            payload["reference_audio"] = base64.b64encode(ref_audio).decode()

        try:
            resp = await self.client.post(
                f"{self.base_url}/v1/tts",
                json=payload,
                timeout=30.0,
            )
            resp.raise_for_status()
            logger.info(f"Fish Speech synthesized: {len(resp.content)} bytes")
            return resp.content
        except httpx.HTTPStatusError as e:
            logger.error(f"Fish Speech API error: {e.response.status_code}")
            raise
        except Exception as e:
            logger.error(f"Fish Speech synthesis error: {e}")
            raise

    async def close(self):
        """Close the HTTP client."""
        await self.client.aclose()
