"""掌握度聚合器。

按知识项聚合交互尝试，用半衰期模型回放算当前掌握度。
采用 replay 模式：从 INITIAL_HALF_LIFE 开始按时间序回放所有考查，
累积算半衰期状态。这样无需持久化中间态也能重算，且确定性可测试。
"""

from datetime import datetime, timezone
from typing import Iterable

from src.services import mastery_engine
from src.services.knowledge_item_resolver import item_type_from_id


def aggregate(
    child_id: str,
    attempts: Iterable[dict],
    now: datetime | None = None,
) -> list[dict]:
    """聚合某儿童的全部交互尝试 → 掌握度状态列表。

    每个 attempt 需含：knowledge_item_id, mastery_score (0-1), created_at (datetime|iso str)。
    返回 [{child_id, knowledge_item_id, item_type, current_half_life_days,
           last_assessed_at, last_mastery_score, assessment_count,
           retention_strength, mastery_band}]。
    """
    if now is None:
        now = datetime.now(timezone.utc)

    # 按 knowledge_item_id 分组并按时间排序。
    grouped: dict[str, list[dict]] = {}
    for att in attempts:
        kid = att.get("knowledge_item_id", "")
        score = att.get("mastery_score")
        if not kid or score is None:
            continue
        grouped.setdefault(kid, []).append(att)

    results = []
    for kid, items in grouped.items():
        items.sort(key=lambda a: _as_dt(a.get("created_at")))
        half_life = mastery_engine.INITIAL_HALF_LIFE
        last_score = 0.0
        last_at = _as_dt(items[0].get("created_at"))
        for it in items:
            score = float(it.get("mastery_score"))
            applied = mastery_engine.apply_assessment(half_life, score)
            half_life = applied["new_half_life"]
            last_score = score
            last_at = _as_dt(it.get("created_at"))

        computed = mastery_engine.compute_mastery(half_life, last_at, last_score, now)
        results.append({
            "child_id": child_id,
            "knowledge_item_id": kid,
            "item_type": item_type_from_id(kid),
            "current_half_life_days": computed["half_life"],
            "last_assessed_at": last_at.isoformat(),
            "last_mastery_score": round(last_score, 4),
            "assessment_count": len(items),
            "retention_strength": computed["retention_strength"],
            "mastery_band": computed["mastery_band"],
        })

    return results


def _as_dt(value) -> datetime:
    """把 iso 字符串或 datetime 统一为 timezone-aware datetime。"""
    if isinstance(value, datetime):
        dt = value
    elif value:
        dt = datetime.fromisoformat(str(value))
    else:
        dt = datetime.now(timezone.utc)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt
