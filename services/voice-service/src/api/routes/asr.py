import base64
from fastapi import APIRouter, UploadFile, File, Form
from pydantic import BaseModel
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


@router.post("/asr/recognize")
async def recognize_godot(
    audio: UploadFile = File(...),
    language: str = Form(default="en")
):
    """Godot client compatible endpoint (multipart form-data)."""
    audio_bytes = await audio.read()
    result = await whisper_service.transcribe(audio_bytes, language)
    return {
        "text": result.text,
        "confidence": result.confidence,
        "language": result.language
    }


class ASRRequest(BaseModel):
    audio_data: str  # base64 encoded
    lang: str = "en"


@router.post("/api/v1/voice/asr/json")
async def transcribe_json(req: ASRRequest):
    """Accept base64 audio in JSON body (Godot/Cocos clients)."""
    audio_bytes = base64.b64decode(req.audio_data)
    result = await whisper_service.transcribe(audio_bytes, req.lang)
    return {
        "text": result.text,
        "confidence": result.confidence,
        "language": result.language
    }
