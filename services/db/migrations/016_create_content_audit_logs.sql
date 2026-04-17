CREATE TABLE content_audit_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    session_id UUID REFERENCES game_sessions(session_id),
    content_type TEXT NOT NULL CHECK (content_type IN ('asr_input', 'npc_output', 'coach_intervention')),
    content_text TEXT NOT NULL,
    moderation_result JSONB,
    flagged BOOLEAN DEFAULT false,
    action_taken TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_user ON content_audit_logs(user_id);
CREATE INDEX idx_audit_flagged ON content_audit_logs(flagged);

ALTER TABLE content_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_admin_access ON content_audit_logs
    FOR SELECT USING (true);
