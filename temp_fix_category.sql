UPDATE listening_tracks SET category = CONVERT(UNHEX('E697A5E8AFADE79FADE69687') USING utf8mb4) WHERE HEX(category) = '3F3F3F3F';
SELECT HEX(category), COUNT(*) as cnt FROM listening_tracks GROUP BY category;
