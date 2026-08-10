"""配置读取。照搬 assessment/voice-service 的 os.environ.get 模式。"""

import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://localhost:5433")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY", "")

ASSESSMENT_SERVICE_URL = os.environ.get(
    "ASSESSMENT_SERVICE_URL", "http://localhost:8308"
)
VOICE_SERVICE_URL = os.environ.get(
    "VOICE_SERVICE_URL", "http://localhost:8301"
)

SUMMARY_SERVICE_PORT = int(os.environ.get("SUMMARY_SERVICE_PORT", "8303"))

# 补评升级临界带（ADR-0004）。规则评分落此区间则升级 LLM。
DEEP_ASSESS_CRITICAL_BAND = (
    float(os.environ.get("DEEP_ASSESS_CRITICAL_LOW", "0.35")),
    float(os.environ.get("DEEP_ASSESS_CRITICAL_HIGH", "0.75")),
)

# 语义类 expected_answer_type（直接升级 LLM，不走规则）。
SEMANTIC_ANSWER_TYPES = {
    "expression_scenario",
    "expression_free",
    "sentence_reorder",
    "grammar_judge",
    "reading_infer",
}
