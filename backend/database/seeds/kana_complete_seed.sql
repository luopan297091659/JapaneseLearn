-- Active: 1769860933004@@139.196.44.6@3306@japanese_learn
-- Complete Kana seed data matching mobile client
-- Includes: 五十音、濁音、半濁音、拗音
-- Generated: 2026-04-06

-- 安全删除索引（不存在也不报错）
SET @exist := (SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'kana' AND INDEX_NAME = 'kana_type_character');
SET @sqlStmt := IF(@exist > 0, 'ALTER TABLE kana DROP INDEX kana_type_character', 'SELECT "Index not found, skip" as status');
PREPARE stmt FROM @sqlStmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE kana;
SET FOREIGN_KEY_CHECKS=1;

-- ─── 清音 (五十音) ──────────────────────────────────────────────
-- Row 1: あ いるえ お
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'あ', 'a', '五十音', 1, NOW(), NOW()),
(UUID(), 'hiragana', 'い', 'i', '五十音', 2, NOW(), NOW()),
(UUID(), 'hiragana', 'う', 'u', '五十音', 3, NOW(), NOW()),
(UUID(), 'hiragana', 'え', 'e', '五十音', 4, NOW(), NOW()),
(UUID(), 'hiragana', 'お', 'o', '五十音', 5, NOW(), NOW()),
(UUID(), 'katakana', 'ア', 'a', '五十音', 6, NOW(), NOW()),
(UUID(), 'katakana', 'イ', 'i', '五十音', 7, NOW(), NOW()),
(UUID(), 'katakana', 'ウ', 'u', '五十音', 8, NOW(), NOW()),
(UUID(), 'katakana', 'エ', 'e', '五十音', 9, NOW(), NOW()),
(UUID(), 'katakana', 'オ', 'o', '五十音', 10, NOW(), NOW());

-- Row 2: か き く け こ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'か', 'ka', '五十音', 11, NOW(), NOW()),
(UUID(), 'hiragana', 'き', 'ki', '五十音', 12, NOW(), NOW()),
(UUID(), 'hiragana', 'く', 'ku', '五十音', 13, NOW(), NOW()),
(UUID(), 'hiragana', 'け', 'ke', '五十音', 14, NOW(), NOW()),
(UUID(), 'hiragana', 'こ', 'ko', '五十音', 15, NOW(), NOW()),
(UUID(), 'katakana', 'カ', 'ka', '五十音', 16, NOW(), NOW()),
(UUID(), 'katakana', 'キ', 'ki', '五十音', 17, NOW(), NOW()),
(UUID(), 'katakana', 'ク', 'ku', '五十音', 18, NOW(), NOW()),
(UUID(), 'katakana', 'ケ', 'ke', '五十音', 19, NOW(), NOW()),
(UUID(), 'katakana', 'コ', 'ko', '五十音', 20, NOW(), NOW());

-- Row 3: さ し す せ そ
INSERT INTO kana (id, type,`character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'さ', 'sa', '五十音', 21, NOW(), NOW()),
(UUID(), 'hiragana', 'し', 'shi', '五十音', 22, NOW(), NOW()),
(UUID(), 'hiragana', 'す', 'su', '五十音', 23, NOW(), NOW()),
(UUID(), 'hiragana', 'せ', 'se', '五十音', 24, NOW(), NOW()),
(UUID(), 'hiragana', 'そ', 'so', '五十音', 25, NOW(), NOW()),
(UUID(), 'katakana', 'サ', 'sa', '五十音', 26, NOW(), NOW()),
(UUID(), 'katakana', 'シ', 'shi', '五十音', 27, NOW(), NOW()),
(UUID(), 'katakana', 'ス', 'su', '五十音', 28, NOW(), NOW()),
(UUID(), 'katakana', 'セ', 'se', '五十音', 29, NOW(), NOW()),
(UUID(), 'katakana', 'ソ', 'so', '五十音', 30, NOW(), NOW());

-- Row 4: た ち つ て と
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'た', 'ta', '五十音', 31, NOW(), NOW()),
(UUID(), 'hiragana', 'ち', 'chi', '五十音', 32, NOW(), NOW()),
(UUID(), 'hiragana', 'つ', 'tsu', '五十音', 33, NOW(), NOW()),
(UUID(), 'hiragana', 'て', 'te', '五十音', 34, NOW(), NOW()),
(UUID(), 'hiragana', 'と', 'to', '五十音', 35, NOW(), NOW()),
(UUID(), 'katakana', 'タ', 'ta', '五十音', 36, NOW(), NOW()),
(UUID(), 'katakana', 'チ', 'chi', '五十音', 37, NOW(), NOW()),
(UUID(), 'katakana', 'ツ', 'tsu', '五十音', 38, NOW(), NOW()),
(UUID(), 'katakana', 'テ', 'te', '五十音', 39, NOW(), NOW()),
(UUID(), 'katakana', 'ト', 'to', '五十音', 40, NOW(), NOW());

-- Row 5: な に ぬ ね の
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'な', 'na', '五十音', 41, NOW(), NOW()),
(UUID(), 'hiragana', 'に', 'ni', '五十音', 42, NOW(), NOW()),
(UUID(), 'hiragana', 'ぬ', 'nu', '五十音', 43, NOW(), NOW()),
(UUID(), 'hiragana', 'ね', 'ne', '五十音', 44, NOW(), NOW()),
(UUID(), 'hiragana', 'の', 'no', '五十音', 45, NOW(), NOW()),
(UUID(), 'katakana', 'ナ', 'na', '五十音', 46, NOW(), NOW()),
(UUID(), 'katakana', 'ニ', 'ni', '五十音', 47, NOW(), NOW()),
(UUID(), 'katakana', 'ヌ', 'nu', '五十音', 48, NOW(), NOW()),
(UUID(), 'katakana', 'ネ', 'ne', '五十音', 49, NOW(), NOW()),
(UUID(), 'katakana', 'ノ', 'no', '五十音', 50, NOW(), NOW());

-- Row 6: は ひ ふ へ ほ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'は', 'ha', '五十音', 51, NOW(), NOW()),
(UUID(), 'hiragana', 'ひ', 'hi', '五十音', 52, NOW(), NOW()),
(UUID(), 'hiragana', 'ふ', 'fu', '五十音', 53, NOW(), NOW()),
(UUID(), 'hiragana', 'へ', 'he', '五十音', 54, NOW(), NOW()),
(UUID(), 'hiragana', 'ほ', 'ho', '五十音', 55, NOW(), NOW()),
(UUID(), 'katakana', 'ハ', 'ha', '五十音', 56, NOW(), NOW()),
(UUID(), 'katakana', 'ヒ', 'hi', '五十音', 57, NOW(), NOW()),
(UUID(), 'katakana', 'フ', 'fu', '五十音', 58, NOW(), NOW()),
(UUID(), 'katakana', 'ヘ', 'he', '五十音', 59, NOW(), NOW()),
(UUID(), 'katakana', 'ホ', 'ho', '五十音', 60, NOW(), NOW());

-- Row 7: ま み む め も
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ま', 'ma', '五十音', 61, NOW(), NOW()),
(UUID(), 'hiragana', 'み', 'mi', '五十音', 62, NOW(), NOW()),
(UUID(), 'hiragana', 'む', 'mu', '五十音', 63, NOW(), NOW()),
(UUID(), 'hiragana', 'め', 'me', '五十音', 64, NOW(), NOW()),
(UUID(), 'hiragana', 'も', 'mo', '五十音', 65, NOW(), NOW()),
(UUID(), 'katakana', 'マ', 'ma', '五十音', 66, NOW(), NOW()),
(UUID(), 'katakana', 'ミ', 'mi', '五十音', 67, NOW(), NOW()),
(UUID(), 'katakana', 'ム', 'mu', '五十音', 68, NOW(), NOW()),
(UUID(), 'katakana', 'メ', 'me', '五十音', 69, NOW(), NOW()),
(UUID(), 'katakana', 'モ', 'mo', '五十音', 70, NOW(), NOW());

-- Row 8: や ゆ よ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'や', 'ya', '五十音', 71, NOW(), NOW()),
(UUID(), 'hiragana', 'ゆ', 'yu', '五十音', 72, NOW(), NOW()),
(UUID(), 'hiragana', 'よ', 'yo', '五十音', 73, NOW(), NOW()),
(UUID(), 'katakana', 'ヤ', 'ya', '五十音', 74, NOW(), NOW()),
(UUID(), 'katakana', 'ユ', 'yu', '五十音', 75, NOW(), NOW()),
(UUID(), 'katakana', 'ヨ', 'yo', '五十音', 76, NOW(), NOW());

-- Row 9: ら り る れ ろ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ら', 'ra', '五十音', 77, NOW(), NOW()),
(UUID(), 'hiragana', 'り', 'ri', '五十音', 78, NOW(), NOW()),
(UUID(), 'hiragana', 'る', 'ru', '五十音', 79, NOW(), NOW()),
(UUID(), 'hiragana', 'れ', 're', '五十音', 80, NOW(), NOW()),
(UUID(), 'hiragana', 'ろ', 'ro', '五十音', 81, NOW(), NOW()),
(UUID(), 'katakana', 'ラ', 'ra', '五十音', 82, NOW(), NOW()),
(UUID(), 'katakana', 'リ', 'ri', '五十音', 83, NOW(), NOW()),
(UUID(), 'katakana', 'ル', 'ru', '五十音', 84, NOW(), NOW()),
(UUID(), 'katakana', 'レ', 're', '五十音', 85, NOW(), NOW()),
(UUID(), 'katakana', 'ロ', 'ro', '五十音', 86, NOW(), NOW());

-- Row 10: わ を
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'わ', 'wa', '五十音', 87, NOW(), NOW()),
(UUID(), 'hiragana', 'を', 'wo', '五十音', 88, NOW(), NOW()),
(UUID(), 'katakana', 'ワ', 'wa', '五十音', 89, NOW(), NOW()),
(UUID(), 'katakana', 'ヲ', 'wo', '五十音', 90, NOW(), NOW());

-- Row 11: ん
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ん', 'n', '五十音', 91, NOW(), NOW()),
(UUID(), 'katakana', 'ン', 'n', '五十音', 92, NOW(), NOW());

-- ─── 濁音 (Dakuten) ──────────────────────────────────────────────
-- Row 1: が ぎ ぐ げ ご
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'が', 'ga', '濁音', 101, NOW(), NOW()),
(UUID(), 'hiragana', 'ぎ', 'gi', '濁音', 102, NOW(), NOW()),
(UUID(), 'hiragana', 'ぐ', 'gu', '濁音', 103, NOW(), NOW()),
(UUID(), 'hiragana', 'げ', 'ge', '濁音', 104, NOW(), NOW()),
(UUID(), 'hiragana', 'ご', 'go', '濁音', 105, NOW(), NOW()),
(UUID(), 'katakana', 'ガ', 'ga', '濁音', 106, NOW(), NOW()),
(UUID(), 'katakana', 'ギ', 'gi', '濁音', 107, NOW(), NOW()),
(UUID(), 'katakana', 'グ', 'gu', '濁音', 108, NOW(), NOW()),
(UUID(), 'katakana', 'ゲ', 'ge', '濁音', 109, NOW(), NOW()),
(UUID(), 'katakana', 'ゴ', 'go', '濁音', 110, NOW(), NOW());

-- Row 2: ざ じ ず ぜ ぞ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ざ', 'za', '濁音', 111, NOW(), NOW()),
(UUID(), 'hiragana', 'じ', 'ji', '濁音', 112, NOW(), NOW()),
(UUID(), 'hiragana', 'ず', 'zu', '濁音', 113, NOW(), NOW()),
(UUID(), 'hiragana', 'ぜ', 'ze', '濁音', 114, NOW(), NOW()),
(UUID(), 'hiragana', 'ぞ', 'zo', '濁音', 115, NOW(), NOW()),
(UUID(), 'katakana', 'ザ', 'za', '濁音', 116, NOW(), NOW()),
(UUID(), 'katakana', 'ジ', 'ji', '濁音', 117, NOW(), NOW()),
(UUID(), 'katakana', 'ズ', 'zu', '濁音', 118, NOW(), NOW()),
(UUID(), 'katakana', 'ゼ', 'ze', '濁音', 119, NOW(), NOW()),
(UUID(), 'katakana', 'ゾ', 'zo', '濁音', 120, NOW(), NOW());

-- Row 3: だ ぢ づ で ど
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'だ', 'da', '濁音', 121, NOW(), NOW()),
(UUID(), 'hiragana', 'ぢ', 'ji', '濁音', 122, NOW(), NOW()),
(UUID(), 'hiragana', 'づ', 'zu', '濁音', 123, NOW(), NOW()),
(UUID(), 'hiragana', 'で', 'de', '濁音', 124, NOW(), NOW()),
(UUID(), 'hiragana', 'ど', 'do', '濁音', 125, NOW(), NOW()),
(UUID(), 'katakana', 'ダ', 'da', '濁音', 126, NOW(), NOW()),
(UUID(), 'katakana', 'ヂ', 'ji', '濁音', 127, NOW(), NOW()),
(UUID(), 'katakana', 'ヅ', 'zu', '濁音', 128, NOW(), NOW()),
(UUID(), 'katakana', 'デ', 'de', '濁音', 129, NOW(), NOW()),
(UUID(), 'katakana', 'ド', 'do', '濁音', 130, NOW(), NOW());

-- Row 4: ば び ぶ べ ぼ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ば', 'ba', '濁音', 131, NOW(), NOW()),
(UUID(), 'hiragana', 'び', 'bi', '濁音', 132, NOW(), NOW()),
(UUID(), 'hiragana', 'ぶ', 'bu', '濁音', 133, NOW(), NOW()),
(UUID(), 'hiragana', 'べ', 'be', '濁音', 134, NOW(), NOW()),
(UUID(), 'hiragana', 'ぼ', 'bo', '濁音', 135, NOW(), NOW()),
(UUID(), 'katakana', 'バ', 'ba', '濁音', 136, NOW(), NOW()),
(UUID(), 'katakana', 'ビ', 'bi', '濁音', 137, NOW(), NOW()),
(UUID(), 'katakana', 'ブ', 'bu', '濁音', 138, NOW(), NOW()),
(UUID(), 'katakana', 'ベ', 'be', '濁音', 139, NOW(), NOW()),
(UUID(), 'katakana', 'ボ', 'bo', '濁音', 140, NOW(), NOW());

-- ─── 半濁音 (Handakuten) ──────────────────────────────────────────────
-- Row 1: ぱ ぴ ぷ ぺ ぽ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ぱ', 'pa', '半濁音', 151, NOW(), NOW()),
(UUID(), 'hiragana', 'ぴ', 'pi', '半濁音', 152, NOW(), NOW()),
(UUID(), 'hiragana', 'ぷ', 'pu', '半濁音', 153, NOW(), NOW()),
(UUID(), 'hiragana', 'ぺ', 'pe', '半濁音', 154, NOW(), NOW()),
(UUID(), 'hiragana', 'ぽ', 'po', '半濁音', 155, NOW(), NOW()),
(UUID(), 'katakana', 'パ', 'pa', '半濁音', 156, NOW(), NOW()),
(UUID(), 'katakana', 'ピ', 'pi', '半濁音', 157, NOW(), NOW()),
(UUID(), 'katakana', 'プ', 'pu', '半濁音', 158, NOW(), NOW()),
(UUID(), 'katakana', 'ペ', 'pe', '半濁音', 159, NOW(), NOW()),
(UUID(), 'katakana', 'ポ', 'po', '半濁音', 160, NOW(), NOW());

-- ─── 拗音 (Youon) ────────────────────────────────────────────────
-- Row 1: きゃ きゅ きょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'きゃ', 'kya', '拗音', 201, NOW(), NOW()),
(UUID(), 'hiragana', 'きゅ', 'kyu', '拗音', 202, NOW(), NOW()),
(UUID(), 'hiragana', 'きょ', 'kyo', '拗音', 203, NOW(), NOW()),
(UUID(), 'katakana', 'キャ', 'kya', '拗音', 204, NOW(), NOW()),
(UUID(), 'katakana', 'キュ', 'kyu', '拗音', 205, NOW(), NOW()),
(UUID(), 'katakana', 'キョ', 'kyo', '拗音', 206, NOW(), NOW());

-- Row 2: しゃ しゅ しょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'しゃ', 'sha', '拗音', 207, NOW(), NOW()),
(UUID(), 'hiragana', 'しゅ', 'shu', '拗音', 208, NOW(), NOW()),
(UUID(), 'hiragana', 'しょ', 'sho', '拗音', 209, NOW(), NOW()),
(UUID(), 'katakana', 'シャ', 'sha', '拗音', 210, NOW(), NOW()),
(UUID(), 'katakana', 'シュ', 'shu', '拗音', 211, NOW(), NOW()),
(UUID(), 'katakana', 'ショ', 'sho', '拗音', 212, NOW(), NOW());

-- Row 3: ちゃ ちゅ ちょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ちゃ', 'cha', '拗音', 213, NOW(), NOW()),
(UUID(), 'hiragana', 'ちゅ', 'chu', '拗音', 214, NOW(), NOW()),
(UUID(), 'hiragana', 'ちょ', 'cho', '拗音', 215, NOW(), NOW()),
(UUID(), 'katakana', 'チャ', 'cha', '拗音', 216, NOW(), NOW()),
(UUID(), 'katakana', 'チュ', 'chu', '拗音', 217, NOW(), NOW()),
(UUID(), 'katakana', 'チョ', 'cho', '拗音', 218, NOW(), NOW());

-- Row 4: にゃ にゅ にょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'にゃ', 'nya', '拗音', 219, NOW(), NOW()),
(UUID(), 'hiragana', 'にゅ', 'nyu', '拗音', 220, NOW(), NOW()),
(UUID(), 'hiragana', 'にょ', 'nyo', '拗音', 221, NOW(), NOW()),
(UUID(), 'katakana', 'ニャ', 'nya', '拗音', 222, NOW(), NOW()),
(UUID(), 'katakana', 'ニュ', 'nyu', '拗音', 223, NOW(), NOW()),
(UUID(), 'katakana', 'ニョ', 'nyo', '拗音', 224, NOW(), NOW());

-- Row 5: ひゃ ひゅ ひょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ひゃ', 'hya', '拗音', 225, NOW(), NOW()),
(UUID(), 'hiragana', 'ひゅ', 'hyu', '拗音', 226, NOW(), NOW()),
(UUID(), 'hiragana', 'ひょ', 'hyo', '拗音', 227, NOW(), NOW()),
(UUID(), 'katakana', 'ヒャ', 'hya', '拗音', 228, NOW(), NOW()),
(UUID(), 'katakana', 'ヒュ', 'hyu', '拗音', 229, NOW(), NOW()),
(UUID(), 'katakana', 'ヒョ', 'hyo', '拗音', 230, NOW(), NOW());

-- Row 6: みゃ みゅ みょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'みゃ', 'mya', '拗音', 231, NOW(), NOW()),
(UUID(), 'hiragana', 'みゅ', 'myu', '拗音', 232, NOW(), NOW()),
(UUID(), 'hiragana', 'みょ', 'myo', '拗音', 233, NOW(), NOW()),
(UUID(), 'katakana', 'ミャ', 'mya', '拗音', 234, NOW(), NOW()),
(UUID(), 'katakana', 'ミュ', 'myu', '拗音', 235, NOW(), NOW()),
(UUID(), 'katakana', 'ミョ', 'myo', '拗音', 236, NOW(), NOW());

-- Row 7: りゃ りゅ りょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'りゃ', 'rya', '拗音', 237, NOW(), NOW()),
(UUID(), 'hiragana', 'りゅ', 'ryu', '拗音', 238, NOW(), NOW()),
(UUID(), 'hiragana', 'りょ', 'ryo', '拗音', 239, NOW(), NOW()),
(UUID(), 'katakana', 'リャ', 'rya', '拗音', 240, NOW(), NOW()),
(UUID(), 'katakana', 'リュ', 'ryu', '拗音', 241, NOW(), NOW()),
(UUID(), 'katakana', 'リョ', 'ryo', '拗音', 242, NOW(), NOW());

-- Row 8: ぎゃ ぎゅ ぎょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ぎゃ', 'gya', '拗音', 243, NOW(), NOW()),
(UUID(), 'hiragana', 'ぎゅ', 'gyu', '拗音', 244, NOW(), NOW()),
(UUID(), 'hiragana', 'ぎょ', 'gyo', '拗音', 245, NOW(), NOW()),
(UUID(), 'katakana', 'ギャ', 'gya', '拗音', 246, NOW(), NOW()),
(UUID(), 'katakana', 'ギュ', 'gyu', '拗音', 247, NOW(), NOW()),
(UUID(), 'katakana', 'ギョ', 'gyo', '拗音', 248, NOW(), NOW());

-- Row 9: じゃ じゅ じょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'じゃ', 'ja', '拗音', 249, NOW(), NOW()),
(UUID(), 'hiragana', 'じゅ', 'ju', '拗音', 250, NOW(), NOW()),
(UUID(), 'hiragana', 'じょ', 'jo', '拗音', 251, NOW(), NOW()),
(UUID(), 'katakana', 'ジャ', 'ja', '拗音', 252, NOW(), NOW()),
(UUID(), 'katakana', 'ジュ', 'ju', '拗音', 253, NOW(), NOW()),
(UUID(), 'katakana', 'ジョ', 'jo', '拗音', 254, NOW(), NOW());

-- Row 10: びゃ びゅ びょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'びゃ', 'bya', '拗音', 255, NOW(), NOW()),
(UUID(), 'hiragana', 'びゅ', 'byu', '拗音', 256, NOW(), NOW()),
(UUID(), 'hiragana', 'びょ', 'byo', '拗音', 257, NOW(), NOW()),
(UUID(), 'katakana', 'ビャ', 'bya', '拗音', 258, NOW(), NOW()),
(UUID(), 'katakana', 'ビュ', 'byu', '拗音', 259, NOW(), NOW()),
(UUID(), 'katakana', 'ビョ', 'byo', '拗音', 260, NOW(), NOW());

-- Row 11: ぴゃ ぴゅ ぴょ
INSERT INTO kana (id, type, `character`, romanization, category, order_index, created_at, updated_at) VALUES
(UUID(), 'hiragana', 'ぴゃ', 'pya', '拗音', 261, NOW(), NOW()),
(UUID(), 'hiragana', 'ぴゅ', 'pyu', '拗音', 262, NOW(), NOW()),
(UUID(), 'hiragana', 'ぴょ', 'pyo', '拗音', 263, NOW(), NOW()),
(UUID(), 'katakana', 'ピャ', 'pya', '拗音', 264, NOW(), NOW()),
(UUID(), 'katakana', 'ピュ', 'pyu', '拗音', 265, NOW(), NOW()),
(UUID(), 'katakana', 'ピョ', 'pyo', '拗音', 266, NOW(), NOW());

-- Verify the data
SELECT COUNT(*) as total_count, 
       SUM(CASE WHEN type='hiragana' THEN 1 ELSE 0 END) as hiragana_count,
       SUM(CASE WHEN type='katakana' THEN 1 ELSE 0 END) as katakana_count,
       COUNT(DISTINCT category) as category_count
FROM kana;
