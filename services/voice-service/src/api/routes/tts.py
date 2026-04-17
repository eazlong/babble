from fastapi import APIRouter
from pydantic import BaseModel
from src.services.elevenlabs import elevenlabs_service

router = APIRouter()


class TTSRequest(BaseModel):
    text: str
    voice_id: str = "spirit"
    language: str = "en"


@router.post("/api/v1/voice/tts")
async def synthesize_speech(req: TTSRequest):
    result = await elevenlabs_service.synthesize(req.text, req.voice_id)
    return {"audio_url": result.audio_url, "duration_ms": result.duration_ms}
