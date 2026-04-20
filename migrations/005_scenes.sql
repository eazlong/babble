-- 005_scenes.sql
-- Chapter 1 scene configurations

CREATE TABLE IF NOT EXISTS scenes (
  scene_id VARCHAR(50) PRIMARY KEY,
  scene_name VARCHAR(100) NOT NULL,
  scene_name_en VARCHAR(100) NOT NULL,
  scene_order INTEGER NOT NULL,
  description TEXT,
  description_en TEXT,
  npcs JSONB DEFAULT '[]',
  vocabulary_focus JSONB DEFAULT '[]',
  tasks JSONB DEFAULT '[]',
  badge_id VARCHAR(50),
  required_lxp INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Seed chapter 1 scenes
INSERT INTO scenes (scene_id, scene_name, scene_name_en, scene_order, description, description_en, npcs, vocabulary_focus, tasks, badge_id, required_lxp) VALUES
  ('spirit_forest', '精灵森林', 'Spirit Forest', 1, '初识魔法，学习问候语、颜色和数字', 'Learn greetings, colors, and numbers', '["oakley"]', '["greetings", "colors", "numbers"]', '["greet_oakley", "activate_flowers", "open_chest"]', 'forest_badge', 30),
  ('spell_library', '咒语图书馆', 'Spell Library', 2, '学习课堂用语和学习用品', 'Learn classroom commands and school items', '["bookmark", "luna"]', '["classroom_items", "commands", "actions"]', '["organize_books", "follow_commands", "practice_dialogue"]', 'library_badge', 60),
  ('rainbow_garden', '彩虹花园', 'Rainbow Garden', 3, '探索自然，学习天气、动物、方位', 'Explore weather, animals, and positions', '["petalia"]', '["weather", "animals", "plants", "positions", "emotions"]', '["fix_weather_crystal", "find_lost_animals", "plant_flowers"]', 'garden_badge', 90);

CREATE INDEX idx_scenes_order ON scenes(scene_order);
