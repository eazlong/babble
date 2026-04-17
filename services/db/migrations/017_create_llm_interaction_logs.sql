CREATE TABLE llm_interaction_logs (
    log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    session_id UUID REFERENCES game_sessions(session_id),
    model_used TEXT NOT NULL,
    deployment_mode TEXT NOT NULL CHECK (deployment_mode IN ('cloud', 'local')),
    prompt_text TEXT,
    response_text TEXT,
    prompt_tokens INTEGER,
    completion_tokens INTEGER,
    latency_ms INTEGER,
    task_type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_llm_log_user ON llm_interaction_logs(user_id);
CREATE INDEX idx_llm_log_model ON llm_interaction_logs(model_used);

ALTER TABLE llm_interaction_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY llm_log_admin_access ON llm_interaction_logs
    FOR SELECT USING (true);
