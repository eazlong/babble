import logging
import time

from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logging.getLogger("src").setLevel(logging.INFO)

from fastapi import FastAPI
from src.api.routes import health
from src.api.routes import asr
from src.api.routes import tts
from src.services.asr_postprocess import asr_postprocessor
from src.services.service_manager import service_manager

logger = logging.getLogger(__name__)

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)
app.include_router(asr.router)
app.include_router(tts.router)

# 最近一次 postprocess provider 探针结果，由 /health 暴露。
# 见 docs/plans/2026-09-15-intent-accuracy.md §15.4：F6 守卫把 provider 故障从
# "每个请求 500"变成"安静降级"，必须有一条能主动喊出来的通道。
_postprocess_health: dict = {"status": "unknown", "reason": "尚未探测"}


async def probe_postprocess_provider() -> dict:
    """跑一次 provider 探针并把结果记入 /health。失败只报错，不停服。"""
    global _postprocess_health
    result = await asr_postprocessor.check_provider()
    _postprocess_health = {**result, "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z")}

    if result.get("status") == "ok":
        logger.info(
            "[ASR-POSTPROCESS] provider probe ok base_url=%s model=%s latency_ms=%s",
            result.get("base_url"),
            result.get("model"),
            result.get("latency_ms"),
        )
    elif result.get("status") == "disabled":
        logger.info("[ASR-POSTPROCESS] provider probe skipped: disabled")
    else:
        logger.error(
            "[ASR-POSTPROCESS] provider probe FAILED status=%s base_url=%s model=%s reason=%s"
            " —— 意图判定将全程降级（客户端退回 corrected_text）：既不纠错也不判 off_topic。"
            " 常见原因：BASE_URL 少了 /v1（会拿到站点首页 HTML）、密钥失效、网关不可达。",
            result.get("status"),
            result.get("base_url"),
            result.get("model"),
            result.get("reason"),
        )
    return _postprocess_health


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup."""
    # 使用ServiceManager统一初始化所有引擎
    await service_manager.init_all()
    # 探针放在引擎初始化之后：它不影响引擎可用性，但必须尽早给出结论
    await probe_postprocess_provider()


@app.on_event("shutdown")
async def shutdown_event():
    """关停时释放复用的 LLM 客户端（连接池）。"""
    await asr_postprocessor.aclose()


@app.get("/health")
async def health_check(probe: int = 0):
    """服务健康。

    `probe=1` 会**重新**跑一次 provider 探针（默认用启动时的结果，避免每次健康检查都打 provider）。
    HTTP 状态刻意保持 200：容器 HEALTHCHECK 只看 200，若在这里返回 5xx，编排器可能陷入重启风暴。
    provider 的真实状态放在 `postprocess` 字段里（Dockerfile 的 HEALTHCHECK 会读它判定 unhealthy）。
    """
    if probe:
        await probe_postprocess_provider()
    return {
        "status": "ok",
        "service": "voice-service",
        "mode": service_manager.mode.value,
        "postprocess": _postprocess_health,
    }
