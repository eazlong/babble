"""
讯飞在线语音合成 WebSocket 服务
文档: https://www.xfyun.cn/doc/tts/online_tts/API.html
"""

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import ssl
from dataclasses import dataclass
from datetime import datetime
from time import mktime
from typing import Optional
from urllib.parse import urlencode
from wsgiref.handlers import format_date_time

import websockets

logger = logging.getLogger(__name__)


@dataclass
class XfyunTTSResult:
    """TTS合成结果"""
    audio_data: str  # base64编码
    format: str      # 音频格式
    duration_ms: int


class XfyunTTSService:
    """
    讯飞在线语音合成 WebSocket 接口
    """

    # WebSocket API 端点
    WS_URL = "wss://tts-api.xfyun.cn/v2/tts"

    # 音色ID映射 - 统一使用xiaoyan（女声，儿童友好）
    VOICE_MAP = {
        "spirit": "x4_yezi",     # 精灵导师 - x4_yezi（优质女声）
        "spark": "x4_yezi",      # 火花精灵
        "oakley": "x4_yezi",     # 橡树守卫
        "default": "x4_yezi",    # 默认
    }

    # 儿童优化参数
    CHILD_OPTIMIZED_PARAMS = {
        "auf": "audio/L16;rate=16000",  # 采样率
        "aue": "raw",                    # PCM格式（原始音频）
        "speed": 40,                     # 语速（0-100，儿童稍慢）
        "volume": 60,                    # 音量（0-100）
        "pitch": 55,                     # 音高（0-100，儿童稍高）
        "tte": "utf8",                   # 文本编码
    }

    def __init__(self):
        self.app_id = os.environ.get("XFYUN_APP_ID", "")
        self.api_key = os.environ.get("XFYUN_API_KEY", "")
        self.api_secret = os.environ.get("XFYUN_API_SECRET", "")
        self.is_available = False

    async def init(self) -> bool:
        """初始化服务"""
        if not all([self.app_id, self.api_key, self.api_secret]):
            logger.warning("XfyunTTSService: Missing credentials")
            self.is_available = False
            return False

        self.is_available = True
        logger.info("XfyunTTSService initialized successfully (WebSocket mode)")
        return True

    async def synthesize(
        self,
        text: str,
        voice_id: str = "spirit",
        language: str = "cn_en"
    ) -> XfyunTTSResult:
        """
        合成语音（WebSocket 流式传输）

        Args:
            text: 待合成文本
            voice_id: 游戏内语音ID（映射到讯飞音色）
            language: 语言（cn_en中英混合）

        Returns:
            XfyunTTSResult: 合成结果
        """
        if not self.is_available:
            raise RuntimeError("XfyunTTSService not initialized")

        # 生成 WebSocket URL
        ws_url = self._create_ws_url(text, voice_id)

        # 音频数据收集
        audio_chunks = []
        duration_ms = 0

        try:
            # 连接 WebSocket
            ssl_context = ssl.create_default_context()
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE

            async with websockets.connect(
                ws_url,
                ssl=ssl_context,
                ping_interval=None,
                close_timeout=5
            ) as ws:
                # 发送请求
                request_body = self._build_ws_request(text, voice_id)
                await ws.send(json.dumps(request_body))
                logger.info(f"Xfyun WebSocket request sent: text='{text[:20]}...'")

                # 接收流式响应
                while True:
                    try:
                        message = await asyncio.wait_for(ws.recv(), timeout=30.0)
                        response = json.loads(message)

                        code = response.get("code", 0)
                        sid = response.get("sid", "")
                        status = response.get("data", {}).get("status", 0)

                        if code != 0:
                            error_msg = response.get("message", "Unknown error")
                            logger.error(f"Xfyun WebSocket error: code={code}, sid={sid}, message={error_msg}")
                            raise RuntimeError(f"API error: {error_msg}")

                        # 提取音频数据
                        audio_base64 = response.get("data", {}).get("audio", "")
                        if audio_base64:
                            audio_bytes = base64.b64decode(audio_base64)
                            audio_chunks.append(audio_bytes)
                            logger.debug(f"Received audio chunk: {len(audio_bytes)} bytes, status={status}")

                        # 状态 2 表示最后一帧
                        if status == 2:
                            logger.info(f"Xfyun WebSocket complete: sid={sid}, chunks={len(audio_chunks)}")
                            break

                    except asyncio.TimeoutError:
                        logger.error("Xfyun WebSocket timeout")
                        raise RuntimeError("WebSocket timeout")

            # 拼接音频数据（PCM）
            audio_data_bytes = b"".join(audio_chunks)

            # 转换 PCM 为 WAV
            wav_data = self._pcm_to_wav(audio_data_bytes)
            audio_base64 = base64.b64encode(wav_data).decode("utf-8")

            # 估算时长
            duration_ms = self._estimate_duration(text)

            logger.info(f"Xfyun TTS success: {len(audio_base64)} chars base64, {len(audio_data_bytes)} bytes")

            return XfyunTTSResult(
                audio_data=audio_base64,
                format="wav",  # PCM 格式转换为 WAV
                duration_ms=duration_ms
            )

        except Exception as e:
            logger.error(f"Xfyun TTS synthesis error: {e}")
            raise

    def _create_ws_url(self, text: str, voice_id: str) -> str:
        """生成 WebSocket URL（带鉴权）"""
        # 生成 RFC1123 格式的时间戳
        now = datetime.now()
        date = format_date_time(mktime(now.timetuple()))

        # 拼接签名字符串
        signature_origin = "host: tts-api.xfyun.cn\n"
        signature_origin += f"date: {date}\n"
        signature_origin += "GET /v2/tts HTTP/1.1"

        # HMAC-SHA256 加密
        signature_sha = hmac.new(
            self.api_secret.encode("utf-8"),
            signature_origin.encode("utf-8"),
            digestmod=hashlib.sha256
        ).digest()
        signature_sha_base64 = base64.b64encode(signature_sha).decode("utf-8")

        # 构建授权字符串
        authorization_origin = (
            f"api_key=\"{self.api_key}\", "
            f"algorithm=\"hmac-sha256\", "
            f"headers=\"host date request-line\", "
            f"signature=\"{signature_sha_base64}\""
        )
        authorization = base64.b64encode(authorization_origin.encode("utf-8")).decode("utf-8")

        # 构建鉴权参数
        auth_params = {
            "authorization": authorization,
            "date": date,
            "host": "tts-api.xfyun.cn"
        }

        # 拼接完整 URL
        url = self.WS_URL + "?" + urlencode(auth_params)
        return url

    def _build_ws_request(self, text: str, voice_id: str) -> dict:
        """构建 WebSocket 请求体"""
        business_params = self.CHILD_OPTIMIZED_PARAMS.copy()
        business_params["vcn"] = self._resolve_voice(voice_id)

        # 文本需要 base64 编码
        text_base64 = base64.b64encode(text.encode("utf-8")).decode("utf-8")

        return {
            "common": {"app_id": self.app_id},
            "business": business_params,
            "data": {"status": 2, "text": text_base64}
        }

    def _resolve_voice(self, voice_id: str) -> str:
        """解析voice_id到讯飞音色"""
        return self.VOICE_MAP.get(voice_id, self.VOICE_MAP["default"])

    def _pcm_to_wav(self, pcm_data: bytes, sample_rate: int = 16000) -> bytes:
        """将 PCM 数据转换为 WAV 格式"""
        import struct

        num_channels = 1
        bits_per_sample = 16
        byte_rate = sample_rate * num_channels * bits_per_sample // 8
        block_align = num_channels * bits_per_sample // 8
        data_size = len(pcm_data)

        # WAV header
        header = bytearray()
        header.extend(b"RIFF")
        header.extend(struct.pack("<I", 36 + data_size))
        header.extend(b"WAVE")
        header.extend(b"fmt ")
        header.extend(struct.pack("<I", 16))
        header.extend(struct.pack("<H", 1))   # PCM format
        header.extend(struct.pack("<H", num_channels))
        header.extend(struct.pack("<I", sample_rate))
        header.extend(struct.pack("<I", byte_rate))
        header.extend(struct.pack("<H", block_align))
        header.extend(struct.pack("<H", bits_per_sample))
        header.extend(b"data")
        header.extend(struct.pack("<I", data_size))

        return header + pcm_data

    def _estimate_duration(self, text: str) -> int:
        """估算音频时长（毫秒）"""
        # 简单估算：每个字符60ms，加上基础300ms
        # 儿童语速较慢，因此用60ms而非50ms
        return len(text) * 60 + 300

    async def close(self):
        """关闭服务（WebSocket 无需关闭客户端）"""
        logger.info("XfyunTTSService closed")


# 全局单例
xfyun_tts_service = XfyunTTSService()