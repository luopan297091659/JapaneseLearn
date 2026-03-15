#!/usr/bin/env python3
import re, json, sys

html = open('/tmp/nhk_full.html', 'r', encoding='utf-8').read()

# Extract all __next_f data chunks
chunks = re.findall(r'self\.__next_f\.push\(\[1,(.*?)\]\)</script>', html)
print(f'Total chunks: {len(chunks)}')

# Concatenate all chunk values
full_data = ''
for c in chunks:
    try:
        val = json.loads(c)
        if isinstance(val, str):
            full_data += val
    except:
        pass

print(f'Total data length: {len(full_data)}')

# Find Japanese text blocks (article paragraphs)
jp_blocks = re.findall(r'[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff\u3000-\u303f\uff01-\uff9f、。！？「」『』（）・ー\d\w]{20,}', full_data)
print(f'\nJapanese text blocks (>20 chars): {len(jp_blocks)}')
for i, b in enumerate(jp_blocks[:15]):
    print(f'  [{i}] ({len(b)}) {b[:100]}')

# Look for HTML-like content with article body
body_patterns = [
    r'"body"\s*:\s*"([^"]{50,})"',
    r'"content"\s*:\s*"([^"]{50,})"', 
    r'"text"\s*:\s*"([^"]{50,})"',
    r'"articleBody"\s*:\s*"([^"]{50,})"',
    r'"detail"\s*:\s*"([^"]{50,})"',
]
for pat in body_patterns:
    matches = re.findall(pat, full_data)
    if matches:
        print(f'\nPattern {pat}:')
        for m in matches[:3]:
            print(f'  ({len(m)}) {m[:150]}')

# Check for p tags with content
p_tags = re.findall(r'<p[^>]*>([\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff].*?)</p>', full_data)
if p_tags:
    print(f'\n<p> tags with Japanese: {len(p_tags)}')
    for p in p_tags[:10]:
        print(f'  ({len(p)}) {p[:100]}')

# Look for content_detail or similar patterns in RSC format
# RSC uses $L prefix for references and T: for text nodes
detail_match = re.findall(r'content[-_]?detail|article[-_]?body|news[-_]?body|module--content', full_data, re.I)
print(f'\nContent markers found: {detail_match[:10]}')

# Search for large text segments that look like news content  
# In RSC, text is usually between delimiters
lines = full_data.split('\\n')
long_jp_lines = [(i, l) for i, l in enumerate(lines) if len(l) > 30 and re.search(r'[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]{5,}', l)]
print(f'\nLong JP lines: {len(long_jp_lines)}')
for idx, (i, l) in enumerate(long_jp_lines[:10]):
    print(f'  line {i}: ({len(l)}) {l[:120]}')
