CREATE TABLE player_rewards (
    reward_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    item_id UUID NOT NULL REFERENCES reward_items(item_id),
    source_type TEXT NOT NULL,
    source_id TEXT,
    obtained_at TIMESTAMPTZ DEFAULT NOW(),
    is_equipped BOOLEAN DEFAULT false
);

CREATE INDEX idx_player_rewards_user ON player_rewards(user_id);
CREATE INDEX idx_player_rewards_item ON player_rewards(item_id);

ALTER TABLE player_rewards ENABLE ROW LEVEL SECURITY;
CREATE POLICY player_rewards_user_access ON player_rewards
    FOR ALL USING (auth.uid() = user_id);
