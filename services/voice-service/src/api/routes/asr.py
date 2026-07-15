import base64
import json
from typing import Any

from fastapi import APIRouter, UploadFile, File, Form
from pydantic import BaseModel
from src.services.service_manager import service_manager
from src.services.asr_postprocess import asr_postprocessor

router = APIRouter()


def parse_context(raw_context: str | None) -> dict[str, Any] | None:
    if not raw_context:
        return None
    try:
        parsed = json.loads(raw_context)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


async def build_asr_response(result, context: dict[str, Any] | None):
    postprocess = await asr_postprocessor.process(
        text=result.text,
        asr_confidence=result.confidence,
        language=result.language,
        context=context,
    )
    return {
        "text": result.text,
        "confidence": result.confidence,
        "language": result.language,
        "postprocess": postprocess,
    }


@router.post("/api/v1/voice/asr")
async def transcribe(
    audio: UploadFile = File(...),
    language: str = Form(default="en"),
    context: str | None = Form(default=None),
):
    audio_bytes = await audio.read()
    # 使用ServiceManager处理引擎选择和fallback
    result = await service_manager.transcribe(audio_bytes, language)
    return await build_asr_response(result, parse_context(context))


@router.post("/asr/recognize")
async def recognize_godot(
    audio: UploadFile = File(...),
    language: str = Form(default="en"),
    context: str | None = Form(default=None),
):
    """Godot client compatible endpoint (multipart form-data)."""
    audio_bytes = await audio.read()
    result = await service_manager.transcribe(audio_bytes, language)
    return await build_asr_response(result, parse_context(context))


class ASRRequest(BaseModel):
    audio_data: str  # base64 encoded
    lang: str = "en"
    context: dict[str, Any] | None = None


@router.post("/api/v1/voice/asr/json")
async def transcribe_json(req: ASRRequest):
    """Accept base64 audio in JSON body (Godot/Cocos clients)."""
    audio_bytes = base64.b64decode(req.audio_data)
    result = await service_manager.transcribe(audio_bytes, req.lang)
    return await build_asr_response(result, req.context)
