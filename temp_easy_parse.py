#!/usr/bin/env python3
import re, json

html = open('/tmp/easy_page.html', 'r', encoding='utf-8').read()
print(f'HTML length: {len(html)}')

# Check for __next_f data
chunks = re.findall(r'self\.__next_f\.push\(\[1,(.*?)\]\)</script>', html)
full_data = ''
for c in chunks:
    try:
        val = json.loads(c)
        if isinstance(val, str):
            full_data += val
    except:
        pass

print(f'RSC data length: {len(full_data)}')

# Find article IDs (easy news format: k followed by digits)
easy_ids = re.findall(r'k\d{12,}', full_data)
unique_ids = list(set(easy_ids))
print(f'Easy news IDs found: {len(unique_ids)}')
for eid in unique_ids[:10]:
    print(f'  {eid}')

# Find article URLs
easy_urls = re.findall(r'easy/[a-z]\d+', full_data)
print(f'\nEasy URLs: {list(set(easy_urls))[:10]}')

# Find titles and IDs
# RSC format likely has news_id and title fields
news_ids = re.findall(r'"identifier"\s*:\s*"([^"]+)"', full_data)
print(f'\nIdentifiers: {news_ids[:10]}')

# Find easy article links
links = re.findall(r'href["\s:]*"?(/news/easy/[^"\\,\s]+)', full_data)
print(f'\nEasy links: {list(set(links))[:10]}')

# Look for any article content
titles = re.findall(r'"children"\s*:\s*"([\u3040-\u9fff][\u3000-\u9fff\u30a0-\u30ff\u3040-\u309f]{5,})"', full_data)
print(f'\nJP children text: {len(titles)}')
for t in titles[:10]:
    print(f'  ({len(t)}) {t[:80]}')

# Look for easy-specific identifiers
easy_refs = re.findall(r'ne-[a-z]\d+', full_data)
print(f'\nEasy refs (ne-): {list(set(easy_refs))[:10]}')
