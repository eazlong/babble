"""report_builder 单元测试：两视图报告结构。"""

from src.services.report_builder import build_player_report, build_diagnosis_report


def _state(kid, band, strength=0.5, count=1):
    return {
        "knowledge_item_id": kid,
        "item_type": kid.split(":", 1)[0] if ":" in kid else "",
        "mastery_band": band,
        "retention_strength": strength,
        "current_half_life_days": 3.0,
        "last_mastery_score": 0.7,
        "assessment_count": count,
        "last_assessed_at": "2026-07-28T00:00:00+00:00",
    }


class TestPlayerReport:
    def test_partitions_by_band(self):
        states = [
            _state("word:apple", "mastered", 0.9),
            _state("word:cat", "partial", 0.5),
            _state("word:dog", "unmastered", 0.2),
        ]
        report = build_player_report("child1", states, "session1")
        assert report["child_id"] == "child1"
        assert report["session_id"] == "session1"
        assert len(report["mastered"]) == 1
        assert len(report["in_progress"]) == 1
        assert len(report["needs_review"]) == 1
        assert report["summary"]["mastered_count"] == 1

    def test_item_label_strips_prefix(self):
        states = [_state("word:apple", "mastered")]
        report = build_player_report("child1", states)
        assert report["mastered"][0]["item"] == "apple"

    def test_stars_by_band(self):
        states = [
            _state("word:a", "mastered"),
            _state("word:b", "partial"),
            _state("word:c", "unmastered"),
        ]
        report = build_player_report("child1", states)
        assert report["mastered"][0]["stars"] == 3
        assert report["in_progress"][0]["stars"] == 2
        assert report["needs_review"][0]["stars"] == 1


class TestDiagnosisReport:
    def test_breakdown_and_ranking(self):
        states = [
            _state("word:apple", "mastered", 0.9),
            _state("word:cat", "unmastered", 0.2),
            _state("word:dog", "partial", 0.5),
        ]
        report = build_diagnosis_report("child1", states)
        assert report["diagnosis"]["total_items"] == 3
        assert report["diagnosis"]["mastered_count"] == 1
        assert report["diagnosis"]["unmastered_count"] == 1
        # weak = partial + unmastered，按强度升序：cat(0.2) 在 dog(0.5) 前
        weak = report["weak_items_ranked"]
        assert len(weak) == 2
        assert weak[0]["knowledge_item_id"] == "word:cat"
        assert weak[1]["knowledge_item_id"] == "word:dog"

    def test_note_mentions_quest(self):
        report = build_diagnosis_report("child1", [])
        assert "quest" in report["note"]

    def test_diag_item_fields(self):
        states = [_state("word:apple", "mastered", 0.9, count=3)]
        report = build_diagnosis_report("child1", states)
        item = report["mastery_breakdown"]["mastered"][0]
        assert item["retention_strength"] == 0.9
        assert item["assessment_count"] == 3
        assert item["item_type"] == "word"
