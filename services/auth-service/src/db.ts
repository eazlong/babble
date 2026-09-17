import pg from 'pg'
import type { FastifyInstance } from 'fastify'

const { Pool } = pg

export const DATABASE_URL =
  process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/linguaquest'

export interface Db {
  pool: pg.Pool
  /**
   * Run a parameterized query and return all rows.
   * Row objects use snake_case column names as returned by Postgres.
   */
  query<T = any>(text: string, params?: unknown[]): Promise<T[]>
}

/**
 * Make a pg connection pool bound to DATABASE_URL.
 */
export function makePool(): pg.Pool {
  return new Pool({ connectionString: DATABASE_URL })
}

/**
 * Bootstrap the plain-Postgres schema (idempotent). Called once at startup so
 * auth-service works against an empty local Postgres without manual migration.
 * Column names match what the route SQL expects.
 */
export async function applySchema(app: FastifyInstance): Promise<void> {
  await app.pool.query(SCHEMA_SQL)
}

/**
 * Minimal schema for auth-service (was previously provided by the Supabase
 * project). Embedded so it ships inside the compiled image and works in dev.
 */
const SCHEMA_SQL = `
CREATE SCHEMA IF NOT EXISTS child_data;

CREATE TABLE IF NOT EXISTS users (
  user_id             TEXT PRIMARY KEY,
  email               TEXT NOT NULL UNIQUE,
  password_hash       TEXT NOT NULL,
  display_name        TEXT NOT NULL,
  account_type        TEXT NOT NULL DEFAULT 'parent',
  age_group           TEXT NOT NULL DEFAULT 'adult',
  cefr_level          TEXT NOT NULL DEFAULT 'pre-A1',
  preferred_language  TEXT NOT NULL DEFAULT 'en',
  target_language     TEXT NOT NULL DEFAULT 'en',
  subscription_status TEXT NOT NULL DEFAULT 'free',
  is_active           BOOLEAN NOT NULL DEFAULT TRUE,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS child_data.child_accounts (
  parent_id                TEXT NOT NULL,
  child_id                 TEXT NOT NULL PRIMARY KEY,
  daily_time_limit_minutes INTEGER NOT NULL DEFAULT 30,
  content_filter_level     TEXT NOT NULL DEFAULT 'moderate',
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_child_accounts_parent ON child_data.child_accounts(parent_id);

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
`
