-- Migration 019: Learning summary & mastery tables
-- 见 CONTEXT.md "学习总结与掌握度" 与 ADR 0002-0005。
-- child_data schema 下四张表：游戏会话、提示轮次、交互尝试、掌握度状态。
-- child_id 用 TEXT 而非 UUID：客户端 MagicEchoManager 用 player_name 作 child_id，
-- 本地未注册儿童也能上报，不强外键到 child_accounts。

CREATE SCHEMA IF NOT EXISTS child_data;

-- 游戏会话：玩家从进入一个可学习场景到离开。
CREATE TABLE IF NOT EXISTS child_data.learning_sessions (
    session_id TEXT PRIMARY KEY,
    child_id TEXT NOT NULL,
    client_session_id TEXT NOT NULL,
    scene_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    end_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_learning_sessions_idempotent
    ON child_data.learning_sessions (child_id, client_session_id);
CREATE INDEX IF NOT EXISTS idx_learning_sessions_child
    ON child_data.learning_sessions (child_id, started_at DESC);

-- 提示轮次：一次 NPC 或系统发起的教学提示或问题，保存内容快照。
CREATE TABLE IF NOT EXISTS child_data.prompt_turns (
    prompt_turn_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES child_data.learning_sessions(session_id) ON DELETE CASCADE,
    child_id TEXT NOT NULL,
    scene_id TEXT NOT NULL,
    quest_id TEXT NOT NULL DEFAULT '',
    content_id TEXT NOT NULL DEFAULT '',
    content_version INTEGER NOT NULL DEFAULT 1,
    prompt_text_snapshot TEXT NOT NULL DEFAULT '',
    target_utterance_snapshot TEXT NOT NULL DEFAULT '',
    expected_answer_type TEXT NOT NULL DEFAULT 'short_answer',
    assessment_rule_version TEXT NOT NULL DEFAULT 'v1',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_prompt_turns_session
    ON child_data.prompt_turns (session_id);

-- 交互尝试：玩家对一次明确提示作出的回答，绑定录音/ASR/评分。
CREATE TABLE IF NOT EXISTS child_data.interaction_attempts (
    interaction_attempt_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES child_data.learning_sessions(session_id) ON DELETE CASCADE,
    prompt_turn_id TEXT NOT NULL REFERENCES child_data.prompt_turns(prompt_turn_id) ON DELETE CASCADE,
    child_id TEXT NOT NULL,
    local_attempt_id TEXT NOT NULL,
    attempt_index INTEGER NOT NULL DEFAULT 0,
    attempt_type TEXT NOT NULL DEFAULT 'short_answer',
    recording_status TEXT NOT NULL DEFAULT 'not_started',
    asr_status TEXT NOT NULL DEFAULT 'not_started',
    asr_text TEXT NOT NULL DEFAULT '',
    realtime_assessment_status TEXT NOT NULL DEFAULT 'not_started',
    realtime_mastery_score REAL,
    deep_assessment_status TEXT NOT NULL DEFAULT 'not_started',
    deep_mastery_score REAL,
    knowledge_item_id TEXT NOT NULL DEFAULT '',
    recording_file_path TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deep_assessed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_interaction_attempts_idempotent
    ON child_data.interaction_attempts (child_id, local_attempt_id);
CREATE INDEX IF NOT EXISTS idx_interaction_attempts_knowledge
    ON child_data.interaction_attempts (knowledge_item_id, child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_interaction_attempts_session
    ON child_data.interaction_attempts (session_id);

-- 掌握度状态：半衰期模型核心状态，每 (child, 知识项) 一行。
CREATE TABLE IF NOT EXISTS child_data.mastery_state (
    child_id TEXT NOT NULL,
    knowledge_item_id TEXT NOT NULL,
    item_type TEXT NOT NULL,
    current_half_life_days REAL NOT NULL DEFAULT 3.0,
    last_assessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_mastery_score REAL,
    assessment_count INTEGER NOT NULL DEFAULT 0,
    retention_strength REAL NOT NULL DEFAULT 1.0,
    mastery_band TEXT NOT NULL DEFAULT 'mastered',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (child_id, knowledge_item_id)
);

CREATE INDEX IF NOT EXISTS idx_mastery_state_child_band
    ON child_data.mastery_state (child_id, mastery_band);
CREATE INDEX IF NOT EXISTS idx_mastery_state_child_type
    ON child_data.mastery_state (child_id, item_type, retention_strength);
