#!/bin/bash

mysql -u root -p6586156 japanese_learn << 'SQLEOF'
DROP TABLE IF EXISTS kana;

CREATE TABLE IF NOT EXISTS kana (
  id CHAR(36) PRIMARY KEY,
  type ENUM('hiragana','katakana') NOT NULL,
  character VARCHAR(10) NOT NULL,
  romanization VARCHAR(20) NOT NULL,
  category VARCHAR(20) NOT NULL DEFAULT '五十音',
  audio_url VARCHAR(500) NULL,
  order_index INT NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY uk_kana_type_char (type, character),
  KEY idx_kana_category (category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO kana (id, type, character, romanization, category, order_index) VALUES 
(UUID(), 'hiragana', 'あ', 'a', '五十音', 0), (UUID(), 'hiragana', 'い', 'i', '五十音', 1), (UUID(), 'hiragana', 'う', 'u', '五十音', 2), (UUID(), 'hiragana', 'え', 'e', '五十音', 3), (UUID(), 'hiragana', 'お', 'o', '五十音', 4),
(UUID(), 'hiragana', 'か', 'ka', '五十音', 5), (UUID(), 'hiragana', 'き', 'ki', '五十音', 6), (UUID(), 'hiragana', 'く', 'ku', '五十音', 7), (UUID(), 'hiragana', 'け', 'ke', '五十音', 8), (UUID(), 'hiragana', 'こ', 'ko', '五十音', 9),
(UUID(), 'hiragana', 'が', 'ga', '濁音', 10), (UUID(), 'hiragana', 'ぎ', 'gi', '濁音', 11), (UUID(), 'hiragana', 'ぐ', 'gu', '濁音', 12), (UUID(), 'hiragana', 'げ', 'ge', '濁音', 13), (UUID(), 'hiragana', 'ご', 'go', '濁音', 14),
(UUID(), 'hiragana', 'さ', 'sa', '五十音', 15), (UUID(), 'hiragana', 'し', 'shi', '五十音', 16), (UUID(), 'hiragana', 'す', 'su', '五十音', 17), (UUID(), 'hiragana', 'せ', 'se', '五十音', 18), (UUID(), 'hiragana', 'そ', 'so', '五十音', 19),
(UUID(), 'hiragana', 'ざ', 'za', '濁音', 20), (UUID(), 'hiragana', 'じ', 'ji', '濁音', 21), (UUID(), 'hiragana', 'ず', 'zu', '濁音', 22), (UUID(), 'hiragana', 'ぜ', 'ze', '濁音', 23), (UUID(), 'hiragana', 'ぞ', 'zo', '濁音', 24),
(UUID(), 'hiragana', 'た', 'ta', '五十音', 25), (UUID(), 'hiragana', 'ち', 'chi', '五十音', 26), (UUID(), 'hiragana', 'つ', 'tsu', '五十音', 27), (UUID(), 'hiragana', 'て', 'te', '五十音', 28), (UUID(), 'hiragana', 'と', 'to', '五十音', 29),
(UUID(), 'hiragana', 'だ', 'da', '濁音', 30), (UUID(), 'hiragana', 'ぢ', 'di', '濁音', 31), (UUID(), 'hiragana', 'づ', 'du', '濁音', 32), (UUID(), 'hiragana', 'で', 'de', '濁音', 33), (UUID(), 'hiragana', 'ど', 'do', '濁音', 34),
(UUID(), 'hiragana', 'な', 'na', '五十音', 35), (UUID(), 'hiragana', 'に', 'ni', '五十音', 36), (UUID(), 'hiragana', 'ぬ', 'nu', '五十音', 37), (UUID(), 'hiragana', 'ね', 'ne', '五十音', 38), (UUID(), 'hiragana', 'の', 'no', '五十音', 39),
(UUID(), 'hiragana', 'は', 'ha', '五十音', 40), (UUID(), 'hiragana', 'ひ', 'hi', '五十音', 41), (UUID(), 'hiragana', 'ふ', 'fu', '五十音', 42), (UUID(), 'hiragana', 'へ', 'he', '五十音', 43), (UUID(), 'hiragana', 'ほ', 'ho', '五十音', 44),
(UUID(), 'hiragana', 'ば', 'ba', '濁音', 45), (UUID(), 'hiragana', 'び', 'bi', '濁音', 46), (UUID(), 'hiragana', 'ぶ', 'bu', '濁音', 47), (UUID(), 'hiragana', 'べ', 'be', '濁音', 48), (UUID(), 'hiragana', 'ぼ', 'bo', '濁音', 49),
(UUID(), 'hiragana', 'ぱ', 'pa', '半濁音', 50), (UUID(), 'hiragana', 'ぴ', 'pi', '半濁音', 51), (UUID(), 'hiragana', 'ぷ', 'pu', '半濁音', 52), (UUID(), 'hiragana', 'ぺ', 'pe', '半濁音', 53), (UUID(), 'hiragana', 'ぽ', 'po', '半濁音', 54),
(UUID(), 'hiragana', 'ま', 'ma', '五十音', 55), (UUID(), 'hiragana', 'み', 'mi', '五十音', 56), (UUID(), 'hiragana', 'む', 'mu', '五十音', 57), (UUID(), 'hiragana', 'め', 'me', '五十音', 58), (UUID(), 'hiragana', 'も', 'mo', '五十音', 59),
(UUID(), 'hiragana', 'や', 'ya', '五十音', 60), (UUID(), 'hiragana', 'ゆ', 'yu', '五十音', 61), (UUID(), 'hiragana', 'よ', 'yo', '五十音', 62),
(UUID(), 'hiragana', 'ら', 'ra', '五十音', 65), (UUID(), 'hiragana', 'り', 'ri', '五十音', 66), (UUID(), 'hiragana', 'る', 'ru', '五十音', 67), (UUID(), 'hiragana', 'れ', 're', '五十音', 68), (UUID(), 'hiragana', 'ろ', 'ro', '五十音', 69),
(UUID(), 'hiragana', 'わ', 'wa', '五十音', 70), (UUID(), 'hiragana', 'を', 'wo', '五十音', 71), (UUID(), 'hiragana', 'ん', 'n', '五十音', 72),
(UUID(), 'hiragana', 'きゃ', 'kya', '拗音', 73), (UUID(), 'hiragana', 'きゅ', 'kyu', '拗音', 74), (UUID(), 'hiragana', 'きょ', 'kyo', '拗音', 75),
(UUID(), 'hiragana', 'しゃ', 'sha', '拗音', 76), (UUID(), 'hiragana', 'しゅ', 'shu', '拗音', 77), (UUID(), 'hiragana', 'しょ', 'sho', '拗音', 78),
(UUID(), 'hiragana', 'ちゃ', 'cha', '拗音', 79), (UUID(), 'hiragana', 'ちゅ', 'chu', '拗音', 80), (UUID(), 'hiragana', 'ちょ', 'cho', '拗音', 81),
(UUID(), 'hiragana', 'にゃ', 'nya', '拗音', 82), (UUID(), 'hiragana', 'にゅ', 'nyu', '拗音', 83), (UUID(), 'hiragana', 'にょ', 'nyo', '拗音', 84),
(UUID(), 'hiragana', 'ひゃ', 'hya', '拗音', 85), (UUID(), 'hiragana', 'ひゅ', 'hyu', '拗音', 86), (UUID(), 'hiragana', 'ひょ', 'hyo', '拗音', 87),
(UUID(), 'hiragana', 'みゃ', 'mya', '拗音', 88), (UUID(), 'hiragana', 'みゅ', 'myu', '拗音', 89), (UUID(), 'hiragana', 'みょ', 'myo', '拗音', 90),
(UUID(), 'hiragana', 'りゃ', 'rya', '拗音', 91), (UUID(), 'hiragana', 'りゅ', 'ryu', '拗音', 92), (UUID(), 'hiragana', 'りょ', 'ryo', '拗音', 93),
(UUID(), 'hiragana', 'ぎゃ', 'gya', '拗音', 94), (UUID(), 'hiragana', 'ぎゅ', 'gyu', '拗音', 95), (UUID(), 'hiragana', 'ぎょ', 'gyo', '拗音', 96),
(UUID(), 'hiragana', 'じゃ', 'ja', '拗音', 97), (UUID(), 'hiragana', 'じゅ', 'ju', '拗音', 98), (UUID(), 'hiragana', 'じょ', 'jo', '拗音', 99),
(UUID(), 'hiragana', 'びゃ', 'bya', '拗音', 100), (UUID(), 'hiragana', 'びゅ', 'byu', '拗音', 101), (UUID(), 'hiragana', 'びょ', 'byo', '拗音', 102),
(UUID(), 'hiragana', 'ぴゃ', 'pya', '拗音', 103), (UUID(), 'hiragana', 'ぴゅ', 'pyu', '拗音', 104), (UUID(), 'hiragana', 'ぴょ', 'pyo', '拗音', 105);

INSERT INTO kana (id, type, character, romanization, category, order_index) VALUES 
(UUID(), 'katakana', 'ア', 'a', '五十音', 0), (UUID(), 'katakana', 'イ', 'i', '五十音', 1), (UUID(), 'katakana', 'ウ', 'u', '五十音', 2), (UUID(), 'katakana', 'エ', 'e', '五十音', 3), (UUID(), 'katakana', 'オ', 'o', '五十音', 4),
(UUID(), 'katakana', 'カ', 'ka', '五十音', 5), (UUID(), 'katakana', 'キ', 'ki', '五十音', 6), (UUID(), 'katakana', 'ク', 'ku', '五十音', 7), (UUID(), 'katakana', 'ケ', 'ke', '五十音', 8), (UUID(), 'katakana', 'コ', 'ko', '五十音', 9),
(UUID(), 'katakana', 'ガ', 'ga', '濁音', 10), (UUID(), 'katakana', 'ギ', 'gi', '濁音', 11), (UUID(), 'katakana', 'グ', 'gu', '濁音', 12), (UUID(), 'katakana', 'ゲ', 'ge', '濁音', 13), (UUID(), 'katakana', 'ゴ', 'go', '濁音', 14),
(UUID(), 'katakana', 'サ', 'sa', '五十音', 15), (UUID(), 'katakana', 'シ', 'shi', '五十音', 16), (UUID(), 'katakana', 'ス', 'su', '五十音', 17), (UUID(), 'katakana', 'セ', 'se', '五十音', 18), (UUID(), 'katakana', 'ソ', 'so', '五十音', 19),
(UUID(), 'katakana', 'ザ', 'za', '濁音', 20), (UUID(), 'katakana', 'ジ', 'ji', '濁音', 21), (UUID(), 'katakana', 'ズ', 'zu', '濁音', 22), (UUID(), 'katakana', 'ゼ', 'ze', '濁音', 23), (UUID(), 'katakana', 'ゾ', 'zo', '濁音', 24),
(UUID(), 'katakana', 'タ', 'ta', '五十音', 25), (UUID(), 'katakana', 'チ', 'chi', '五十音', 26), (UUID(), 'katakana', 'ツ', 'tsu', '五十音', 27), (UUID(), 'katakana', 'テ', 'te', '五十音', 28), (UUID(), 'katakana', 'ト', 'to', '五十音', 29),
(UUID(), 'katakana', 'ダ', 'da', '濁音', 30), (UUID(), 'katakana', 'ヂ', 'di', '濁音', 31), (UUID(), 'katakana', 'ヅ', 'du', '濁音', 32), (UUID(), 'katakana', 'デ', 'de', '濁音', 33), (UUID(), 'katakana', 'ド', 'do', '濁音', 34),
(UUID(), 'katakana', 'ナ', 'na', '五十音', 35), (UUID(), 'katakana', 'ニ', 'ni', '五十音', 36), (UUID(), 'katakana', 'ヌ', 'nu', '五十音', 37), (UUID(), 'katakana', 'ネ', 'ne', '五十音', 38), (UUID(), 'katakana', 'ノ', 'no', '五十音', 39),
(UUID(), 'katakana', 'ハ', 'ha', '五十音', 40), (UUID(), 'katakana', 'ヒ', 'hi', '五十音', 41), (UUID(), 'katakana', 'フ', 'fu', '五十音', 42), (UUID(), 'katakana', 'ヘ', 'he', '五十音', 43), (UUID(), 'katakana', 'ホ', 'ho', '五十音', 44),
(UUID(), 'katakana', 'バ', 'ba', '濁音', 45), (UUID(), 'katakana', 'ビ', 'bi', '濁音', 46), (UUID(), 'katakana', 'ブ', 'bu', '濁音', 47), (UUID(), 'katakana', 'ベ', 'be', '濁音', 48), (UUID(), 'katakana', 'ボ', 'bo', '濁音', 49),
(UUID(), 'katakana', 'パ', 'pa', '半濁音', 50), (UUID(), 'katakana', 'ピ', 'pi', '半濁音', 51), (UUID(), 'katakana', 'プ', 'pu', '半濁音', 52), (UUID(), 'katakana', 'ペ', 'pe', '半濁音', 53), (UUID(), 'katakana', 'ポ', 'po', '半濁音', 54),
(UUID(), 'katakana', 'マ', 'ma', '五十音', 55), (UUID(), 'katakana', 'ミ', 'mi', '五十音', 56), (UUID(), 'katakana', 'ム', 'mu', '五十音', 57), (UUID(), 'katakana', 'メ', 'me', '五十音', 58), (UUID(), 'katakana', 'モ', 'mo', '五十音', 59),
(UUID(), 'katakana', 'ヤ', 'ya', '五十音', 60), (UUID(), 'katakana', 'ユ', 'yu', '五十音', 61), (UUID(), 'katakana', 'ヨ', 'yo', '五十音', 62),
(UUID(), 'katakana', 'ラ', 'ra', '五十音', 65), (UUID(), 'katakana', 'リ', 'ri', '五十音', 66), (UUID(), 'katakana', 'ル', 'ru', '五十音', 67), (UUID(), 'katakana', 'レ', 're', '五十音', 68), (UUID(), 'katakana', 'ロ', 'ro', '五十音', 69),
(UUID(), 'katakana', 'ワ', 'wa', '五十音', 70), (UUID(), 'katakana', 'ヲ', 'wo', '五十音', 71), (UUID(), 'katakana', 'ン', 'n', '五十音', 72),
(UUID(), 'katakana', 'キャ', 'kya', '拗音', 73), (UUID(), 'katakana', 'キュ', 'kyu', '拗音', 74), (UUID(), 'katakana', 'キョ', 'kyo', '拗音', 75),
(UUID(), 'katakana', 'シャ', 'sha', '拗音', 76), (UUID(), 'katakana', 'シュ', 'shu', '拗音', 77), (UUID(), 'katakana', 'ショ', 'sho', '拗音', 78),
(UUID(), 'katakana', 'チャ', 'cha', '拗音', 79), (UUID(), 'katakana', 'チュ', 'chu', '拗音', 80), (UUID(), 'katakana', 'チョ', 'cho', '拗音', 81),
(UUID(), 'katakana', 'ニャ', 'nya', '拗音', 82), (UUID(), 'katakana', 'ニュ', 'nyu', '拗音', 83), (UUID(), 'katakana', 'ニョ', 'nyo', '拗音', 84),
(UUID(), 'katakana', 'ヒャ', 'hya', '拗音', 85), (UUID(), 'katakana', 'ヒュ', 'hyu', '拗音', 86), (UUID(), 'katakana', 'ヒョ', 'hyo', '拗音', 87),
(UUID(), 'katakana', 'ミャ', 'mya', '拗音', 88), (UUID(), 'katakana', 'ミュ', 'myu', '拗音', 89), (UUID(), 'katakana', 'ミョ', 'myo', '拗音', 90),
(UUID(), 'katakana', 'リャ', 'rya', '拗音', 91), (UUID(), 'katakana', 'リュ', 'ryu', '拗音', 92), (UUID(), 'katakana', 'リョ', 'ryo', '拗音', 93),
(UUID(), 'katakana', 'ギャ', 'gya', '拗音', 94), (UUID(), 'katakana', 'ギュ', 'gyu', '拗音', 95), (UUID(), 'katakana', 'ギョ', 'gyo', '拗音', 96),
(UUID(), 'katakana', 'ジャ', 'ja', '拗音', 97), (UUID(), 'katakana', 'ジュ', 'ju', '拗音', 98), (UUID(), 'katakana', 'ジョ', 'jo', '拗音', 99),
(UUID(), 'katakana', 'ビャ', 'bya', '拗音', 100), (UUID(), 'katakana', 'ビュ', 'byu', '拗音', 101), (UUID(), 'katakana', 'ビョ', 'byo', '拗音', 102),
(UUID(), 'katakana', 'ピャ', 'pya', '拗音', 103), (UUID(), 'katakana', 'ピュ', 'pyu', '拗音', 104), (UUID(), 'katakana', 'ピョ', 'pyo', '拗音', 105);

SELECT COUNT(*) as total_records, 
       SUM(CASE WHEN category='五十音' THEN 1 ELSE 0 END) as fifty_on,
       SUM(CASE WHEN category='濁音' THEN 1 ELSE 0 END) as voiced,
       SUM(CASE WHEN category='半濁音' THEN 1 ELSE 0 END) as semi_voiced,
       SUM(CASE WHEN category='拗音' THEN 1 ELSE 0 END) as youon
FROM kana;
SQLEOF
