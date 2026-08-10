from fastapi import APIRouter

router = APIRouter()


@router.get("/api/v1/summary/health")
async def health():
    return {"status": "ok", "service": "summary-service"}


@router.get("/ping")
async def ping():
    return {"pong": True}
