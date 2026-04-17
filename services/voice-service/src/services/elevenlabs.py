import os
from dataclasses import dataclass


@dataclass
class TTSResult:
    audio_url: str
    duration_ms: int


class ElevenLabsService:
    def __init__(self):
        self.api_key = os.environ.get("ELEVENLABS_API_KEY", "dev-key")
        # MVP: 5 basic NPC voices
        self.voice_map = {
            "scholar": "scholar_voice_id",
            "merchant": "merchant_voice_id",
            "storyteller": "storyteller_voice_id",
            "receptionist": "receptionist_voice_id",
            "street_child": "street_child_voice_id",
            "spirit": "spirit_voice_id"
        }

    async def synthesize(self, text: str, voice_id: str = "spirit") -> TTSResult:
        """Synthesize text to audio using ElevenLabs."""
        import uuid
        audio_ref = f"tts/{uuid.uuid4()}.mp3"

        # MVP: Return placeholder; actual ElevenLabs call requires API key
        return TTSResult(audio_url=audio_ref, duration_ms=len(text) * 50)


elevenlabs_service = ElevenLabsService()
