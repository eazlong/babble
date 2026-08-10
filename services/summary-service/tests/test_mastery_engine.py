"""mastery_engine 单元测试：半衰期伸缩/衰减/档位切分边界。"""

from datetime import datetime, timedelta, timezone

from src.services import mastery_engine as me


class TestBandForScore:
    def test_clear_threshold(self):
        assert me.band_for_score(0.85) == "clear"
        assert me.band_for_score(1.0) == "clear"

    def test_close_band(self):
        assert me.band_for_score(0.65) == "close"
        assert me.band_for_score(0.84) == "close"

    def test_retry_band(self):
        assert me.band_for_score(0.40) == "retry"
        assert me.band_for_score(0.64) == "retry"

    def test_need_help(self):
        assert me.band_for_score(0.39) == "need_help"
        assert me.band_for_score(0.0) == "need_help"

    def test_boundary_just_below_clear(self):
        assert me.band_for_score(0.8499) == "close"

    def test_boundary_just_below_close(self):
        assert me.band_for_score(0.6499) == "retry"

    def test_boundary_just_below_retry(self):
        assert me.band_for_score(0.3999) == "need_help"


class TestUpdateHalfLife:
    def test_clear_extends_by_1_6(self):
        assert me.update_half_life(3.0, 0.9) == round(3.0 * 1.6, 4)

    def test_close_extends_by_1_2(self):
        assert me.update_half_life(3.0, 0.7) == round(3.0 * 1.2, 4)

    def test_retry_shrinks_by_0_6(self):
        assert me.update_half_life(3.0, 0.5) == round(3.0 * 0.6, 4)

    def test_need_help_shrinks_by_0_4(self):
        assert me.update_half_life(3.0, 0.2) == round(3.0 * 0.4, 4)

    def test_clamped_to_max(self):
        # 30 * 1.6 = 48 → clamp 30
        assert me.update_half_life(me.HALF_LIFE_MAX, 1.0) == me.HALF_LIFE_MAX

    def test_clamped_to_min(self):
        # 0.5 * 0.4 = 0.2 → clamp 0.5
        assert me.update_half_life(me.HALF_LIFE_MIN, 0.0) == me.HALF_LIFE_MIN


class TestRetentionStrength:
    def test_zero_days_full_strength(self):
        assert me.retention_strength(3.0, 0.0) == 1.0

    def test_negative_days_full_strength(self):
        assert me.retention_strength(3.0, -1.0) == 1.0

    def test_one_half_life_halves(self):
        # 经过一个半衰期 → 强度 0.5
        assert abs(me.retention_strength(3.0, 3.0) - 0.5) < 1e-9

    def test_two_half_lives_quarters(self):
        assert abs(me.retention_strength(3.0, 6.0) - 0.25) < 1e-9

    def test_zero_half_life_zero_strength(self):
        assert me.retention_strength(0.0, 1.0) == 0.0


class TestMasteryBand:
    def test_mastered(self):
        assert me.mastery_band(0.70) == me.MASTERY_MASTERED
        assert me.mastery_band(1.0) == me.MASTERY_MASTERED

    def test_partial(self):
        assert me.mastery_band(0.40) == me.MASTERY_PARTIAL
        assert me.mastery_band(0.69) == me.MASTERY_PARTIAL

    def test_unmastered(self):
        assert me.mastery_band(0.39) == me.MASTERY_UNMASTERED
        assert me.mastery_band(0.0) == me.MASTERY_UNMASTERED

    def test_boundary_just_below_mastered(self):
        assert me.mastery_band(0.6999) == me.MASTERY_PARTIAL

    def test_boundary_just_below_partial(self):
        assert me.mastery_band(0.3999) == me.MASTERY_UNMASTERED


class TestComputeMastery:
    def test_recent_assessment_high_strength(self):
        now = datetime.now(timezone.utc)
        last = now - timedelta(hours=1)  # ~0.04 天
        result = me.compute_mastery(3.0, last, 0.9, now)
        assert result["retention_strength"] > 0.95
        assert result["mastery_band"] == me.MASTERY_MASTERED

    def test_old_assessment_decays(self):
        now = datetime.now(timezone.utc)
        last = now - timedelta(days=6)  # 两个半衰期 → 0.25
        result = me.compute_mastery(3.0, last, 0.9, now)
        assert abs(result["retention_strength"] - 0.25) < 1e-3
        assert result["mastery_band"] == me.MASTERY_UNMASTERED


class TestApplyAssessment:
    def test_returns_new_half_life_and_band(self):
        result = me.apply_assessment(3.0, 0.9)
        assert result["new_half_life"] == round(3.0 * 1.6, 4)
        assert result["band"] == "clear"

    def test_shrinks_on_wrong_answer(self):
        result = me.apply_assessment(10.0, 0.1)
        assert result["new_half_life"] == round(10.0 * 0.4, 4)
        assert result["band"] == "need_help"
