#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys

os.chdir('/home/japanese-learn')
sys.path.insert(0, '/home/japanese-learn/backend')

import uuid

# Kana data  
kana_list = [
    (1, "あ", "ア", "a", 0, 3), (1, "い", "イ", "i", 1, 1), (1, "う", "ウ", "u", 2, 2), (1, "え", "エ", "e", 3, 1),
    (1, "お", "オ", "o", 4, 1), (1, "か", "カ", "ka", 5, 3), (1, "き", "キ", "ki", 6, 3), (1, "く", "ク", "ku", 7, 1),
    (1, "け", "ケ", "ke", 8, 3), (1, "こ", "コ", "ko", 9, 2), (1, "さ", "サ", "sa", 10, 3), (1, "し", "シ", "shi", 11, 1),
    (1, "す", "ス", "su", 12, 1), (1, "せ", "セ", "se", 13, 3), (1, "そ", "ソ", "so", 14, 1), (1, "た", "タ", "ta", 15, 1),
    (1, "ち", "チ", "chi", 16, 3), (1, "つ", "ツ", "tsu", 17, 2), (1, "て", "テ", "te", 18, 1), (1, "と", "ト", "to", 19, 1),
    (1, "な", "ナ", "na", 20, 1), (1, "に", "ニ", "ni", 21, 2), (1, "ぬ", "ヌ", "nu", 22, 2), (1, "ね", "ネ", "ne", 23, 1),
    (1, "の", "ノ", "no", 24, 1), (1, "は", "ハ", "ha", 25, 3), (1, "ひ", "ヒ", "hi", 26, 1), (1, "ふ", "フ", "fu", 27, 3),
    (1, "へ", "ヘ", "he", 28, 1), (1, "ほ", "ホ", "ho", 29, 4), (1, "ま", "マ", "ma", 30, 3), (1, "み", "ミ", "mi", 31, 3),
    (1, "む", "ム", "mu", 32, 3), (1, "め", "メ", "me", 33, 3), (1, "も", "モ", "mo", 34, 4), (1, "や", "ヤ", "ya", 35, 3),
    (1, "ゆ", "ユ", "yu", 36, 2), (1, "よ", "ヨ", "yo", 37, 3), (1, "ら", "ラ", "ra", 38, 2), (1, "り", "リ", "ri", 39, 2),
    (1, "る", "ル", "ru", 40, 1), (1, "れ", "レ", "re", 41, 2), (1, "ろ", "ロ", "ro", 42, 1), (1, "わ", "ワ", "wa", 43, 1),
    (1, "ゐ", "ヰ", "wi", 44, 3), (1, "ゑ", "ヱ", "we", 45, 1), (1, "を", "ヲ", "wo", 46, 1), (1, "ん", "ン", "n", 47, 1),
    (3, "が", "ガ", "ga", 0, 4), (3, "ぎ", "ギ", "gi", 1, 4), (3, "ぐ", "グ", "gu", 2, 2), (3, "げ", "ゲ", "ge", 3, 4),
    (3, "ご", "ゴ", "go", 4, 3), (3, "ざ", "ザ", "za", 5, 4), (3, "じ", "ジ", "ji", 6, 4), (3, "ず", "ズ", "zu", 7, 2),
    (3, "ぜ", "ゼ", "ze", 8, 4), (3, "ぞ", "ゾ", "zo", 9, 2), (3, "だ", "ダ", "da", 10, 2), (3, "ぢ", "ヂ", "di", 11, 4),
    (3, "づ", "ヅ", "du", 12, 3), (3, "で", "デ", "de", 13, 2), (3, "ど", "ド", "do", 14, 2), (3, "ば", "バ", "ba", 15, 4),
    (3, "び", "ビ", "bi", 16, 4), (3, "ぶ", "ブ", "bu", 17, 4), (3, "べ", "ベ", "be", 18, 2), (3, "ぼ", "ボ", "bo", 19, 5),
    (4, "ぱ", "パ", "pa", 0, 5), (4, "ぴ", "ピ", "pi", 1, 5), (4, "ぷ", "プ", "pu", 2, 5), (4, "ぺ", "ペ", "pe", 3, 3),
    (4, "ぽ", "ポ", "po", 4, 6),
    (5, "きゃ", "キャ", "kya", 0, 4), (5, "きゅ", "キュ", "kyu", 1, 5), (5, "きょ", "キョ", "kyo", 2, 4),
    (5, "しゃ", "シャ", "sha", 3, 4), (5, "しゅ", "シュ", "shu", 4, 4), (5, "しょ", "ショ", "sho", 5, 4),
    (5, "ちゃ", "チャ", "cha", 6, 5), (5, "ちゅ", "チュ", "chu", 7, 5), (5, "ちょ", "チョ", "cho", 8, 5),
    (5, "にゃ", "ニャ", "nya", 9, 3), (5, "にゅ", "ニュ", "nyu", 10, 4), (5, "にょ", "ニョ", "nyo", 11, 3),
    (5, "ひゃ", "ヒャ", "hya", 12, 4), (5, "ひゅ", "ヒュ", "hyu", 13, 5), (5, "ひょ", "ヒョ", "hyo", 14, 4),
    (5, "みゃ", "ミャ", "mya", 15, 6), (5, "みゅ", "ミュ", "myu", 16, 7), (5, "みょ", "ミョ", "myo", 17, 6),
    (5, "りゃ", "リャ", "rya", 18, 3), (5, "りゅ", "リュ", "ryu", 19, 4), (5, "りょ", "リョ", "ryo", 20, 3),
    (5, "ぎゃ", "ギャ", "gya", 21, 5), (5, "ぎゅ", "ギュ", "gyu", 22, 6), (5, "ぎょ", "ギョ", "gyo", 23, 5),
    (5, "じゃ", "ジャ", "ja", 24, 5), (5, "じゅ", "ジュ", "ju", 25, 5), (5, "じょ", "ジョ", "jo", 26, 5),
    (5, "びゃ", "ビャ", "bya", 27, 5), (5, "びゅ", "ビュ", "byu", 28, 6), (5, "びょ", "ビョ", "byo", 29, 5),
    (5, "ぴゃ", "ピャ", "pya", 30, 6), (5, "ぴゅ", "ピュ", "pyu", 31, 7), (5, "ぴょ", "ピョ", "pyo", 32, 6),
]

# Generate SQL script that avoids encoding issues by NOT using special chars in SQL
sql_file = [
    "SET FOREIGN_KEY_CHECKS=0;",
    "DELETE FROM kana_characters;",
    "SET FOREIGN_KEY_CHECKS=1;",
]

for cat_id, hira, kata, roma, idx, stroke in kana_list:
    uid = str(uuid.uuid4())
    hira_esc = hira.replace("'", "''")
    kata_esc = kata.replace("'", "''")
    sql_file.append(f"INSERT INTO kana_characters (id, category_id, hiragana, katakana, romaji, order_index, stroke_count) VALUES ('{uid}', {cat_id}, {repr(hira)}, {repr(kata)}, '{roma}', {idx}, {stroke});")

with open('/tmp/insert_kana.sql', 'w', encoding='utf-8') as f:
    f.write('\n'.join(sql_file))

# Execute SQL
import subprocess
result = subprocess.run(['mysql', '-u', 'root', '-p6586156', 'japanese_learn'], 
                       stdin=open('/tmp/insert_kana.sql', 'r', encoding='utf-8'),
                       capture_output=True, text=True)

if result.returncode == 0:
    print("Successfully inserted Kana characters")
    result2 = subprocess.run(['mysql', '-u', 'root', '-p6586156', 'japanese_learn', '-e', 'SELECT COUNT(*) FROM kana_characters;'],
                            capture_output=True, text=True)
    print(result2.stdout)
else:
    print("Error:", result.stderr[:500])
