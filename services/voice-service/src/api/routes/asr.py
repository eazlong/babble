import base64
import json
import logging
from typing import Any

from fastapi import APIRouter, UploadFile, File, Form
from pydantic import BaseModel
from src.services.service_manager import service_manager
from src.services.asr_postprocess import asr_postprocessor

router = APIRouter()
logger = logging.getLogger(__name__)


def parse_context(raw_context: str | None) -> dict[str, Any] | None:
    if not raw_context:
        return None
    try:
        parsed = json.loads(raw_context)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def context_keys(context: dict[str, Any] | None) -> list[str]:
    if not context:
        return []
    return sorted(context.keys())


async def build_asr_response(result, context: dict[str, Any] | None, endpoint: str):
    logger.info(
        "[ASR-POSTPROCESS] request endpoint=%s text=%r language=%s confidence=%.4f context_present=%s context_keys=%s",
        endpoint,
        result.text,
        result.language,
        result.confidence,
        bool(context),
        context_keys(context),
    )
    postprocess = await asr_postprocessor.process(
        text=result.text,
        asr_confidence=result.confidence,
        language=result.language,
        context=context,
    )
    logger.info(
        "[ASR-POSTPROCESS] response text=%r applied=%s fallback_reason=%s corrected_text=%r extracted_keys=%s intent_matched=%s latency_ms=%s model=%s",
        result.text,
        postprocess.get("applied"),
        postprocess.get("fallback_reason"),
        postprocess.get("corrected_text"),
        context_keys(postprocess.get("extracted", {})),
        postprocess.get("intent_matched"),
        postprocess.get("latency_ms"),
        postprocess.get("model"),
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
    return await build_asr_response(result, parse_context(context), "/api/v1/voice/asr")


@router.post("/asr/recognize")
async def recognize_godot(
    audio: UploadFile = File(...),
    language: str = Form(default="en"),
    context: str | None = Form(default=None),
):
    """Godot client compatible endpoint (multipart form-data)."""
    audio_bytes = await audio.read()
    result = await service_manager.transcribe(audio_bytes, language)
    return await build_asr_response(result, parse_context(context), "/asr/recognize")


class ASRRequest(BaseModel):
    audio_data: str  # base64 encoded
    lang: str = "en"
    context: dict[str, Any] | None = None


@router.post("/api/v1/voice/asr/json")
async def transcribe_json(req: ASRRequest):
    """Accept base64 audio in JSON body (Godot/Cocos clients)."""
    audio_bytes = base64.b64decode(req.audio_data)
    result = await service_manager.transcribe(audio_bytes, req.lang)
    return await build_asr_response(result, req.context, "/api/v1/voice/asr/json")
