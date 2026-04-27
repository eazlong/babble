import os
import base64
import struct
import logging
from dataclasses import dataclass
from elevenlabs.client import ElevenLabs

from src.services.fish_client import FishSpeechClient
from src.services.ref_manager import VoiceReferenceManager

logger = logging.getLogger(__name__)


@dataclass
class TTSResult:
    audio_url: str
    duration_ms: int


class TTSService:
    """Unified TTS service with Fish Speech primary and ElevenLabs fallback."""

    def __init__(self):
        self.api_key = os.environ.get("ELEVENLABS_API_KEY", "")
        self.default_voice_id = "jBpfuIX1Pn7vGtT5LBcL"

        # Fish Speech client
        self.fish_client = FishSpeechClient()
        self.fish_available = False

        # Reference manager
        self.ref_manager = VoiceReferenceManager()

        # ElevenLabs fallback
        if self.api_key:
            self.elevenlabs = ElevenLabs(api_key=self.api_key)
            logger.info("ElevenLabs fallback initialized")
        else:
            self.elevenlabs = None
            logger.warning("No ElevenLabs API key - using silent fallback")

    async def init(self):
        """Initialize Fish Speech connection."""
        self.fish_available = await self.fish_client.health_check()
        if not self.fish_available:
            logger.warning("Fish Speech unavailable, using fallback")

    async def synthesize_audio(self, text: str, voice_id: str = "spirit") -> tuple[str, str]:
        """Synthesize text and return (base64 encoded audio, format).

        Returns:
            Tuple of (base64_audio, format_string)
        """
        # Try Fish Speech first
        if self.fish_available:
            try:
                ref_audio = self.ref_manager.get_reference(voice_id)
                audio_bytes = await self.fish_client.synthesize(text, ref_audio)
                return base64.b64encode(audio_bytes).decode("utf-8"), "wav"
            except Exception as e:
                logger.error(f"Fish Speech error: {e}, falling back")

        # Fallback to ElevenLabs
        if self.elevenlabs:
            try:
                target_voice = voice_id if voice_id != "spirit" else self.default_voice_id
                audio = self.elevenlabs.text_to_speech.convert(
                    text=text,
                    voice_id=target_voice,
                    model_id="eleven_multilingual_v2",
                    output_format="mp3_44100_128",
                )
                audio_bytes = b"".join(audio)
                return base64.b64encode(audio_bytes).decode("utf-8"), "mp3"
            except Exception as e:
                logger.error(f"ElevenLabs error: {e}")

        # Silent fallback
        return self._generate_silent_wav(duration_ms=len(text) * 50), "wav"

    def _generate_silent_wav(self, duration_ms: int = 1000) -> str:
        """Generate a valid silent WAV file as base64."""
        sample_rate = 22050
        bits_per_sample = 16
        num_channels = 1

        num_samples = int(sample_rate * duration_ms / 1000)
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        data_size = num_samples * block_align

        header = bytearray()
        header.extend(b"RIFF")
        header.extend(struct.pack("<I", 36 + data_size))
        header.extend(b"WAVE")
        header.extend(b"fmt ")
        header.extend(struct.pack("<I", 16))
        header.extend(struct.pack("<H", 1))
        header.extend(struct.pack("<H", num_channels))
        header.extend(struct.pack("<I", sample_rate))
        header.extend(struct.pack("<I", byte_rate))
        header.extend(struct.pack("<H", block_align))
        header.extend(struct.pack("<H", bits_per_sample))
        header.extend(b"data")
        header.extend(struct.pack("<I", data_size))

        silent_data = bytearray(data_size)
        wav_bytes = header + silent_data
        return base64.b64encode(wav_bytes).decode("utf-8")


# Singleton instance
tts_service = TTSService()
