-- Active: 1769860933004@@139.196.44.6@3306@japanese_learn
-- Japanese Learning System - Database Initialization
-- Run this script against MySQL to create the database and all tables.

CREATE DATABASE IF NOT EXISTS japanese_learn
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE japanese_learn;

-- ─── Table: users ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            CHAR(36)      NOT NULL PRIMARY KEY,
  username      VARCHAR(50)   NOT NULL UNIQUE,
  email         VARCHAR(255)  NOT NULL UNIQUE,
  password_hash VARCHAR(255)  NOT NULL,
  avatar_url    VARCHAR(500)  NULL,
  level         ENUM('N5','N4','N3','N2','N1') NOT NULL DEFAULT 'N5',
  streak_days         INT     NOT NULL DEFAULT 0,
  total_study_minutes INT     NOT NULL DEFAULT 0,
  last_study_date     DATE    NULL,
  is_active           TINYINT(1) NOT NULL DEFAULT 1,
  notification_enabled TINYINT(1) NOT NULL DEFAULT 1,
  daily_goal_minutes  INT     NOT NULL DEFAULT 15,
  created_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: vocabulary ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vocabulary (
  id                 CHAR(36)     NOT NULL PRIMARY KEY,
  word               VARCHAR(100) NOT NULL,
  reading            VARCHAR(200) NOT NULL COMMENT '読み方 (hiragana/katakana)',
  meaning_zh         TEXT         NOT NULL,
  meaning_en         TEXT         NULL,
  part_of_speech     ENUM('noun','verb','adjective','adverb','particle','conjunction','interjection','other') NOT NULL DEFAULT 'noun',
  jlpt_level         ENUM('N5','N4','N3','N2','N1') NOT NULL,
  example_sentence   TEXT         NULL,
  example_reading    TEXT         NULL,
  example_meaning_zh TEXT         NULL,
  audio_url          VARCHAR(500) NULL,
  image_url          VARCHAR(500) NULL,
  category           VARCHAR(50)  NULL COMMENT 'e.g. food, travel, body',
  tags               JSON         NULL,
  created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_jlpt_level (jlpt_level),
  INDEX idx_word (word)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: grammar_lessons ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS grammar_lessons (
  id              CHAR(36)     NOT NULL PRIMARY KEY,
  title           VARCHAR(200) NOT NULL,
  title_zh        VARCHAR(200) NULL,
  jlpt_level      ENUM('N5','N4','N3','N2','N1') NOT NULL,
  pattern         VARCHAR(300) NOT NULL COMMENT '文型 e.g. ～てもいい',
  explanation     TEXT         NOT NULL,
  explanation_zh  TEXT         NULL,
  usage_notes     TEXT         NULL,
  order_index     INT          NOT NULL DEFAULT 0,
  created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_jlpt_level (jlpt_level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: grammar_examples ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS grammar_examples (
  id                CHAR(36) NOT NULL PRIMARY KEY,
  grammar_lesson_id CHAR(36) NOT NULL,
  sentence          TEXT     NOT NULL,
  reading           TEXT     NULL,
  meaning_zh        TEXT     NOT NULL,
  audio_url         VARCHAR(500) NULL,
  created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_grammar_lesson_id (grammar_lesson_id),
  CONSTRAINT fk_grammar_examples_lesson
    FOREIGN KEY (grammar_lesson_id) REFERENCES grammar_lessons(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: listening_tracks ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS listening_tracks (
  id               CHAR(36)     NOT NULL PRIMARY KEY,
  title            VARCHAR(200) NOT NULL,
  title_zh         VARCHAR(200) NULL,
  description      TEXT         NULL,
  audio_url        VARCHAR(500) NOT NULL,
  transcript       TEXT         NULL,
  transcript_zh    TEXT         NULL,
  duration_seconds INT          NULL,
  jlpt_level       ENUM('N5','N4','N3','N2','N1') NOT NULL,
  category         VARCHAR(50)  NULL,
  play_count       INT          NOT NULL DEFAULT 0,
  created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_jlpt_level (jlpt_level)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: quiz_questions ───────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quiz_questions (
  id                  CHAR(36)  NOT NULL PRIMARY KEY,
  question_type       ENUM('meaning','reading','listening','fill_blank') NOT NULL,
  question            TEXT      NOT NULL,
  correct_answer      TEXT      NOT NULL,
  options             JSON      NULL COMMENT 'Array of choices for MCQ',
  explanation         TEXT      NULL,
  ref_vocabulary_id   CHAR(36)  NULL,
  ref_grammar_id      CHAR(36)  NULL,
  jlpt_level          ENUM('N5','N4','N3','N2','N1') NOT NULL,
  created_at          DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_jlpt_level (jlpt_level),
  INDEX idx_question_type (question_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: quiz_sessions ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS quiz_sessions (
  id                 CHAR(36)  NOT NULL PRIMARY KEY,
  user_id            CHAR(36)  NOT NULL,
  quiz_type          ENUM('vocabulary','grammar','mixed','listening') NOT NULL DEFAULT 'vocabulary',
  jlpt_level         ENUM('N5','N4','N3','N2','N1') NOT NULL,
  total_questions    INT       NOT NULL DEFAULT 0,
  correct_count      INT       NOT NULL DEFAULT 0,
  score_percent      FLOAT     NOT NULL DEFAULT 0,
  time_spent_seconds INT       NOT NULL DEFAULT 0,
  completed_at       DATETIME  NULL,
  created_at         DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_user_id (user_id),
  CONSTRAINT fk_quiz_sessions_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: news_articles ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS news_articles (
  id                 CHAR(36)     NOT NULL PRIMARY KEY,
  external_id        VARCHAR(100) NULL UNIQUE,
  title              TEXT         NOT NULL,
  body               LONGTEXT     NOT NULL,
  body_with_ruby     LONGTEXT     NULL COMMENT 'HTML with ruby tags',
  audio_url          VARCHAR(500) NULL,
  image_url          VARCHAR(500) NULL,
  published_at       DATETIME     NULL,
  source             VARCHAR(100) NOT NULL DEFAULT 'NHK Easy',
  difficulty         ENUM('easy','medium','hard') NOT NULL DEFAULT 'easy',
  related_vocabulary JSON         NULL,
  created_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_published_at (published_at),
  INDEX idx_difficulty (difficulty)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: srs_cards ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS srs_cards (
  id               CHAR(36)  NOT NULL PRIMARY KEY,
  user_id          CHAR(36)  NOT NULL,
  card_type        ENUM('vocabulary','grammar') NOT NULL DEFAULT 'vocabulary',
  ref_id           CHAR(36)  NOT NULL COMMENT 'vocabulary.id or grammar_lessons.id',
  repetitions      INT       NOT NULL DEFAULT 0,
  ease_factor      FLOAT     NOT NULL DEFAULT 2.5,
  interval_days    INT       NOT NULL DEFAULT 0,
  due_date         DATE      NOT NULL DEFAULT (CURDATE()),
  last_reviewed_at DATETIME  NULL,
  is_graduated     TINYINT(1) NOT NULL DEFAULT 0,
  created_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_card (user_id, ref_id, card_type),
  INDEX idx_user_due (user_id, due_date),
  CONSTRAINT fk_srs_cards_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Table: user_progress ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_progress (
  id               CHAR(36)  NOT NULL PRIMARY KEY,
  user_id          CHAR(36)  NOT NULL,
  activity_type    ENUM('vocabulary','grammar','listening','quiz','news','srs_review') NOT NULL,
  ref_id           CHAR(36)  NULL,
  duration_seconds INT       NOT NULL DEFAULT 0,
  score            FLOAT     NULL,
  xp_earned        INT       NOT NULL DEFAULT 0,
  studied_at       DATE      NOT NULL DEFAULT (CURDATE()),
  created_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME  NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_user_studied (user_id, studied_at),
  CONSTRAINT fk_user_progress_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─── Sample N5 Vocabulary ───────────────────────────────────────────────────
INSERT IGNORE INTO vocabulary 
  (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level, 
   example_sentence, example_reading, example_meaning_zh, category, created_at, updated_at)
VALUES
  (UUID(), '食べる', 'たべる', '吃', 'to eat', 'verb', 'N5',
   '私はご飯を食べる。', 'わたしはごはんをたべる。', '我吃米饭。', 'daily', NOW(), NOW()),
  (UUID(), '飲む', 'のむ', '喝', 'to drink', 'verb', 'N5',
   '水を飲む。', 'みずをのむ。', '喝水。', 'daily', NOW(), NOW()),
  (UUID(), '行く', 'いく', '去', 'to go', 'verb', 'N5',
   '学校に行く。', 'がっこうにいく。', '去学校。', 'travel', NOW(), NOW()),
  (UUID(), '来る', 'くる', '来', 'to come', 'verb', 'N5',
   '友達が来る。', 'ともだちがくる。', '朋友来了。', 'daily', NOW(), NOW()),
  (UUID(), '見る', 'みる', '看', 'to see/watch', 'verb', 'N5',
   'テレビを見る。', 'テレビをみる。', '看电视。', 'daily', NOW(), NOW()),
  (UUID(), '聞く', 'きく', '听', 'to listen/ask', 'verb', 'N5',
   '音楽を聞く。', 'おんがくをきく。', '听音乐。', 'daily', NOW(), NOW()),
  (UUID(), '話す', 'はなす', '说/讲', 'to speak', 'verb', 'N5',
   '日本語を話す。', 'にほんごをはなす。', '说日语。', 'daily', NOW(), NOW()),
  (UUID(), '書く', 'かく', '写', 'to write', 'verb', 'N5',
   '手紙を書く。', 'てがみをかく。', '写信。', 'daily', NOW(), NOW()),
  (UUID(), '読む', 'よむ', '读', 'to read', 'verb', 'N5',
   '本を読む。', 'ほんをよむ。', '读书。', 'daily', NOW(), NOW()),
  (UUID(), '買う', 'かう', '买', 'to buy', 'verb', 'N5',
   'りんごを買う。', 'りんごをかう。', '买苹果。', 'shopping', NOW(), NOW()),
  (UUID(), '水', 'みず', '水', 'water', 'noun', 'N5',
   '水を飲む。', 'みずをのむ。', '喝水。', 'daily', NOW(), NOW()),
  (UUID(), '学校', 'がっこう', '学校', 'school', 'noun', 'N5',
   '学校に行く。', 'がっこうにいく。', '去学校。', 'education', NOW(), NOW()),
  (UUID(), '先生', 'せんせい', '老师', 'teacher', 'noun', 'N5',
   '先生が来る。', 'せんせいがくる。', '老师来了。', 'education', NOW(), NOW()),
  (UUID(), '友達', 'ともだち', '朋友', 'friend', 'noun', 'N5',
   '友達と話す。', 'ともだちとはなす。', '和朋友说话。', 'social', NOW(), NOW()),
  (UUID(), '大学', 'だいがく', '大学', 'university', 'noun', 'N5',
   '大学に行く。', 'だいがくにいく。', '去大学。', 'education', NOW(), NOW()),
  (UUID(), '好き', 'すき', '喜欢', 'to like', 'adjective', 'N5',
   '日本語が好きです。', 'にほんごがすきです。', '我喜欢日语。', 'daily', NOW(), NOW()),
  (UUID(), '嫌い', 'きらい', '讨厌', 'to dislike', 'adjective', 'N5',
   '虫が嫌いです。', 'むしがきらいです。', '我讨厌虫子。', 'daily', NOW(), NOW()),
  (UUID(), 'おいしい', 'おいしい', '好吃', 'delicious', 'adjective', 'N5',
   'このご飯はおいしい。', 'このごはんはおいしい。', '这顿饭很好吃。', 'food', NOW(), NOW()),
  (UUID(), '駅', 'えき', '车站', 'station', 'noun', 'N5',
   '駅に行く。', 'えきにいく。', '去车站。', 'travel', NOW(), NOW()),
  (UUID(), '電車', 'でんしゃ', '电车/地铁', 'train', 'noun', 'N5',
   '電車に乗る。', 'でんしゃにのる。', '乘电车。', 'travel', NOW(), NOW());

-- ─── Sample N5 Grammar Lessons ──────────────────────────────────────────────
INSERT IGNORE INTO grammar_lessons 
  (id, title, title_zh, jlpt_level, pattern, explanation, explanation_zh, order_index, created_at, updated_at)
VALUES
  (UUID(), 'は (Topic Marker)', '主题助词は', 'N5', '～は～です',
   'は marks the topic of a sentence. It indicates what the sentence is about.',
   'は是主题助词，表示句子的主题。常见结构：AはBです（A是B）。',
   1, NOW(), NOW()),
  (UUID(), 'が (Subject Marker)', '主语助词が', 'N5', '～が～',
   'が marks the grammatical subject of a verb. Often used to emphasize new information.',
   'が是主语助词，标记动词的主语，常用于强调新信息。',
   2, NOW(), NOW()),
  (UUID(), 'を (Object Marker)', '宾语助词を', 'N5', '～を～する',
   'を marks the direct object of a transitive verb.',
   'を是宾语助词，标记及物动词的直接宾语。',
   3, NOW(), NOW()),
  (UUID(), 'に (Direction/Time)', '方向/时间助词に', 'N5', '～に行く/来る/いる',
   'に indicates direction of movement (to), time, or location of existence.',
   'に表示移动方向（到...去）、时间点、或存在场所。',
   4, NOW(), NOW()),
  (UUID(), 'て形 (Te-form)', 'て形连接', 'N5', '～て、～',
   'The te-form connects clauses sequentially, or makes requests (～てください).',
   'て形用于连接两个动作（先做...再做...），或表示请求（请...）。',
   5, NOW(), NOW()),
  (UUID(), 'たい (Want to)', '想做～', 'N5', '～たい',
   'Attach たい to the verb stem to express desire. "I want to ~".',
   '动词ます形词干 + たい，表示"想做某事"。',
   6, NOW(), NOW()),
  (UUID(), 'ている (Ongoing Action)', '正在进行', 'N5', '～ている',
   'Indicates an ongoing action or a resulting state. "is doing ~" or "has done ~".',
   '表示正在进行的动作或动作完成后的持续状态。',
   7, NOW(), NOW()),
  (UUID(), 'なかった (Past Negative)', '过去否定', 'N5', '～なかった',
   'Past negative form of verbs and adjectives.',
   '动词和形容词的过去否定形式，"没有做..."。',
   8, NOW(), NOW());

-- ─── Sample Quiz Questions ───────────────────────────────────────────────────
INSERT IGNORE INTO quiz_questions
  (id, question_type, question, correct_answer, options, explanation, jlpt_level, created_at, updated_at)
VALUES
  (UUID(), 'meaning', '「食べる」の意味は？', '吃',
   '["吃","喝","看","写"]', '食べる (たべる) means "to eat"。', 'N5', NOW(), NOW()),
  (UUID(), 'meaning', '「飲む」の意味は？', '喝',
   '["吃","喝","买","走"]', '飲む (のむ) means "to drink"。', 'N5', NOW(), NOW()),
  (UUID(), 'reading', '「学校」の読み方は？', 'がっこう',
   '["がっこう","がくせい","せんせい","だいがく"]', '学校 is read as がっこう (gakkou)。', 'N5', NOW(), NOW()),
  (UUID(), 'reading', '「先生」の読み方は？', 'せんせい',
   '["がっこう","ともだち","せんせい","でんしゃ"]', '先生 is read as せんせい (sensei)。', 'N5', NOW(), NOW()),
  (UUID(), 'fill_blank', '私は学校___行きます。', 'に',
   '["に","を","は","が"]', 'に marks direction: 学校に行く (go to school)。', 'N5', NOW(), NOW()),
  (UUID(), 'meaning', '「好き」の意味は？', '喜欢',
   '["喜欢","讨厌","好看","好吃"]', '好き (すき) means "to like"。', 'N5', NOW(), NOW()),
  (UUID(), 'fill_blank', 'ご飯___食べます。', 'を',
   '["を","は","に","が"]', 'を marks the direct object: ご飯を食べる (eat rice)。', 'N5', NOW(), NOW()),
  (UUID(), 'meaning', '「電車」の意味は？', '电车/地铁',
   '["自行车","电车/地铁","公交车","出租车"]', '電車 (でんしゃ) means "train/subway"。', 'N5', NOW(), NOW());
