"""
音频格式转换工具
处理Godot客户端音频（PCM float32 stereo 44100Hz）到讯飞标准格式（int16 mono 16000Hz）
"""

import logging
from typing import Union

import numpy as np
from scipy import signal

logger = logging.getLogger(__name__)


class AudioConverter:
    """音频格式转换器"""

    # Godot输入格式
    GODOT_SAMPLE_RATE = 44100
    GODOT_CHANNELS = 2
    GODOT_DTYPE = np.float32

    # 讯飞输出格式
    XFYUN_SAMPLE_RATE = 16000
    XFYUN_CHANNELS = 1
    XFYUN_DTYPE = np.int16

    @classmethod
    def convert_to_xfyun_format(cls, audio_bytes: bytes) -> bytes:
        """
        将Godot音频转换为讯飞标准格式

        Args:
            audio_bytes: PCM float32 stereo 44100Hz（原始字节）

        Returns:
            bytes: PCM int16 mono 16000Hz（原始字节）
        """
        try:
            # 检查音频数据大小
            if len(audio_bytes) == 0:
                logger.error("Audio data is empty (0 bytes)")
                raise ValueError("Empty audio data")

            # 处理奇数长度：截断到 float32 倍数
            if len(audio_bytes) % 4 != 0:
                logger.warning(f"Audio data size {len(audio_bytes)} is not multiple of 4, truncating to {len(audio_bytes) - (len(audio_bytes) % 4)} bytes")
                audio_bytes = audio_bytes[:len(audio_bytes) - (len(audio_bytes) % 4)]

            if len(audio_bytes) == 0:
                logger.error("Audio data became empty after truncation")
                raise ValueError("Empty audio data after truncation")

            # Step 1: 字节流转换为numpy数组
            samples = np.frombuffer(audio_bytes, dtype=cls.GODOT_DTYPE)
            logger.debug(f"Input: {len(samples)} samples ({len(audio_bytes)} bytes), dtype={samples.dtype}")

            # Step 2: 立体声转单声道
            mono_samples = cls._stereo_to_mono(samples)
            logger.debug(f"After stereo->mono: {len(mono_samples)} samples")

            # Step 3: float32转int16
            int16_samples = cls._float32_to_int16(mono_samples)
            logger.debug(f"After float32->int16: dtype={int16_samples.dtype}")

            # Step 4: 重采样 44100Hz -> 16000Hz
            resampled = cls._resample(int16_samples, cls.GODOT_SAMPLE_RATE, cls.XFYUN_SAMPLE_RATE)
            logger.debug(f"After resampling: {len(resampled)} samples")

            # Step 5: 转回字节
            return resampled.tobytes()

        except Exception as e:
            logger.error(f"Audio conversion error: {e}")
            raise

    @classmethod
    def _stereo_to_mono(cls, samples: np.ndarray) -> np.ndarray:
        """立体声转单声道（取平均值）"""
        if len(samples) % 2 != 0:
            # 奇数样本，截断最后一个
            samples = samples[:-1]
            logger.debug("Truncated odd sample")

        # reshape为(stereo_samples, 2)并取均值
        stereo_samples = samples.reshape(-1, 2)
        mono_samples = stereo_samples.mean(axis=1)
        return mono_samples

    @classmethod
    def _float32_to_int16(cls, samples: np.ndarray) -> np.ndarray:
        """float32转int16（带clipping）"""
        # 归一化到[-1, 1]范围（如果还没归一化）
        if samples.max() > 1.0 or samples.min() < -1.0:
            samples = np.clip(samples, -1.0, 1.0)
            logger.debug("Clipped samples to [-1, 1] range")

        # 转换到int16范围
        # float32 [-1, 1] -> int16 [-32768, 32767]
        # 使用公式：乘以32768并截断，但1.0会超出范围，所以特殊处理
        # 标准做法：乘以32767后clip
        int16_samples = np.round(samples * 32767.0).clip(-32768, 32767).astype(np.int16)
        return int16_samples

    @classmethod
    def _resample(
        cls,
        samples: np.ndarray,
        orig_sr: int,
        target_sr: int
    ) -> np.ndarray:
        """
        重采样

        使用scipy.signal.resample_poly进行高质量重采样
        """
        if orig_sr == target_sr:
            return samples

        # 计算最简整数倍率
        gcd = np.gcd(orig_sr, target_sr)
        up = target_sr // gcd
        down = orig_sr // gcd

        logger.debug(f"Resampling: {orig_sr}Hz -> {target_sr}Hz (up={up}, down={down})")

        # 使用polyphase重采样（更高质量）
        resampled = signal.resample_poly(samples, up, down)

        # 确保输出是int16
        return resampled.astype(np.int16)


def pcm_float32_to_int16_stereo_to_mono(audio_bytes: bytes) -> np.ndarray:
    """便利函数：PCM float32 stereo -> int16 mono"""
    samples = np.frombuffer(audio_bytes, dtype=np.float32)
    if len(samples) % 2 == 0:
        samples = samples.reshape(-1, 2).mean(axis=1)
    return (samples * 32767.0).clip(-32768, 32767).astype(np.int16)


def resample_44100_to_16000(samples: np.ndarray) -> np.ndarray:
    """便利函数：44100Hz -> 16000Hz重采样"""
    from scipy import signal
    gcd = np.gcd(44100, 16000)
    return signal.resample_poly(samples, 16000 // gcd, 44100 // gcd)