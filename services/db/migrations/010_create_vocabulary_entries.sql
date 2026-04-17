CREATE TABLE vocabulary_entries (
    entry_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    word TEXT NOT NULL,
    translation TEXT NOT NULL,
    part_of_speech TEXT,
    cefr_level TEXT DEFAULT 'A1' CHECK (cefr_level IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2')),
    example_sentence TEXT,
    audio_ref TEXT,
    image_ref TEXT,
    scene_context TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_vocabulary_word ON vocabulary_entries(word);
CREATE INDEX idx_vocabulary_cefr ON vocabulary_entries(cefr_level);

ALTER TABLE vocabulary_entries ENABLE ROW LEVEL SECURITY;
CREATE POLICY vocabulary_read_access ON vocabulary_entries
    FOR SELECT USING (true);
