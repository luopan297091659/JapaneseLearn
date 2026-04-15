#!/usr/bin/env python3
import sys
import MySQLdb

sys.stdout.reconfigure(encoding='utf-8')

kana_data = [
    ('hiragana', 'あ', 'a', 'normal', 1),
    ('hiragana', 'い', 'i', 'normal', 2),
    ('hiragana', 'う', 'u', 'normal', 3),
    ('hiragana', 'え', 'e', 'normal', 4),
    ('hiragana', 'お', 'o', 'normal', 5),
    ('hiragana', 'か', 'ka', 'normal', 6),
    ('hiragana', 'き', 'ki', 'normal', 7),
    ('hiragana', 'く', 'ku', 'normal', 8),
    ('hiragana', 'け', 'ke', 'normal', 9),
    ('hiragana', 'こ', 'ko', 'normal', 10),
    ('katakana', 'ア', 'a', 'normal', 11),
    ('katakana', 'イ', 'i', 'normal', 12),
    ('katakana', 'ウ', 'u', 'normal', 13),
    ('katakana', 'エ', 'e', 'normal', 14),
    ('katakana', 'オ', 'o', 'normal', 15),
    ('katakana', 'カ', 'ka', 'normal', 16),
    ('katakana', 'キ', 'ki', 'normal', 17),
    ('katakana', 'ク', 'ku', 'normal', 18),
    ('katakana', 'ケ', 'ke', 'normal', 19),
    ('katakana', 'コ', 'ko', 'normal', 20),
    ('hiragana', 'が', 'ga', 'dakuten', 21),
    ('hiragana', 'ぎ', 'gi', 'dakuten', 22),
    ('hiragana', 'ぐ', 'gu', 'dakuten', 23),
    ('hiragana', 'げ', 'ge', 'dakuten', 24),
    ('hiragana', 'ご', 'go', 'dakuten', 25),
    ('hiragana', 'ざ', 'za', 'dakuten', 26),
    ('hiragana', 'じ', 'ji', 'dakuten', 27),
    ('hiragana', 'ず', 'zu', 'dakuten', 28),
    ('hiragana', 'ぜ', 'ze', 'dakuten', 29),
    ('hiragana', 'ぞ', 'zo', 'dakuten', 30),
    ('katakana', 'ガ', 'ga', 'dakuten', 31),
    ('katakana', 'ギ', 'gi', 'dakuten', 32),
    ('katakana', 'グ', 'gu', 'dakuten', 33),
    ('katakana', 'ゲ', 'ge', 'dakuten', 34),
    ('katakana', 'ゴ', 'go', 'dakuten', 35),
    ('katakana', 'ザ', 'za', 'dakuten', 36),
    ('katakana', 'ジ', 'ji', 'dakuten', 37),
    ('katakana', 'ズ', 'zu', 'dakuten', 38),
    ('katakana', 'ゼ', 'ze', 'dakuten', 39),
    ('katakana', 'ゾ', 'zo', 'dakuten', 40),
    ('hiragana', 'ぱ', 'pa', 'handakuten', 41),
    ('hiragana', 'ぴ', 'pi', 'handakuten', 42),
    ('hiragana', 'ぷ', 'pu', 'handakuten', 43),
    ('hiragana', 'ぺ', 'pe', 'handakuten', 44),
    ('hiragana', 'ぽ', 'po', 'handakuten', 45),
    ('katakana', 'パ', 'pa', 'handakuten', 46),
    ('katakana', 'ピ', 'pi', 'handakuten', 47),
    ('katakana', 'プ', 'pu', 'handakuten', 48),
    ('katakana', 'ペ', 'pe', 'handakuten', 49),
    ('katakana', 'ポ', 'po', 'handakuten', 50),
    ('hiragana', 'きゃ', 'kya', 'youon', 51),
    ('hiragana', 'きゅ', 'kyu', 'youon', 52),
    ('hiragana', 'きょ', 'kyo', 'youon', 53),
    ('hiragana', 'しゃ', 'sha', 'youon', 54),
    ('hiragana', 'しゅ', 'shu', 'youon', 55),
    ('hiragana', 'しょ', 'sho', 'youon', 56),
    ('hiragana', 'ちゃ', 'cha', 'youon', 57),
    ('hiragana', 'ちゅ', 'chu', 'youon', 58),
    ('hiragana', 'ちょ', 'cho', 'youon', 59),
    ('hiragana', 'にゃ', 'nya', 'youon', 60),
    ('hiragana', 'にゅ', 'nyu', 'youon', 61),
    ('hiragana', 'にょ', 'nyo', 'youon', 62),
    ('hiragana', 'ひゃ', 'hya', 'youon', 63),
    ('hiragana', 'ひゅ', 'hyu', 'youon', 64),
    ('hiragana', 'ひょ', 'hyo', 'youon', 65),
    ('hiragana', 'みゃ', 'mya', 'youon', 66),
    ('hiragana', 'みゅ', 'myu', 'youon', 67),
    ('hiragana', 'みょ', 'myo', 'youon', 68),
    ('hiragana', 'りゃ', 'rya', 'youon', 69),
    ('hiragana', 'りゅ', 'ryu', 'youon', 70),
    ('hiragana', 'りょ', 'ryo', 'youon', 71),
    ('hiragana', 'ぎゃ', 'gya', 'youon', 72),
    ('hiragana', 'ぎゅ', 'gyu', 'youon', 73),
    ('hiragana', 'ぎょ', 'gyo', 'youon', 74),
    ('hiragana', 'じゃ', 'ja', 'youon', 75),
    ('hiragana', 'じゅ', 'ju', 'youon', 76),
    ('hiragana', 'じょ', 'jo', 'youon', 77),
    ('hiragana', 'びゃ', 'bya', 'youon', 78),
    ('hiragana', 'びゅ', 'byu', 'youon', 79),
    ('hiragana', 'びょ', 'byo', 'youon', 80),
    ('hiragana', 'ぴゃ', 'pya', 'youon', 81),
    ('hiragana', 'ぴゅ', 'pyu', 'youon', 82),
    ('hiragana', 'ぴょ', 'pyo', 'youon', 83),
    ('katakana', 'キャ', 'kya', 'youon', 84),
    ('katakana', 'キュ', 'kyu', 'youon', 85),
    ('katakana', 'キョ', 'kyo', 'youon', 86),
    ('katakana', 'シャ', 'sha', 'youon', 87),
    ('katakana', 'シュ', 'shu', 'youon', 88),
    ('katakana', 'ショ', 'sho', 'youon', 89),
    ('katakana', 'チャ', 'cha', 'youon', 90),
    ('katakana', 'チュ', 'chu', 'youon', 91),
    ('katakana', 'チョ', 'cho', 'youon', 92),
    ('katakana', 'ニャ', 'nya', 'youon', 93),
    ('katakana', 'ニュ', 'nyu', 'youon', 94),
    ('katakana', 'ニョ', 'nyo', 'youon', 95),
    ('katakana', 'ヒャ', 'hya', 'youon', 96),
    ('katakana', 'ヒュ', 'hyu', 'youon', 97),
    ('katakana', 'ヒョ', 'hyo', 'youon', 98),
    ('katakana', 'ミャ', 'mya', 'youon', 99),
    ('katakana', 'ミュ', 'myu', 'youon', 100),
    ('katakana', 'ミョ', 'myo', 'youon', 101),
    ('katakana', 'リャ', 'rya', 'youon', 102),
    ('katakana', 'リュ', 'ryu', 'youon', 103),
    ('katakana', 'リョ', 'ryo', 'youon', 104),
    ('katakana', 'ギャ', 'gya', 'youon', 105),
    ('katakana', 'ギュ', 'gyu', 'youon', 106),
    ('katakana', 'ギョ', 'gyo', 'youon', 107),
    ('katakana', 'ジャ', 'ja', 'youon', 108),
    ('katakana', 'ジュ', 'ju', 'youon', 109),
    ('katakana', 'ジョ', 'jo', 'youon', 110),
    ('katakana', 'ビャ', 'bya', 'youon', 111),
    ('katakana', 'ビュ', 'byu', 'youon', 112),
    ('katakana', 'ビョ', 'byo', 'youon', 113),
    ('katakana', 'ピャ', 'pya', 'youon', 114),
    ('katakana', 'ピュ', 'pyu', 'youon', 115),
    ('katakana', 'ピョ', 'pyo', 'youon', 116),
]

try:
    conn = MySQLdb.connect(host='127.0.0.1', user='root', passwd='6586156', db='japanese_learn', charset='utf8mb4')
    cur = conn.cursor()
    
    # Clear existing
    cur.execute('DELETE FROM kana')
    
    # Insert all
    for t, c, r, cat, o in kana_data:
        cur.execute('INSERT INTO kana (id, type, character, romanization, category, order_index, created_at, updated_at) VALUES (UUID(), %s, %s, %s, %s, %s, NOW(), NOW())', (t, c, r, cat, o))
    
    conn.commit()
    
    cur.execute('SELECT COUNT(*) FROM kana')
    count = cur.fetchone()[0]
    print(f'✅ Successfully imported {count} kana records')
    
    cur.close()
    conn.close()
except Exception as e:
    print(f'❌ Error: {e}')
    import traceback
    traceback.print_exc()
