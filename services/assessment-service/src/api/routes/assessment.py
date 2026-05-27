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


class ScoreRequest(BaseModel):
    user_id: str = "anonymous"
    quest_id: str = ""
    scene_id: str = ""
    player_input: str = ""
    context: dict = {}


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


@router.post("/api/v1/assessment/score")
async def score_player_input(req: ScoreRequest):
    """MVP rule-based scoring for player voice input.

    Returns accuracy/fluency/vocabulary scores (0-100) based on:
    - text length (fluency proxy)
    - keyword matching against scene-specific targets
    - vocabulary diversity (unique word ratio)
    """
    service = MicroAssessmentService()
    scores = service.score_from_text(
        player_input=req.player_input,
        quest_id=req.quest_id,
        scene_id=req.scene_id,
        context=req.context,
    )

    return {
        "scores": scores.to_dict(),
    }
