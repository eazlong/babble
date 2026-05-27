from dataclasses import dataclass
from typing import List, Dict
import math
import re


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

    @staticmethod
    def score_from_text(
        player_input: str,
        quest_id: str = "",
        scene_id: str = "",
        context: Dict = None,
    ) -> AssessmentScores:
        """MVP rule-based scoring from raw player text.

        Three dimensions:
        - accuracy: keyword match against expected quest terms (0-100)
        - fluency: text length + word count as speech fluency proxy (0-100)
        - vocabulary: unique-word ratio + lexical complexity (0-100)
        """
        if context is None:
            context = {}

        text = player_input.strip().lower()
        if not text:
            return AssessmentScores(50.0, 50.0, 50.0)

        # ——— Accuracy: keyword matching ———
        # Expected keywords per quest (scene-specific target vocabulary)
        quest_keywords = {
            "greet_oakley": ["hello", "hi", "name", "i am", "my name"],
            "activate_flowers": ["red", "blue", "yellow", "green", "pink", "purple"],
            "open_chest": ["seven", "7", "mushroom", "count", "数"],
            "organize_books": ["big", "small", "red", "book", "sort", "分类"],
            "follow_commands": ["stand up", "open", "read", "book", "aloud"],
            "practice_dialogue": ["book", "favorite", "color", "because", "magic"],
            "fix_weather_crystal": ["sunny", "rainy", "cloudy", "snowy", "weather"],
            "find_lost_animals": ["cat", "dog", "bird", "tree", "bridge", "bush"],
            "plant_flowers": ["plant", "water", "grow", "red", "blue", "yellow"],
        }
        keywords = quest_keywords.get(quest_id, [])
        if keywords:
            matched = sum(1 for kw in keywords if kw in text)
            accuracy = min(100, (matched / len(keywords)) * 120)  # Allow slight bonus for exceeding
        else:
            # Generic scoring: any non-empty input gets moderate accuracy
            accuracy = 70.0

        # ——— Fluency: text length proxy ———
        word_count = len(text.split())
        char_count = len(text)
        # Ideal: 5-15 words for a child learner
        if word_count <= 1:
            fluency = 40.0
        elif word_count <= 3:
            fluency = 60.0
        elif word_count <= 8:
            fluency = 80.0
        elif word_count <= 15:
            fluency = 90.0
        else:
            fluency = 95.0
        # Bonus for longer character count (indicates fuller sentences)
        if char_count > 30:
            fluency = min(100, fluency + 5)

        # ——— Vocabulary: diversity + complexity ———
        words = re.findall(r'\b\w+\b', text)
        if not words:
            vocabulary = 50.0
        else:
            unique_words = len(set(words))
            total_words = len(words)
            ttr = unique_words / max(1, total_words)
            # Base vocabulary from TTR
            vocabulary = min(80, ttr * 100)
            # Bonus for longer/more complex words (avg word length)
            avg_word_len = sum(len(w) for w in words) / len(words)
            if avg_word_len > 5:
                vocabulary += 10
            elif avg_word_len > 4:
                vocabulary += 5
            vocabulary = min(100, vocabulary)

        return AssessmentScores(round(accuracy, 1), round(fluency, 1), round(vocabulary, 1))
