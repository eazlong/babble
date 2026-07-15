"""
讯飞星火大模型语音识别 WebSocket 服务
文档: https://www.xfyun.cn/doc/spark/spark_mul_cn_iat.html
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
from typing import Optional

import websocket

from src.services.audio_utils import AudioConverter

logger = logging.getLogger(__name__)


@dataclass
class XfyunASRResult:
    """ASR识别结果"""
    text: str
    is_final: bool
    confidence: float = 0.0
    language: str = "cn_en"


class XfyunASRService:
    """
    讯飞星火大模型语音识别 WebSocket 服务
    每次对话新建短连接
    """

    HOST = "iat.cn-huabei-1.xf-yun.com"
    WS_URL = "wss://iat.cn-huabei-1.xf-yun.com/v1"

    def __init__(self):
        self.app_id = os.environ.get("XFYUN_APP_ID", "")
        self.api_key = os.environ.get("XFYUN_API_KEY", "")
        self.api_secret = os.environ.get("XFYUN_API_SECRET", "")
        self.is_available = False

    async def init(self) -> bool:
        """初始化服务，验证配置"""
        if not all([self.app_id, self.api_key, self.api_secret]):
            logger.warning("XfyunASRService: Missing credentials (need APP_ID + API_KEY + API_SECRET)")
            self.is_available = False
            return False

        try:
            self._build_auth_url()
            logger.info("XfyunASRService initialized successfully")
            self.is_available = True
            return True
        except Exception as e:
            logger.error(f"XfyunASRService init failed: {e}")
            self.is_available = False
            return False

    def _build_auth_url(self) -> str:
        """
        HMAC-SHA256 鉴权 URL
        签名原文: host: {host}\ndate: {date}\nGET /v1 HTTP/1.1
        """
        date = time.strftime("%a, %d %b %Y %H:%M:%S %Z", time.gmtime())

        signature_origin = f"host: {self.HOST}\ndate: {date}\nGET /v1 HTTP/1.1"

        signature_sha = hmac.new(
            self.api_secret.encode('utf-8'),
            signature_origin.encode('utf-8'),
            digestmod=hashlib.sha256
        ).digest()
        signature = base64.b64encode(signature_sha).decode('utf-8')

        authorization_origin = (
            f'api_key="{self.api_key}", '
            f'algorithm="hmac-sha256", '
            f'headers="host date request-line", '
            f'signature="{signature}"'
        )
        authorization = base64.b64encode(authorization_origin.encode('utf-8')).decode('utf-8')

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
        同步转录接口（兼容 Whisper 接口）

        Args:
            audio_bytes: PCM float32 stereo 44100Hz（Godot 原始格式）
            language: 语言模式

        Returns:
            XfyunASRResult
        """
        if not self.is_available:
            raise RuntimeError("XfyunASRService not initialized")

        try:
            xfyun_audio = AudioConverter.convert_to_xfyun_format(audio_bytes)
            logger.debug(f"Audio converted: {len(audio_bytes)} -> {len(xfyun_audio)} bytes")
        except Exception as e:
            logger.error(f"Audio conversion failed: {e}")
            raise

        url = self._build_auth_url()

        try:
            ws = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: websocket.create_connection(url, timeout=10)
            )

            result_text = []
            try:
                chunk_size = 1280  # 40ms @ 16kHz mono int16
                chunk_idx = 0

                for i in range(0, len(xfyun_audio), chunk_size):
                    chunk = xfyun_audio[i:i + chunk_size]
                    is_last = (i + chunk_size >= len(xfyun_audio))

                    if chunk_idx == 0:
                        audio_status = 0
                    elif is_last:
                        audio_status = 2
                    else:
                        audio_status = 1

                    audio_b64 = base64.b64encode(chunk).decode('utf-8')

                    # 首帧: header + parameter + payload
                    # 中间/末帧: header + payload
                    if chunk_idx == 0:
                        message = json.dumps({
                            "header": {
                                "app_id": self.app_id,
                                "status": 0,
                            },
                            "parameter": {
                                "iat": {
                                    "domain": "slm",
                                    "language": "mul_cn",
                                    "accent": "mandarin",
                                    "eos": 6000,
                                    "result": {
                                        "encoding": "utf8",
                                        "compress": "raw",
                                        "format": "json",
                                    },
                                }
                            },
                            "payload": {
                                "audio": {
                                    "encoding": "raw",
                                    "sample_rate": 16000,
                                    "channels": 1,
                                    "bit_depth": 16,
                                    "seq": chunk_idx,
                                    "status": audio_status,
                                    "audio": audio_b64,
                                }
                            }
                        })
                        logger.debug(f"First frame sent: chunks_total≈{len(xfyun_audio)//chunk_size + 1}")
                    else:
                        message = json.dumps({
                            "header": {
                                "app_id": self.app_id,
                                "status": audio_status,
                            },
                            "payload": {
                                "audio": {
                                    "encoding": "raw",
                                    "sample_rate": 16000,
                                    "status": audio_status,
                                    "audio": audio_b64,
                                }
                            }
                        })

                    await asyncio.get_event_loop().run_in_executor(
                        None,
                        lambda m=message: ws.send(m)
                    )

                    chunk_idx += 1
                    await asyncio.sleep(0.04)

                    # 非阻塞接收
                    ws.settimeout(0.01)
                    try:
                        response = await asyncio.get_event_loop().run_in_executor(
                            None,
                            lambda: ws.recv()
                        )
                        text = self._extract_text(response)
                        if text:
                            result_text.append(text)
                            logger.debug(f"Partial result: {text}")
                    except websocket.WebSocketTimeoutException:
                        pass

                # 接收所有响应直到服务端 status=2
                ws.settimeout(5.0)
                for _ in range(50):
                    try:
                        response = await asyncio.get_event_loop().run_in_executor(
                            None,
                            lambda: ws.recv()
                        )
                        resp = json.loads(response) if response else {}

                        header = resp.get("header", {})
                        code = header.get("code", -1)
                        if code != 0:
                            logger.warning(f"Xfyun ASR error: code={code}, message={header.get('message', '')}")
                            break

                        text = self._extract_text(response)
                        if text and (not result_text or text != result_text[-1]):
                            result_text.append(text)

                        if header.get("status") == 2:
                            break
                    except websocket.WebSocketTimeoutException:
                        logger.warning("Timeout waiting for final response")
                        break

            finally:
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: ws.close()
                )

            final_text = "".join(result_text) if result_text else ""
            logger.info(f"Xfyun ASR success: '{final_text[:50]}' ({len(final_text)} chars)")

            return XfyunASRResult(
                text=final_text,
                is_final=True,
                confidence=0.9,
                language=language
            )

        except websocket.WebSocketException as e:
            logger.error(f"WebSocket error: {e}")
            raise
        except Exception as e:
            logger.error(f"Xfyun ASR failed: {e}")
            raise

    def _extract_text(self, response: str) -> str:
        """
        从讯飞响应中提取文本
        响应 payload.result.text 是 base64 编码的 JSON
        """
        try:
            if not response:
                return ""
            resp = json.loads(response)
            header = resp.get("header", {})
            if header.get("code", -1) != 0:
                return ""

            result = resp.get("payload", {}).get("result", {})
            text_b64 = result.get("text", "")
            if not text_b64:
                return ""

            decoded = json.loads(base64.b64decode(text_b64).decode('utf-8'))

            # 讯飞返回结构：可能是 {"rt": [{"ws": [...]}]} 或 {"ws": [...]}
            texts = []

            # 尝试 rt 结构
            rt_list = decoded.get("rt", [])
            if rt_list:
                for rt in rt_list:
                    for ws in rt.get("ws", []):
                        for cw in ws.get("cw", []):
                            w = cw.get("w", "")
                            if w:
                                texts.append(w)
            else:
                # 直接 ws 结构
                for ws in decoded.get("ws", []):
                    for cw in ws.get("cw", []):
                        w = cw.get("w", "")
                        if w:
                            texts.append(w)

            return "".join(texts)

        except Exception as e:
            logger.error(f"Extract text error: {e}")
            return ""


xfyun_asr_service = XfyunASRService()
