"""报告端点：玩家视图 + 策划诊断视图。"""

import logging
from typing import Optional

from fastapi import APIRouter, Query

from src import supabase_client
from src.services.aggregator import aggregate
from src.services.report_builder import build_player_report, build_diagnosis_report

logger = logging.getLogger("src.report")

router = APIRouter()


def _load_mastery_states(child_id: str, session_id: Optional[str] = None) -> list[dict]:
    """从 mastery_state 表加载；若空且有 session，则从交互尝试实时聚合。"""
    client = supabase_client.get_client()
    if client is None:
        return []

    try:
        resp = client.table("mastery_state").select("*").eq("child_id", child_id).execute()
        states = resp.data or []
        if states:
            return states
    except Exception as exc:
        logger.error("load mastery_state failed: %s", exc)
        return []

    # 无持久化掌握度，回退到从交互尝试实时聚合。
    if session_id:
        try:
            resp = client.table("interaction_attempts").select(
                "knowledge_item_id,realtime_mastery_score,deep_mastery_score,created_at"
            ).eq("child_id", child_id).eq("session_id", session_id).execute()
            attempts = []
            for row in (resp.data or []):
                score = row.get("deep_mastery_score") or row.get("realtime_mastery_score")
                if score is None:
                    continue
                attempts.append({
                    "knowledge_item_id": row.get("knowledge_item_id"),
                    "mastery_score": score,
                    "created_at": row.get("created_at"),
                })
            if attempts:
                return aggregate(child_id, attempts)
        except Exception as exc:
            logger.error("fallback aggregate failed: %s", exc)
    return []


@router.get("/api/v1/summary/report/player")
async def player_report(
    child_id: str = Query(...),
    session_id: Optional[str] = Query(None),
):
    states = _load_mastery_states(child_id, session_id)
    return build_player_report(child_id, states, session_id)


@router.get("/api/v1/summary/report/diagnosis")
async def diagnosis_report(
    child_id: str = Query(...),
):
    states = _load_mastery_states(child_id, None)
    return build_diagnosis_report(child_id, states)
