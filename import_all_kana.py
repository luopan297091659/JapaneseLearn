#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
完整的日本语 kana 数据导入脚本 - 支持 utf8mb4
包含：五十音 + 濁音 + 半濁音 + 拗音（共 208 条）
"""

import mysql.connector
import uuid

# Database connection
config = {
    'host': '139.196.44.6',
    'user': 'root',
    'password': '6586156',
    'database': 'japanese_learn'
}

# 完整数据定义
KANA_DATA = [
    # ===== 基础五十音 HIRAGANA (43条) =====
    ('hiragana', 'あ', 'a', '五十音', 0),
    ('hiragana', 'い', 'i', '五十音', 1),
    ('hiragana', 'う', 'u', '五十音', 2),
    ('hiragana', 'え', 'e', '五十音', 3),
    ('hiragana', 'お', 'o', '五十音', 4),
    ('hiragana', 'か', 'ka', '五十音', 5),
    ('hiragana', 'き', 'ki', '五十音', 6),
    ('hiragana', 'く', 'ku', '五十音', 7),
    ('hiragana', 'け', 'ke', '五十音', 8),
    ('hiragana', 'こ', 'ko', '五十音', 9),
    ('hiragana', 'さ', 'sa', '五十音', 10),
    ('hiragana', 'し', 'shi', '五十音', 11),
    ('hiragana', 'す', 'su', '五十音', 12),
    ('hiragana', 'せ', 'se', '五十音', 13),
    ('hiragana', 'そ', 'so', '五十音', 14),
    ('hiragana', 'た', 'ta', '五十音', 15),
    ('hiragana', 'ち', 'chi', '五十音', 16),
    ('hiragana', 'つ', 'tsu', '五十音', 17),
    ('hiragana', 'て', 'te', '五十音', 18),
    ('hiragana', 'と', 'to', '五十音', 19),
    ('hiragana', 'な', 'na', '五十音', 20),
    ('hiragana', 'に', 'ni', '五十音', 21),
    ('hiragana', 'ぬ', 'nu', '五十音', 22),
    ('hiragana', 'ね', 'ne', '五十音', 23),
    ('hiragana', 'の', 'no', '五十音', 24),
    ('hiragana', 'は', 'ha', '五十音', 25),
    ('hiragana', 'ひ', 'hi', '五十音', 26),
    ('hiragana', 'ふ', 'fu', '五十音', 27),
    ('hiragana', 'へ', 'he', '五十音', 28),
    ('hiragana', 'ほ', 'ho', '五十音', 29),
    ('hiragana', 'ま', 'ma', '五十音', 30),
    ('hiragana', 'み', 'mi', '五十音', 31),
    ('hiragana', 'む', 'mu', '五十音', 32),
    ('hiragana', 'め', 'me', '五十音', 33),
    ('hiragana', 'も', 'mo', '五十音', 34),
    ('hiragana', 'や', 'ya', '五十音', 35),
    ('hiragana', 'ゆ', 'yu', '五十音', 36),
    ('hiragana', 'よ', 'yo', '五十音', 37),
    ('hiragana', 'ら', 'ra', '五十音', 38),
    ('hiragana', 'り', 'ri', '五十音', 39),
    ('hiragana', 'る', 'ru', '五十音', 40),
    ('hiragana', 'れ', 're', '五十音', 41),
    ('hiragana', 'ろ', 'ro', '五十音', 42),
    ('hiragana', 'わ', 'wa', '五十音', 43),
    ('hiragana', 'を', 'wo', '五十音', 44),
    ('hiragana', 'ん', 'n', '五十音', 45),

    # ===== 濁音 HIRAGANA (20条) =====
    ('hiragana', 'が', 'ga', '濁音', 46),
    ('hiragana', 'ぎ', 'gi', '濁音', 47),
    ('hiragana', 'ぐ', 'gu', '濁音', 48),
    ('hiragana', 'げ', 'ge', '濁音', 49),
    ('hiragana', 'ご', 'go', '濁音', 50),
    ('hiragana', 'ざ', 'za', '濁音', 51),
    ('hiragana', 'じ', 'ji', '濁音', 52),
    ('hiragana', 'ず', 'zu', '濁音', 53),
    ('hiragana', 'ぜ', 'ze', '濁音', 54),
    ('hiragana', 'ぞ', 'zo', '濁音', 55),
    ('hiragana', 'だ', 'da', '濁音', 56),
    ('hiragana', 'ぢ', 'di', '濁音', 57),
    ('hiragana', 'づ', 'du', '濁音', 58),
    ('hiragana', 'で', 'de', '濁音', 59),
    ('hiragana', 'ど', 'do', '濁音', 60),
    ('hiragana', 'ば', 'ba', '濁音', 61),
    ('hiragana', 'び', 'bi', '濁音', 62),
    ('hiragana', 'ぶ', 'bu', '濁音', 63),
    ('hiragana', 'べ', 'be', '濁音', 64),
    ('hiragana', 'ぼ', 'bo', '濁音', 65),

    # ===== 半濁音 HIRAGANA (5条) =====
    ('hiragana', 'ぱ', 'pa', '半濁音', 66),
    ('hiragana', 'ぴ', 'pi', '半濁音', 67),
    ('hiragana', 'ぷ', 'pu', '半濁音', 68),
    ('hiragana', 'ぺ', 'pe', '半濁音', 69),
    ('hiragana', 'ぽ', 'po', '半濁音', 70),

    # ===== 拗音 HIRAGANA (36条) =====
    ('hiragana', 'きゃ', 'kya', '拗音', 71),
    ('hiragana', 'きゅ', 'kyu', '拗音', 72),
    ('hiragana', 'きょ', 'kyo', '拗音', 73),
    ('hiragana', 'しゃ', 'sha', '拗音', 74),
    ('hiragana', 'しゅ', 'shu', '拗音', 75),
    ('hiragana', 'しょ', 'sho', '拗音', 76),
    ('hiragana', 'ちゃ', 'cha', '拗音', 77),
    ('hiragana', 'ちゅ', 'chu', '拗音', 78),
    ('hiragana', 'ちょ', 'cho', '拗音', 79),
    ('hiragana', 'にゃ', 'nya', '拗音', 80),
    ('hiragana', 'にゅ', 'nyu', '拗音', 81),
    ('hiragana', 'にょ', 'nyo', '拗音', 82),
    ('hiragana', 'ひゃ', 'hya', '拗音', 83),
    ('hiragana', 'ひゅ', 'hyu', '拗音', 84),
    ('hiragana', 'ひょ', 'hyo', '拗音', 85),
    ('hiragana', 'みゃ', 'mya', '拗音', 86),
    ('hiragana', 'みゅ', 'myu', '拗音', 87),
    ('hiragana', 'みょ', 'myo', '拗音', 88),
    ('hiragana', 'りゃ', 'rya', '拗音', 89),
    ('hiragana', 'りゅ', 'ryu', '拗音', 90),
    ('hiragana', 'りょ', 'ryo', '拗音', 91),
    ('hiragana', 'ぎゃ', 'gya', '拗音', 92),
    ('hiragana', 'ぎゅ', 'gyu', '拗音', 93),
    ('hiragana', 'ぎょ', 'gyo', '拗音', 94),
    ('hiragana', 'じゃ', 'ja', '拗音', 95),
    ('hiragana', 'じゅ', 'ju', '拗音', 96),
    ('hiragana', 'じょ', 'jo', '拗音', 97),
    ('hiragana', 'びゃ', 'bya', '拗音', 98),
    ('hiragana', 'びゅ', 'byu', '拗音', 99),
    ('hiragana', 'びょ', 'byo', '拗音', 100),
    ('hiragana', 'ぴゃ', 'pya', '拗音', 101),
    ('hiragana', 'ぴゅ', 'pyu', '拗音', 102),
    ('hiragana', 'ぴょ', 'pyo', '拗音', 103),
    ('hiragana', 'でぃ', 'di', '拗音', 104),
    ('hiragana', 'ふぁ', 'fa', '拗音', 105),
    ('hiragana', 'うぃ', 'wi', '拗音', 106),

    # ===== 基础五十音 KATAKANA (43条) =====
    ('katakana', 'ア', 'a', '五十音', 107),
    ('katakana', 'イ', 'i', '五十音', 108),
    ('katakana', 'ウ', 'u', '五十音', 109),
    ('katakana', 'エ', 'e', '五十音', 110),
    ('katakana', 'オ', 'o', '五十音', 111),
    ('katakana', 'カ', 'ka', '五十音', 112),
    ('katakana', 'キ', 'ki', '五十音', 113),
    ('katakana', 'ク', 'ku', '五十音', 114),
    ('katakana', 'ケ', 'ke', '五十音', 115),
    ('katakana', 'コ', 'ko', '五十音', 116),
    ('katakana', 'サ', 'sa', '五十音', 117),
    ('katakana', 'シ', 'shi', '五十音', 118),
    ('katakana', 'ス', 'su', '五十音', 119),
    ('katakana', 'セ', 'se', '五十音', 120),
    ('katakana', 'ソ', 'so', '五十音', 121),
    ('katakana', 'タ', 'ta', '五十音', 122),
    ('katakana', 'チ', 'chi', '五十音', 123),
    ('katakana', 'ツ', 'tsu', '五十音', 124),
    ('katakana', 'テ', 'te', '五十音', 125),
    ('katakana', 'ト', 'to', '五十音', 126),
    ('katakana', 'ナ', 'na', '五十音', 127),
    ('katakana', 'ニ', 'ni', '五十音', 128),
    ('katakana', 'ヌ', 'nu', '五十音', 129),
    ('katakana', 'ネ', 'ne', '五十音', 130),
    ('katakana', 'ノ', 'no', '五十音', 131),
    ('katakana', 'ハ', 'ha', '五十音', 132),
    ('katakana', 'ヒ', 'hi', '五十音', 133),
    ('katakana', 'フ', 'fu', '五十音', 134),
    ('katakana', 'ヘ', 'he', '五十音', 135),
    ('katakana', 'ホ', 'ho', '五十音', 136),
    ('katakana', 'マ', 'ma', '五十音', 137),
    ('katakana', 'ミ', 'mi', '五十音', 138),
    ('katakana', 'ム', 'mu', '五十音', 139),
    ('katakana', 'メ', 'me', '五十音', 140),
    ('katakana', 'モ', 'mo', '五十音', 141),
    ('katakana', 'ヤ', 'ya', '五十音', 142),
    ('katakana', 'ユ', 'yu', '五十音', 143),
    ('katakana', 'ヨ', 'yo', '五十音', 144),
    ('katakana', 'ラ', 'ra', '五十音', 145),
    ('katakana', 'リ', 'ri', '五十音', 146),
    ('katakana', 'ル', 'ru', '五十音', 147),
    ('katakana', 'レ', 're', '五十音', 148),
    ('katakana', 'ロ', 'ro', '五十音', 149),
    ('katakana', 'ワ', 'wa', '五十音', 150),
    ('katakana', 'ヲ', 'wo', '五十音', 151),
    ('katakana', 'ン', 'n', '五十音', 152),

    # ===== 濁音 KATAKANA (20条) =====
    ('katakana', 'ガ', 'ga', '濁音', 153),
    ('katakana', 'ギ', 'gi', '濁音', 154),
    ('katakana', 'グ', 'gu', '濁音', 155),
    ('katakana', 'ゲ', 'ge', '濁音', 156),
    ('katakana', 'ゴ', 'go', '濁音', 157),
    ('katakana', 'ザ', 'za', '濁音', 158),
    ('katakana', 'ジ', 'ji', '濁音', 159),
    ('katakana', 'ズ', 'zu', '濁音', 160),
    ('katakana', 'ゼ', 'ze', '濁音', 161),
    ('katakana', 'ゾ', 'zo', '濁音', 162),
    ('katakana', 'ダ', 'da', '濁音', 163),
    ('katakana', 'ヂ', 'di', '濁音', 164),
    ('katakana', 'ヅ', 'du', '濁音', 165),
    ('katakana', 'デ', 'de', '濁音', 166),
    ('katakana', 'ド', 'do', '濁音', 167),
    ('katakana', 'バ', 'ba', '濁音', 168),
    ('katakana', 'ビ', 'bi', '濁音', 169),
    ('katakana', 'ブ', 'bu', '濁音', 170),
    ('katakana', 'ベ', 'be', '濁音', 171),
    ('katakana', 'ボ', 'bo', '濁音', 172),

    # ===== 半濁音 KATAKANA (5条) =====
    ('katakana', 'パ', 'pa', '半濁音', 173),
    ('katakana', 'ピ', 'pi', '半濁音', 174),
    ('katakana', 'プ', 'pu', '半濁音', 175),
    ('katakana', 'ペ', 'pe', '半濁音', 176),
    ('katakana', 'ポ', 'po', '半濁音', 177),

    # ===== 拗音 KATAKANA (36条) =====
    ('katakana', 'キャ', 'kya', '拗音', 178),
    ('katakana', 'キュ', 'kyu', '拗音', 179),
    ('katakana', 'キョ', 'kyo', '拗音', 180),
    ('katakana', 'シャ', 'sha', '拗音', 181),
    ('katakana', 'シュ', 'shu', '拗音', 182),
    ('katakana', 'ショ', 'sho', '拗音', 183),
    ('katakana', 'チャ', 'cha', '拗音', 184),
    ('katakana', 'チュ', 'chu', '拗音', 185),
    ('katakana', 'チョ', 'cho', '拗音', 186),
    ('katakana', 'ニャ', 'nya', '拗音', 187),
    ('katakana', 'ニュ', 'nyu', '拗音', 188),
    ('katakana', 'ニョ', 'nyo', '拗音', 189),
    ('katakana', 'ヒャ', 'hya', '拗音', 190),
    ('katakana', 'ヒュ', 'hyu', '拗音', 191),
    ('katakana', 'ヒョ', 'hyo', '拗音', 192),
    ('katakana', 'ミャ', 'mya', '拗音', 193),
    ('katakana', 'ミュ', 'myu', '拗音', 194),
    ('katakana', 'ミョ', 'myo', '拗音', 195),
    ('katakana', 'リャ', 'rya', '拗音', 196),
    ('katakana', 'リュ', 'ryu', '拗音', 197),
    ('katakana', 'リョ', 'ryo', '拗音', 198),
    ('katakana', 'ギャ', 'gya', '拗音', 199),
    ('katakana', 'ギュ', 'gyu', '拗音', 200),
    ('katakana', 'ギョ', 'gyo', '拗音', 201),
    ('katakana', 'ジャ', 'ja', '拗音', 202),
    ('katakana', 'ジュ', 'ju', '拗音', 203),
    ('katakana', 'ジョ', 'jo', '拗音', 204),
    ('katakana', 'ビャ', 'bya', '拗音', 205),
    ('katakana', 'ビュ', 'byu', '拗音', 206),
    ('katakana', 'ビョ', 'byo', '拗音', 207),
    ('katakana', 'ピャ', 'pya', '拗音', 208),
    ('katakana', 'ピュ', 'pyu', '拗音', 209),
    ('katakana', 'ピョ', 'pyo', '拗音', 210),
    ('katakana', 'ディ', 'di', '拗音', 211),
    ('katakana', 'ファ', 'fa', '拗音', 212),
    ('katakana', 'ウィ', 'wi', '拗音', 213),
]

def main():
    try:
        conn = mysql.connector.connect(**config)
        cursor = conn.cursor()
        
        print("开始导入 kana 数据...")
        print(f"总共要导入 {len(KANA_DATA)} 条记录")
        
        # 清空表
        cursor.execute("DELETE FROM kana")
        print("已清空旧数据")
        
        # 批量插入
        sql = """
        INSERT INTO kana (id, type, kana_char, romanization, category, order_index)
        VALUES (%s, %s, %s, %s, %s, %s)
        """
        
        success_count = 0
        fail_count = 0
        
        for type_val, char_val, roman_val, cat_val, order_val in KANA_DATA:
            try:
                cursor.execute(sql, (str(uuid.uuid4()), type_val, char_val, roman_val, cat_val, order_val))
                success_count += 1
            except Exception as e:
                print(f"失败: {type_val} {char_val} - {str(e)}")
                fail_count += 1
        
        conn.commit()
        print(f"\n导入完成！")
        print(f"成功: {success_count} 条")
        print(f"失败: {fail_count} 条")
        
        # 验证
        cursor.execute("SELECT COUNT(*) FROM kana")
        total = cursor.fetchone()[0]
        print(f"\n数据库中现有: {total} 条记录")
        
        # 按类别统计
        cursor.execute("SELECT category, COUNT(*) FROM kana GROUP BY category")
        print("\n按类别统计:")
        for cat, cnt in cursor.fetchall():
            print(f"  {cat}: {cnt} 条")
        
        # 按类型统计
        cursor.execute("SELECT type, COUNT(*) FROM kana GROUP BY type")
        print("\n按类型统计:")
        for typ, cnt in cursor.fetchall():
            print(f"  {typ}: {cnt} 条")
        
        cursor.close()
        conn.close()
        
    except Exception as e:
        print(f"错误: {str(e)}")
        return 1
    
    return 0

if __name__ == '__main__':
    exit(main())
