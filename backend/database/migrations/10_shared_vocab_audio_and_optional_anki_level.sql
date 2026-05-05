-- 共享词库音频同步 + Anki 级别可选
-- MySQL 8.x

ALTER TABLE user_vocabulary
  MODIFY COLUMN jlpt_level ENUM('N5','N4','N3','N2','N1') NULL DEFAULT NULL,
  ADD COLUMN example_audio_url VARCHAR(500) NULL AFTER example_sentence;

ALTER TABLE shared_vocab_cards
  ADD COLUMN example_audio_url VARCHAR(500) NULL AFTER example_meaning_zh;
