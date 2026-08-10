"""接收客户端上报：游戏会话 / 提示轮次 / 交互尝试。

数据落 child_data schema（migration 019）。收到交互尝试后触发掌握度更新。
未配置 SUPABASE_KEY 时降级为无持久化模式（仅日志），便于本地开发。
"""

import logging
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

from src import supabase_client
from src.services import knowledge_item_resolver
from src.services.aggregator import aggregate

logger = logging.getLogger("src.ingest")

router = APIRouter()


# ── 请求模型 ────────────────────────────────────────────────────────

class SessionReport(BaseModel):
    session_id: str
    child_id: str
    client_session_id: str
    scene_id: str
    status: str = "active"
    started_at: Optional[str] = None
    ended_at: Optional[str] = None
    end_reason: Optional[str] = None


class PromptTurnReport(BaseModel):
    prompt_turn_id: str
    session_id: str
    child_id: str
    scene_id: str
    quest_id: str = ""
    content_id: str = ""
    content_version: int = 1
    prompt_text_snapshot: str = ""
    target_utterance_snapshot: str = ""
    expected_answer_type: str = "short_answer"
    assessment_rule_version: str = "v1"
    created_at: Optional[str] = None


class InteractionAttemptReport(BaseModel):
    interaction_attempt_id: str
    session_id: str
    prompt_turn_id: str
    child_id: str
    local_attempt_id: str
    attempt_index: int = 0
    attempt_type: str = "short_answer"
    recording_status: str = "not_started"
    asr_status: str = "not_started"
    asr_text: str = ""
    realtime_assessment_status: str = "not_started"
    realtime_mastery_score: Optional[float] = None
    deep_assessment_status: str = "not_started"
    deep_mastery_score: Optional[float] = None
    knowledge_item_id: str = ""
    recording_file_path: str = ""
    created_at: Optional[str] = None
    # 提示轮次的 content_id / target_utterance，用于推导 knowledge_item_id。
    content_id_hint: str = ""
    target_utterance_hint: str = ""
    expected_answer_type_hint: str = ""


# ── 路由 ────────────────────────────────────────────────────────────

@router.post("/api/v1/summary/sessions")
async def ingest_session(req: SessionReport):
    client = supabase_client.get_client()
    if client is None:
        logger.info("[no-persist] session %s child=%s scene=%s", req.session_id, req.child_id, req.scene_id)
        return {"accepted": True, "persisted": False}

    row = req.model_dump()
    if row.get("started_at") is None:
        row["started_at"] = datetime.now(timezone.utc).isoformat()
    try:
        client.table("learning_sessions").upsert(row, on_conflict="child_id,client_session_id").execute()
    except Exception as exc:
        logger.error("upsert learning_sessions failed: %s", exc)
        return {"accepted": False, "error": str(exc)}
    return {"accepted": True, "persisted": True}


@router.post("/api/v1/summary/prompt-turns")
async def ingest_prompt_turn(req: PromptTurnReport):
    client = supabase_client.get_client()
    if client is None:
        logger.info("[no-persist] prompt_turn %s", req.prompt_turn_id)
        return {"accepted": True, "persisted": False}

    row = req.model_dump()
    if row.get("created_at") is None:
        row["created_at"] = datetime.now(timezone.utc).isoformat()
    try:
        client.table("prompt_turns").upsert(row).execute()
    except Exception as exc:
        logger.error("upsert prompt_turns failed: %s", exc)
        return {"accepted": False, "error": str(exc)}
    return {"accepted": True, "persisted": True}


@router.post("/api/v1/summary/interaction-attempts")
async def ingest_interaction_attempt(req: InteractionAttemptReport):
    # 推导 knowledge_item_id（若客户端未传）。
    kid = req.knowledge_item_id
    if not kid:
        kid = knowledge_item_resolver.resolve(
            req.content_id_hint or "",
            req.target_utterance_hint,
            req.expected_answer_type_hint or req.attempt_type,
        ) or ""

    client = supabase_client.get_client()
    if client is None:
        logger.info(
            "[no-persist] attempt %s kid=%s score=%s",
            req.interaction_attempt_id, kid, req.realtime_mastery_score,
        )
        return {"accepted": True, "persisted": False, "knowledge_item_id": kid}

    row = req.model_dump(exclude={"content_id_hint", "target_utterance_hint", "expected_answer_type_hint"})
    row["knowledge_item_id"] = kid
    if row.get("created_at") is None:
        row["created_at"] = datetime.now(timezone.utc).isoformat()

    try:
        client.table("interaction_attempts").upsert(
            row, on_conflict="child_id,local_attempt_id"
        ).execute()
    except Exception as exc:
        logger.error("upsert interaction_attempts failed: %s", exc)
        return {"accepted": False, "error": str(exc)}

    # 触发掌握度更新（实时聚合层：只消费已评分尝试）。
    score = req.realtime_mastery_score
    if score is not None and kid:
        _refresh_mastery(client, req.child_id, kid)

    return {"accepted": True, "persisted": True, "knowledge_item_id": kid}


def _refresh_mastery(client, child_id: str, knowledge_item_id: str) -> None:
    """重新聚合某知识项的掌握度并 upsert mastery_state。"""
    try:
        resp = client.table("interaction_attempts").select(
            "knowledge_item_id,realtime_mastery_score,deep_mastery_score,created_at"
        ).eq("child_id", child_id).eq("knowledge_item_id", knowledge_item_id).execute()
        attempts = []
        for row in (resp.data or []):
            score = row.get("deep_mastery_score")
            if score is None:
                score = row.get("realtime_mastery_score")
            attempts.append({
                "knowledge_item_id": row.get("knowledge_item_id"),
                "mastery_score": score,
                "created_at": row.get("created_at"),
            })
        if not attempts:
            return
        states = aggregate(child_id, attempts)
        if states:
            state = states[0]
            state["updated_at"] = datetime.now(timezone.utc).isoformat()
            client.table("mastery_state").upsert(state).execute()
    except Exception as exc:
        logger.error("refresh mastery failed for %s: %s", knowledge_item_id, exc)
