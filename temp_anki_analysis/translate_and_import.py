"""
N4 单词翻译 + 例句生成 + SQL 导入脚本 (带断点续传)
"""
import json
import re
import time
import uuid
import os
import random
from deep_translator import GoogleTranslator

CACHE_FILE = 'translation_cache.json'
WORDS_FILE = 'n4_words_raw.json'

# ── 读取原始数据 ──
with open(WORDS_FILE, 'r', encoding='utf-8') as f:
    words = json.load(f)

print(f'Total words: {len(words)}')

# ── 读取缓存 ──
cache = {}
if os.path.exists(CACHE_FILE):
    with open(CACHE_FILE, 'r', encoding='utf-8') as f:
        cache = json.load(f)
    print(f'Loaded cache: {len(cache.get("meanings", {}))} meanings, {len(cache.get("examples", {}))} examples')

if 'meanings' not in cache:
    cache['meanings'] = {}
if 'examples' not in cache:
    cache['examples'] = {}

def save_cache():
    with open(CACHE_FILE, 'w', encoding='utf-8') as f:
        json.dump(cache, f, ensure_ascii=False, indent=2)

# ── 词性推断 ──
def guess_pos(meaning_en, word, reading):
    m = meaning_en.lower().strip()
    m_clean = re.sub(r'\(\d+\)\s*', '', m)
    m_clean = re.sub(r'\([a-z]{1,4}\)\s*', '', m_clean)
    
    if '（する）' in word or '(する)' in word:
        return 'verb'
    if m_clean.startswith('to ') or ', to ' in m_clean:
        return 'verb'
    if '（な）' in word or '(な)' in word:
        return 'adjective'
    if word.endswith('い') and len(word) >= 2:
        kana = reading if reading else word
        if kana.endswith('い'):
            return 'adjective'
    if re.search(r'\b(adverb)\b', m_clean):
        return 'adverb'
    if 'particle' in m_clean:
        return 'particle'
    if 'conjunction' in m_clean:
        return 'conjunction'
    if 'interjection' in m_clean or 'exclamation' in m_clean:
        return 'interjection'
    return 'noun'

# ── 翻译英文释义 ──
translator_en = GoogleTranslator(source='en', target='zh-CN')

print('\n── Phase 1: Translate English meanings ──')
meanings_to_translate = []
for i, w in enumerate(words):
    key = f"{w['word']}|{w['meaning_en'][:80]}"
    if key not in cache['meanings']:
        m = w['meaning_en']
        m = re.sub(r'\(\d+\)\s*', '', m)
        m = re.sub(r'\([a-z]{1,4}\)\s*', '', m)
        if len(m) > 100:
            m = ', '.join(m.split(',')[:3])
        meanings_to_translate.append((i, key, m.strip()))

print(f'  Need to translate: {len(meanings_to_translate)} (cached: {len(words) - len(meanings_to_translate)})')

for idx, (i, key, text) in enumerate(meanings_to_translate):
    for attempt in range(3):
        try:
            result = translator_en.translate(text)
            cache['meanings'][key] = result if result else text
            break
        except Exception as e:
            if attempt < 2:
                time.sleep(2)
            else:
                print(f'  Error [{i}] "{text[:40]}": {e}')
                cache['meanings'][key] = text
    
    if (idx + 1) % 30 == 0:
        save_cache()
        print(f'  Translated {idx + 1}/{len(meanings_to_translate)}...')
        time.sleep(0.3)

save_cache()
print(f'  All meanings translated.')

# ── 生成例句 ──
random.seed(42)

print('\n── Phase 2: Generate and translate example sentences ──')

def make_example(word, reading, pos):
    clean = re.sub(r'[（(][^）)]*[）)]', '', word).strip()
    if pos == 'verb':
        templates = [
            f'{clean}ことができます。',
            f'毎日{clean}ようにしています。',
            f'友達と一緒に{clean}。',
        ]
    elif pos == 'adjective':
        if clean.endswith('い'):
            templates = [
                f'この部屋はとても{clean}です。',
                f'今日の天気は{clean}ですね。',
                f'日本語の勉強は{clean}です。',
            ]
        else:
            templates = [
                f'この場所はとても{clean}です。',
                f'彼女はとても{clean}な人です。',
                f'この問題は{clean}です。',
            ]
    elif pos == 'adverb':
        templates = [
            f'{clean}歩いてください。',
            f'{clean}話してください。',
            f'{clean}考えましょう。',
        ]
    else:
        templates = [
            f'{clean}はとても大切です。',
            f'この{clean}はいいですね。',
            f'{clean}について勉強しています。',
        ]
    return random.choice(templates)

translator_ja = GoogleTranslator(source='ja', target='zh-CN')

examples_to_translate = []
example_sentences = {}
for i, w in enumerate(words):
    pos = guess_pos(w['meaning_en'], w['word'], w['reading'])
    ex = make_example(w['word'], w['reading'], pos)
    example_sentences[i] = ex
    key = ex
    if key not in cache['examples']:
        examples_to_translate.append((i, key, ex))

print(f'  Need to translate: {len(examples_to_translate)} examples (cached: {len(words) - len(examples_to_translate)})')

for idx, (i, key, text) in enumerate(examples_to_translate):
    for attempt in range(3):
        try:
            translator_ja2 = GoogleTranslator(source='ja', target='zh-CN')
            result = translator_ja2.translate(text)
            cache['examples'][key] = result if result else ''
            break
        except Exception as e:
            if attempt < 2:
                time.sleep(3 + attempt * 2)
            else:
                print(f'  Error [{i}] "{text[:40]}": {e}')
                cache['examples'][key] = ''
    
    if (idx + 1) % 20 == 0:
        save_cache()
        print(f'  Translated {idx + 1}/{len(examples_to_translate)} examples...')
        time.sleep(1)

save_cache()
print(f'  All examples translated.')

# ── 生成 SQL ──
print('\n── Phase 3: Generate SQL ──')

def sql_escape(s):
    if s is None:
        return 'NULL'
    s = str(s).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{s}'"

sql_lines = []
sql_lines.append('-- N4 Vocabulary Import from JLPT N4 Anki Deck')
sql_lines.append(f'-- Generated: {time.strftime("%Y-%m-%d %H:%M:%S")}')
sql_lines.append(f'-- Total words: {len(words)}')
sql_lines.append('')

batch_size = 50
for batch_start in range(0, len(words), batch_size):
    batch_end = min(batch_start + batch_size, len(words))
    sql_lines.append(f'-- Batch {batch_start//batch_size + 1}')
    sql_lines.append('INSERT IGNORE INTO vocabulary (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level, example_sentence, example_reading, example_meaning_zh, audio_url, image_url, category, tags) VALUES')
    
    values = []
    for i in range(batch_start, batch_end):
        w = words[i]
        pos = guess_pos(w['meaning_en'], w['word'], w['reading'])
        uid = str(uuid.uuid4())
        
        word = w['word'].strip()
        reading = w['reading'].strip()
        
        meaning_key = f"{w['word']}|{w['meaning_en'][:80]}"
        meaning_zh = cache['meanings'].get(meaning_key, '')
        meaning_en = w['meaning_en'].strip()
        
        ex_sentence = example_sentences.get(i, '')
        ex_meaning = cache['examples'].get(ex_sentence, '')
        
        row = f"({sql_escape(uid)}, {sql_escape(word)}, {sql_escape(reading)}, {sql_escape(meaning_zh)}, {sql_escape(meaning_en)}, {sql_escape(pos)}, 'N4', {sql_escape(ex_sentence)}, NULL, {sql_escape(ex_meaning)}, NULL, NULL, NULL, NULL)"
        values.append(row)
    
    sql_lines.append(',\n'.join(values) + ';')
    sql_lines.append('')

with open('import_n4.sql', 'w', encoding='utf-8') as f:
    f.write('\n'.join(sql_lines))

# ── 保存处理结果 ──
processed = []
for i, w in enumerate(words):
    pos = guess_pos(w['meaning_en'], w['word'], w['reading'])
    meaning_key = f"{w['word']}|{w['meaning_en'][:80]}"
    ex = example_sentences.get(i, '')
    processed.append({
        'word': w['word'],
        'reading': w['reading'],
        'meaning_en': w['meaning_en'],
        'meaning_zh': cache['meanings'].get(meaning_key, ''),
        'part_of_speech': pos,
        'example_sentence': ex,
        'example_meaning_zh': cache['examples'].get(ex, ''),
    })

with open('n4_words_processed.json', 'w', encoding='utf-8') as f:
    json.dump(processed, f, ensure_ascii=False, indent=2)

print(f'\nDone! Generated import_n4.sql ({len(words)} words)')
print(f'\nSample:')
for p in processed[:15]:
    print(f'  {p["word"]} ({p["reading"]})')
    print(f'    中文: {p["meaning_zh"]}')
    print(f'    例句: {p["example_sentence"]}')
    print(f'    译文: {p["example_meaning_zh"]}')

pos_counts = {}
for p in processed:
    pos_counts[p['part_of_speech']] = pos_counts.get(p['part_of_speech'], 0) + 1
print(f'\n词性分布:')
for k, v in sorted(pos_counts.items(), key=lambda x: -x[1]):
    print(f'  {k}: {v}')
