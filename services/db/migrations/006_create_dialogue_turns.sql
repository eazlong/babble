CREATE TABLE dialogue_turns (
    turn_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES game_sessions(session_id),
    user_id UUID NOT NULL REFERENCES users(user_id),
    npc_id UUID REFERENCES npc_profiles(npc_id),
    turn_number INTEGER NOT NULL,
    speaker_type TEXT NOT NULL CHECK (speaker_type IN ('player', 'npc', 'system')),
    asr_text TEXT,
    asr_confidence FLOAT,
    npc_response_text TEXT,
    quest_context TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_turns_session ON dialogue_turns(session_id);
CREATE INDEX idx_turns_user ON dialogue_turns(user_id);
CREATE INDEX idx_turns_number ON dialogue_turns(session_id, turn_number);

ALTER TABLE dialogue_turns ENABLE ROW LEVEL SECURITY;
CREATE POLICY turns_user_access ON dialogue_turns
    FOR ALL USING (auth.uid() = user_id);
