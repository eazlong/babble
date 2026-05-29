-- Migration 018: Add columns for parent dashboard
-- Adds scene_access JSONB column to child_accounts
-- Adds is_active column to users table

-- Add scene_access JSONB column to child_accounts (nullable, defaults null meaning all scenes enabled)
ALTER TABLE child_data.child_accounts
ADD COLUMN IF NOT EXISTS scene_access JSONB;

-- Add is_active column to users table (default true)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

CREATE INDEX idx_child_accounts_scene_access ON child_data.child_accounts USING GIN (scene_access);
