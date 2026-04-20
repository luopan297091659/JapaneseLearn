ALTER TABLE membership_orders
  ADD COLUMN apple_original_transaction_id VARCHAR(200) NULL,
  ADD COLUMN apple_environment VARCHAR(20) NULL,
  ADD COLUMN apple_expires_at DATETIME NULL,
  ADD COLUMN apple_auto_renew_status TINYINT(1) NULL,
  ADD COLUMN apple_notification_type VARCHAR(60) NULL,
  ADD INDEX idx_apple_original_tx (apple_original_transaction_id);
