"""ingest 端点测试：无 supabase 模式下确认端点可调用且推导 knowledge_item_id。"""

import pytest
from httpx import ASGITransport, AsyncClient

from src.main import app


@pytest.fixture
def client():
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


class TestIngestNoPersist:
    @pytest.mark.asyncio
    async def test_session_accepted(self, client):
        async with client as c:
            resp = await c.post("/api/v1/summary/sessions", json={
                "session_id": "s1",
                "child_id": "child1",
                "client_session_id": "cs1",
                "scene_id": "word_spirit_library_archive_hall",
            })
        assert resp.status_code == 200
        body = resp.json()
        assert body["accepted"] is True

    @pytest.mark.asyncio
    async def test_interaction_attempt_resolves_word_kid(self, client):
        async with client as c:
            resp = await c.post("/api/v1/summary/interaction-attempts", json={
                "interaction_attempt_id": "a1",
                "session_id": "s1",
                "prompt_turn_id": "p1",
                "child_id": "child1",
                "local_attempt_id": "la1",
                "content_id_hint": "archive_inscribe_apple",
                "target_utterance_hint": "APPLE",
                "expected_answer_type_hint": "word_pronunciation",
                "realtime_mastery_score": 0.9,
            })
        assert resp.status_code == 200
        body = resp.json()
        assert body["knowledge_item_id"] == "word:apple"

    @pytest.mark.asyncio
    async def test_prompt_turn_accepted(self, client):
        async with client as c:
            resp = await c.post("/api/v1/summary/prompt-turns", json={
                "prompt_turn_id": "p1",
                "session_id": "s1",
                "child_id": "child1",
                "scene_id": "word_spirit_library_archive_hall",
                "content_id": "archive_inscribe_apple",
                "target_utterance_snapshot": "APPLE",
                "expected_answer_type": "word_pronunciation",
            })
        assert resp.status_code == 200
        assert resp.json()["accepted"] is True

    @pytest.mark.asyncio
    async def test_prompt_turn_rejects_missing_session_id(self, client):
        # session_id 是必填字段；客户端若误传 game_session_id 会 422。
        async with client as c:
            resp = await c.post("/api/v1/summary/prompt-turns", json={
                "prompt_turn_id": "p2",
                "child_id": "child1",
                "scene_id": "x",
            })
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_interaction_attempt_unmapped_kid(self, client):
        async with client as c:
            resp = await c.post("/api/v1/summary/interaction-attempts", json={
                "interaction_attempt_id": "a2",
                "session_id": "s1",
                "prompt_turn_id": "p2",
                "child_id": "child1",
                "local_attempt_id": "la2",
                "content_id_hint": "grammar_q1",
                "expected_answer_type_hint": "grammar_judge",
            })
        assert resp.status_code == 200
        body = resp.json()
        # 语法类第一版未登记 → 空 kid
        assert body["knowledge_item_id"] == ""


class TestHealth:
    @pytest.mark.asyncio
    async def test_health(self, client):
        async with client as c:
            resp = await c.get("/health")
        assert resp.status_code == 200
        assert resp.json()["service"] == "summary-service"


class TestDeepAssessStub:
    @pytest.mark.asyncio
    async def test_escalate_llm_returns_501(self, client):
        async with client as c:
            resp = await c.post("/api/v1/summary/deep-assess/escalate-llm")
        assert resp.status_code == 501
