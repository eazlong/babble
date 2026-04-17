from fastapi import FastAPI
from src.api.routes import health
from src.api.routes import asr
from src.api.routes import tts

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)
app.include_router(asr.router)
app.include_router(tts.router)


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "voice-service"}
