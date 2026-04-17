import pytest
from httpx import AsyncClient, ASGITransport
from src.main import app
from src.services.micro_assessment import MicroAssessmentService, AssessmentScores


@pytest.mark.asyncio
async def test_micro_assessment_endpoint():
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


def test_assessment_calculation():
    service = MicroAssessmentService()
    scores = service.calculate(
        [{"asr_text": "Hello world"}, {"asr_text": "How are you today"}],
        [0.9, 0.85],
        [2000, 2500]
    )

    assert 0 <= scores.accuracy <= 100
    assert 0 <= scores.fluency <= 100
    assert 0 <= scores.vocabulary <= 100

    radar = scores.radar_chart_data()
    assert len(radar) == 3
    assert radar[0]["axis"] == "Accuracy"


def test_empty_input_returns_zero_scores():
    service = MicroAssessmentService()
    scores = service.calculate([], [], [])
    assert scores.accuracy == 0
    assert scores.fluency == 0
    assert scores.vocabulary == 0
