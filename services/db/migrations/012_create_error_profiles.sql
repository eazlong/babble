CREATE TABLE error_profiles (
    error_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    error_type TEXT NOT NULL CHECK (error_type IN ('grammar', 'vocabulary', 'pronunciation', 'pragmatic')),
    pattern_description TEXT NOT NULL,
    frequency INTEGER DEFAULT 1,
    last_occurred TIMESTAMPTZ DEFAULT NOW(),
    severity TEXT DEFAULT 'low' CHECK (severity IN ('low', 'medium', 'high'))
);

CREATE INDEX idx_error_profile_user ON error_profiles(user_id);
CREATE INDEX idx_error_profile_type ON error_profiles(error_type);

ALTER TABLE error_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY error_profile_user_access ON error_profiles
    FOR ALL USING (auth.uid() = user_id);
