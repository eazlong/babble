"""深度补评端点（第一版 stub，ADR-0004）。

第一版实现：
- /deep-assess/batch：筛 C∩D 关键资料 → 调 assessment-service /score 规则打分作占位
  → 写 deep_assessment_status + deep_mastery_score。
  ASR 重跑/LLM 升级分支预留 TODO，不实现。
- /deep-assess/escalate-llm：LLM 升级端点签名预留，返回 501。

后续阶段补全：voice-service ASR 重跑 + LLM 评判 + 升级判定规则。
"""

import logging
from typing import Optional

import httpx
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from src import config, supabase_client
from src.services import knowledge_item_resolver

logger = logging.getLogger("src.deep_assessment")

router = APIRouter()


class BatchRequest(BaseModel):
    child_id: str
    session_id: Optional[str] = None
    # 第一版：是否只补缺失评分的（True）或也补临界带的（False）。
    only_missing: bool = True


@router.post("/api/v1/summary/deep-assess/batch")
async def deep_assess_batch(req: BatchRequest):
    client = supabase_client.get_client()
    if client is None:
        return {"assessed": 0, "persisted": False, "note": "no supabase configured"}

    # 取该 child 的交互尝试，筛关键资料（第一版简化：有 asr_text 且 realtime 分数缺失或临界）。
    try:
        query = client.table("interaction_attempts").select(
            "interaction_attempt_id,child_id,asr_text,realtime_mastery_score,"
            "knowledge_item_id,prompt_turn_id"
        ).eq("child_id", req.child_id)
        if req.session_id:
            query = query.eq("session_id", req.session_id)
        resp = query.execute()
        rows = resp.data or []
    except Exception as exc:
        logger.error("load attempts for deep-assess failed: %s", exc)
        return {"assessed": 0, "error": str(exc)}

    assessed = 0
    low, high = config.DEEP_ASSESS_CRITICAL_BAND

    for row in rows:
        asr_text = row.get("asr_text") or ""
        if not asr_text:
            continue
        realtime = row.get("realtime_mastery_score")

        # C∩D 筛选简化：缺失评分 或 落临界带。
        is_missing = realtime is None
        is_critical = realtime is not None and low <= realtime <= high
        if req.only_missing and not is_missing:
            continue
        if not (is_missing or is_critical):
            continue

        # 占位：调 assessment-service /score 规则打分。
        score = await _rule_score(asr_text, row.get("prompt_turn_id", ""))
        if score is None:
            continue

        from datetime import datetime, timezone
        try:
            client.table("interaction_attempts").update({
                "deep_assessment_status": "completed",
                "deep_mastery_score": score,
                "deep_assessed_at": datetime.now(timezone.utc).isoformat(),
            }).eq("interaction_attempt_id", row["interaction_attempt_id"]).execute()
            assessed += 1
        except Exception as exc:
            logger.error("update deep score failed: %s", exc)

    return {"assessed": assessed, "persisted": True}


@router.post("/api/v1/summary/deep-assess/escalate-llm")
async def escalate_llm():
    # TODO ADR-0004 phase 2：实现 LLM 评判（ASR 文本 + 场景内容 + 目标句 → 掌握分 + 理由）。
    raise HTTPException(status_code=501, detail="LLM escalation not implemented in phase 1")


async def _rule_score(player_input: str, quest_id: str) -> Optional[float]:
    """调 assessment-service /score 作占位补评。返回 0-1 掌握分。"""
    try:
        async with httpx.AsyncClient(timeout=15.0) as http:
            resp = await http.post(
                f"{config.ASSESSMENT_SERVICE_URL}/api/v1/assessment/score",
                json={
                    "user_id": "summary-service",
                    "quest_id": quest_id,
                    "player_input": player_input,
                    "context": {},
                },
            )
            resp.raise_for_status()
            data = resp.json()
        scores = data.get("scores", {})
        accuracy = float(scores.get("accuracy", 50)) / 100.0
        fluency = float(scores.get("fluency", 50)) / 100.0
        vocabulary = float(scores.get("vocabulary", 50)) / 100.0
        return round((accuracy + fluency + vocabulary) / 3, 4)
    except Exception as exc:
        logger.warning("rule score failed for quest=%s: %s", quest_id, exc)
        return None
