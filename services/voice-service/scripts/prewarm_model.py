"""Pre-download Whisper model for offline deployment.

Usage:
    python scripts/prewarm_model.py              # download small model to default cache
    python scripts/prewarm_model.py --model large-v3 --cache /data/models/whisper
"""

import argparse
import io
import os
import wave

from faster_whisper import WhisperModel


def _generate_silent_wav(duration_sec: float = 1.0, sample_rate: int = 16000) -> bytes:
    """Generate a tiny silent WAV file in memory for model warm-up."""
    buf = io.BytesIO()
    n_samples = int(sample_rate * duration_sec)
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(b"\x00\x00" * n_samples)
    return buf.getvalue()


def main():
    parser = argparse.ArgumentParser(description="Pre-download Whisper model")
    parser.add_argument(
        "--model", default=os.environ.get("WHISPER_MODEL_SIZE", "small"),
        help="Model size (default: small)"
    )
    parser.add_argument(
        "--cache", default=os.environ.get("WHISPER_CACHE", "/models/whisper"),
        help="Download cache directory (default: /models/whisper)"
    )
    parser.add_argument(
        "--device", default="cpu",
        help="Device for test load after download (default: cpu)"
    )
    parser.add_argument(
        "--compute-type", default="int8",
        help="Compute type for test load (default: int8)"
    )
    args = parser.parse_args()

    os.makedirs(args.cache, exist_ok=True)

    print(f"Downloading model '{args.model}' to {args.cache} ...")
    model = WhisperModel(
        args.model,
        device=args.device,
        compute_type=args.compute_type,
        download_root=args.cache,
    )
    print("Model downloaded. Running quick test transcription ...")

    audio_bytes = _generate_silent_wav()
    segments, info = model.transcribe(audio_bytes, language="en")
    text = " ".join(s.text for s in segments)
    print(f"Test OK: detected_lang={info.language}, text='{text}'")
    print("Pre-warm complete.")


if __name__ == "__main__":
    main()
