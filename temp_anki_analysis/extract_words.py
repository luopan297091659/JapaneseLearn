import sqlite3
import json

conn = sqlite3.connect('collection.anki2')
c = conn.cursor()

# Get all notes
c.execute('SELECT mid, flds, tags FROM notes ORDER BY id')
notes = c.fetchall()

# Get model info
c.execute('SELECT models FROM col')
models = json.loads(c.fetchone()[0])

words = []
for mid, flds, tags in notes:
    fields = flds.split('\x1f')
    model = models.get(str(mid), {})
    field_names = [f['name'] for f in model.get('flds', [])]
    
    if len(fields) >= 3:
        # Model "3 fields": Front=word, Mid=reading, Back=meaning_en
        # Model "Japanese to English": Expression=word, Reading=reading, English=meaning_en
        word = fields[0].strip()
        reading = fields[1].strip()
        meaning_en = fields[2].strip()
    elif len(fields) >= 2:
        word = fields[0].strip()
        reading = ''
        meaning_en = fields[1].strip()
    else:
        continue
    
    # Clean HTML tags if any
    import re
    word = re.sub(r'<[^>]+>', '', word).strip()
    reading = re.sub(r'<[^>]+>', '', reading).strip()
    meaning_en = re.sub(r'<[^>]+>', '', meaning_en).strip()
    
    if word:
        words.append({
            'word': word,
            'reading': reading,
            'meaning_en': meaning_en,
            'tags': tags.strip()
        })

conn.close()

# Save to JSON
with open('n4_words_raw.json', 'w', encoding='utf-8') as f:
    json.dump(words, f, ensure_ascii=False, indent=2)

print(f'Total words extracted: {len(words)}')
print(f'\nFirst 20 words:')
for w in words[:20]:
    print(f'  {w["word"]} ({w["reading"]}) - {w["meaning_en"]}')

print(f'\nLast 5 words:')
for w in words[-5:]:
    print(f'  {w["word"]} ({w["reading"]}) - {w["meaning_en"]}')

# Check for potential issues
no_reading = [w for w in words if not w['reading']]
print(f'\nWords without reading: {len(no_reading)}')
if no_reading:
    for w in no_reading[:5]:
        print(f'  {w["word"]} - {w["meaning_en"]}')
