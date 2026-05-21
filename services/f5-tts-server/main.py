"""F5-TTS MLX HTTP server with FastAPI, optimized for Apple Silicon."""

import io
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from pathlib import Path

import mlx.core as mx
import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from f5_tts_mlx.cfm import F5TTS
from f5_tts_mlx.utils import convert_char_to_pinyin

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
SAMPLE_RATE = 24_000
TARGET_RMS = 0.1
STEPS = int(os.environ.get("F5_STEPS", "10"))
METHOD = os.environ.get("F5_METHOD", "euler")
QUANTIZATION_BITS = int(os.environ.get("F5_QUANTIZATION_BITS", "0")) or None
HOST = os.environ.get("F5_HOST", "0.0.0.0")
PORT = int(os.environ.get("F5_PORT", "8002"))

# Load voice configuration
_voice_config_path = Path(__file__).parent / "voices.json"
with open(_voice_config_path) as f:
    _voice_config = json.load(f)

VOICES: dict = _voice_config["voices"]
AUDIO_DIR = Path(_voice_config["audio_dir"])
if not AUDIO_DIR.is_absolute():
    AUDIO_DIR = (Path(__file__).parent / AUDIO_DIR).resolve()

model = None


def load_model():
    """Load F5-TTS MLX model."""
    global model
    logger.info(f"Loading F5-TTS MLX model (quantization={QUANTIZATION_BITS})...")
    start = time.time()
    model = F5TTS.from_pretrained("lucasnewman/f5-tts-mlx", quantization_bits=QUANTIZATION_BITS)
    elapsed = time.time() - start
    logger.info(f"Model loaded in {elapsed:.1f}s")


def synthesize(text: str, ref_audio_path: str, ref_text: str, steps: int = STEPS, method: str = METHOD) -> bytes:
    """Generate speech using F5-TTS MLX."""
    global model

    # Load reference audio (same approach as webui.py)
    audio, sr = sf.read(ref_audio_path)
    audio = audio.astype(np.float32)
    if sr != SAMPLE_RATE:
        from scipy.signal import resample
        audio = resample(audio, int(len(audio) * SAMPLE_RATE / sr))

    audio = audio.flatten()
    rms = float(np.sqrt(np.mean(np.square(audio))))
    if rms < TARGET_RMS:
        audio = audio * TARGET_RMS / rms
    audio_mx = mx.array(audio)
    audio_mx = mx.expand_dims(audio_mx, axis=0)

    # Convert text to pinyin
    full_text = convert_char_to_pinyin([ref_text + " " + text])

    # Generate
    start = time.time()
    wave, _ = model.sample(
        audio_mx,
        text=full_text,
        duration=None,
        steps=steps,
        method=method,
        speed=1.0,
        cfg_strength=2.0,
        sway_sampling_coef=-1.0,
    )

    # Trim reference audio portion
    wave = wave[audio.shape[0]:]
    mx.eval(wave)

    elapsed = time.time() - start
    duration = wave.shape[0] / SAMPLE_RATE
    logger.info(f"Generated {duration:.2f}s of audio in {elapsed:.2f}s for steps={steps} and method={method} (RTF={elapsed/max(duration,0.01):.2f})")

    # Convert to WAV bytes
    wav_buffer = io.BytesIO()
    sf.write(wav_buffer, np.array(wave), SAMPLE_RATE, format="WAV")
    return wav_buffer.getvalue()


@asynccontextmanager
async def lifespan(app: FastAPI):
    load_model()
    yield


app = FastAPI(title="F5-TTS MLX Server", version="0.1.0", lifespan=lifespan)


class TTSRequest(BaseModel):
    text: str
    voice_id: str = "spirit"
    language: str = "en"
    steps: int = 8
    method: str = "euler"


class HealthResponse(BaseModel):
    status: str
    model: str
    steps: int
    method: str


@app.get("/health", response_model=HealthResponse)
async def health_check():
    return {
        "status": "ok",
        "model": "f5-tts-mlx",
        "steps": STEPS,
        "method": METHOD,
    }


@app.post("/v1/tts")
async def text_to_speech(req: TTSRequest):
    global model

    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    voice = VOICES.get(req.voice_id)
    if not voice:
        raise HTTPException(status_code=400, detail=f"Unknown voice_id: {req.voice_id}")

    ref_path = AUDIO_DIR / voice["file"]
    if not ref_path.exists():
        raise HTTPException(status_code=400, detail=f"Reference audio not found: {voice['file']}")

    wav_bytes = synthesize(
        req.text,
        str(ref_path),
        voice["ref_text"],
        steps=req.steps,
        method=req.method,
    )

    return Response(content=wav_bytes, media_type="audio/wav")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
