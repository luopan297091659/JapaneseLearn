#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json

# 完整的五十音数据
kana_data = {
    "categories": [
        {"id": 1, "name": "平假名", "description": "Hiragana - Japanese phonetic script for native words"},
        {"id": 2, "name": "片假名", "description": "Katakana - Japanese phonetic script for foreign words"},
        {"id": 3, "name": "浊音", "description": "Dakuten - Voiced syllables (゛ mark)"},
        {"id": 4, "name": "半浊音", "description": "Handakuten - Semi-voiced syllables (゜ mark)"},
        {"id": 5, "name": "拗音", "description": "Youon - Combined syllables"}
    ],
    "characters": [
        # 平假名 (Hiragana) - Category 1
        {"category_id": 1, "hiragana": "あ", "katakana": "ア", "romaji": "a", "order_index": 0, "stroke_count": 3},
        {"category_id": 1, "hiragana": "い", "katakana": "イ", "romaji": "i", "order_index": 1, "stroke_count": 1},
        {"category_id": 1, "hiragana": "う", "katakana": "ウ", "romaji": "u", "order_index": 2, "stroke_count": 2},
        {"category_id": 1, "hiragana": "え", "katakana": "エ", "romaji": "e", "order_index": 3, "stroke_count": 1},
        {"category_id": 1, "hiragana": "お", "katakana": "オ", "romaji": "o", "order_index": 4, "stroke_count": 1},
        {"category_id": 1, "hiragana": "か", "katakana": "カ", "romaji": "ka", "order_index": 5, "stroke_count": 3},
        {"category_id": 1, "hiragana": "き", "katakana": "キ", "romaji": "ki", "order_index": 6, "stroke_count": 3},
        {"category_id": 1, "hiragana": "く", "katakana": "ク", "romaji": "ku", "order_index": 7, "stroke_count": 1},
        {"category_id": 1, "hiragana": "け", "katakana": "ケ", "romaji": "ke", "order_index": 8, "stroke_count": 3},
        {"category_id": 1, "hiragana": "こ", "katakana": "コ", "romaji": "ko", "order_index": 9, "stroke_count": 2},
        {"category_id": 1, "hiragana": "さ", "katakana": "サ", "romaji": "sa", "order_index": 10, "stroke_count": 3},
        {"category_id": 1, "hiragana": "し", "katakana": "シ", "romaji": "shi", "order_index": 11, "stroke_count": 1},
        {"category_id": 1, "hiragana": "す", "katakana": "ス", "romaji": "su", "order_index": 12, "stroke_count": 1},
        {"category_id": 1, "hiragana": "せ", "katakana": "セ", "romaji": "se", "order_index": 13, "stroke_count": 3},
        {"category_id": 1, "hiragana": "そ", "katakana": "ソ", "romaji": "so", "order_index": 14, "stroke_count": 1},
        {"category_id": 1, "hiragana": "た", "katakana": "タ", "romaji": "ta", "order_index": 15, "stroke_count": 1},
        {"category_id": 1, "hiragana": "ち", "katakana": "チ", "romaji": "chi", "order_index": 16, "stroke_count": 3},
        {"category_id": 1, "hiragana": "つ", "katakana": "ツ", "romaji": "tsu", "order_index": 17, "stroke_count": 2},
        {"category_id": 1, "hiragana": "て", "katakana": "テ", "romaji": "te", "order_index": 18, "stroke_count": 1},
        {"category_id": 1, "hiragana": "と", "katakana": "ト", "romaji": "to", "order_index": 19, "stroke_count": 1},
        {"category_id": 1, "hiragana": "な", "katakana": "ナ", "romaji": "na", "order_index": 20, "stroke_count": 1},
        {"category_id": 1, "hiragana": "に", "katakana": "ニ", "romaji": "ni", "order_index": 21, "stroke_count": 2},
        {"category_id": 1, "hiragana": "ぬ", "katakana": "ヌ", "romaji": "nu", "order_index": 22, "stroke_count": 2},
        {"category_id": 1, "hiragana": "ね", "katakana": "ネ", "romaji": "ne", "order_index": 23, "stroke_count": 1},
        {"category_id": 1, "hiragana": "の", "katakana": "ノ", "romaji": "no", "order_index": 24, "stroke_count": 1},
        {"category_id": 1, "hiragana": "は", "katakana": "ハ", "romaji": "ha", "order_index": 25, "stroke_count": 3},
        {"category_id": 1, "hiragana": "ひ", "katakana": "ヒ", "romaji": "hi", "order_index": 26, "stroke_count": 1},
        {"category_id": 1, "hiragana": "ふ", "katakana": "フ", "romaji": "fu", "order_index": 27, "stroke_count": 3},
        {"category_id": 1, "hiragana": "へ", "katakana": "ヘ", "romaji": "he", "order_index": 28, "stroke_count": 1},
        {"category_id": 1, "hiragana": "ほ", "katakana": "ホ", "romaji": "ho", "order_index": 29, "stroke_count": 4},
        {"category_id": 1, "hiragana": "ま", "katakana": "マ", "romaji": "ma", "order_index": 30, "stroke_count": 3},
        {"category_id": 1, "hiragana": "み", "katakana": "ミ", "romaji": "mi", "order_index": 31, "stroke_count": 3},
        {"category_id": 1, "hiragana": "む", "katakana": "ム", "romaji": "mu", "order_index": 32, "stroke_count": 3},
        {"category_id": 1, "hiragana": "め", "katakana": "メ", "romaji": "me", "order_index": 33, "stroke_count": 3},
        {"category_id": 1, "hiragana": "も", "katakana": "モ", "romaji": "mo", "order_index": 34, "stroke_count": 4},
        {"category_id": 1, "hiragana": "や", "katakana": "ヤ", "romaji": "ya", "order_index": 35, "stroke_count": 3},
        {"category_id": 1, "hiragana": "ゆ", "katakana": "ユ", "romaji": "yu", "order_index": 36, "stroke_count": 2},
        {"category_id": 1, "hiragana": "よ", "katakana": "ヨ", "romaji": "yo", "order_index": 37, "stroke_count": 3},
        {"category_id": 1, "hiragana": "ら", "katakana": "ラ", "romaji": "ra", "order_index": 38, "stroke_count": 2},
        {"category_id": 1, "hiragana": "り", "katakana": "リ", "romaji": "ri", "order_index": 39, "stroke_count": 2},
        {"category_id": 1, "hiragana": "る", "katakana": "ル", "romaji": "ru", "order_index": 40, "stroke_count": 1},
        {"category_id": 1, "hiragana": "れ", "katakana": "レ", "romaji": "re", "order_index": 41, "stroke_count": 2},
        {"category_id": 1, "hiragana": "ろ", "katakana": "ロ", "romaji": "ro", "order_index": 42, "stroke_count": 1},
        {"category_id": 1, "hiragana": "わ", "katakana": "ワ", "romaji": "wa", "order_index": 43, "stroke_count": 1},
        {"category_id": 1, "hiragana": "ゐ", "katakana": "ヰ", "romaji": "wi", "order_index": 44, "stroke_count": 3},
        {"category_id": 1, "hiragana": "ゑ", "katakana": "ヱ", "romaji": "we", "order_index": 45, "stroke_count": 1},
        {"category_id": 1, "hiragana": "を", "katakana": "ヲ", "romaji": "wo", "order_index": 46, "stroke_count": 1},
        {"category_id": 1, "hiragana": "ん", "katakana": "ン", "romaji": "n", "order_index": 47, "stroke_count": 1},
        
        # 浊音 (Dakuten - Category 3)
        {"category_id": 3, "hiragana": "が", "katakana": "ガ", "romaji": "ga", "order_index": 0, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ぎ", "katakana": "ギ", "romaji": "gi", "order_index": 1, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ぐ", "katakana": "グ", "romaji": "gu", "order_index": 2, "stroke_count": 2},
        {"category_id": 3, "hiragana": "げ", "katakana": "ゲ", "romaji": "ge", "order_index": 3, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ご", "katakana": "ゴ", "romaji": "go", "order_index": 4, "stroke_count": 3},
        {"category_id": 3, "hiragana": "ざ", "katakana": "ザ", "romaji": "za", "order_index": 5, "stroke_count": 4},
        {"category_id": 3, "hiragana": "じ", "katakana": "ジ", "romaji": "ji", "order_index": 6, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ず", "katakana": "ズ", "romaji": "zu", "order_index": 7, "stroke_count": 2},
        {"category_id": 3, "hiragana": "ぜ", "katakana": "ゼ", "romaji": "ze", "order_index": 8, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ぞ", "katakana": "ゾ", "romaji": "zo", "order_index": 9, "stroke_count": 2},
        {"category_id": 3, "hiragana": "だ", "katakana": "ダ", "romaji": "da", "order_index": 10, "stroke_count": 2},
        {"category_id": 3, "hiragana": "ぢ", "katakana": "ヂ", "romaji": "di", "order_index": 11, "stroke_count": 4},
        {"category_id": 3, "hiragana": "づ", "katakana": "ヅ", "romaji": "du", "order_index": 12, "stroke_count": 3},
        {"category_id": 3, "hiragana": "で", "katakana": "デ", "romaji": "de", "order_index": 13, "stroke_count": 2},
        {"category_id": 3, "hiragana": "ど", "katakana": "ド", "romaji": "do", "order_index": 14, "stroke_count": 2},
        {"category_id": 3, "hiragana": "ば", "katakana": "バ", "romaji": "ba", "order_index": 15, "stroke_count": 4},
        {"category_id": 3, "hiragana": "び", "katakana": "ビ", "romaji": "bi", "order_index": 16, "stroke_count": 4},
        {"category_id": 3, "hiragana": "ぶ", "katakana": "ブ", "romaji": "bu", "order_index": 17, "stroke_count": 4},
        {"category_id": 3, "hiragana": "べ", "katakana": "ベ", "romaji": "be", "order_index": 18, "stroke_count": 2},
        {"category_id": 3, "hiragana": "ぼ", "katakana": "ボ", "romaji": "bo", "order_index": 19, "stroke_count": 5},
        
        # 半浊音 (Handakuten - Category 4)
        {"category_id": 4, "hiragana": "ぱ", "katakana": "パ", "romaji": "pa", "order_index": 0, "stroke_count": 5},
        {"category_id": 4, "hiragana": "ぴ", "katakana": "ピ", "romaji": "pi", "order_index": 1, "stroke_count": 5},
        {"category_id": 4, "hiragana": "ぷ", "katakana": "プ", "romaji": "pu", "order_index": 2, "stroke_count": 5},
        {"category_id": 4, "hiragana": "ぺ", "katakana": "ペ", "romaji": "pe", "order_index": 3, "stroke_count": 3},
        {"category_id": 4, "hiragana": "ぽ", "katakana": "ポ", "romaji": "po", "order_index": 4, "stroke_count": 6},
        
        # 拗音 (Youon - Category 5) - Small ya/yu/yo combinations
        {"category_id": 5, "hiragana": "きゃ", "katakana": "キャ", "romaji": "kya", "order_index": 0, "stroke_count": 4},
        {"category_id": 5, "hiragana": "きゅ", "katakana": "キュ", "romaji": "kyu", "order_index": 1, "stroke_count": 5},
        {"category_id": 5, "hiragana": "きょ", "katakana": "キョ", "romaji": "kyo", "order_index": 2, "stroke_count": 4},
        {"category_id": 5, "hiragana": "しゃ", "katakana": "シャ", "romaji": "sha", "order_index": 3, "stroke_count": 4},
        {"category_id": 5, "hiragana": "しゅ", "katakana": "シュ", "romaji": "shu", "order_index": 4, "stroke_count": 4},
        {"category_id": 5, "hiragana": "しょ", "katakana": "ショ", "romaji": "sho", "order_index": 5, "stroke_count": 4},
        {"category_id": 5, "hiragana": "ちゃ", "katakana": "チャ", "romaji": "cha", "order_index": 6, "stroke_count": 5},
        {"category_id": 5, "hiragana": "ちゅ", "katakana": "チュ", "romaji": "chu", "order_index": 7, "stroke_count": 5},
        {"category_id": 5, "hiragana": "ちょ", "katakana": "チョ", "romaji": "cho", "order_index": 8, "stroke_count": 5},
        {"category_id": 5, "hiragana": "にゃ", "katakana": "ニャ", "romaji": "nya", "order_index": 9, "stroke_count": 3},
        {"category_id": 5, "hiragana": "にゅ", "katakana": "ニュ", "romaji": "nyu", "order_index": 10, "stroke_count": 4},
        {"category_id": 5, "hiragana": "にょ", "katakana": "ニョ", "romaji": "nyo", "order_index": 11, "stroke_count": 3},
        {"category_id": 5, "hiragana": "ひゃ", "katakana": "ヒャ", "romaji": "hya", "order_index": 12, "stroke_count": 4},
        {"category_id": 5, "hiragana": "ひゅ", "katakana": "ヒュ", "romaji": "hyu", "order_index": 13, "stroke_count": 5},
        {"category_id": 5, "hiragana": "ひょ", "katakana": "ヒョ", "romaji": "hyo", "order_index": 14, "stroke_count": 4},
        {"category_id": 5, "hiragana": "みゃ", "katakana": "ミャ", "romaji": "mya", "order_index": 15, "stroke_count": 6},
        {"category_id": 5, "hiragana": "みゅ", "katakana": "ミュ", "romaji": "myu", "order_index": 16, "stroke_count": 7},
        {"category_id": 5, "hiragana": "みょ", "katakana": "ミョ", "romaji": "myo", "order_index": 17, "stroke_count": 6},
        {"category_id": 5, "hiragana": "りゃ", "katakana": "リャ", "romaji": "rya", "order_index": 18, "stroke_count": 3},
        {"category_id": 5, "hiragana": "りゅ", "katakana": "リュ", "romaji": "ryu", "order_index": 19, "stroke_count": 4},
        {"category_id": 5, "hiragana": "りょ", "katakana": "リョ", "romaji": "ryo", "order_index": 20, "stroke_count": 3},
        {"category_id": 5, "hiragana": "ぎゃ", "katakana": "ギャ", "romaji": "gya", "order_index": 21, "stroke_count": 5},
        {"category_id": 5, "hiragana": "ぎゅ", "katakana": "ギュ", "romaji": "gyu", "order_index": 22, "stroke_count": 6},
        {"category_id": 5, "hiragana": "ぎょ", "katakana": "ギョ", "romaji": "gyo", "order_index": 23, "stroke_count": 5},
        {"category_id": 5, "hiragana": "じゃ", "katakana": "ジャ", "romaji": "ja", "order_index": 24, "stroke_count": 5},
        {"category_id": 5, "hiragana": "じゅ", "katakana": "ジュ", "romaji": "ju", "order_index": 25, "stroke_count": 5},
        {"category_id": 5, "hiragana": "じょ", "katakana": "ジョ", "romaji": "jo", "order_index": 26, "stroke_count": 5},
        {"category_id": 5, "hiragana": "びゃ", "katakana": "ビャ", "romaji": "bya", "order_index": 27, "stroke_count": 5},
        {"category_id": 5, "hiragana": "びゅ", "katakana": "ビュ", "romaji": "byu", "order_index": 28, "stroke_count": 6},
        {"category_id": 5, "hiragana": "びょ", "katakana": "ビョ", "romaji": "byo", "order_index": 29, "stroke_count": 5},
        {"category_id": 5, "hiragana": "ぴゃ", "katakana": "ピャ", "romaji": "pya", "order_index": 30, "stroke_count": 6},
        {"category_id": 5, "hiragana": "ぴゅ", "katakana": "ピュ", "romaji": "pyu", "order_index": 31, "stroke_count": 7},
        {"category_id": 5, "hiragana": "ぴょ", "katakana": "ピョ", "romaji": "pyo", "order_index": 32, "stroke_count": 6},
    ]
}

# 生成 SQL
sql_lines = []

# 插入 categories
sql_lines.append("SET FOREIGN_KEY_CHECKS=0;")
sql_lines.append("")
sql_lines.append("INSERT INTO kana_categories (id, name, description) VALUES")
category_values = []
for cat in kana_data["categories"]:
    val = f"({cat['id']}, {repr(cat['name'])}, {repr(cat['description'])})"
    category_values.append(val)
sql_lines.append(",\n".join(category_values) + ";")
sql_lines.append("")

# 插入 characters
sql_lines.append("INSERT INTO kana_characters (category_id, hiragana, katakana, romaji, order_index, stroke_count) VALUES")
character_values = []
for char in kana_data["characters"]:
    val = f"({char['category_id']}, {repr(char['hiragana'])}, {repr(char['katakana'])}, {repr(char['romaji'])}, {char['order_index']}, {char['stroke_count']})"
    character_values.append(val)
sql_lines.append(",\n".join(character_values) + ";")
sql_lines.append("")

sql_lines.append("SET FOREIGN_KEY_CHECKS=1;")
sql_lines.append("")
sql_lines.append("SELECT COUNT(*) as category_count FROM kana_categories;")
sql_lines.append("SELECT COUNT(*) as character_count FROM kana_characters;")

# 输出到文件
with open("backend/database/seeds/kana_seed_clean.sql", "w", encoding="utf-8") as f:
    f.write("\n".join(sql_lines))

print("Generated kana_seed_clean.sql successfully!")
print(f"Categories: {len(kana_data['categories'])}")
print(f"Characters: {len(kana_data['characters'])}")
