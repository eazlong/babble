"""掌握度查询与重算。"""

import logging
from typing import Optional

from fastapi import APIRouter, Query

from src import supabase_client
from src.services.aggregator import aggregate

logger = logging.getLogger("src.mastery")

router = APIRouter()


@router.get("/api/v1/summary/mastery")
async def get_mastery(
    child_id: str = Query(...),
    item_type: Optional[str] = Query(None),
):
    client = supabase_client.get_client()
    if client is None:
        return {"mastery": [], "persisted": False}

    try:
        query = client.table("mastery_state").select("*").eq("child_id", child_id)
        if item_type:
            query = query.eq("item_type", item_type)
        resp = query.execute()
        return {"mastery": resp.data or [], "persisted": True}
    except Exception as exc:
        logger.error("query mastery failed: %s", exc)
        return {"mastery": [], "error": str(exc)}


@router.post("/api/v1/summary/mastery/recompute")
async def recompute_mastery(
    child_id: str = Query(...),
    session_id: Optional[str] = Query(None),
):
    """手动触发某 child（可选限定 session）的掌握度重算。"""
    client = supabase_client.get_client()
    if client is None:
        return {"recomputed": 0, "persisted": False}

    try:
        query = client.table("interaction_attempts").select(
            "knowledge_item_id,realtime_mastery_score,deep_mastery_score,created_at"
        ).eq("child_id", child_id)
        if session_id:
            query = query.eq("session_id", session_id)
        resp = query.execute()
        rows = resp.data or []
    except Exception as exc:
        logger.error("load attempts for recompute failed: %s", exc)
        return {"recomputed": 0, "error": str(exc)}

    attempts = []
    for row in rows:
        score = row.get("deep_mastery_score")
        if score is None:
            score = row.get("realtime_mastery_score")
        if score is None:
            continue
        attempts.append({
            "knowledge_item_id": row.get("knowledge_item_id"),
            "mastery_score": score,
            "created_at": row.get("created_at"),
        })

    if not attempts:
        return {"recomputed": 0, "persisted": True}

    states = aggregate(child_id, attempts)
    for state in states:
        from datetime import datetime, timezone
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        try:
            client.table("mastery_state").upsert(state).execute()
        except Exception as exc:
            logger.error("upsert mastery_state failed: %s", exc)

    return {"recomputed": len(states), "persisted": True}
