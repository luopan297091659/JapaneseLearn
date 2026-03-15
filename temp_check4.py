import subprocess, re, json

proc = subprocess.Popen(
    ['curl', '-sL', '-A', 'Mozilla/5.0', 'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
out, _ = proc.communicate(timeout=30)
html = out.decode('utf-8')

# Look for embedded JSON data (__NEXT_DATA__, etc.)
patterns = [
    ('__NEXT_DATA__', r'<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>'),
    ('window.__data', r'window\.__data\s*=\s*(\{[\s\S]*?\});'),
    ('window.__INITIAL', r'window\.__INITIAL[^=]*=\s*(\{[\s\S]*?\});'),
    ('articleBody', r'"articleBody"\s*:\s*"([^"]*)"'),
    ('text content', r'"text"\s*:\s*"([^"]{50,})"'),
    ('description json', r'"description"\s*:\s*"([^"]{50,})"'),
]

for name, pat in patterns:
    matches = re.findall(pat, html)
    print('{}: {} matches'.format(name, len(matches)))
    for i, m in enumerate(matches[:2]):
        print('  [{}]: {}...'.format(i, m[:300]))

# Check for <section> tags
sections = re.findall(r'<section[^>]*>([\s\S]*?)</section>', html, re.IGNORECASE)
print('\n<section> tags: {}'.format(len(sections)))
for i, s in enumerate(sections):
    text = re.sub(r'<[^>]+>', '', s).strip()
    if len(text) > 20:
        print('  section[{}] ({} chars): {}...'.format(i, len(text), text[:200]))

# Check for <article> tags
articles = re.findall(r'<article[^>]*>([\s\S]*?)</article>', html, re.IGNORECASE)
print('\n<article> tags: {}'.format(len(articles)))
for i, a in enumerate(articles):
    text = re.sub(r'<[^>]+>', '', a).strip()
    if len(text) > 20:
        print('  article[{}] ({} chars): {}...'.format(i, len(text), text[:200]))

# Look for class names containing "body" or "content" or "detail" or "main"
class_matches = re.findall(r'class="([^"]*(?:body|content|detail|main|article)[^"]*)"', html, re.IGNORECASE)
print('\nRelevant CSS classes:')
for c in sorted(set(class_matches)):
    print('  {}'.format(c[:100]))
