"""
讯飞实时语音转写WebSocket服务
文档: https://www.xfyun.cn/doc/asr/rtasr/API.html
"""

import asyncio
import base64
import hashlib
import hmac
import json
import logging
import os
import time
import urllib.parse
from dataclasses import dataclass
from typing import Optional, Callable

import websocket

from src.services.audio_utils import AudioConverter

logger = logging.getLogger(__name__)


@dataclass
class XfyunASRResult:
    """ASR识别结果"""
    text: str
    is_final: bool  # 是否最终识别结果
    confidence: float = 0.0
    language: str = "cn_en"  # 讯飞返回的是混合语言


class XfyunASRService:
    """
    讯飞实时语音转写WebSocket服务
    每次对话新建连接，对话粒度短连接
    """

    # 讯飞API配置
    HOST = "rtasr.xfyun.cn"
    PORT = 8080
    PROTOCOL = "wss"
    WS_URL = "wss://rtasr.xfyun.cn/v1/ws"

    def __init__(self):
        self.app_id = os.environ.get("XFYUN_APP_ID", "")
        self.api_key = os.environ.get("XFYUN_API_KEY", "")
        self.api_secret = os.environ.get("XFYUN_API_SECRET", "")
        self.is_available = False

    async def init(self) -> bool:
        """初始化服务，验证配置"""
        if not all([self.app_id, self.api_key, self.api_secret]):
            logger.warning("XfyunASRService: Missing credentials")
            self.is_available = False
            return False

        # 测试鉴权URL生成（不实际连接）
        try:
            url = self._build_auth_url()
            logger.info("XfyunASRService initialized successfully")
            self.is_available = True
            return True
        except Exception as e:
            logger.error(f"XfyunASRService init failed: {e}")
            self.is_available = False
            return False

    def _build_auth_url(self) -> str:
        """
        生成鉴权URL（HMAC-SHA256签名）
        讯飞鉴权格式：wss://rtasr.xfyun.cn/v1/ws?authorization=xxx&date=xxx&host=xxx
        """
        # RFC1123格式时间
        date = time.strftime("%a, %d %b %Y %H:%M:%S %Z", time.gmtime())

        # 构建签名原文
        signature_origin = f"host: {self.HOST}\n"
        signature_origin += f"date: {date}\n"
        signature_origin += f"GET /v1/ws HTTP/1.1"

        # HMAC-SHA256签名
        signature_sha = hmac.new(
            self.api_secret.encode('utf-8'),
            signature_origin.encode('utf-8'),
            digestmod=hashlib.sha256
        ).digest()
        signature = base64.b64encode(signature_sha).decode('utf-8')

        # 构建authorization
        authorization_origin = f'api_key="{self.api_key}", algorithm="hmac-sha256", headers="host date request-line", signature="{signature}"'
        authorization = base64.b64encode(authorization_origin.encode('utf-8')).decode('utf-8')

        # 构建URL参数
        params = {
            "authorization": authorization,
            "date": date,
            "host": self.HOST,
        }

        url = f"{self.WS_URL}?{urllib.parse.urlencode(params)}"
        logger.debug(f"Generated auth URL: {url[:80]}...")
        return url

    async def transcribe(
        self,
        audio_bytes: bytes,
        language: str = "cn_en"
    ) -> XfyunASRResult:
        """
        同步转录接口（兼容现有Whisper接口）

        Args:
            audio_bytes: 音频数据（PCM float32 stereo 44100Hz，Godot原始格式）
            language: 语言模式（cn_en中英混合）

        Returns:
            XfyunASRResult: 识别结果
        """
        if not self.is_available:
            raise RuntimeError("XfyunASRService not initialized")

        # 音频格式转换
        try:
            xfyun_audio = AudioConverter.convert_to_xfyun_format(audio_bytes)
            logger.debug(f"Audio converted: {len(audio_bytes)} -> {len(xfyun_audio)} bytes")
        except Exception as e:
            logger.error(f"Audio conversion failed: {e}")
            raise

        # 建立WebSocket连接（每次对话新建）
        url = self._build_auth_url()

        try:
            # 使用websocket-client（同步库，在async中需要包装）
            ws = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: websocket.create_connection(url, timeout=10)
            )

            result_text = []
            try:
                # 分片发送音频（每片1280字节 = 40ms @ 16kHz mono int16）
                chunk_size = 1280
                total_chunks = (len(xfyun_audio) + chunk_size - 1) // chunk_size

                for i in range(0, len(xfyun_audio), chunk_size):
                    chunk = xfyun_audio[i:i+chunk_size]

                    # 最后一片补齐
                    if len(chunk) < chunk_size:
                        chunk += b"\x00" * (chunk_size - len(chunk))

                    # 发送音频数据（二进制帧）
                    # 讯飞 ASR WebSocket 需要发送 JSON 格式，包含 base64 编码的音频
                    audio_b64 = base64.b64encode(c).decode('utf-8')
                    message = json.dumps({
                        "data": {
                            "status": 1 if i + chunk_size < len(xfyun_audio) else 2,  # 2=最后一帧
                            "format": "audio/L16;rate=16000",
                            "encoding": "raw",
                            "audio": audio_b64
                        }
                    })

                    await asyncio.get_event_loop().run_in_executor(
                        None,
                        lambda m=message: ws.send(m)
                    )

                    # 等待40ms（模拟实时流）
                    await asyncio.sleep(0.04)

                    # 非阻塞接收结果
                    ws.settimeout(0.01)
                    try:
                        response = await asyncio.get_event_loop().run_in_executor(
                            None,
                            lambda: ws.recv()
                        )
                        result = self._parse_response(response)
                        if result:
                            text = self._extract_text(result)
                            if text:
                                result_text.append(text)
                                logger.debug(f"Partial result: {text}")
                    except websocket.WebSocketTimeoutException:
                        # 没有收到结果，继续发送
                        pass

                # 发送结束标记
                end_message = json.dumps({
                    "data": {
                        "status": 2,
                        "format": "audio/L16;rate=16000",
                        "encoding": "raw",
                        "audio": ""
                    }
                })
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: ws.send(end_message)
                )

                # 等待最终确认（最长5s）
                ws.settimeout(5.0)
                try:
                    final_response = await asyncio.get_event_loop().run_in_executor(
                        None,
                        lambda: ws.recv()
                    )
                    logger.debug(f"Final response: {final_response[:100]}")
                except websocket.WebSocketTimeoutException:
                    logger.warning("Timeout waiting for final response")

            finally:
                # 关闭连接
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: ws.close()
                )

            # 合并结果
            final_text = " ".join(result_text) if result_text else ""
            logger.info(f"Xfyun ASR success: '{final_text[:50]}...' ({len(final_text)} chars)")

            return XfyunASRResult(
                text=final_text,
                is_final=True,
                confidence=0.9,  # 讯飞不直接返回置信度，默认值
                language=language
            )

        except websocket.WebSocketException as e:
            logger.error(f"WebSocket error: {e}")
            raise
        except Exception as e:
            logger.error(f"Xfyun ASR failed: {e}")
            raise

    def _parse_response(self, response: str) -> Optional[dict]:
        """解析讯飞返回的JSON"""
        try:
            data = json.loads(response)
            return data.get("data")
        except json.JSONDecodeError:
            logger.warning(f"Failed to parse response: {response[:100]}")
            return None

    def _extract_text(self, data: dict) -> str:
        """从讯飞数据格式中提取文本"""
        try:
            # 讯飞返回格式：{"cn":{"st":{"rt":[{"ws":[{"cw":[{"w":"Hello"}]}]}]}}}
            rt_list = data.get("cn", {}).get("st", {}).get("rt", [])
            texts = []
            for rt in rt_list:
                for ws in rt.get("ws", []):
                    for cw in ws.get("cw", []):
                        texts.append(cw.get("w", ""))
            return "".join(texts)
        except Exception as e:
            logger.error(f"Extract text error: {e}")
            return ""


# 全局单例
xfyun_asr_service = XfyunASRService()