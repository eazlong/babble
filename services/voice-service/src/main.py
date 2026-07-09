import logging

from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logging.getLogger("src").setLevel(logging.INFO)

from fastapi import FastAPI
from src.api.routes import health
from src.api.routes import asr
from src.api.routes import tts
from src.services.service_manager import service_manager

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)
app.include_router(asr.router)
app.include_router(tts.router)


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup."""
    # 使用ServiceManager统一初始化所有引擎
    await service_manager.init_all()


@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "service": "voice-service",
        "mode": service_manager.mode.value
    }
