import io
import wave

import numpy as np
import pytest

from src.services.audio_utils import AudioConverter


def make_wav(samples: np.ndarray, sample_rate: int, channels: int) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(samples.astype(np.int16).tobytes())
    return buffer.getvalue()


def test_convert_wav_16k_mono_int16_keeps_expected_shape():
    samples = np.arange(1600, dtype=np.int16)
    wav_bytes = make_wav(samples, sample_rate=16000, channels=1)

    result = AudioConverter.convert_to_xfyun_format(wav_bytes)
    converted = np.frombuffer(result, dtype=np.int16)

    assert len(result) == 1600 * 2
    assert converted.dtype == np.int16
    assert converted.size == 1600


def test_convert_wav_44100_stereo_int16_to_16k_mono():
    left = np.linspace(-1000, 1000, 4410, dtype=np.int16)
    right = np.linspace(1000, -1000, 4410, dtype=np.int16)
    stereo = np.column_stack((left, right)).reshape(-1)
    wav_bytes = make_wav(stereo, sample_rate=44100, channels=2)

    result = AudioConverter.convert_to_xfyun_format(wav_bytes)
    converted = np.frombuffer(result, dtype=np.int16)

    assert len(result) == 1600 * 2
    assert converted.dtype == np.int16
    assert converted.size == 1600


def test_convert_godot_raw_pcm_still_supported():
    duration_seconds = 0.1
    frame_count = int(AudioConverter.GODOT_SAMPLE_RATE * duration_seconds)
    mono = np.linspace(-0.5, 0.5, frame_count, dtype=np.float32)
    stereo = np.column_stack((mono, mono)).reshape(-1).astype(np.float32)

    result = AudioConverter.convert_to_xfyun_format(stereo.tobytes())
    converted = np.frombuffer(result, dtype=np.int16)

    assert converted.dtype == np.int16
    assert converted.size == int(AudioConverter.XFYUN_SAMPLE_RATE * duration_seconds)


def test_empty_audio_raises_clear_error():
    with pytest.raises(ValueError, match="Empty audio data"):
        AudioConverter.convert_to_xfyun_format(b"")
