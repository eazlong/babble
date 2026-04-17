CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    display_name TEXT NOT NULL,
    account_type TEXT NOT NULL CHECK (account_type IN ('standard', 'child', 'parent', 'institution')),
    age_group TEXT NOT NULL CHECK (age_group IN ('child', 'teen', 'adult')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_login TIMESTAMPTZ,
    subscription_status TEXT DEFAULT 'free' CHECK (subscription_status IN ('free', 'premium_monthly', 'premium_annual', 'b2b')),
    preferred_language TEXT NOT NULL,
    target_language TEXT NOT NULL,
    cefr_level TEXT DEFAULT 'A1' CHECK (cefr_level IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2'))
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_account_type ON users(account_type);

-- RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY user_self_access ON users
    FOR ALL USING (auth.uid() = user_id OR auth.uid() IN (
        SELECT parent_id FROM child_data.child_accounts WHERE child_id = users.user_id
    ));
