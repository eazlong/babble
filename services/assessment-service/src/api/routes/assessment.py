from fastapi import APIRouter
from pydantic import BaseModel
from src.services.micro_assessment import MicroAssessmentService

router = APIRouter()


class AssessmentRequest(BaseModel):
    user_id: str
    session_id: str
    quest_id: str
    dialogue_turns: list
    asr_confidence_scores: list
    response_times_ms: list


@router.post("/api/v1/assessment/micro")
async def calculate_micro_assessment(req: AssessmentRequest):
    service = MicroAssessmentService()
    scores = service.calculate(
        req.dialogue_turns,
        req.asr_confidence_scores,
        req.response_times_ms
    )

    return {
        "scores": scores.to_dict(),
        "radar_chart": scores.radar_chart_data()
    }
