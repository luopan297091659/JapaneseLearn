-- ============================================================================
-- 迁移 #07: 创建五十音（Kana）管理系统
-- 功能：
-- 1. 管理五十音字符数据（平假名、片假名、浊音、半浊音、拗音）
-- 2. 管理五十音音频资源
-- 3. 追踪用户学习进度
-- 4. 支持多种音频类型（标准、缓速、自然、音标）
-- ============================================================================

USE japanese_learn;

-- 1. 创建 kana_categories 表（五十音分类）
CREATE TABLE IF NOT EXISTS kana_categories (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL UNIQUE COMMENT '分类名称：平假名、片假名、浊音、半浊音、拗音',
  name_en VARCHAR(50) COMMENT 'English name: Hiragana, Katakana, Dakuten, Handakuten, Yoon',
  description TEXT COMMENT '分类描述',
  order_index INT NOT NULL DEFAULT 0 COMMENT '显示顺序',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. 创建 kana_characters 表（五十音字符）
CREATE TABLE IF NOT EXISTS kana_characters (
  id CHAR(36) NOT NULL PRIMARY KEY,
  category_id INT NOT NULL COMMENT '分类ID',
  hiragana VARCHAR(10) NOT NULL UNIQUE COMMENT '平假名',
  katakana VARCHAR(10) COMMENT '片假名',
  romaji VARCHAR(20) NOT NULL UNIQUE COMMENT '罗马字',
  order_index INT NOT NULL DEFAULT 0 COMMENT '显示顺序',
  stroke_count INT COMMENT '笔画数',
  writing_guide_url VARCHAR(500) COMMENT '写法指南URL（视频或图片）',
  is_obsolete TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否为废弃字符',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_category_id (category_id),
  INDEX idx_hiragana (hiragana),
  INDEX idx_romaji (romaji),
  CONSTRAINT fk_kana_char_category
    FOREIGN KEY (category_id) REFERENCES kana_categories(id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. 创建 kana_audio 表（五十音音频）
CREATE TABLE IF NOT EXISTS kana_audio (
  id CHAR(36) NOT NULL PRIMARY KEY,
  kana_character_id CHAR(36) NOT NULL COMMENT '假名字符ID',
  audio_type ENUM('standard', 'slow', 'natural', 'phonetic') NOT NULL DEFAULT 'standard' COMMENT '音频类型',
  audio_url VARCHAR(500) NOT NULL COMMENT '音频URL',
  audio_url_type ENUM('none', 'upload', 'kokoro') DEFAULT 'kokoro' COMMENT '音频源类型',
  audio_generated_at DATETIME COMMENT '生成时间',
  audio_expires_at DATETIME COMMENT '过期时间',
  voice_actor VARCHAR(50) COMMENT '声优/发音者',
  voice_emotion VARCHAR(50) COMMENT '语调情感',
  duration_ms INT COMMENT '音频时长（毫秒）',
  bitrate INT COMMENT '比特率',
  is_verified TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已验证',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_kana_audio_type (kana_character_id, audio_type),
  INDEX idx_kana_character_id (kana_character_id),
  INDEX idx_audio_type (audio_type),
  INDEX idx_expires_at (audio_expires_at),
  CONSTRAINT fk_kana_audio_char
    FOREIGN KEY (kana_character_id) REFERENCES kana_characters(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. 创建 user_kana_progress 表（用户学习进度）
CREATE TABLE IF NOT EXISTS user_kana_progress (
  id CHAR(36) NOT NULL PRIMARY KEY,
  user_id CHAR(36) NOT NULL COMMENT '用户ID',
  kana_character_id CHAR(36) NOT NULL COMMENT '假名字符ID',
  category_id INT NOT NULL COMMENT '分类ID（冗余，用于优化查询）',
  correct_count INT NOT NULL DEFAULT 0 COMMENT '答对次数',
  incorrect_count INT NOT NULL DEFAULT 0 COMMENT '答错次数',
  total_attempts INT NOT NULL DEFAULT 0 COMMENT '总尝试次数',
  correct_rate FLOAT COMMENT '正确率 (0-1)',
  is_mastered TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已掌握',
  last_reviewed_at DATETIME COMMENT '最后复习时间',
  mastered_at DATETIME COMMENT '掌握时间',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_kana (user_id, kana_character_id),
  INDEX idx_user_id (user_id),
  INDEX idx_category_id (category_id),
  INDEX idx_is_mastered (is_mastered),
  INDEX idx_last_reviewed_at (last_reviewed_at),
  CONSTRAINT fk_user_kana_progress_user
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  CONSTRAINT fk_user_kana_progress_char
    FOREIGN KEY (kana_character_id) REFERENCES kana_characters(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. 创建视图：快速查询假名及其音频
CREATE OR REPLACE VIEW v_kana_with_audio AS
SELECT
  kc.id AS kana_id,
  kc.category_id,
  cat.name AS category_name,
  kc.hiragana,
  kc.katakana,
  kc.romaji,
  kc.stroke_count,
  ka.id AS audio_id,
  ka.audio_type,
  ka.audio_url,
  ka.voice_emotion,
  ka.duration_ms
FROM
  kana_characters kc
  LEFT JOIN kana_categories cat ON kc.category_id = cat.id
  LEFT JOIN kana_audio ka ON kc.id = ka.kana_character_id
WHERE
  kc.is_obsolete = 0
  AND cat.is_active = 1
ORDER BY
  cat.order_index ASC,
  kc.order_index ASC,
  ka.audio_type ASC;

-- 6. 创建索引以优化常见查询
CREATE INDEX IF NOT EXISTS idx_kana_audio_generated ON kana_audio(audio_generated_at);
CREATE INDEX IF NOT EXISTS idx_user_kana_mastered ON user_kana_progress(user_id, is_mastered);
CREATE INDEX IF NOT EXISTS idx_user_kana_updated ON user_kana_progress(user_id, updated_at);

-- 7. 初始化五十音分类（可选）
INSERT IGNORE INTO kana_categories (name, name_en, description, order_index) VALUES
  ('平假名', 'Hiragana', '基础假名，用于现代日语书写', 1),
  ('片假名', 'Katakana', '用于外来词和拟声词', 2),
  ('浊音', 'Dakuten', '带浊音标记的假名', 3),
  ('半浊音', 'Handakuten', '带半浊音标记的假名', 4),
  ('拗音', 'Yoon', '小号假名的组合音节', 5);
