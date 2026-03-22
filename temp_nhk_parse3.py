#!/usr/bin/env python3
import re, json

html = open('/tmp/nhk_full.html', 'r', encoding='utf-8').read()

# Extract chunks
chunks = re.findall(r'self\.__next_f\.push\(\[1,(.*?)\]\)</script>', html)
full_data = ''
for c in chunks:
    try:
        val = json.loads(c)
        if isinstance(val, str):
            full_data += val
    except:
        pass

# Find the segment with the article API URL (biggest data chunk)
idx = full_data.find('newsarticle/na/na-k100150757')
if idx < 0:
    idx = full_data.find('k10015075721000')
print(f'Found at index: {idx}')

if idx > 0:
    # Print surrounding 2000 chars
    start = max(0, idx - 500)
    end = min(len(full_data), idx + 3000)
    chunk = full_data[start:end]
    print(f'\n=== Context around article ref ({start}-{end}) ===')
    print(chunk[:4000])

# Also look for the body/html structure - RSC uses T: prefix for text
# and $L references. Let me look for content module div patterns
print('\n\n=== Searching for content module patterns ===')
# module--content-main, content--detail-body, etc
for pat in ['module--content', 'content--detail', 'detail-body', 'body_text', 'content-text', 'article-text', 'bodyText']:
    idx2 = full_data.find(pat)
    if idx2 > -1:
        print(f'\nFound "{pat}" at {idx2}:')
        print(full_data[idx2:idx2+500])

# Search for class names that look like article body containers
class_names = re.findall(r'"className"\s*:\s*"([^"]*(?:body|content|article|detail|text|main)[^"]*)"', full_data, re.I)
print(f'\n=== Class names with body/content/article: {len(class_names)} ===')
for cn in class_names[:30]:
    print(f'  {cn}')

# Look for dangerouslySetInnerHTML (common for rendered article content)
inner_html = re.findall(r'dangerouslySetInnerHTML.*?"__html"\s*:\s*"([^"]{30,})"', full_data)
print(f'\n=== dangerouslySetInnerHTML: {len(inner_html)} ===')
for ih in inner_html[:5]:
    print(f'  ({len(ih)}) {ih[:300]}')
