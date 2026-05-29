#!/usr/bin/env node
/**
 * Migration 018 Runner
 * Adds scene_access JSONB column to child_accounts
 * Adds is_active column to users table
 * 
 * Usage: cd services/auth-service && node ../../scripts/run-migration-018.js
 */

const { createClient } = require('@supabase/supabase-js')

const SUPABASE_URL = process.env.SUPABASE_URL || 'http://localhost:54321'
const SUPABASE_KEY = process.env.SUPABASE_KEY || 'dev-key'

console.log('=== Migration 018 Runner ===')
console.log(`Supabase URL: ${SUPABASE_URL}`)
console.log(`Using key: ${SUPABASE_KEY.substring(0, 10)}...`)
console.log('')

// Use service role key for admin operations
const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false }
})

// SQL migration statements
const migrations = [
    {
        name: 'Add scene_access JSONB column',
        sql: `ALTER TABLE child_data.child_accounts ADD COLUMN IF NOT EXISTS scene_access JSONB;`
    },
    {
        name: 'Add is_active column to users',
        sql: `ALTER TABLE users ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;`
    },
    {
        name: 'Create GIN index for scene_access',
        sql: `CREATE INDEX IF NOT EXISTS idx_child_accounts_scene_access ON child_data.child_accounts USING GIN (scene_access);`
    }
]

async function runMigration() {
    console.log('Starting migration...')
    console.log('')

    // Try using Supabase Management API (requires service role key)
    // For local dev, we need to use psql via Docker
    console.log('NOTE: This migration requires direct SQL access to PostgreSQL.')
    console.log('Please run one of the following:')
    console.log('')
    console.log('Option 1 - Docker (recommended for local dev):')
    console.log('  cd /Users/gongzuoyonghu/Documents/code/games/lauguage_game')
    console.log('  docker compose up -d postgres')
    console.log('  docker compose exec postgres psql -U postgres -d linguaquest -f services/db/migrations/018_add_parent_dashboard_columns.sql')
    console.log('')
    console.log('Option 2 - Supabase Dashboard (for cloud deployment):')
    console.log('  1. Open your Supabase project dashboard')
    console.log('  2. Go to SQL Editor')
    console.log('  3. Paste and run the content of services/db/migrations/018_add_parent_dashboard_columns.sql')
    console.log('')
    
    // Try to verify if columns already exist
    console.log('Verifying if columns already exist...')
    
    try {
        // Check scene_access column
        const { data: caData, error: caError } = await supabase
            .from('child_data.child_accounts')
            .select('scene_access')
            .limit(1)
        
        if (caError && caError.message.includes('scene_access')) {
            console.log('❌ scene_access column does NOT exist - migration needed')
        } else if (caError) {
            console.log(`⚠️  Could not verify scene_access: ${caError.message}`)
        } else {
            console.log('✅ scene_access column already exists')
        }
        
        // Check is_active column
        const { data: usersData, error: usersError } = await supabase
            .from('users')
            .select('is_active')
            .limit(1)
        
        if (usersError && usersError.message.includes('is_active')) {
            console.log('❌ is_active column does NOT exist - migration needed')
        } else if (usersError) {
            console.log(`⚠️  Could not verify is_active: ${usersError.message}`)
        } else {
            console.log('✅ is_active column already exists')
        }
        
    } catch (err) {
        console.log(`⚠️  Verification failed: ${err.message}`)
        console.log('   This is expected if Supabase is not running locally')
    }
    
    console.log('')
    console.log('=== Migration 018 Info Complete ===')
}

runMigration()
