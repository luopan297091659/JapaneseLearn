DROP TABLE IF EXISTS notifications;
CREATE TABLE notifications (
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
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  KEY idx_user (user_id),
  KEY idx_user_read (user_id, is_read),
  KEY idx_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
