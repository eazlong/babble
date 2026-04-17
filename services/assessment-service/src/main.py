from fastapi import FastAPI
from src.api.routes import assessment

app = FastAPI(title="LinguaQuest Assessment Service", version="0.1.0")
app.include_router(assessment.router)


@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "assessment-service"}
