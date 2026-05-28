-- Migration: 001_quest_persistence.sql
-- Purpose: Create tables for quest completion persistence in Supabase
-- Date: 2026-05-28

-- ============================================================
-- Table: user_quest_completion
-- Stores each quest completion with scores and rewards.
-- UNIQUE(user_id, quest_id) enforces idempotent completions.
-- ============================================================
CREATE TABLE IF NOT EXISTS user_quest_completion (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id VARCHAR NOT NULL,
    quest_id VARCHAR NOT NULL,
    scene_id VARCHAR NOT NULL,
    accuracy INT NOT NULL,
    fluency INT NOT NULL,
    vocabulary INT NOT NULL,
    lxp_earned INT NOT NULL,
    stars_earned INT NOT NULL,
    badge_unlocked VARCHAR,
    rewards JSONB DEFAULT '[]'::jsonb,
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_user_quest UNIQUE (user_id, quest_id)
);

-- Index for fast lookups by user
CREATE INDEX IF NOT EXISTS idx_quest_user ON user_quest_completion(user_id);

-- Index for fast lookups by user + scene (for getQuestStatus)
CREATE INDEX IF NOT EXISTS idx_quest_user_scene ON user_quest_completion(user_id, scene_id);

-- ============================================================
-- Table: user_stats
-- Aggregated user statistics: total stars, unlocked badges.
-- Upserted by the storage adapter on each quest completion.
-- ============================================================
CREATE TABLE IF NOT EXISTS user_stats (
    user_id VARCHAR PRIMARY KEY,
    total_stars INT DEFAULT 0,
    badges JSONB DEFAULT '[]'::jsonb,  -- array of badge_id strings
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Table: daily_quest_state
-- Tracks daily quest assignments and per-quest completion.
-- PK(user_id, quest_date, quest_id) for efficient daily reset.
-- ============================================================
CREATE TABLE IF NOT EXISTS daily_quest_state (
    user_id VARCHAR NOT NULL,
    quest_date VARCHAR NOT NULL,      -- 'YYYY-MM-DD' format
    quest_id VARCHAR NOT NULL,
    completed BOOLEAN DEFAULT FALSE,
    stars_earned INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_daily_quest PRIMARY KEY (user_id, quest_date, quest_id)
);

-- Index for listing daily quests by user + date
CREATE INDEX IF NOT EXISTS idx_daily_user_date ON daily_quest_state(user_id, quest_date);
