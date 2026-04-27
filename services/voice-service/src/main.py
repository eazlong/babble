from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI
from src.api.routes import health
from src.api.routes import asr
from src.api.routes import tts
from src.services.tts import tts_service

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)
app.include_router(asr.router)
app.include_router(tts.router)


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup."""
    await tts_service.init()


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "voice-service"}
