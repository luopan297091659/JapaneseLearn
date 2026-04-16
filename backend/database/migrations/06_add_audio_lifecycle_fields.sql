-- ============================================================================
-- 迁移 #06: 添加音频生命周期管理字段
-- 功能：
-- 1. 为vocabulary表添加音频元数据管理字段
-- 2. 为vocabulary_examples表添加音频元数据管理字段
-- 3. 为grammar_examples表添加音频元数据管理字段
-- 4. 创建Kokoro音频清理日志表
-- 5. 创建音频统计信息表
--
-- 统一音频路径: /uploads/audio/kokoro_xxx.wav
-- 一键和单个生成都使用此路径，统一存储在 /uploads/audio/ 目录中
-- ============================================================================

USE japanese_learn;

-- 为 vocabulary 表添加字段
-- 检查表是否存在，然后添加缺失的字段
ALTER TABLE vocabulary 
  ADD COLUMN IF NOT EXISTS audio_url_type ENUM('none', 'upload', 'kokoro') DEFAULT 'none' AFTER audio_url,
  ADD COLUMN IF NOT EXISTS audio_generated_at DATETIME NULL AFTER audio_url_type,
  ADD COLUMN IF NOT EXISTS audio_expires_at DATETIME NULL AFTER audio_generated_at;

-- 为 vocabulary_examples 表添加字段（如果存在）
ALTER TABLE vocabulary_examples 
  ADD COLUMN IF NOT EXISTS audio_url_type ENUM('none', 'upload', 'kokoro') DEFAULT 'none' AFTER audio_url,
  ADD COLUMN IF NOT EXISTS audio_generated_at DATETIME NULL AFTER audio_url_type,
  ADD COLUMN IF NOT EXISTS audio_expires_at DATETIME NULL AFTER audio_generated_at;

-- 为 grammar_examples 表添加字段
ALTER TABLE grammar_examples 
  ADD COLUMN IF NOT EXISTS audio_url_type ENUM('none', 'upload', 'kokoro') DEFAULT 'none' AFTER audio_url,
  ADD COLUMN IF NOT EXISTS audio_generated_at DATETIME NULL AFTER audio_url_type,
  ADD COLUMN IF NOT EXISTS audio_expires_at DATETIME NULL AFTER audio_generated_at;

-- 创建 Kokoro 音频清理日志表
CREATE TABLE IF NOT EXISTS kokoro_audio_cleanup_logs (
  id CHAR(36) NOT NULL PRIMARY KEY,
  cleanup_type ENUM('expired', 'orphaned', 'manual') NOT NULL COMMENT '清理类型',
  table_name VARCHAR(100) COMMENT '来自哪个表',
  audio_filename VARCHAR(255) COMMENT '被清理的音频文件名',
  reason TEXT COMMENT '清理原因',
  deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  admin_id CHAR(36) COMMENT '执行清理的管理员ID',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_cleanup_type (cleanup_type),
  INDEX idx_deleted_at (deleted_at),
  INDEX idx_admin_id (admin_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 创建音频统计信息表
CREATE TABLE IF NOT EXISTS kokoro_audio_stats (
  id CHAR(36) NOT NULL PRIMARY KEY,
  stat_date DATE NOT NULL UNIQUE COMMENT '统计日期',
  total_audio_count INT NOT NULL DEFAULT 0 COMMENT '总音频数',
  vocab_audio_count INT NOT NULL DEFAULT 0 COMMENT '词汇音频数',
  grammar_audio_count INT NOT NULL DEFAULT 0 COMMENT '语法音频数',
  kana_audio_count INT NOT NULL DEFAULT 0 COMMENT '假名音频数',
  disk_usage_bytes BIGINT NOT NULL DEFAULT 0 COMMENT '磁盘用量（字节）',
  expired_audio_count INT NOT NULL DEFAULT 0 COMMENT '过期音频数',
  cleanup_count INT NOT NULL DEFAULT 0 COMMENT '本日清理数量',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_stat_date (stat_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 创建索引以提升查询性能
CREATE INDEX IF NOT EXISTS idx_vocab_audio_expires ON vocabulary(audio_expires_at)
  WHERE audio_expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_grammar_audio_expires ON grammar_examples(audio_expires_at)
  WHERE audio_expires_at IS NOT NULL;

-- 预定义的清理日志触发器（可选）
-- 这会自动记录音频更新事件
DELIMITER //

CREATE TRIGGER IF NOT EXISTS tr_vocab_audio_update
BEFORE UPDATE ON vocabulary
FOR EACH ROW
BEGIN
  IF OLD.audio_url IS NOT NULL AND NEW.audio_url IS NULL THEN
    -- 音频被清理，记录到日志（可选实现）
    SET NEW.audio_expires_at = NULL;
  END IF;
END//

DELIMITER ;
