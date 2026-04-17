from fastapi import APIRouter, UploadFile, File, Form
from src.services.whisper import whisper_service

router = APIRouter()


@router.post("/api/v1/voice/asr")
async def transcribe(
    audio: UploadFile = File(...),
    language: str = Form(default="en")
):
    audio_bytes = await audio.read()
    result = await whisper_service.transcribe(audio_bytes, language)
    return {
        "text": result.text,
        "confidence": result.confidence,
        "language": result.language
    }
