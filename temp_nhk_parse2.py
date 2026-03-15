#!/usr/bin/env python3
import re, json

html = open('/tmp/nhk_full.html', 'r', encoding='utf-8').read()

# Extract and concatenate all __next_f data chunks
chunks = re.findall(r'self\.__next_f\.push\(\[1,(.*?)\]\)</script>', html)
full_data = ''
for c in chunks:
    try:
        val = json.loads(c)
        if isinstance(val, str):
            full_data += val
    except:
        pass

# Split by newlines and find the big chunk (line 4 with ~30K chars)
lines = full_data.split('\n')
for i, line in enumerate(lines):
    if len(line) > 5000:
        print(f'=== Line {i} (len={len(line)}) ===')
        # Look for the article body text segments
        # In RSC format, text is embedded as $children or direct strings
        # Find long Japanese text segments
        jp_segs = re.findall(r'[\u3000-\u9fff\u30a0-\u30ff\u3040-\u309f\uff01-\uff9f、。！？「」『』（）・ー々〇〻\u200b\s]{30,}', line)
        print(f'  JP segments > 30 chars: {len(jp_segs)}')
        for j, seg in enumerate(jp_segs[:20]):
            seg_clean = seg.strip()
            if len(seg_clean) > 20:
                print(f'  [{j}] ({len(seg_clean)}) {seg_clean[:150]}')
        
        # Also look for "body" or "text" or "detail" or paragraph markers
        body_m = re.findall(r'body_html|content_html|detail_html|module--body|content--body|article_body|module--detail-main', line)
        if body_m:
            print(f'  Body markers: {body_m}')
        
        # Find the api URL
        api_urls = re.findall(r'https?://[^\s"\\,\]]+\.json[^\s"\\,\]]*', line)
        for u in api_urls:
            print(f'  API URL: {u}')

print('\n=== Looking for paragraph-like structures ===')
# In RSC, content is typically: ["$","p",null,{"children":"text..."}]
# or: ["$","div",null,{"className":"...","children":...}]
p_content = re.findall(r'\["\$","p",[^,]*,\{[^}]*"children"\s*:\s*"([^"]{20,})"', full_data)
print(f'<p> children text: {len(p_content)}')
for i, p in enumerate(p_content[:15]):
    print(f'  [{i}] ({len(p)}) {p[:150]}')

# Also try div with content
div_content = re.findall(r'module--content[^"]*"[^}]*children.*?"([^"]{30,})"', full_data)
print(f'\nDiv content: {len(div_content)}')
for i, d in enumerate(div_content[:10]):
    print(f'  [{i}] ({len(d)}) {d[:150]}')

# Try a broader search for the biggest text nodes
text_nodes = re.findall(r'"children"\s*:\s*"([\u3000-\u9fff\u30a0-\u30ff\u3040-\u309f\uff01-\uff9f、。！？「」『』（）・ー々\s]{15,})"', full_data)
print(f'\nJP text nodes (children): {len(text_nodes)}')
for i, t in enumerate(text_nodes[:20]):
    print(f'  [{i}] ({len(t)}) {t[:150]}')
