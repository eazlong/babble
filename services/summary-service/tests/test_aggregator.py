"""aggregator 单元测试：掌握度回放聚合。"""

from datetime import datetime, timedelta, timezone

from src.services.aggregator import aggregate


def _iso(dt):
    return dt.isoformat()


class TestAggregate:
    def test_single_assessment_initial_half_life(self):
        now = datetime.now(timezone.utc)
        attempts = [{
            "knowledge_item_id": "word:apple",
            "mastery_score": 0.9,
            "created_at": _iso(now - timedelta(hours=1)),
        }]
        states = aggregate("child1", attempts, now=now)
        assert len(states) == 1
        s = states[0]
        assert s["knowledge_item_id"] == "word:apple"
        assert s["item_type"] == "word"
        assert s["assessment_count"] == 1
        # 清晰档 ×1.6 → 3.0 * 1.6 = 4.8
        assert s["current_half_life_days"] == round(4.8, 4)
        assert s["mastery_band"] == "mastered"

    def test_multiple_items_grouped(self):
        now = datetime.now(timezone.utc)
        attempts = [
            {"knowledge_item_id": "word:apple", "mastery_score": 0.9, "created_at": _iso(now - timedelta(hours=2))},
            {"knowledge_item_id": "word:cat", "mastery_score": 0.3, "created_at": _iso(now - timedelta(hours=1))},
        ]
        states = aggregate("child1", attempts, now=now)
        assert len(states) == 2
        kids = {s["knowledge_item_id"] for s in states}
        assert kids == {"word:apple", "word:cat"}

    def test_replay_accumulates_half_life(self):
        now = datetime.now(timezone.utc)
        # 连续两次清晰答对：3.0 → 4.8 → 7.68
        attempts = [
            {"knowledge_item_id": "word:apple", "mastery_score": 0.9, "created_at": _iso(now - timedelta(days=2))},
            {"knowledge_item_id": "word:apple", "mastery_score": 0.9, "created_at": _iso(now - timedelta(days=1))},
        ]
        states = aggregate("child1", attempts, now=now)
        s = states[0]
        assert s["assessment_count"] == 2
        # 3.0 * 1.6 * 1.6 = 7.68
        assert s["current_half_life_days"] == round(7.68, 4)

    def test_wrong_answer_shrinks_half_life(self):
        now = datetime.now(timezone.utc)
        attempts = [
            {"knowledge_item_id": "word:apple", "mastery_score": 0.9, "created_at": _iso(now - timedelta(days=2))},
            {"knowledge_item_id": "word:apple", "mastery_score": 0.1, "created_at": _iso(now - timedelta(days=1))},
        ]
        states = aggregate("child1", attempts, now=now)
        s = states[0]
        # 3.0 * 1.6 = 4.8 → 4.8 * 0.4 = 1.92
        assert s["current_half_life_days"] == round(1.92, 4)

    def test_skips_attempts_without_score(self):
        now = datetime.now(timezone.utc)
        attempts = [
            {"knowledge_item_id": "word:apple", "mastery_score": None, "created_at": _iso(now)},
            {"knowledge_item_id": "word:apple", "mastery_score": 0.9, "created_at": _iso(now)},
        ]
        states = aggregate("child1", attempts, now=now)
        assert len(states) == 1
        assert states[0]["assessment_count"] == 1

    def test_empty_attempts(self):
        assert aggregate("child1", []) == []

    def test_old_assessment_decays_to_unmastered(self):
        now = datetime.now(timezone.utc)
        # 半衰期 3.0，10 天前答对一次 → 强度 0.5^(10/4.8)... 先看单次答对后半衰期 4.8
        attempts = [{
            "knowledge_item_id": "word:apple",
            "mastery_score": 0.9,
            "created_at": _iso(now - timedelta(days=10)),
        }]
        states = aggregate("child1", attempts, now=now)
        s = states[0]
        # 半衰期 4.8，10 天 → 0.5^(10/4.8) ≈ 0.236 → unmastered
        assert s["retention_strength"] < 0.40
        assert s["mastery_band"] == "unmastered"
