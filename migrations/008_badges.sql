-- 008_badges.sql
-- Badge definitions and user badge progress

CREATE TABLE IF NOT EXISTS badge_definitions (
  badge_id VARCHAR(50) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  name_en VARCHAR(100) NOT NULL,
  description TEXT,
  description_en TEXT,
  icon_ref VARCHAR(100),
  unlock_condition VARCHAR(100),
  scene_id VARCHAR(50) REFERENCES scenes(scene_id),
  reward_type VARCHAR(50),
  reward_value VARCHAR(100),
  required_lxp INTEGER DEFAULT 0
);

-- Seed chapter 1 badges
INSERT INTO badge_definitions (badge_id, name, name_en, description, description_en, icon_ref, unlock_condition, scene_id, reward_type, reward_value, required_lxp) VALUES
  ('forest_badge', '森林徽章', 'Forest Badge', '完成精灵森林挑战', 'Complete the Spirit Forest challenge', 'icon_forest', 'complete_spirit_forest', 'spirit_forest', 'visual_effect', 'color_magic_effect', 30),
  ('library_badge', '图书馆徽章', 'Library Badge', '完成咒语图书馆挑战', 'Complete the Spell Library challenge', 'icon_library', 'complete_spell_library', 'spell_library', 'companion', 'floating_book_pet', 60),
  ('garden_badge', '花园徽章', 'Garden Badge', '完成彩虹花园挑战', 'Complete the Rainbow Garden challenge', 'icon_garden', 'complete_rainbow_garden', 'rainbow_garden', 'background', 'rainbow_background', 90),
  ('apprentice_title', '魔法学徒', 'Magic Apprentice', '集齐所有徽章获得称号', 'Collect all badges to earn the title', 'icon_apprentice', 'collect_all_badges', NULL, 'title', 'apprentice_title', 0);

CREATE TABLE IF NOT EXISTS user_badges (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  badge_id VARCHAR(50) NOT NULL REFERENCES badge_definitions(badge_id),
  earned_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, badge_id)
);

CREATE TABLE IF NOT EXISTS user_scene_progress (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  scene_id VARCHAR(50) NOT NULL REFERENCES scenes(scene_id),
  stars_earned INTEGER DEFAULT 0,
  quests_completed JSONB DEFAULT '[]',
  completed BOOLEAN DEFAULT false,
  completed_at TIMESTAMP,
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, scene_id)
);

CREATE INDEX idx_user_badges_user ON user_badges(user_id);
CREATE INDEX idx_user_scene_progress_user ON user_scene_progress(user_id);
