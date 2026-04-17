CREATE TABLE reward_items (
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    item_type TEXT NOT NULL CHECK (item_type IN ('skin_protagonist', 'skin_spirit', 'decoration', 'title', 'effect')),
    rarity TEXT NOT NULL CHECK (rarity IN ('common', 'rare', 'epic', 'legendary', 'limited')),
    thumbnail_ref TEXT,
    chapter_id TEXT,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_rewards_type ON reward_items(item_type);
CREATE INDEX idx_rewards_rarity ON reward_items(rarity);

ALTER TABLE reward_items ENABLE ROW LEVEL SECURITY;
CREATE POLICY rewards_read_access ON reward_items
    FOR SELECT USING (is_active = true);
