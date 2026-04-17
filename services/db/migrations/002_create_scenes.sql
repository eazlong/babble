CREATE TABLE scenes (
    scene_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scene_name TEXT NOT NULL,
    scene_type TEXT NOT NULL,
    real_world_context TEXT,
    core_language_functions JSONB NOT NULL DEFAULT '[]',
    cefr_unlock_requirement TEXT DEFAULT 'A1' CHECK (cefr_unlock_requirement IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')),
    visual_assets_ref TEXT,
    ambient_audio_ref TEXT,
    chapter_id TEXT NOT NULL,
    is_active BOOLEAN DEFAULT true
);

CREATE INDEX idx_scenes_chapter ON scenes(chapter_id);
CREATE INDEX idx_scenes_cefr ON scenes(cefr_unlock_requirement);

-- MVP: Seed 3 scenes
INSERT INTO scenes (scene_name, scene_type, real_world_context, core_language_functions, cefr_unlock_requirement, chapter_id) VALUES
('王都集市', 'marketplace', '购物/市场交易', '["描述物品", "询价", "议价", "数量表达"]', 'A1', 'chapter_1'),
('冒险者酒馆', 'tavern', '餐厅/社交场所', '["点餐", "寒暄", "讲故事", "邀约"]', 'A1', 'chapter_1'),
('冒险者公会', 'guild', '机构办事', '["任务描述", "方向表达", "指令理解"]', 'A1', 'chapter_1');

ALTER TABLE scenes ENABLE ROW LEVEL SECURITY;
CREATE POLICY scenes_read_access ON scenes
    FOR SELECT USING (is_active = true);
