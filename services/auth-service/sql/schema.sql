-- ============================================================================
-- LinguaQuest auth-service — plain-Postgres bootstrap schema
-- ----------------------------------------------------------------------------
-- 用途：auth-service 不再依赖 Supabase Auth/Data，改为直连本地 Postgres。
-- 本文件只建 auth-service 读写用到的表（替代原来 Supabase 项目里的表）。
-- 通过 docker-compose 挂载并在 auth-service 启动时自动执行（见 db.ts），
-- 也可手动执行：psql "$DATABASE_URL" -f services/auth-service/sql/schema.sql
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS child_data;

-- 用户表（家长 + 孩子共用）。password_hash 用于 bcrypt 登录校验。
CREATE TABLE IF NOT EXISTS users (
  user_id             TEXT PRIMARY KEY,
  email               TEXT NOT NULL UNIQUE,
  password_hash       TEXT NOT NULL,
  display_name        TEXT NOT NULL,
  account_type        TEXT NOT NULL DEFAULT 'parent',   -- 'parent' | 'child'
  age_group           TEXT NOT NULL DEFAULT 'adult',
  cefr_level          TEXT NOT NULL DEFAULT 'pre-A1',
  preferred_language  TEXT NOT NULL DEFAULT 'en',
  target_language     TEXT NOT NULL DEFAULT 'en',
  subscription_status TEXT NOT NULL DEFAULT 'free',
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 家长 - 孩子 关联表
CREATE TABLE IF NOT EXISTS child_data.child_accounts (
  parent_id                TEXT NOT NULL,
  child_id                 TEXT NOT NULL PRIMARY KEY,
  daily_time_limit_minutes INTEGER NOT NULL DEFAULT 30,
  content_filter_level     TEXT NOT NULL DEFAULT 'moderate',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_child_accounts_parent ON child_data.child_accounts(parent_id);

-- 家长后台聚合 / 删除所引用的业务表（最小兼容结构，避免查询报错）。
CREATE TABLE IF NOT EXISTS game_sessions (
  id         BIGSERIAL PRIMARY KEY,
  user_id    TEXT NOT NULL,
  start_time TIMESTAMPTZ,
  end_time   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_game_sessions_user ON game_sessions(user_id);

CREATE TABLE IF NOT EXISTS assessment_results (
  id          BIGSERIAL PRIMARY KEY,
  user_id     TEXT NOT NULL,
  assessed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_assessment_user ON assessment_results(user_id);

CREATE TABLE IF NOT EXISTS quest_progress (
  id      BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL,
  status  TEXT
);
CREATE INDEX IF NOT EXISTS idx_quest_user ON quest_progress(user_id);

CREATE TABLE IF NOT EXISTS player_rewards (
  id      BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_rewards_user ON player_rewards(user_id);

CREATE TABLE IF NOT EXISTS dialogue_turns (
  id      BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_dialogue_user ON dialogue_turns(user_id);
