-- 为 membership_orders 添加 user_note 字段
ALTER TABLE membership_orders
  ADD COLUMN user_note TEXT NULL COMMENT '用户提交时的文字说明';

-- notifications 表会由 Sequelize 自动创建（CREATE TABLE IF NOT EXISTS）
-- 如自动创建失败可手动执行：
CREATE TABLE IF NOT EXISTS notifications (
  id BIGINT NOT NULL AUTO_INCREMENT,
  user_id CHAR(36) NOT NULL,
  type VARCHAR(40) NOT NULL,
  title VARCHAR(120) NOT NULL,
  content TEXT NULL,
  ref_type VARCHAR(30) NULL,
  ref_id VARCHAR(64) NULL,
  extra JSON NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  read_at DATETIME NULL,
  createdAt DATETIME NOT NULL,
  updatedAt DATETIME NOT NULL,
  PRIMARY KEY (id),
  KEY idx_user (user_id),
  KEY idx_user_read (user_id, is_read),
  KEY idx_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
