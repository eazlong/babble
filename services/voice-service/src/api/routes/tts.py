from fastapi import APIRouter
from fastapi.responses import Response
from pydantic import BaseModel
from src.services.tts import tts_service

router = APIRouter()


class TTSRequest(BaseModel):
    text: str
    voice_id: str = "spirit"
    language: str = "en"


@router.post("/api/v1/voice/tts")
async def synthesize_speech(req: TTSRequest):
    """Return audio data directly as base64."""
    audio_data, format_type = await tts_service.synthesize_audio(req.text, req.voice_id)
    return {
        "audio_data": audio_data,
        "duration_ms": len(req.text) * 50,
        "format": format_type
    }
