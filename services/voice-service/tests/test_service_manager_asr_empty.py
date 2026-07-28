import pytest
from unittest.mock import AsyncMock, patch

from src.services.service_manager import ASREngine, ServiceManager
from src.services.whisper import ASRResult
from src.services.xfyun_asr import XfyunASRResult


@pytest.mark.asyncio
async def test_transcribe_falls_back_when_xfyun_returns_empty_text():
    manager = ServiceManager()
    manager._asr_chain = [ASREngine.XFYUN, ASREngine.WHISPER]

    with patch("src.services.service_manager.xfyun_asr_service") as xfyun_service:
        with patch("src.services.service_manager.whisper_service") as whisper_service:
            xfyun_service.is_available = True
            xfyun_service.transcribe = AsyncMock(
                return_value=XfyunASRResult(text="", is_final=True, confidence=0.9, language="zh")
            )
            whisper_service.transcribe = AsyncMock(
                return_value=ASRResult(text="我叫卡卡，卡卡的卡", confidence=0.8, language="zh")
            )

            result = await manager.transcribe(b"audio", "zh")

    assert result.text == "我叫卡卡，卡卡的卡"
    assert result.language == "zh"


@pytest.mark.asyncio
async def test_transcribe_raises_when_all_engines_return_empty_text():
    manager = ServiceManager()
    manager._asr_chain = [ASREngine.XFYUN, ASREngine.WHISPER]

    with patch("src.services.service_manager.xfyun_asr_service") as xfyun_service:
        with patch("src.services.service_manager.whisper_service") as whisper_service:
            xfyun_service.is_available = True
            xfyun_service.transcribe = AsyncMock(
                return_value=XfyunASRResult(text="", is_final=True, confidence=0.9, language="zh")
            )
            whisper_service.transcribe = AsyncMock(
                return_value=ASRResult(text="", confidence=0.8, language="zh")
            )

            with pytest.raises(RuntimeError, match="All ASR engines failed"):
                await manager.transcribe(b"audio", "zh")
