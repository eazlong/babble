from dataclasses import dataclass
from typing import List, Dict
import math


@dataclass
class AssessmentScores:
    accuracy: float  # 0-100
    fluency: float   # 0-100
    vocabulary: float  # 0-100

    def to_dict(self) -> Dict[str, float]:
        return {
            "accuracy": round(self.accuracy, 1),
            "fluency": round(self.fluency, 1),
            "vocabulary": round(self.vocabulary, 1)
        }

    def radar_chart_data(self) -> List[Dict]:
        return [
            {"axis": "Accuracy", "value": self.accuracy},
            {"axis": "Fluency", "value": self.fluency},
            {"axis": "Vocabulary", "value": self.vocabulary}
        ]


class MicroAssessmentService:
    def calculate(self,
                  dialogue_turns: List[Dict],
                  asr_confidence_scores: List[float],
                  response_times_ms: List[int]) -> AssessmentScores:
        """Calculate 3D assessment scores from a quest completion."""

        if not dialogue_turns:
            return AssessmentScores(0, 0, 0)

        # Accuracy: based on ASR confidence (proxy for clear pronunciation)
        avg_confidence = sum(asr_confidence_scores) / len(asr_confidence_scores)
        accuracy = min(100, avg_confidence * 100)

        # Fluency: based on response time (faster = more fluent)
        avg_response_time = sum(response_times_ms) / len(response_times_ms)
        # Ideal: < 2000ms, Poor: > 5000ms
        fluency = max(0, min(100, 100 - (avg_response_time - 2000) / 30))

        # Vocabulary: based on unique word count
        all_words = []
        for turn in dialogue_turns:
            words = turn.get('asr_text', '').split()
            all_words.extend(w.lower() for w in words)

        unique_words = len(set(all_words))
        total_words = len(all_words)
        ttr = unique_words / max(1, total_words)  # Type-Token Ratio
        vocabulary = min(100, ttr * 150)  # Scale TTR to 0-100

        return AssessmentScores(accuracy, fluency, vocabulary)
