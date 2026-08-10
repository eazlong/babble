"""报告构建器。

从 mastery_state 派生两份视图（CONTEXT.md "诊断层"）：
- 玩家视图：游戏化、低压力、共鸣度语言（掌握项/薄弱项/星辉/明日预告）。
- 策划诊断视图：掌握/未掌握明细、保留强度排行、补评依据、趋势。

诊断层只描述"学得怎么样"，不开处方（处方由 quest-service 出，ADR-0005）。
"""

from typing import Iterable

BAND_LABEL_PLAYER = {
    "mastered": "已掌握",
    "partial": "接近掌握",
    "unmastered": "需要复习",
}


def build_player_report(
    child_id: str,
    mastery_states: Iterable[dict],
    session_id: str | None = None,
) -> dict:
    """玩家视图：游戏化修复报告。"""
    states = list(mastery_states)
    mastered = [s for s in states if s.get("mastery_band") == "mastered"]
    partial = [s for s in states if s.get("mastery_band") == "partial"]
    unmastered = [s for s in states if s.get("mastery_band") == "unmastered"]

    return {
        "child_id": child_id,
        "session_id": session_id,
        "summary": {
            "mastered_count": len(mastered),
            "partial_count": len(partial),
            "unmastered_count": len(unmastered),
        },
        "mastered": [_player_item(s) for s in mastered],
        "in_progress": [_player_item(s) for s in partial],
        "needs_review": [_player_item(s) for s in unmastered],
        "next_preview": "明日修复令将包含需要复习的词灵",
    }


def build_diagnosis_report(
    child_id: str,
    mastery_states: Iterable[dict],
) -> dict:
    """策划诊断视图：诊断层，供内容策划看。"""
    states = list(mastery_states)
    # 按保留强度升序（最薄弱在前）。
    ranked = sorted(states, key=lambda s: s.get("retention_strength", 1.0))

    mastered = [s for s in states if s.get("mastery_band") == "mastered"]
    partial = [s for s in states if s.get("mastery_band") == "partial"]
    unmastered = [s for s in states if s.get("mastery_band") == "unmastered"]

    # 薄弱项：未掌握 + 部分掌握，按保留强度升序。
    weak = [s for s in ranked if s.get("mastery_band") in ("unmastered", "partial")]

    return {
        "child_id": child_id,
        "diagnosis": {
            "total_items": len(states),
            "mastered_count": len(mastered),
            "partial_count": len(partial),
            "unmastered_count": len(unmastered),
        },
        "mastery_breakdown": {
            "mastered": [_diag_item(s) for s in mastered],
            "partial": [_diag_item(s) for s in partial],
            "unmastered": [_diag_item(s) for s in unmastered],
        },
        "weak_items_ranked": [_diag_item(s) for s in weak],
        "note": "诊断层只描述掌握度；下次内容（处方）由 quest-service 生成。",
    }


def _player_item(state: dict) -> dict:
    kid = state.get("knowledge_item_id", "")
    label = kid.split(":", 1)[1] if ":" in kid else kid
    band = state.get("mastery_band", "partial")
    return {
        "item": label,
        "knowledge_item_id": kid,
        "status": BAND_LABEL_PLAYER.get(band, band),
        "stars": _stars_for_band(band),
    }


def _diag_item(state: dict) -> dict:
    return {
        "knowledge_item_id": state.get("knowledge_item_id", ""),
        "item_type": state.get("item_type", ""),
        "retention_strength": state.get("retention_strength", 0.0),
        "mastery_band": state.get("mastery_band", ""),
        "current_half_life_days": state.get("current_half_life_days", 0.0),
        "last_mastery_score": state.get("last_mastery_score", 0.0),
        "assessment_count": state.get("assessment_count", 0),
        "last_assessed_at": state.get("last_assessed_at", ""),
    }


def _stars_for_band(band: str) -> int:
    if band == "mastered":
        return 3
    if band == "partial":
        return 2
    return 1
