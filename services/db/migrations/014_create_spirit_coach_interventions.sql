CREATE TABLE spirit_coach_interventions (
    intervention_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    turn_id UUID REFERENCES dialogue_turns(turn_id),
    session_id UUID REFERENCES game_sessions(session_id),
    user_id UUID NOT NULL REFERENCES users(user_id),
    error_type TEXT CHECK (error_type IN ('grammar', 'vocabulary', 'pronunciation', 'pragmatic')),
    severity TEXT CHECK (severity IN ('low', 'medium', 'high')),
    coach_suggestion_text TEXT,
    player_adopted BOOLEAN DEFAULT false,
    intervention_timing_ms INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_interventions_user ON spirit_coach_interventions(user_id);
CREATE INDEX idx_interventions_session ON spirit_coach_interventions(session_id);

ALTER TABLE spirit_coach_interventions ENABLE ROW LEVEL SECURITY;
CREATE POLICY interventions_user_access ON spirit_coach_interventions
    FOR ALL USING (auth.uid() = user_id);
