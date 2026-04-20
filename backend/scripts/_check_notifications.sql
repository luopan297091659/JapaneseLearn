SHOW TABLES LIKE 'notifications';
SELECT COUNT(*) AS cnt FROM notifications;
SELECT id, user_id, type, title, LEFT(content, 60) as content, is_read, createdAt FROM notifications ORDER BY id DESC LIMIT 10;
