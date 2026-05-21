import io
import os
import asyncio
import logging
import wave
from dataclasses import dataclass

import numpy as np
from faster_whisper import WhisperModel

logger = logging.getLogger(__name__)


@dataclass
class ASRResult:
    text: str
    confidence: float
    language: str


def _detect_device() -> str:
    device = os.environ.get("WHISPER_DEVICE", "auto")
    if device != "auto":
        return device
    try:
        import ctranslate2
        if ctranslate2.get_cuda_device_count() > 0:
            return "cuda"
    except Exception:
        pass
    try:
        import torch
        if torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def _detect_compute_type(device: str) -> str:
    ct = os.environ.get("WHISPER_COMPUTE_TYPE", "")
    if ct:
        return ct
    if device == "cuda":
        return "float16"
    if device == "mps":
        return "int8"
    return "int8"


def _raw_pcm_to_wav(audio_bytes: bytes) -> io.BytesIO:
    """Convert raw PCM float32 stereo 44100Hz to a mono int16 WAV in memory."""
    samples = np.frombuffer(audio_bytes, dtype=np.float32)
    if len(samples) % 2 == 0:
        samples = samples.reshape(-1, 2).mean(axis=1)
    int16_data = (samples * 32767.0).clip(-32768, 32767).astype(np.int16)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(44100)
        wf.writeframes(int16_data.tobytes())
    buf.seek(0)
    return buf


class WhisperService:
    def __init__(self):
        self.model = None
        self.device = None
        self.compute_type = None

    def init(self):
        model_size = os.environ.get("WHISPER_MODEL_SIZE", "small")
        self.device = _detect_device()
        self.compute_type = _detect_compute_type(self.device)

        logger.info(
            f"Loading Whisper model: size={model_size}, "
            f"device={self.device}, compute_type={self.compute_type}"
        )
        self.model = WhisperModel(
            model_size,
            device=self.device,
            compute_type=self.compute_type,
            download_root=os.environ.get("WHISPER_CACHE", None),
        )
        logger.info("Whisper model loaded successfully")

    async def transcribe(self, audio_bytes: bytes, language: str = "en") -> ASRResult:
        if self.model is None:
            raise RuntimeError("WhisperService not initialized, call init() first")

        lang = None if language in ("auto", "") else language

        try:
            segments, info = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.model.transcribe(io.BytesIO(audio_bytes), language=lang, beam_size=5),
            )
        except Exception:
            # Godot sends raw PCM float32 stereo at 44100Hz — no WAV header,
            # so PyAV fails. Wrap in a proper WAV container and retry.
            logger.info("PyAV decode failed, wrapping raw PCM in WAV container")
            wav_buf = _raw_pcm_to_wav(audio_bytes)
            segments, info = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.model.transcribe(wav_buf, language=lang, beam_size=5),
            )

        text = " ".join(s.text.strip() for s in segments)
        confidence = info.language_probability

        logger.info(
            "ASR result: text=%r language=%s confidence=%.4f",
            text, info.language, confidence,
        )

        return ASRResult(
            text=text,
            confidence=round(confidence, 4),
            language=info.language,
        )


whisper_service = WhisperService()
