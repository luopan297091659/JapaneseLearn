import re

lines = open('temp_tanpun_import.sql', 'r', encoding='utf-8').readlines()
updates = []
for line in lines[1:]:
    m = re.match(r"\('([^']+)',\s*'([^']*)',\s*'([^']*)',\s*'([^']+)',", line.strip())
    if m:
        uid, title, title_zh, audio_url = m.groups()
        title_esc = title.replace("'", "''")
        title_zh_esc = title_zh.replace("'", "''")
        updates.append(f"UPDATE listening_tracks SET title='{title_esc}', title_zh='{title_zh_esc}' WHERE audio_url='{audio_url}';")

with open('temp_fix_titles.sql', 'w', encoding='utf-8') as f:
    f.write('\n'.join(updates) + '\n')
print(f'Generated {len(updates)} UPDATE statements')
