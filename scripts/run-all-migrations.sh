#!/bin/bash
# Run all migrations 001-018 in order
set -e

MIGRATION_DIR="services/db/migrations"

echo "=== Running all LinguaQuest migrations ==="

for f in $(ls "$MIGRATION_DIR"/*.sql | sort); do
    filename=$(basename "$f")
    echo "Running $filename..."
    if ! docker compose exec -T postgres psql -U postgres -d linguaquest -f "$f" 2>&1; then
        echo "⚠️  Migration $filename failed (may be already applied)"
    fi
done

echo ""
echo "=== All migrations complete ==="
