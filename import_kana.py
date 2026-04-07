#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
导入日语五十音数据到 kana 表
"""
import uuid
import sys
sys.path.insert(0, '/home/japanese-learn/backend')

try:
    import pymysql
    conn = pymysql.connect(
        host='localhost',
        user='root',
        password='6586156',
        database='japanese_learn',
        charset='utf8mb4'
    )
    cursor = conn.cursor()
    
    # 基础五十音数据
    kana_data = [
        # HIRAGANA (43)
        ('hiragana', 'あ', 'a', '五十音', 0), ('hiragana', 'い', 'i', '五十音', 1), ('hiragana', 'う', 'u', '五十音', 2),
        ('hiragana', 'え', 'e', '五十音', 3), ('hiragana', 'お', 'o', '五十音', 4),
        ('hiragana', 'か', 'ka', '五十音', 5), ('hiragana', 'き', 'ki', '五十音', 6), ('hiragana', 'く', 'ku', '五十音', 7),
        ('hiragana', 'け', 'ke', '五十音', 8), ('hiragana', 'こ', 'ko', '五十音', 9),
        ('hiragana', 'さ', 'sa', '五十音', 15), ('hiragana', 'し', 'shi', '五十音', 16), ('hiragana', 'す', 'su', '五十音', 17),
        ('hiragana', 'せ', 'se', '五十音', 18), ('hiragana', 'そ', 'so', '五十音', 19),
        ('hiragana', 'た', 'ta', '五十音', 25), ('hiragana', 'ち', 'chi', '五十音', 26), ('hiragana', 'つ', 'tsu', '五十音', 27),
        ('hiragana', 'て', 'te', '五十音', 28), ('hiragana', 'と', 'to', '五十音', 29),
        ('hiragana', 'な', 'na', '五十音', 35), ('hiragana', 'に', 'ni', '五十音', 36), ('hiragana', 'ぬ', 'nu', '五十音', 37),
        ('hiragana', 'ね', 'ne', '五十音', 38), ('hiragana', 'の', 'no', '五十音', 39),
        ('hiragana', 'は', 'ha', '五十音', 40), ('hiragana', 'ひ', 'hi', '五十音', 41), ('hiragana', 'ふ', 'fu', '五十音', 42),
        ('hiragana', 'へ', 'he', '五十音', 43), ('hiragana', 'ほ', 'ho', '五十音', 44),
        ('hiragana', 'ま', 'ma', '五十音', 55), ('hiragana', 'み', 'mi', '五十音', 56), ('hiragana', 'む', 'mu', '五十音', 57),
        ('hiragana', 'め', 'me', '五十音', 58), ('hiragana', 'も', 'mo', '五十音', 59),
        ('hiragana', 'や', 'ya', '五十音', 60), ('hiragana', 'ゆ', 'yu', '五十音', 61), ('hiragana', 'よ', 'yo', '五十音', 62),
        ('hiragana', 'ら', 'ra', '五十音', 65), ('hiragana', 'り', 'ri', '五十音', 66), ('hiragana', 'る', 'ru', '五十音', 67),
        ('hiragana', 'れ', 're', '五十音', 68), ('hiragana', 'ろ', 'ro', '五十音', 69),
        ('hiragana', 'わ', 'wa', '五十音', 70), ('hiragana', 'を', 'wo', '五十音', 71), ('hiragana', 'ん', 'n', '五十音', 72),
        # 濁音 HIRAGANA (20)
        ('hiragana', 'が', 'ga', '濁音', 10), ('hiragana', 'ぎ', 'gi', '濁音', 11), ('hiragana', 'ぐ', 'gu', '濁音', 12),
        ('hiragana', 'げ', 'ge', '濁音', 13), ('hiragana', 'ご', 'go', '濁音', 14),
        ('hiragana', 'ざ', 'za', '濁音', 20), ('hiragana', 'じ', 'ji', '濁音', 21), ('hiragana', 'ず', 'zu', '濁音', 22),
        ('hiragana', 'ぜ', 'ze', '濁音', 23), ('hiragana', 'ぞ', 'zo', '濁音', 24),
        ('hiragana', 'だ', 'da', '濁音', 30), ('hiragana', 'ぢ', 'di', '濁音', 31), ('hiragana', 'づ', 'du', '濁音', 32),
        ('hiragana', 'で', 'de', '濁音', 33), ('hiragana', 'ど', 'do', '濁音', 34),
        ('hiragana', 'ば', 'ba', '濁音', 45), ('hiragana', 'び', 'bi', '濁音', 46), ('hiragana', 'ぶ', 'bu', '濁音', 47),
        ('hiragana', 'べ', 'be', '濁音', 48), ('hiragana', 'ぼ', 'bo', '濁音', 49),
        # 半濁音 HIRAGANA (5)
        ('hiragana', 'ぱ', 'pa', '半濁音', 50), ('hiragana', 'ぴ', 'pi', '半濁音', 51), ('hiragana', 'ぷ', 'pu', '半濁音', 52),
        ('hiragana', 'ぺ', 'pe', '半濁音', 53), ('hiragana', 'ぽ', 'po', '半濁音', 54),
        # 拗音 HIRAGANA (36)
        ('hiragana', 'きゃ', 'kya', '拗音', 100), ('hiragana', 'きゅ', 'kyu', '拗音', 101), ('hiragana', 'きょ', 'kyo', '拗音', 102),
        ('hiragana', 'しゃ', 'sha', '拗音', 110), ('hiragana', 'しゅ', 'shu', '拗音', 111), ('hiragana', 'しょ', 'sho', '拗音', 112),
        ('hiragana', 'ちゃ', 'cha', '拗音', 120), ('hiragana', 'ちゅ', 'chu', '拗音', 121), ('hiragana', 'ちょ', 'cho', '拗音', 122),
        ('hiragana', 'にゃ', 'nya', '拗音', 130), ('hiragana', 'にゅ', 'nyu', '拗音', 131), ('hiragana', 'にょ', 'nyo', '拗音', 132),
        ('hiragana', 'ひゃ', 'hya', '拗音', 140), ('hiragana', 'ひゅ', 'hyu', '拗音', 141), ('hiragana', 'ひょ', 'hyo', '拗音', 142),
        ('hiragana', 'みゃ', 'mya', '拗音', 150), ('hiragana', 'みゅ', 'myu', '拗音', 151), ('hiragana', 'みょ', 'myo', '拗音', 152),
        ('hiragana', 'りゃ', 'rya', '拗音', 160), ('hiragana', 'りゅ', 'ryu', '拗音', 161), ('hiragana', 'りょ', 'ryo', '拗音', 162),
        ('hiragana', 'ぎゃ', 'gya', '拗音', 170), ('hiragana', 'ぎゅ', 'gyu', '拗音', 171), ('hiragana', 'ぎょ', 'gyo', '拗音', 172),
        ('hiragana', 'じゃ', 'ja', '拗音', 180), ('hiragana', 'じゅ', 'ju', '拗音', 181), ('hiragana', 'じょ', 'jo', '拗音', 182),
        ('hiragana', 'びゃ', 'bya', '拗音', 190), ('hiragana', 'びゅ', 'byu', '拗音', 191), ('hiragana', 'びょ', 'byo', '拗音', 192),
        ('hiragana', 'ぴゃ', 'pya', '拗音', 200), ('hiragana', 'ぴゅ', 'pyu', '拗音', 201), ('hiragana', 'ぴょ', 'pyo', '拗音', 202),
        
        # KATAKANA (104 - same as hiragana but with katakana characters)
        ('katakana', 'ア', 'a', '五十音', 0), ('katakana', 'イ', 'i', '五十音', 1), ('katakana', 'ウ', 'u', '五十音', 2),
        ('katakana', 'エ', 'e', '五十音', 3), ('katakana', 'オ', 'o', '五十音', 4),
        ('katakana', 'カ', 'ka', '五十音', 5), ('katakana', 'キ', 'ki', '五十音', 6), ('katakana', 'ク', 'ku', '五十音', 7),
        ('katakana', 'ケ', 'ke', '五十音', 8), ('katakana', 'コ', 'ko', '五十音', 9),
        ('katakana', 'サ', 'sa', '五十音', 15), ('katakana', 'シ', 'shi', '五十音', 16), ('katakana', 'ス', 'su', '五十音', 17),
        ('katakana', 'セ', 'se', '五十音', 18), ('katakana', 'ソ', 'so', '五十音', 19),
        ('katakana', 'タ', 'ta', '五十音', 25), ('katakana', 'チ', 'chi', '五十音', 26), ('katakana', 'ツ', 'tsu', '五十音', 27),
        ('katakana', 'テ', 'te', '五十音', 28), ('katakana', 'ト', 'to', '五十音', 29),
        ('katakana', 'ナ', 'na', '五十音', 35), ('katakana', 'ニ', 'ni', '五十音', 36), ('katakana', 'ヌ', 'nu', '五十音', 37),
        ('katakana', 'ネ', 'ne', '五十音', 38), ('katakana', 'ノ', 'no', '五十音', 39),
        ('katakana', 'ハ', 'ha', '五十音', 40), ('katakana', 'ヒ', 'hi', '五十音', 41), ('katakana', 'フ', 'fu', '五十音', 42),
        ('katakana', 'ヘ', 'he', '五十音', 43), ('katakana', 'ホ', 'ho', '五十音', 44),
        ('katakana', 'マ', 'ma', '五十音', 55), ('katakana', 'ミ', 'mi', '五十音', 56), ('katakana', 'ム', 'mu', '五十音', 57),
        ('katakana', 'メ', 'me', '五十音', 58), ('katakana', 'モ', 'mo', '五十音', 59),
        ('katakana', 'ヤ', 'ya', '五十音', 60), ('katakana', 'ユ', 'yu', '五十音', 61), ('katakana', 'ヨ', 'yo', '五十音', 62),
        ('katakana', 'ラ', 'ra', '五十音', 65), ('katakana', 'リ', 'ri', '五十音', 66), ('katakana', 'ル', 'ru', '五十音', 67),
        ('katakana', 'レ', 're', '五十音', 68), ('katakana', 'ロ', 'ro', '五十音', 69),
        ('katakana', 'ワ', 'wa', '五十音', 70), ('katakana', 'ヲ', 'wo', '五十音', 71), ('katakana', 'ン', 'n', '五十音', 72),
        # 濁音 KATAKANA (20)
        ('katakana', 'ガ', 'ga', '濁音', 10), ('katakana', 'ギ', 'gi', '濁音', 11), ('katakana', 'グ', 'gu', '濁音', 12),
        ('katakana', 'ゲ', 'ge', '濁音', 13), ('katakana', 'ゴ', 'go', '濁音', 14),
        ('katakana', 'ザ', 'za', '濁音', 20), ('katakana', 'ジ', 'ji', '濁音', 21), ('katakana', 'ズ', 'zu', '濁音', 22),
        ('katakana', 'ゼ', 'ze', '濁音', 23), ('katakana', 'ゾ', 'zo', '濁音', 24),
        ('katakana', 'ダ', 'da', '濁音', 30), ('katakana', 'ヂ', 'di', '濁音', 31), ('katakana', 'ヅ', 'du', '濁音', 32),
        ('katakana', 'デ', 'de', '濁音', 33), ('katakana', 'ド', 'do', '濁音', 34),
        ('katakana', 'バ', 'ba', '濁音', 45), ('katakana', 'ビ', 'bi', '濁音', 46), ('katakana', 'ブ', 'bu', '濁音', 47),
        ('katakana', 'ベ', 'be', '濁音', 48), ('katakana', 'ボ', 'bo', '濁音', 49),
        # 半濁音 KATAKANA (5)
        ('katakana', 'パ', 'pa', '半濁音', 50), ('katakana', 'ピ', 'pi', '半濁音', 51), ('katakana', 'プ', 'pu', '半濁音', 52),
        ('katakana', 'ペ', 'pe', '半濁音', 53), ('katakana', 'ポ', 'po', '半濁音', 54),
        # 拗音 KATAKANA (36)
        ('katakana', 'キャ', 'kya', '拗音', 100), ('katakana', 'キュ', 'kyu', '拗音', 101), ('katakana', 'キョ', 'kyo', '拗音', 102),
        ('katakana', 'シャ', 'sha', '拗音', 110), ('katakana', 'シュ', 'shu', '拗音', 111), ('katakana', 'ショ', 'sho', '拗音', 112),
        ('katakana', 'チャ', 'cha', '拗音', 120), ('katakana', 'チュ', 'chu', '拗音', 121), ('katakana', 'チョ', 'cho', '拗音', 122),
        ('katakana', 'ニャ', 'nya', '拗音', 130), ('katakana', 'ニュ', 'nyu', '拗音', 131), ('katakana', 'ニョ', 'nyo', '拗音', 132),
        ('katakana', 'ヒャ', 'hya', '拗音', 140), ('katakana', 'ヒュ', 'hyu', '拗音', 141), ('katakana', 'ヒョ', 'hyo', '拗音', 142),
        ('katakana', 'ミャ', 'mya', '拗音', 150), ('katakana', 'ミュ', 'myu', '拗音', 151), ('katakana', 'ミョ', 'myo', '拗音', 152),
        ('katakana', 'リャ', 'rya', '拗音', 160), ('katakana', 'リュ', 'ryu', '拗音', 161), ('katakana', 'リョ', 'ryo', '拗音', 162),
        ('katakana', 'ギャ', 'gya', '拗音', 170), ('katakana', 'ギュ', 'gyu', '拗音', 171), ('katakana', 'ギョ', 'gyo', '拗音', 172),
        ('katakana', 'ジャ', 'ja', '拗音', 180), ('katakana', 'ジュ', 'ju', '拗音', 181), ('katakana', 'ジョ', 'jo', '拗音', 182),
        ('katakana', 'ビャ', 'bya', '拗音', 190), ('katakana', 'ビュ', 'byu', '拗音', 191), ('katakana', 'ビョ', 'byo', '拗音', 192),
        ('katakana', 'ピャ', 'pya', '拗音', 200), ('katakana', 'ピュ', 'pyu', '拗音', 201), ('katakana', 'ピョ', 'pyo', '拗音', 202),
    ]
    
    count = 0
    for type_val, char, roman, category, order_idx in kana_data:
        uid = str(uuid.uuid4())
        sql = "INSERT INTO kana (id, type, character, romanization, category, order_index) VALUES (%s, %s, %s, %s, %s, %s)"
        cursor.execute(sql, (uid, type_val, char, roman, category, order_idx))
        count += 1
    
    conn.commit()
    print(f"成功导入 {count} 条 Kana 数据", file=sys.stderr)
    
    # 验证
    cursor.execute("SELECT COUNT(*) FROM kana")
    result = cursor.fetchone()
    print(f"kana 表现在有 {result[0]} 条记录", file=sys.stderr)
    
    cursor.close()
    conn.close()
except Exception as e:
    print(f"错误: {e}", file=sys.stderr)
    sys.exit(1)
