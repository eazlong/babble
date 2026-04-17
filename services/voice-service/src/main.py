from fastapi import FastAPI
from src.api.routes import health

app = FastAPI(title="LinguaQuest Voice Service", version="0.1.0")
app.include_router(health.router)


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "voice-service"}
