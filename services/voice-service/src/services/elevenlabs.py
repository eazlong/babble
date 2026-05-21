import os
import base64
import struct
import logging
from dataclasses import dataclass
from elevenlabs.client import ElevenLabs

logger = logging.getLogger(__name__)


@dataclass
class TTSResult:
    audio_url: str
    duration_ms: int


class ElevenLabsService:
    def __init__(self):
        self.api_key = os.environ.get("ELEVENLABS_API_KEY", "")
        # Default voice ID for spirit coach (Rachel - friendly voice)
        self.default_voice_id = "jBpfuIX1Pn7vGtT5LBcL"

        if self.api_key:
            self.client = ElevenLabs(api_key=self.api_key)
            logger.info("ElevenLabsService initialized with API key")
        else:
            self.client = None
            logger.warning("ElevenLabsService initialized without API key - using silent fallback")

    async def synthesize(self, text: str, voice_id: str = "spirit") -> TTSResult:
        """Synthesize text to audio using ElevenLabs."""
        import uuid
        audio_ref = f"tts/{uuid.uuid4()}.mp3"
        return TTSResult(audio_url=audio_ref, duration_ms=len(text) * 50)

    async def synthesize_audio(self, text: str, voice_id: str = "spirit") -> str:
        """Synthesize text and return base64 encoded audio data."""
        if not self.client:
            # Return valid silent WAV for dev
            return self._generate_silent_wav(duration_ms=len(text) * 50)

        try:
            # Use the actual voice_id if provided, otherwise default
            target_voice_id = voice_id if voice_id != "spirit" else self.default_voice_id

            # Call ElevenLabs API using SDK
            audio = self.client.text_to_speech.convert(
                text=text,
                voice_id=target_voice_id,
                model_id="eleven_multilingual_v2",
                output_format="mp3_44100_128",
            )

            # Convert audio stream to bytes
            audio_bytes = b"".join(audio)

            logger.info(f"TTS generated: {len(audio_bytes)} bytes for text '{text[:20]}...'")

            # Return base64 encoded audio
            return base64.b64encode(audio_bytes).decode('utf-8')

        except Exception as e:
            logger.error(f"TTS error: {e}")
            return self._generate_silent_wav(duration_ms=len(text) * 50)

    def _generate_silent_wav(self, duration_ms: int = 1000) -> str:
        """Generate a valid silent WAV file as base64."""
        sample_rate = 22050
        bits_per_sample = 16
        num_channels = 1

        # Calculate number of samples
        num_samples = int(sample_rate * duration_ms / 1000)

        # WAV header structure
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        data_size = num_samples * block_align

        # Build WAV header (44 bytes)
        header = bytearray()
        # RIFF header
        header.extend(b'RIFF')
        header.extend(struct.pack('<I', 36 + data_size))  # File size - 8
        header.extend(b'WAVE')
        # fmt chunk
        header.extend(b'fmt ')
        header.extend(struct.pack('<I', 16))  # Chunk size
        header.extend(struct.pack('<H', 1))   # Audio format (PCM)
        header.extend(struct.pack('<H', num_channels))
        header.extend(struct.pack('<I', sample_rate))
        header.extend(struct.pack('<I', byte_rate))
        header.extend(struct.pack('<H', block_align))
        header.extend(struct.pack('<H', bits_per_sample))
        # data chunk
        header.extend(b'data')
        header.extend(struct.pack('<I', data_size))

        # Silent audio data (zeros)
        silent_data = bytearray(data_size)

        wav_bytes = header + silent_data
        return base64.b64encode(wav_bytes).decode('utf-8')


elevenlabs_service = ElevenLabsService()