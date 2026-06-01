ALTER TABLE users
  ADD COLUMN IF NOT EXISTS tokyo_app_login_token VARCHAR(36) NULL AFTER app_login_token;
