-- 007_curriculum.sql
-- Grade 4 English curriculum items

CREATE TABLE IF NOT EXISTS curriculum_items (
  id SERIAL PRIMARY KEY,
  category VARCHAR(50) NOT NULL,
  category_cn VARCHAR(50) NOT NULL,
  category_en VARCHAR(50),
  scene VARCHAR(50) REFERENCES scenes(scene_id),
  text_en TEXT NOT NULL,
  text_cn TEXT,
  audio_ref VARCHAR(100),
  difficulty INTEGER DEFAULT 1,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_curriculum_category ON curriculum_items(category);
CREATE INDEX idx_curriculum_scene ON curriculum_items(scene);
CREATE INDEX idx_curriculum_difficulty ON curriculum_items(difficulty);
