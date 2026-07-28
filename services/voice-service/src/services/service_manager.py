"""
服务管理器 - 统一管理ASR/TTS服务初始化和引擎优先级
根据环境变量控制服务优先级和fallback链
"""

import logging
import os
from enum import Enum
from typing import Optional

import base64

from src.services.whisper import WhisperService, whisper_service, ASRResult
from src.services.xfyun_asr import XfyunASRService, xfyun_asr_service, XfyunASRResult
from src.services.tts import TTSService, tts_service
from src.services.xfyun_tts import XfyunTTSService, xfyun_tts_service, XfyunTTSResult

logger = logging.getLogger(__name__)


class ServiceMode(Enum):
    """服务模式"""
    TEST = "test"           # 测试环境：讯飞优先
    PRODUCTION = "production"  # 生产环境：Whisper/Fish优先


class ASREngine(Enum):
    """ASR引擎"""
    XFYUN = "xfyun"
    WHISPER = "whisper"


class TTSEngine(Enum):
    """TTS引擎"""
    FISH = "fish"
    ELEVENLABS = "elevenlabs"
    XFYUN = "xfyun"


class ServiceManager:
    """
    服务管理器
    - 根据环境变量配置服务优先级
    - 管理fallback链
    - 统一服务初始化
    """

    def __init__(self):
        self.mode = self._detect_mode()
        self._asr_chain: list[ASREngine] = []
        self._tts_chain: list[TTSEngine] = []
        self._build_chains()

    def _detect_mode(self) -> ServiceMode:
        """检测运行模式"""
        mode_str = os.environ.get("VOICE_SERVICE_MODE", "production").lower()
        if mode_str == "test":
            logger.info("Service mode: TEST (Xfyun first)")
            return ServiceMode.TEST
        logger.info("Service mode: PRODUCTION (Whisper/Fish first)")
        return ServiceMode.PRODUCTION

    def _build_chains(self):
        """构建引擎优先级链"""
        if self.mode == ServiceMode.TEST:
            # 测试环境：讯飞优先
            self._asr_chain = [ASREngine.XFYUN, ASREngine.WHISPER]
            self._tts_chain = [TTSEngine.XFYUN, TTSEngine.FISH, TTSEngine.ELEVENLABS]
        else:
            # 生产环境：本地/国际服务优先
            self._asr_chain = [ASREngine.WHISPER, ASREngine.XFYUN]
            self._tts_chain = [TTSEngine.FISH, TTSEngine.ELEVENLABS, TTSEngine.XFYUN]

        logger.info(f"ASR chain: {[e.value for e in self._asr_chain]}")
        logger.info(f"TTS chain: {[e.value for e in self._tts_chain]}")

    async def init_all(self):
        """初始化所有服务"""
        logger.info("Initializing all services...")

        # 初始化所有服务（不依赖的先初始化）
        await tts_service.init()
        whisper_service.init()
        await xfyun_asr_service.init()
        await xfyun_tts_service.init()

        logger.info("All services initialized successfully")

    def _ensure_non_empty_asr_result(self, engine: ASREngine, text: str) -> None:
        if text.strip():
            return
        raise RuntimeError(f"{engine.value} returned empty transcript")

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "en"
    ) -> ASRResult:
        """
        ASR识别，按优先级链尝试

        Args:
            audio_bytes: 音频数据
            language: 语言代码

        Returns:
            ASRResult: 识别结果
        """
        errors = []

        for engine in self._asr_chain:
            try:
                if engine == ASREngine.XFYUN:
                    if not xfyun_asr_service.is_available:
                        logger.debug(f"Skipping {engine.value}: not available")
                        continue

                    result = await xfyun_asr_service.transcribe(audio_bytes, language)
                    self._ensure_non_empty_asr_result(engine, result.text)
                    logger.info(f"ASR success: engine={engine.value}, text='{result.text[:50]}...'")

                    return ASRResult(
                        text=result.text,
                        confidence=result.confidence,
                        language=result.language
                    )

                elif engine == ASREngine.WHISPER:
                    result = await whisper_service.transcribe(audio_bytes, language)
                    self._ensure_non_empty_asr_result(engine, result.text)
                    logger.info(f"ASR success: engine={engine.value}, text='{result.text[:50]}...'")

                    return result

            except Exception as e:
                logger.warning(f"ASR engine {engine.value} failed: {e}")
                errors.append(f"{engine.value}: {str(e)}")
                continue

        # 所有引擎都失败
        error_msg = f"All ASR engines failed: {'; '.join(errors)}"
        logger.error(error_msg)
        raise RuntimeError(error_msg)

    async def synthesize(
        self,
        text: str,
        voice_id: str = "spirit",
        language: str = "en"
    ) -> tuple[str, str]:
        """
        TTS合成，按优先级链尝试

        Args:
            text: 待合成文本
            voice_id: 语音ID
            language: 语言代码

        Returns:
            tuple: (base64音频, 格式)
        """
        errors = []

        for engine in self._tts_chain:
            try:
                if engine == TTSEngine.FISH:
                    if not tts_service.fish_available:
                        logger.debug(f"Skipping {engine.value}: not available")
                        continue

                    # 使用现有TTS服务的Fish部分
                    audio_bytes = await tts_service.fish_client.synthesize(text, voice_id)
                    logger.info(f"TTS success: engine={engine.value}, size={len(audio_bytes)} bytes")

                    return base64.b64encode(audio_bytes).decode("utf-8"), "wav"

                elif engine == TTSEngine.ELEVENLABS:
                    if not tts_service.elevenlabs:
                        logger.debug(f"Skipping {engine.value}: not available")
                        continue

                    # 使用现有TTS服务（会fallback到Fish或Silent）
                    audio_data, format_type = await tts_service.synthesize_audio(text, voice_id)
                    logger.info(f"TTS success: engine={engine.value}, format={format_type}")

                    return audio_data, format_type

                elif engine == TTSEngine.XFYUN:
                    if not xfyun_tts_service.is_available:
                        logger.debug(f"Skipping {engine.value}: not available")
                        continue

                    result = await xfyun_tts_service.synthesize(text, voice_id, language)
                    logger.info(f"TTS success: engine={engine.value}, format={result.format}")

                    return result.audio_data, result.format

            except Exception as e:
                logger.warning(f"TTS engine {engine.value} failed: {e}")
                errors.append(f"{engine.value}: {str(e)}")
                continue

        # 所有引擎都失败，返回静音
        logger.error(f"All TTS engines failed: {'; '.join(errors)}, returning silent audio")
        return tts_service._generate_silent_wav(duration_ms=len(text) * 50), "wav"


# 全局服务管理器实例
service_manager = ServiceManager()