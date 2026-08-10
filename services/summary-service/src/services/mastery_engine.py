"""掌握度半衰期模型（ADR-0003）。

掌握度 = 时序遗忘模型算当前保留强度，再用阈值切分掌握/部分/未掌握。
保留强度 = 0.5^(经过天数 / 当前半衰期)。
每次考查后按掌握分所在档位伸缩半衰期并重置衰减起点。

档位阈值与回声廊共鸣度、掌握度阈值同源（0.40 / 0.65 / 0.85）。
"""

import math
from datetime import datetime, timezone

# 新学知识项的初始半衰期（天）。
INITIAL_HALF_LIFE = 3.0

# 半衰期伸缩上下界，防止极端值。
HALF_LIFE_MIN = 0.5
HALF_LIFE_MAX = 30.0

# 掌握分 → 伸缩倍数。复用共鸣度同源阈值。
BAND_MULTIPLIERS = {
    "clear": 1.6,       # 掌握分 >= 0.85
    "close": 1.2,       # 0.65 - 0.84
    "retry": 0.6,       # 0.40 - 0.64
    "need_help": 0.4,   # < 0.40
}

# 掌握度档位切分（当前保留强度 → 档位）。
MASTERY_MASTERED = "mastered"      # >= 0.70
MASTERY_PARTIAL = "partial"        # 0.40 - 0.69
MASTERY_UNMASTERED = "unmastered"  # < 0.40


def band_for_score(score: float) -> str:
    """掌握分（0-1）→ 共鸣度档位名。"""
    if score >= 0.85:
        return "clear"
    if score >= 0.65:
        return "close"
    if score >= 0.40:
        return "retry"
    return "need_help"


def update_half_life(current: float, score: float) -> float:
    """按本次掌握分所在档位伸缩半衰期，clamp 到 [MIN, MAX]。"""
    band = band_for_score(score)
    multiplier = BAND_MULTIPLIERS[band]
    updated = current * multiplier
    return round(max(HALF_LIFE_MIN, min(HALF_LIFE_MAX, updated)), 4)


def retention_strength(half_life: float, days_since: float) -> float:
    """当前保留强度 = 0.5^(经过天数 / 半衰期)。days_since 为负时返回 1.0。"""
    if days_since <= 0:
        return 1.0
    if half_life <= 0:
        return 0.0
    return 0.5 ** (days_since / half_life)


def mastery_band(strength: float) -> str:
    """保留强度 → 掌握度档位。"""
    if strength >= 0.70:
        return MASTERY_MASTERED
    if strength >= 0.40:
        return MASTERY_PARTIAL
    return MASTERY_UNMASTERED


def days_between(later: datetime, earlier: datetime) -> float:
    """两个时间点之间的天数差（later - earlier），用于衰减计算。"""
    if later.tzinfo is None:
        later = later.replace(tzinfo=timezone.utc)
    if earlier.tzinfo is None:
        earlier = earlier.replace(tzinfo=timezone.utc)
    delta = (later - earlier).total_seconds()
    return delta / 86400.0


def compute_mastery(
    current_half_life: float,
    last_assessed_at: datetime,
    last_mastery_score: float,
    now: datetime,
) -> dict:
    """根据半衰期状态计算当前掌握度。

    返回 {retention_strength, mastery_band, half_life}。
    保留强度按"距上次考查的天数"衰减。
    """
    days = days_between(now, last_assessed_at)
    strength = retention_strength(current_half_life, days)
    band = mastery_band(strength)
    return {
        "retention_strength": round(strength, 4),
        "mastery_band": band,
        "half_life": current_half_life,
    }


def apply_assessment(
    current_half_life: float,
    mastery_score: float,
) -> dict:
    """一次考查后更新半衰期状态。

    返回 {new_half_life, band}。调用方负责持久化 new_half_life 和 last_assessed_at。
    """
    new_half_life = update_half_life(current_half_life, mastery_score)
    return {
        "new_half_life": round(new_half_life, 4),
        "band": band_for_score(mastery_score),
    }
