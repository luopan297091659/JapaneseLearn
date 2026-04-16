-- Create Kana Management System tables
-- Database: japanese_learn
-- Purpose: Store Kana characters and learning progress

SET FOREIGN_KEY_CHECKS=0;

-- Table: kana_categories
CREATE TABLE IF NOT EXISTS kana_categories (
  id INT NOT NULL PRIMARY KEY AUTO_INCREMENT COMMENT '分类ID',
  name VARCHAR(50) NOT NULL COMMENT '分类名称',
  description TEXT COMMENT '分类描述',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='五十音分类表';

-- Table: kana_characters  
CREATE TABLE IF NOT EXISTS kana_characters (
  id CHAR(36) NOT NULL PRIMARY KEY COMMENT '字符ID',
  category_id INT NOT NULL COMMENT '分类ID',
  hiragana VARCHAR(10) NOT NULL UNIQUE COMMENT '平假名',
  katakana VARCHAR(10) NOT NULL UNIQUE COMMENT '片假名',
  romaji VARCHAR(50) NOT NULL COMMENT '罗马字',
  type ENUM('normal','dakuten','handakuten','youon') NOT NULL DEFAULT 'normal' COMMENT '字符类型: normal(基本), dakuten(浊音), handakuten(半浊音), youon(拗音)',
  order_index INT NOT NULL DEFAULT 0 COMMENT '排序索引',
  stroke_count INT COMMENT '笔画数',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_category_id (category_id),
  INDEX idx_type (type),
  INDEX idx_romaji (romaji),
  CONSTRAINT fk_kana_char_category
    FOREIGN KEY (category_id) REFERENCES kana_categories(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='五十音字符表';

-- Table: kana_audio
CREATE TABLE IF NOT EXISTS kana_audio (
  id CHAR(36) NOT NULL PRIMARY KEY COMMENT '音频ID',
  kana_character_id CHAR(36) NOT NULL COMMENT '字符ID',
  audio_path VARCHAR(255) COMMENT '音频文件路径',
  generated_at DATETIME COMMENT '生成时间',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_kana_id (kana_character_id),
  CONSTRAINT fk_kana_audio_char
    FOREIGN KEY (kana_character_id) REFERENCES kana_characters(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='五十音音频表';

-- Table: user_kana_progress (without dependency on users table initially)
CREATE TABLE IF NOT EXISTS user_kana_progress (
  id CHAR(36) NOT NULL PRIMARY KEY COMMENT '进度ID',
  user_id CHAR(36) NOT NULL COMMENT '用户ID',
  kana_character_id CHAR(36) NOT NULL COMMENT '字符ID',
  category_id INT NOT NULL COMMENT '分类ID',
  correct_count INT NOT NULL DEFAULT 0 COMMENT '答对次数',
  incorrect_count INT NOT NULL DEFAULT 0 COMMENT '答错次数',
  total_attempts INT NOT NULL DEFAULT 0 COMMENT '总尝试次数',
  correct_rate FLOAT COMMENT '正确率(0-1)',
  is_mastered TINYINT(1) NOT NULL DEFAULT 0 COMMENT '是否已掌握',
  last_reviewed_at DATETIME COMMENT '最后学习时间',
  mastered_at DATETIME COMMENT '掌握时间',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uq_user_kana (user_id, kana_character_id),
  INDEX idx_user_id (user_id),
  INDEX idx_category_id (category_id),
  INDEX idx_is_mastered (is_mastered),
  INDEX idx_last_reviewed_at (last_reviewed_at),
  CONSTRAINT fk_user_kana_progress_char
    FOREIGN KEY (kana_character_id) REFERENCES kana_characters(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='用户五十音学习进度表';

-- Additional indexes for optimization
CREATE INDEX IF NOT EXISTS idx_user_kana_mastered ON user_kana_progress(user_id, is_mastered);
CREATE INDEX IF NOT EXISTS idx_user_kana_updated ON user_kana_progress(user_id, updated_at);

SET FOREIGN_KEY_CHECKS=1;
