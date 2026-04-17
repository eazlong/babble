CREATE TABLE assessment_results (
    assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    session_id UUID REFERENCES game_sessions(session_id),
    quest_id UUID REFERENCES quests(quest_id),
    accuracy_score FLOAT NOT NULL CHECK (accuracy_score BETWEEN 0 AND 100),
    fluency_score FLOAT NOT NULL CHECK (fluency_score BETWEEN 0 AND 100),
    vocabulary_score FLOAT NOT NULL CHECK (vocabulary_score BETWEEN 0 AND 100),
    overall_score FLOAT NOT NULL CHECK (overall_score BETWEEN 0 AND 100),
    assessed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_assessment_user ON assessment_results(user_id);
CREATE INDEX idx_assessment_session ON assessment_results(session_id);

ALTER TABLE assessment_results ENABLE ROW LEVEL SECURITY;
CREATE POLICY assessment_user_access ON assessment_results
    FOR ALL USING (auth.uid() = user_id);
