-- ============================================================================
-- 五十音初始化数据（对应客户端 kana_data.dart）
-- 时间: 2026-04-05
-- 说明: 此脚本初始化所有五十音相关的基础数据
-- ============================================================================

USE japanese_learn;

-- ============================================================================
-- 第1部分：初始化分类（kana_categories）
-- ============================================================================

INSERT INTO kana_categories (id, name, name_en, description, order_index, is_active)
VALUES
(1, '平假名', 'Hiragana', 'ひらがな - 日语基本音节字母，用于词汇、助词、动词变位等', 1, 1),
(2, '片假名', 'Katakana', 'かたかな - 片假名，用于外来词、拟音拟态词和特殊用语', 2, 1),
(3, '浊音', 'Dakuten', 'だくおん - 清音加浊点变清音为浊音，包含 が行、ざ行、だ行、ば行', 3, 1),
(4, '半浊音', 'Handakuten', 'はんだくおん - 清音加半浊点，只有は行变为ぱ行', 4, 1),
(5, '拗音', 'Yoon', 'ようおん - 小号的や行、ゆ行、よ行与其他音的组合，可产生新的发音', 5, 1);

-- ============================================================================
-- 第2部分：初始化清音字符（category_id = 1）
-- ============================================================================

-- あ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'あ', 'ア', 'a', 0, 3),
(UUID(), 1, 'い', 'イ', 'i', 1, 2),
(UUID(), 1, 'う', 'ウ', 'u', 2, 2),
(UUID(), 1, 'え', 'エ', 'e', 3, 2),
(UUID(), 1, 'お', 'オ', 'o', 4, 4);

-- か行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'か', 'カ', 'ka', 5, 2),
(UUID(), 1, 'き', 'キ', 'ki', 6, 3),
(UUID(), 1, 'く', 'ク', 'ku', 7, 2),
(UUID(), 1, 'け', 'ケ', 'ke', 8, 3),
(UUID(), 1, 'こ', 'コ', 'ko', 9, 3);

-- さ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'さ', 'サ', 'sa', 10, 3),
(UUID(), 1, 'し', 'シ', 'shi', 11, 1),
(UUID(), 1, 'す', 'ス', 'su', 12, 3),
(UUID(), 1, 'せ', 'セ', 'se', 13, 3),
(UUID(), 1, 'そ', 'ソ', 'so', 14, 2);

-- た行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'た', 'タ', 'ta', 15, 2),
(UUID(), 1, 'ち', 'チ', 'chi', 16, 3),
(UUID(), 1, 'つ', 'ツ', 'tsu', 17, 2),
(UUID(), 1, 'て', 'テ', 'te', 18, 3),
(UUID(), 1, 'と', 'ト', 'to', 19, 2);

-- な行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'な', 'ナ', 'na', 20, 2),
(UUID(), 1, 'に', 'ニ', 'ni', 21, 2),
(UUID(), 1, 'ぬ', 'ヌ', 'nu', 22, 2),
(UUID(), 1, 'ね', 'ネ', 'ne', 23, 2),
(UUID(), 1, 'の', 'ノ', 'no', 24, 1);

-- は行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'は', 'ハ', 'ha', 25, 3),
(UUID(), 1, 'ひ', 'ヒ', 'hi', 26, 2),
(UUID(), 1, 'ふ', 'フ', 'fu', 27, 3),
(UUID(), 1, 'へ', 'ヘ', 'he', 28, 1),
(UUID(), 1, 'ほ', 'ホ', 'ho', 29, 4);

-- ま行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'ま', 'マ', 'ma', 30, 2),
(UUID(), 1, 'み', 'ミ', 'mi', 31, 3),
(UUID(), 1, 'む', 'ム', 'mu', 32, 2),
(UUID(), 1, 'め', 'メ', 'me', 33, 2),
(UUID(), 1, 'も', 'モ', 'mo', 34, 3);

-- や行（注：い段和え段不存在单独字符，只与其他音组合）
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'や', 'ヤ', 'ya', 35, 2),
(UUID(), 1, 'ゆ', 'ユ', 'yu', 36, 2),
(UUID(), 1, 'よ', 'ヨ', 'yo', 37, 2);

-- ら行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'ら', 'ラ', 'ra', 38, 2),
(UUID(), 1, 'り', 'リ', 'ri', 39, 2),
(UUID(), 1, 'る', 'ル', 'ru', 40, 2),
(UUID(), 1, 'れ', 'レ', 're', 41, 2),
(UUID(), 1, 'ろ', 'ロ', 'ro', 42, 2);

-- わ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 1, 'わ', 'ワ', 'wa', 43, 2),
(UUID(), 1, 'を', 'ヲ', 'wo', 44, 3),
(UUID(), 1, 'ん', 'ン', 'n', 45, 1);

-- ============================================================================
-- 第3部分：初始化浊音字符（category_id = 3）
-- ============================================================================

-- が行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 3, 'が', 'ガ', 'ga', 0, 3),
(UUID(), 3, 'ぎ', 'ギ', 'gi', 1, 4),
(UUID(), 3, 'ぐ', 'グ', 'gu', 2, 3),
(UUID(), 3, 'げ', 'ゲ', 'ge', 3, 4),
(UUID(), 3, 'ご', 'ゴ', 'go', 4, 4);

-- ざ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 3, 'ざ', 'ザ', 'za', 5, 4),
(UUID(), 3, 'じ', 'ジ', 'ji', 6, 2),
(UUID(), 3, 'ず', 'ズ', 'zu', 7, 4),
(UUID(), 3, 'ぜ', 'ゼ', 'ze', 8, 4),
(UUID(), 3, 'ぞ', 'ゾ', 'zo', 9, 3);

-- だ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 3, 'だ', 'ダ', 'da', 10, 3),
(UUID(), 3, 'ぢ', 'ヂ', 'ji', 11, 3),
(UUID(), 3, 'づ', 'ヅ', 'zu', 12, 3),
(UUID(), 3, 'で', 'デ', 'de', 13, 4),
(UUID(), 3, 'ど', 'ド', 'do', 14, 3);

-- ば行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 3, 'ば', 'バ', 'ba', 15, 4),
(UUID(), 3, 'び', 'ビ', 'bi', 16, 3),
(UUID(), 3, 'ぶ', 'ブ', 'bu', 17, 3),
(UUID(), 3, 'べ', 'ベ', 'be', 18, 3),
(UUID(), 3, 'ぼ', 'ボ', 'bo', 19, 4);

-- ============================================================================
-- 第4部分：初始化半浊音字符（category_id = 4）
-- ============================================================================

-- ぱ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 4, 'ぱ', 'パ', 'pa', 0, 4),
(UUID(), 4, 'ぴ', 'ピ', 'pi', 1, 3),
(UUID(), 4, 'ぷ', 'プ', 'pu', 2, 3),
(UUID(), 4, 'ぺ', 'ペ', 'pe', 3, 3),
(UUID(), 4, 'ぽ', 'ポ', 'po', 4, 4);

-- ============================================================================
-- 第5部分：初始化拗音字符（category_id = 5）
-- ============================================================================

-- きゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'きゃ', 'キャ', 'kya', 0, 5),
(UUID(), 5, 'きゅ', 'キュ', 'kyu', 1, 5),
(UUID(), 5, 'きょ', 'キョ', 'kyo', 2, 5);

-- しゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'しゃ', 'シャ', 'sha', 3, 4),
(UUID(), 5, 'しゅ', 'シュ', 'shu', 4, 4),
(UUID(), 5, 'しょ', 'ショ', 'sho', 5, 4);

-- ちゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'ちゃ', 'チャ', 'cha', 6, 4),
(UUID(), 5, 'ちゅ', 'チュ', 'chu', 7, 4),
(UUID(), 5, 'ちょ', 'チョ', 'cho', 8, 4);

-- にゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'にゃ', 'ニャ', 'nya', 9, 4),
(UUID(), 5, 'にゅ', 'ニュ', 'nyu', 10, 4),
(UUID(), 5, 'にょ', 'ニョ', 'nyo', 11, 4);

-- ひゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'ひゃ', 'ヒャ', 'hya', 12, 5),
(UUID(), 5, 'ひゅ', 'ヒュ', 'hyu', 13, 5),
(UUID(), 5, 'ひょ', 'ヒョ', 'hyo', 14, 5);

-- みゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'みゃ', 'ミャ', 'mya', 15, 4),
(UUID(), 5, 'みゅ', 'ミュ', 'myu', 16, 4),
(UUID(), 5, 'みょ', 'ミョ', 'myo', 17, 4);

-- りゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'りゃ', 'リャ', 'rya', 18, 4),
(UUID(), 5, 'りゅ', 'リュ', 'ryu', 19, 4),
(UUID(), 5, 'りょ', 'リョ', 'ryo', 20, 4);

-- ぎゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'ぎゃ', 'ギャ', 'gya', 21, 5),
(UUID(), 5, 'ぎゅ', 'ギュ', 'gyu', 22, 5),
(UUID(), 5, 'ぎょ', 'ギョ', 'gyo', 23, 5);

-- じゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'じゃ', 'ジャ', 'ja', 24, 3),
(UUID(), 5, 'じゅ', 'ジュ', 'ju', 25, 3),
(UUID(), 5, 'じょ', 'ジョ', 'jo', 26, 3);

-- びゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'びゃ', 'ビャ', 'bya', 27, 5),
(UUID(), 5, 'びゅ', 'ビュ', 'byu', 28, 5),
(UUID(), 5, 'びょ', 'ビョ', 'byo', 29, 5);

-- ぴゃ行
INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count)
VALUES
(UUID(), 5, 'ぴゃ', 'ピャ', 'pya', 30, 5),
(UUID(), 5, 'ぴゅ', 'ピュ', 'pyu', 31, 5),
(UUID(), 5, 'ぴょ', 'ピョ', 'pyo', 32, 5);

-- ============================================================================
-- 验证插入结果
-- ============================================================================

SELECT 
  c.name AS category,
  COUNT(k.id) AS character_count
FROM kana_categories c
LEFT JOIN kana_characters k ON c.id = k.category_id
GROUP BY c.id, c.name
ORDER BY c.order_index;

-- 预期输出：
-- | category | character_count |
-- |----------|-----------------|
-- | 平假名   | 46              |
-- | 片假名   | 0               | (平假名和片假名共卡表，katakana在一条记录上)
-- | 浊音     | 25              |
-- | 半浊音   | 5               |
-- | 拗音     | 33              |

-- 总计：104 条记录

SELECT COUNT(*) AS total_kana_characters FROM kana_characters;
-- 预期：104
