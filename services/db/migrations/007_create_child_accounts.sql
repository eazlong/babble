CREATE SCHEMA IF NOT EXISTS child_data;

CREATE TABLE child_data.child_accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id UUID NOT NULL REFERENCES users(user_id),
    child_id UUID NOT NULL REFERENCES users(user_id),
    daily_time_limit_minutes INTEGER DEFAULT 30,
    content_filter_level TEXT DEFAULT 'strict' CHECK (content_filter_level IN ('strict', 'moderate', 'relaxed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (parent_id, child_id)
);

CREATE INDEX idx_child_accounts_parent ON child_data.child_accounts(parent_id);
CREATE INDEX idx_child_accounts_child ON child_data.child_accounts(child_id);

ALTER TABLE child_data.child_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY child_accounts_parent_access ON child_data.child_accounts
    FOR ALL USING (auth.uid() = parent_id);
