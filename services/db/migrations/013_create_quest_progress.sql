CREATE TABLE quest_progress (
    progress_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quest_id UUID NOT NULL REFERENCES quests(quest_id),
    user_id UUID NOT NULL REFERENCES users(user_id),
    status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'in_progress', 'completed', 'failed')),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    accuracy_score FLOAT,
    fluency_score FLOAT,
    vocabulary_score FLOAT,
    lxp_earned INTEGER DEFAULT 0
);

CREATE INDEX idx_quest_progress_user ON quest_progress(user_id);
CREATE INDEX idx_quest_progress_status ON quest_progress(status);

ALTER TABLE quest_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY quest_progress_user_access ON quest_progress
    FOR ALL USING (auth.uid() = user_id);
