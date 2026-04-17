CREATE TABLE quests (
    quest_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    quest_type TEXT NOT NULL CHECK (quest_type IN ('main', 'side', 'daily')),
    scene_id UUID REFERENCES scenes(scene_id),
    npc_id UUID REFERENCES npc_profiles(npc_id),
    difficulty_level INTEGER NOT NULL DEFAULT 1 CHECK (difficulty_level BETWEEN 1 AND 5),
    cefr_requirement TEXT DEFAULT 'A1' CHECK (cefr_requirement IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')),
    lxp_reward_base INTEGER NOT NULL DEFAULT 10,
    target_language_focus JSONB NOT NULL DEFAULT '[]',
    completion_criteria JSONB NOT NULL DEFAULT '{}',
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_quests_type ON quests(quest_type);
CREATE INDEX idx_quests_scene ON quests(scene_id);
CREATE INDEX idx_quests_cefr ON quests(cefr_requirement);

ALTER TABLE quests ENABLE ROW LEVEL SECURITY;
CREATE POLICY quests_read_access ON quests
    FOR SELECT USING (is_active = true);
