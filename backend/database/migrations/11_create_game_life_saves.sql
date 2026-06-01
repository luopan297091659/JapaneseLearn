CREATE TABLE IF NOT EXISTS `game_life_saves` (
  `user_id` CHAR(36) NOT NULL,
  `save_data` JSON NOT NULL,
  `revision` INT NOT NULL DEFAULT 1,
  `client_updated_at` DATETIME NULL,
  `device_id` VARCHAR(120) NULL,
  `app_version` VARCHAR(40) NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  KEY `idx_game_life_saves_updated_at` (`updated_at`),
  KEY `idx_game_life_saves_client_updated_at` (`client_updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
