import os
from openai import AsyncOpenAI
from dataclasses import dataclass


@dataclass
class ASRResult:
    text: str
    confidence: float
    language: str


class WhisperService:
    def __init__(self):
        api_key = os.environ.get("OPENAI_API_KEY", "dev-key")
        self.client = AsyncOpenAI(api_key=api_key)

    async def transcribe(self, audio_bytes: bytes, language: str = "en") -> ASRResult:
        """Transcribe audio bytes to text using Whisper API."""
        import io
        audio_file = io.BytesIO(audio_bytes)
        audio_file.name = "audio.wav"

        response = await self.client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            language=language,
            response_format="verbose_json"
        )

        return ASRResult(
            text=response.text,
            confidence=1.0 - (getattr(response, 'word_confidence', [0.9])[0] if hasattr(response, 'word_confidence') else 0.1),
            language=language
        )


whisper_service = WhisperService()
