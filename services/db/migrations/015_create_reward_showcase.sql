CREATE TABLE reward_showcase (
    showcase_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    item_id UUID NOT NULL REFERENCES reward_items(item_id),
    display_order INTEGER DEFAULT 0,
    is_featured BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_showcase_user ON reward_showcase(user_id);

ALTER TABLE reward_showcase ENABLE ROW LEVEL SECURITY;
CREATE POLICY showcase_user_access ON reward_showcase
    FOR ALL USING (auth.uid() = user_id);
