from fastapi import APIRouter

router = APIRouter()


@router.get("/api/v1/health")
async def health():
    return {"status": "ok"}


@router.get("/ping")
async def ping():
    """Godot client compatibility ping endpoint."""
    return {"status": "ok", "service": "voice-service"}
