"""
Xfyun服务单元测试
测试音频转换、鉴权生成、服务初始化等核心功能
"""

import pytest
import numpy as np
from unittest.mock import Mock, patch, AsyncMock
import os

from src.services.audio_utils import AudioConverter
from src.services.xfyun_asr import XfyunASRService
from src.services.xfyun_tts import XfyunTTSService
from src.services.service_manager import ServiceManager, ServiceMode


class TestAudioConverter:
    """音频转换测试"""

    def test_stereo_to_mono(self):
        """测试立体声转单声道"""
        # 立体声数据：左声道0.5，右声道0.3
        stereo = np.array([0.5, 0.3, 0.8, 0.2], dtype=np.float32)
        mono = AudioConverter._stereo_to_mono(stereo)

        assert len(mono) == 2
        assert mono[0] == 0.4  # (0.5 + 0.3) / 2
        assert mono[1] == 0.5  # (0.8 + 0.2) / 2

    def test_float32_to_int16(self):
        """测试float32转int16"""
        float_samples = np.array([0.0, 0.5, 1.0, -1.0], dtype=np.float32)
        int16_samples = AudioConverter._float32_to_int16(float_samples)

        assert int16_samples.dtype == np.int16
        assert int16_samples[0] == 0
        assert abs(int16_samples[1] - 16384) < 10  # 约32767/2
        assert int16_samples[2] == 32767  # 最大正值
        # 注意：-1.0转换时可能得到-32767（因为乘以32767）
        # 这是标准的PCM转换方式
        assert abs(int16_samples[3]) >= 32767  # 接近最小负值

    def test_resample(self):
        """测试重采样44100Hz -> 16000Hz"""
        # 1秒的44100Hz样本
        samples_44k = np.random.randn(44100).astype(np.int16)
        samples_16k = AudioConverter._resample(samples_44k, 44100, 16000)

        # 预期输出约16000个样本（采样率转换）
        expected_len = int(44100 * 16000 / 44100)
        assert abs(len(samples_16k) - expected_len) < 10

    def test_full_conversion(self):
        """测试完整转换流程"""
        # 模拟44100Hz stereo float32的1秒音频
        samples = np.random.randn(88200).astype(np.float32) * 0.5
        audio_bytes = samples.tobytes()

        result = AudioConverter.convert_to_xfyun_format(audio_bytes)

        # 预期输出：16000Hz mono int16 ≈ 32000 bytes
        # 理论值: 44100 -> 16000 => 88200 / 2 / 44100 * 16000 = 16000 samples * 2 bytes
        assert len(result) > 30000  # 约32000字节
        assert len(result) < 35000


class TestXfyunASRService:
    """讯飞ASR服务测试"""

    @pytest.fixture
    def service(self):
        service = XfyunASRService()
        service.app_id = "test_app_id"
        service.api_key = "test_api_key"
        service.api_secret = "test_secret"
        service.is_available = True
        return service

    def test_build_auth_url(self, service):
        """测试鉴权URL生成"""
        url = service._build_auth_url()

        assert url.startswith("wss://rtasr.xfyun.cn/v1/ws?")
        assert "authorization=" in url
        assert "date=" in url
        assert "host=" in url

    def test_extract_text(self, service):
        """测试结果文本提取"""
        # 模拟讯飞返回格式
        data = {
            "cn": {
                "st": {
                    "type": "1",
                    "rt": [
                        {"ws": [{"cw": [{"w": "Hello"}, {"w": "World"}]}]}
                    ]
                }
            }
        }
        text = service._extract_text(data)
        assert text == "HelloWorld"

    def test_parse_response(self, service):
        """测试JSON响应解析"""
        response = '{"action":"result","data":{"cn":{"st":{"rt":[{"ws":[{"cw":[{"w":"test"}]}]}]}}}}'
        result = service._parse_response(response)

        assert result is not None
        assert "cn" in result

    @pytest.mark.asyncio
    async def test_init_without_credentials(self):
        """测试缺少凭证时的初始化"""
        service = XfyunASRService()
        service.app_id = ""
        service.api_key = ""
        service.api_secret = ""

        result = await service.init()
        assert result == False
        assert service.is_available == False


class TestXfyunTTSService:
    """讯飞TTS服务测试"""

    @pytest.fixture
    def service(self):
        service = XfyunTTSService()
        service.app_id = "test_app_id"
        service.api_key = "test_api_key"
        service.api_secret = "test_secret"
        service.is_available = True
        return service

    def test_resolve_voice(self, service):
        """测试音色映射"""
        assert service._resolve_voice("spirit") == "xiaoyan"
        assert service._resolve_voice("spark") == "xiaoyan"
        assert service._resolve_voice("unknown") == "xiaoyan"  # 默认

    def test_build_business_params(self, service):
        """测试业务参数构建"""
        params = service._build_business_params("spirit", "cn_en")

        assert params["voice_name"] == "xiaoyan"
        assert params["speed"] == 40  # 儿童优化
        assert params["volume"] == 60
        assert params["pitch"] == 55
        assert params["reg"] == 2  # 英文按单词发音

    def test_estimate_duration(self, service):
        """测试时长估算"""
        text = "Hello World"
        duration = service._estimate_duration(text)

        # 每字符60ms + 基础300ms
        expected = len(text) * 60 + 300
        assert duration == expected

    @pytest.mark.asyncio
    async def test_init_without_credentials(self):
        """测试缺少凭证时的初始化"""
        service = XfyunTTSService()
        service.app_id = ""
        service.api_key = ""

        result = await service.init()
        assert result == False


class TestServiceManager:
    """服务管理器测试"""

    def test_mode_detection_test(self):
        """测试模式检测：test模式"""
        with patch.dict("os.environ", {"VOICE_SERVICE_MODE": "test"}):
            manager = ServiceManager()
            assert manager.mode == ServiceMode.TEST
            assert manager._asr_chain[0].value == "xfyun"
            assert manager._tts_chain[0].value == "xfyun"

    def test_mode_detection_production(self):
        """测试模式检测：production模式"""
        with patch.dict("os.environ", {"VOICE_SERVICE_MODE": "production"}):
            manager = ServiceManager()
            assert manager.mode == ServiceMode.PRODUCTION
            assert manager._asr_chain[0].value == "whisper"
            assert manager._tts_chain[0].value == "fish"

    def test_mode_detection_default(self):
        """测试默认模式"""
        with patch.dict("os.environ", {"VOICE_SERVICE_MODE": ""}, clear=True):
            manager = ServiceManager()
            # 默认为production
            assert manager.mode == ServiceMode.PRODUCTION

    def test_build_chains_test_mode(self):
        """测试引擎链构建：test模式"""
        from src.services.service_manager import ASREngine, TTSEngine

        with patch.dict("os.environ", {"VOICE_SERVICE_MODE": "test"}):
            manager = ServiceManager()

            # ASR: 讯飞 -> Whisper
            assert len(manager._asr_chain) == 2
            assert manager._asr_chain[0] == ASREngine.XFYUN
            assert manager._asr_chain[1] == ASREngine.WHISPER

            # TTS: 讯飞 -> Fish -> ElevenLabs
            assert len(manager._tts_chain) == 3
            assert manager._tts_chain[0] == TTSEngine.XFYUN
            assert manager._tts_chain[1] == TTSEngine.FISH
            assert manager._tts_chain[2] == TTSEngine.ELEVENLABS

    @pytest.mark.asyncio
    async def test_transcribe_fallback(self):
        """测试ASR fallback机制"""
        manager = ServiceManager()

        # Mock所有引擎都失败
        with patch.object(manager, '_asr_chain', []):
            with pytest.raises(RuntimeError) as exc:
                await manager.transcribe(b"test_audio", "en")

            assert "All ASR engines failed" in str(exc.value)

    @pytest.mark.asyncio
    async def test_synthesize_fallback_to_silent(self):
        """测试TTS fallback到静音"""
        manager = ServiceManager()

        # Mock所有引擎都失败
        with patch.object(manager, '_tts_chain', []):
            audio_data, format_type = await manager.synthesize("test text", "spirit", "en")

            # 应返回静音WAV
            assert format_type == "wav"
            assert len(audio_data) > 0  # 静音WAV也有数据


# 集成测试标记
@pytest.mark.integration
class TestIntegration:
    """集成测试（需要真实凭证）"""

    @pytest.mark.asyncio
    async def test_full_asr_pipeline(self):
        """测试完整ASR流程（需要讯飞凭证）"""
        # 仅在有凭证时运行
        if not all([os.environ.get("XFYUN_APP_ID"),
                    os.environ.get("XFYUN_API_KEY"),
                    os.environ.get("XFYUN_API_SECRET")]):
            pytest.skip("Missing Xfyun credentials")

        from src.services.service_manager import service_manager
        await service_manager.init_all()

        # 模拟音频（简单PCM数据）
        test_audio = np.random.randn(88200).astype(np.float32).tobytes()

        result = await service_manager.transcribe(test_audio, "cn_en")
        assert result.text  # 应返回一些文本
        assert result.confidence > 0

    @pytest.mark.asyncio
    async def test_full_tts_pipeline(self):
        """测试完整TTS流程（需要讯飞凭证）"""
        if not all([os.environ.get("XFYUN_APP_ID"),
                    os.environ.get("XFYUN_API_KEY"),
                    os.environ.get("XFYUN_API_SECRET")]):
            pytest.skip("Missing Xfyun credentials")

        from src.services.service_manager import service_manager
        await service_manager.init_all()

        audio_data, format_type = await service_manager.synthesize(
            "Hello children", "spirit", "cn_en"
        )

        assert audio_data  # 应返回音频数据
        assert format_type in ["wav", "mp3"]