#!/bin/bash
# Migration 018: Add parent dashboard columns to LinguaQuest database
# Run this script after Docker Desktop is running and postgres container is up

echo "=== Starting Migration 018 ==="
echo "This script requires Docker Desktop to be running and postgres container to be up."
echo ""

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker is not running. Please start Docker Desktop first."
    exit 1
fi

# Check if postgres container is running
if ! docker compose ps postgres 2>/dev/null | grep -q "Up"; then
    echo "Starting postgres container..."
    docker compose up -d postgres
    sleep 5
fi

# Wait for postgres to be ready
echo "Waiting for PostgreSQL to be ready..."
until docker compose exec postgres pg_isready -U postgres > /dev/null 2>&1; do
    sleep 1
done

echo "PostgreSQL is ready."

# Execute migration
echo "Executing migration 018..."
docker compose exec -T postgres psql -U postgres -d linguaquest << 'EOF'
-- Migration 018: Add columns for parent dashboard
-- Adds scene_access JSONB column to child_accounts
-- Adds is_active column to users table

-- Add scene_access JSONB column to child_accounts (nullable, defaults null meaning all scenes enabled)
ALTER TABLE child_data.child_accounts
ADD COLUMN IF NOT EXISTS scene_access JSONB;

-- Add is_active column to users table (default true)
ALTER TABLE users
ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_child_accounts_scene_access ON child_data.child_accounts USING GIN (scene_access);

-- Verify migration
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'child_data' AND table_name = 'child_accounts' AND column_name = 'scene_access';

SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'is_active';
EOF

echo ""
echo "=== Migration 018 Complete ==="
echo "Verify the columns were added by checking the output above."
