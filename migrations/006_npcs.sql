-- 006_npcs.sql
-- Chapter 1 NPC configurations

CREATE TABLE IF NOT EXISTS npcs (
  npc_id VARCHAR(50) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  name_cn VARCHAR(100),
  role VARCHAR(50),
  personality TEXT,
  cefr_level VARCHAR(10) DEFAULT 'A1',
  voice_style VARCHAR(50),
  greeting TEXT,
  scene_id VARCHAR(50) REFERENCES scenes(scene_id),
  teaches JSONB DEFAULT '[]',
  is_persistent BOOLEAN DEFAULT false,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Seed chapter 1 NPCs
INSERT INTO npcs (npc_id, name, name_cn, role, personality, cefr_level, voice_style, greeting, scene_id, teaches, is_persistent) VALUES
  ('spark', 'Spark', '小灵', 'spirit_coach', '活泼热情，全程陪伴', 'A1', 'cheerful_childlike', 'Hi! I''m Spark! Welcome to the Magic Academy!', NULL, '{}', true),
  ('oakley', 'Oakley', NULL, 'forest_guardian', '智慧温和，语速较慢', 'A1', 'wise_slow', 'Welcome, young student. I am Oakley, guardian of this forest.', 'spirit_forest', '["greetings", "colors", "numbers"]', false),
  ('bookmark', 'Bookmark', NULL, 'librarian', '博学稳重，慢慢来', 'A1', 'calm_elderly', 'Welcome to the Spell Library. Take your time, young one.', 'spell_library', '["classroom_items", "commands"]', false),
  ('luna', 'Luna', NULL, 'apprentice', '活泼可爱，像好朋友', 'A1', 'friendly_peer', 'Hey! I''m Luna! Let''s practice magic spells together!', 'spell_library', '["actions", "dialogue_practice"]', false),
  ('petalia', 'Petalia', NULL, 'flower_fairy', '温柔耐心，充满母性关怀', 'A1', 'gentle_warm', 'Hello dear! I''m Petalia. Can you help me with the garden?', 'rainbow_garden', '["weather", "animals", "positions", "emotions"]', false);

CREATE INDEX idx_npcs_scene ON npcs(scene_id);
