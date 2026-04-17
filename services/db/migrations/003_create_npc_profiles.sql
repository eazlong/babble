CREATE TABLE npc_profiles (
    npc_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    npc_name TEXT NOT NULL,
    npc_type TEXT NOT NULL,
    scene_id UUID REFERENCES scenes(scene_id),
    language_style TEXT NOT NULL,
    formality_level TEXT NOT NULL CHECK (formality_level IN ('formal', 'informal', 'mixed')),
    vocabulary_level TEXT NOT NULL CHECK (vocabulary_level IN ('basic', 'intermediate', 'advanced')),
    personality TEXT,
    greeting_text TEXT,
    avatar_ref TEXT,
    voice_ref TEXT,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_npc_scene ON npc_profiles(scene_id);
CREATE INDEX idx_npc_type ON npc_profiles(npc_type);

-- MVP: Seed 5 NPCs
INSERT INTO npc_profiles (npc_name, npc_type, scene_id, language_style, formality_level, vocabulary_level, personality, greeting_text)
SELECT
    '集市商人老王', 'merchant', s.scene_id,
    '市侩但友善，喜欢讨价还价', 'informal', 'basic',
    '热情好客，精明但不贪婪',
    '欢迎来到我的摊位！看看有什么喜欢的吗？'
FROM scenes s WHERE s.scene_name = '王都集市'
LIMIT 1;

INSERT INTO npc_profiles (npc_name, npc_type, scene_id, language_style, formality_level, vocabulary_level, personality, greeting_text)
SELECT
    '酒馆老板娘', 'innkeeper', s.scene_id,
    '温暖亲切，喜欢讲故事', 'mixed', 'intermediate',
    '慈爱、健谈，是酒馆的灵魂人物',
    '来啦？今天想喝点什么？'
FROM scenes s WHERE s.scene_name = '冒险者酒馆'
LIMIT 1;

ALTER TABLE npc_profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY npc_read_access ON npc_profiles
    FOR SELECT USING (is_active = true);
