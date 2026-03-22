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

# Find from after the article metadata (after "tags" marker at ~78880)
# Look for any remaining data that might contain body text
idx = full_data.find('rawHtmlFlg')
if idx > 0:
    print(f'rawHtmlFlg at: {idx}')
    # Print 5000 chars after it
    after = full_data[idx:idx+8000]
    print(after[:5000])
    
print('\n\n=== CHECKING FOR BODY HTML ===')
# Look for HTML p tags in the full data
p_tags = re.findall(r'\\u003cp[^\\]*\\u003e(.*?)\\u003c/p\\u003e', full_data)
print(f'Unicode-escaped <p> tags: {len(p_tags)}')
for p in p_tags[:10]:
    print(f'  ({len(p)}) {p[:200]}')

# Also try <p> directly
p_direct = re.findall(r'<p[^>]*>([^<]{20,})</p>', full_data)
print(f'\nDirect <p> tags: {len(p_direct)}')
for p in p_direct[:10]:
    print(f'  ({len(p)}) {p[:200]}')

# Look for u003c (HTML entities in JSON)
u003c_content = re.findall(r'\\u003cp\\u003e(.*?)\\u003c/p\\u003e', full_data)
print(f'\nu003c <p> tags: {len(u003c_content)}')  
for p in u003c_content[:10]:
    print(f'  ({len(p)}) {p[:200]}')

# Check for body HTML block - some RSC apps put it as a large string
# Look for any block > 200 chars that looks like HTML
html_blocks = re.findall(r'"([^"]{200,})"', full_data)
print(f'\nLarge string values: {len(html_blocks)}')
for h in html_blocks:
    if re.search(r'[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]{10,}', h):
        print(f'  JP block ({len(h)}): {h[:200]}')
