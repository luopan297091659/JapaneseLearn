import json, subprocess, sys, re

# Fetch article
proc = subprocess.Popen(
    ['curl', '-sk', 'https://localhost:8002/api/v1/news/nhk/20260314-k10015075721000'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
out, _ = proc.communicate()
d = json.loads(out.decode('utf-8'))
print('=== Article API Response ===')
print('title:', d.get('title', '')[:100])
print('desc:', d.get('description', '')[:200])
print('body_len:', len(d.get('body', '')))
print('body_preview:', d.get('body', '')[:500])
print()

# Also fetch actual NHK page HTML to see structure
proc2 = subprocess.Popen(
    ['curl', '-sL', '-A', 'Mozilla/5.0', 'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
out2, _ = proc2.communicate(timeout=30)
html = out2.decode('utf-8')
print('=== NHK HTML length:', len(html))

# Find content sections
for pattern_name, pattern in [
    ('content--detail-body', r'class="[^"]*content--detail-body[^"]*"'),
    ('content--detail', r'class="content--detail[^"]*"'),
    ('module--detail', r'class="module--detail[^"]*"'),
    ('article-body', r'class="[^"]*article-body[^"]*"'),
    ('news_add', r'id="news_add"'),
    ('body-text', r'class="[^"]*body-text[^"]*"'),
    ('detail-body', r'class="[^"]*detail.body[^"]*"'),
]:
    matches = re.findall(pattern, html, re.IGNORECASE)
    print('{}: {} matches'.format(pattern_name, len(matches)))
    for i, m in enumerate(matches[:3]):
        print('  [{}]: {}'.format(i, m[:200]))

# Show all p tags
p_tags = re.findall(r'<p[^>]*>([\s\S]*?)</p>', html, re.IGNORECASE)
print('\nAll <p> tags: {}'.format(len(p_tags)))
for i, p in enumerate(p_tags):
    text = re.sub(r'<[^>]+>', '', p).strip()
    if len(text) > 5:
        print('  p[{}] ({} chars): {}'.format(i, len(text), text[:150]))
