import subprocess, re, json

proc = subprocess.Popen(
    ['curl', '-sL', '-A', 'Mozilla/5.0', 'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html'],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
out, _ = proc.communicate(timeout=30)
html = out.decode('utf-8')

# Extract all JSON-LD blocks
ld_regex = re.compile(r'<script[^>]*type="application/ld\+json"[^>]*>([\s\S]*?)</script>', re.IGNORECASE)
ld_matches = ld_regex.findall(html)
print('JSON-LD blocks: {}'.format(len(ld_matches)))
for i, ld in enumerate(ld_matches):
    try:
        obj = json.loads(ld)
        print('\n=== LD Block {} ==='.format(i))
        print('type:', obj.get('@type', 'unknown'))
        if obj.get('@type') == 'NewsArticle':
            print('headline:', obj.get('headline', '')[:100])
            desc = obj.get('description', '')
            print('description length:', len(desc))
            print('description:', desc[:500])
            print('...')
            print('description end:', desc[-200:])
            ab = obj.get('articleBody', '')
            print('articleBody length:', len(ab))
            print('articleBody:', ab[:500])
        else:
            keys = list(obj.keys())
            print('keys:', keys[:10])
    except Exception as e:
        print('Parse error:', e)
        print('Raw:', ld[:200])

# Also check meta description
meta = re.findall(r'<meta\s+name="description"\s+content="([^"]*)"', html, re.IGNORECASE)
print('\n=== Meta description ===')
for m in meta:
    print('len:', len(m))
    print('content:', m[:300])

# Check og:description
og = re.findall(r'<meta\s+property="og:description"\s+content="([^"]*)"', html, re.IGNORECASE)
print('\n=== OG description ===')
for m in og:
    print('len:', len(m))
    print('content:', m[:300])
