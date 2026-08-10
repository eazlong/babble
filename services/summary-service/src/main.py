import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.routes import health, ingest, mastery, report, deep_assessment

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s: %(name)s: %(message)s",
)

app = FastAPI(title="LinguaQuest Summary Service", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(ingest.router)
app.include_router(mastery.router)
app.include_router(report.router)
app.include_router(deep_assessment.router)


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "summary-service"}
