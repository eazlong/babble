CREATE TABLE game_sessions (
    session_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    scene_id UUID REFERENCES scenes(scene_id),
    current_quest_id UUID REFERENCES quests(quest_id),
    start_time TIMESTAMPTZ DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    lxp_earned INTEGER DEFAULT 0,
    total_turns INTEGER DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned'))
);

CREATE INDEX idx_sessions_user ON game_sessions(user_id);
CREATE INDEX idx_sessions_status ON game_sessions(status);

ALTER TABLE game_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY sessions_user_access ON game_sessions
    FOR ALL USING (auth.uid() = user_id);
