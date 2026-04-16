import sqlite3, json

conn = sqlite3.connect('collection.anki2')
c = conn.cursor()

# Tables
tables = c.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
print('Tables:', [t[0] for t in tables])
print()

# Models
c.execute('SELECT models FROM col')
row = c.fetchone()
models = json.loads(row[0])
print('Models:')
for k, v in models.items():
    fields = [f['name'] for f in v['flds']]
    print(f'  ID={k}, name={v["name"]}, fields={fields}')
print()

# Count
c.execute('SELECT COUNT(*) FROM notes')
print(f'Total notes: {c.fetchone()[0]}')
c.execute('SELECT COUNT(*) FROM cards')
print(f'Total cards: {c.fetchone()[0]}')
print()

# Sample notes
c.execute('SELECT id, mid, flds FROM notes LIMIT 15')
notes = c.fetchall()
print('Sample notes (first 15):')
for n in notes:
    fields = n[2].split('\x1f')
    print(f'  mid={n[1]}, fields={fields}')

print()

# Check all unique mids
c.execute('SELECT DISTINCT mid FROM notes')
mids = c.fetchall()
print(f'Unique model IDs in notes: {[m[0] for m in mids]}')

# Tags
c.execute('SELECT DISTINCT tags FROM notes LIMIT 20')
tags = c.fetchall()
print(f'Tags: {[t[0].strip() for t in tags]}')

conn.close()
