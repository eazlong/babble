"""Comprehensive tests for assessment-service."""
import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app
from src.services.micro_assessment import MicroAssessmentService, AssessmentScores


# ============================================================
# API Endpoint Tests
# ============================================================

class TestMicroAssessmentEndpoint:
    """Tests for POST /api/v1/assessment/micro."""

    @pytest.mark.asyncio
    async def test_basic_request(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/micro",
                json={
                    "user_id": "user-1",
                    "session_id": "session-1",
                    "quest_id": "quest-1",
                    "dialogue_turns": [{"asr_text": "Hello world"}, {"asr_text": "How are you"}],
                    "asr_confidence_scores": [0.9, 0.85],
                    "response_times_ms": [2000, 2500]
                }
            )
        assert response.status_code == 200
        data = response.json()
        assert "scores" in data
        assert "radar_chart" in data

    @pytest.mark.asyncio
    async def test_empty_dialogue_returns_zeros(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/micro",
                json={
                    "user_id": "user-2",
                    "session_id": "session-2",
                    "quest_id": "quest-2",
                    "dialogue_turns": [],
                    "asr_confidence_scores": [],
                    "response_times_ms": []
                }
            )
        assert response.status_code == 200
        data = response.json()
        assert data["scores"]["accuracy"] == 0
        assert data["scores"]["fluency"] == 0
        assert data["scores"]["vocabulary"] == 0


class TestScoreEndpoint:
    """Tests for POST /api/v1/assessment/score."""

    @pytest.mark.asyncio
    async def test_greet_oakley_keyword_match(self):
        """Player says hello and introduces name."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/score",
                json={"user_id": "u1", "quest_id": "greet_oakley", "player_input": "Hello! My name is Tom."}
            )
        assert response.status_code == 200
        data = response.json()
        # Should have keyword matches for "hello" and "my name"
        assert data["scores"]["accuracy"] > 60

    @pytest.mark.asyncio
    async def test_activate_flowers_color_match(self):
        """Player says multiple color names."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/score",
                json={"user_id": "u1", "quest_id": "activate_flowers", "player_input": "Red and blue are my favorite colors!"}
            )
        assert response.status_code == 200
        data = response.json()
        # 2/6 keywords matched → (2/6)*120 = 40
        assert data["scores"]["accuracy"] >= 40

    @pytest.mark.asyncio
    async def test_unknown_quest_gets_default_accuracy(self):
        """Non-existent quest_id should get default accuracy of 70."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/score",
                json={"user_id": "u1", "quest_id": "nonexistent", "player_input": "Some text here"}
            )
        assert response.status_code == 200
        data = response.json()
        assert data["scores"]["accuracy"] == 70.0

    @pytest.mark.asyncio
    async def test_empty_player_input(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/score",
                json={"user_id": "u1", "player_input": ""}
            )
        assert response.status_code == 200
        data = response.json()
        assert data["scores"]["accuracy"] == 50.0
        assert data["scores"]["fluency"] == 50.0
        assert data["scores"]["vocabulary"] == 50.0

    @pytest.mark.asyncio
    async def test_whitespace_only_input(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.post(
                "/api/v1/assessment/score",
                json={"user_id": "u1", "player_input": "   \n\t  "}
            )
        assert response.status_code == 200
        data = response.json()
        assert data["scores"]["accuracy"] == 50.0

    @pytest.mark.asyncio
    async def test_health_endpoint(self):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "assessment-service"


# ============================================================
# score_from_text Tests — Rule-based Scoring
# ============================================================

class TestScoreFromText:
    """Tests for MicroAssessmentService.score_from_text()."""

    def setup_method(self):
        self.service = MicroAssessmentService()

    # --- Accuracy tests ---

    def test_greet_oakley_full_match(self):
        result = self.service.score_from_text(
            "Hello! My name is Alice. Nice to meet you!",
            quest_id="greet_oakley"
        )
        # Matches: "hello", "name", "my name" → 3/5 → (3/5)*120 = 72
        assert result.accuracy >= 70

    def test_activate_flowers_all_colors(self):
        result = self.service.score_from_text(
            "I see red, blue, yellow, green, pink and purple flowers!",
            quest_id="activate_flowers"
        )
        assert result.accuracy == pytest.approx(100, abs=1)  # all 6 matched

    def test_open_chest_numbers(self):
        result = self.service.score_from_text(
            "I count seven mushrooms. The number 7 is lucky!",
            quest_id="open_chest"
        )
        assert result.accuracy >= 60  # matches "seven", "7", "count"

    def test_weather_crystal(self):
        result = self.service.score_from_text(
            "The weather is sunny today but it might be rainy tomorrow",
            quest_id="fix_weather_crystal"
        )
        assert result.accuracy >= 60  # matches "sunny", "rainy", "weather"

    def test_unknown_quest_default_accuracy(self):
        result = self.service.score_from_text("Some random text", quest_id="unknown_quest")
        assert result.accuracy == 70.0

    # --- Fluency tests ---

    def test_single_word_low_fluency(self):
        result = self.service.score_from_text("hello")
        assert result.fluency == 40.0

    def test_three_words_medium_fluency(self):
        result = self.service.score_from_text("hello how are")
        assert result.fluency == 60.0

    def test_six_words_good_fluency(self):
        result = self.service.score_from_text("hello how are you doing today friend")
        # 7 words → <= 8 → base 80, char_count=36 > 30 → +5 = 85
        assert result.fluency == 85.0

    def test_ten_words_great_fluency(self):
        result = self.service.score_from_text("I am very happy to be here learning new things today")
        # 11 words → <= 15 → base 90, char_count=51 > 30 → +5 = 95
        assert result.fluency == 95.0

    def test_long_sentence_bonus(self):
        """Text with > 30 chars gets +5 fluency bonus."""
        result = self.service.score_from_text("I am very happy to be here learning new things today")
        assert result.fluency >= 95  # 90 + 5 bonus

    def test_longest_fluency_capped(self):
        result = self.service.score_from_text(
            "The quick brown fox jumps over the lazy dog while the sun shines brightly in the sky and the birds sing"
        )
        assert result.fluency <= 100  # capped at 100

    # --- Vocabulary tests ---

    def test_repeated_words_low_vocab(self):
        result = self.service.score_from_text("hello hello hello hello")
        assert result.vocabulary < 50  # TTR = 1/4 = 0.25

    def test_diverse_words_high_vocab(self):
        result = self.service.score_from_text("apple banana cherry dragonfruit elephant")
        assert result.vocabulary >= 80  # TTR = 1.0, scaled

    def test_complex_words_bonus(self):
        """Words with avg length > 5 get +10 vocab bonus."""
        result = self.service.score_from_text("magnificent extraordinary incomprehensible")
        assert result.vocabulary >= 90  # TTR=1.0 + complexity bonus

    def test_short_words_no_bonus(self):
        """Words with avg length <= 4 get no bonus."""
        result = self.service.score_from_text("the cat sat on the mat")
        # TTR = 5/6 ≈ 0.83, vocab = 83
        assert result.vocabulary < 90  # no complexity bonus

    # --- Edge cases ---

    def test_whitespace_only(self):
        result = self.service.score_from_text("   \n\t  ")
        assert result.accuracy == 50.0
        assert result.fluency == 50.0
        assert result.vocabulary == 50.0

    def test_unicode_text(self):
        result = self.service.score_from_text("你好 world! I am learning English.")
        assert 0 <= result.accuracy <= 100
        assert 0 <= result.fluency <= 100
        assert 0 <= result.vocabulary <= 100

    def test_very_long_text(self):
        """Long text should still produce valid scores."""
        long_text = "the quick brown fox jumps over the lazy dog. " * 100
        result = self.service.score_from_text(long_text)
        assert 0 <= result.accuracy <= 100
        assert 0 <= result.fluency <= 100
        assert 0 <= result.vocabulary <= 100

    def test_all_scores_bounded(self):
        """All scores must be in [0, 100]."""
        test_cases = [
            "",
            "a",
            "Hello world",
            "The quick brown fox jumps over the lazy dog. " * 50,
        ]
        for text in test_cases:
            result = self.service.score_from_text(text, quest_id="greet_oakley")
            assert 0 <= result.accuracy <= 100, f"accuracy out of range for: {text[:30]}"
            assert 0 <= result.fluency <= 100, f"fluency out of range for: {text[:30]}"
            assert 0 <= result.vocabulary <= 100, f"vocabulary out of range for: {text[:30]}"


# ============================================================
# calculate() Tests — ASR/Fluency/Vocab from dialogue
# ============================================================

class TestCalculate:
    """Tests for MicroAssessmentService.calculate()."""

    def setup_method(self):
        self.service = MicroAssessmentService()

    def test_basic_calculation(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello world"}, {"asr_text": "How are you today"}],
            [0.9, 0.85],
            [2000, 2500]
        )
        assert 0 <= scores.accuracy <= 100
        assert 0 <= scores.fluency <= 100
        assert 0 <= scores.vocabulary <= 100

    def test_high_confidence_high_accuracy(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello"}],
            [0.98],
            [1500]
        )
        assert scores.accuracy >= 90  # 0.98 * 100

    def test_low_confidence_low_accuracy(self):
        scores = self.service.calculate(
            [{"asr_text": "Hllo"}],
            [0.3],
            [1500]
        )
        assert scores.accuracy <= 40  # 0.3 * 100

    def test_fast_response_high_fluency(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello world"}],
            [0.9],
            [1000]  # faster than 2000ms ideal
        )
        assert scores.fluency >= 95

    def test_slow_response_low_fluency(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello"}],
            [0.9],
            [8000]  # much slower than 5000ms poor threshold
        )
        assert scores.fluency <= 30

    def test_diverse_vocabulary_high_score(self):
        scores = self.service.calculate(
            [{"asr_text": "The magnificent extraordinary incomprehensible"},
             {"asr_text": "phenomenon demonstration illustration"}],
            [0.9, 0.9],
            [2000, 2000]
        )
        # TTR should be high (many unique words)
        assert scores.vocabulary >= 80

    def test_empty_input_returns_zeros(self):
        scores = self.service.calculate([], [], [])
        assert scores.accuracy == 0
        assert scores.fluency == 0
        assert scores.vocabulary == 0

    def test_scores_rounded_in_dict(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello world"}, {"asr_text": "How are you today"}],
            [0.875, 0.923],
            [2100, 2300]
        )
        d = scores.to_dict()
        # Values should be rounded to 1 decimal
        assert isinstance(d["accuracy"], float)
        # Check rounding: accuracy should be a clean number
        assert str(d["accuracy"]).count(".") == 1  # only one decimal point

    def test_radar_chart_format(self):
        scores = self.service.calculate(
            [{"asr_text": "Hello"}],
            [0.9],
            [2000]
        )
        radar = scores.radar_chart_data()
        assert len(radar) == 3
        assert radar[0]["axis"] == "Accuracy"
        assert radar[1]["axis"] == "Fluency"
        assert radar[2]["axis"] == "Vocabulary"
        assert all("value" in item for item in radar)
