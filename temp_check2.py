import json, subprocess, sys

# Fetch article
result = subprocess.run(
    ['curl', '-sk', 'https://localhost:8002/api/v1/news/nhk/20260314-k10015075721000'],
    capture_output=True, text=True
)
d = json.loads(result.stdout)
print('=== Article API Response ===')
print('title:', d.get('title', '')[:100])
print('desc:', d.get('description', '')[:200])
print('body_len:', len(d.get('body', '')))
print('body_preview:', d.get('body', '')[:500])
print()

# Also fetch actual NHK page HTML to see structure
result2 = subprocess.run(
    ['curl', '-sL', '-A', 'Mozilla/5.0', 'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html'],
    capture_output=True, text=True, timeout=30
)
html = result2.stdout
print('=== NHK HTML length:', len(html))

# Find content sections
import re
# Look for article body patterns
for pattern_name, pattern in [
    ('content--detail-body', r'<div[^>]*class="[^"]*content--detail-body[^"]*"[^>]*>([\s\S]*?)</div>'),
    ('article-body', r'<div[^>]*class="[^"]*article-body[^"]*"[^>]*>([\s\S]*?)</div>'),
    ('news_add', r'<div[^>]*id="news_add"[^>]*>([\s\S]*?)</div>'),
    ('p tags >10 chars', r'<p[^>]*>([^<]{10,})</p>'),
    ('content--detail', r'class="content--detail[^"]*"'),
    ('module--detail', r'class="module--detail[^"]*"'),
]:
    matches = re.findall(pattern, html, re.IGNORECASE)
    print(f'{pattern_name}: {len(matches)} matches')
    if matches:
        for i, m in enumerate(matches[:3]):
            print(f'  [{i}]: {m[:200]}')

# Show all p tags
p_tags = re.findall(r'<p[^>]*>([\s\S]*?)</p>', html, re.IGNORECASE)
print(f'\nAll <p> tags: {len(p_tags)}')
for i, p in enumerate(p_tags):
    text = re.sub(r'<[^>]+>', '', p).strip()
    if len(text) > 5:
        print(f'  p[{i}] ({len(text)} chars): {text[:150]}')
