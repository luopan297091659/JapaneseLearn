#!/usr/bin/env python3
import re
# Compare RSS description vs JSON-LD description lengths
import urllib.request as ur
# Fetch RSS
req = ur.Request('https://www3.nhk.or.jp/rss/news/cat0.xml', headers={'User-Agent':'Mozilla/5.0'})
rss = ur.urlopen(req, timeout=15).read().decode('utf-8')

# Parse RSS items
rss_items = re.findall(r'<item>(.*?)</item>', rss, re.S)
print(f'RSS articles: {len(rss_items)}')

for i, item in enumerate(rss_items[:5]):
    title = (re.search(r'<title>(.*?)</title>', item) or ['',''])[1].strip()
    link = (re.search(r'<link>(.*?)</link>', item) or ['',''])[1].strip()
    desc = (re.search(r'<description>(.*?)</description>', item, re.S) or ['',''])[1].strip()
    
    print(f'\n=== Article {i} ===')
    print(f'Title ({len(title)}): {title[:60]}')
    print(f'RSS desc ({len(desc)}): {desc[:200]}')
    
    # Fetch article HTML for JSON-LD description
    try:
        req2 = ur.Request(link.replace('http://', 'https://'), headers={'User-Agent':'Mozilla/5.0'})
        html = ur.urlopen(req2, timeout=15).read().decode('utf-8')
        
        # JSON-LD
        ld_match = re.search(r'"@type"\s*:\s*"NewsArticle".*?"description"\s*:\s*"([^"]+)"', html, re.S)
        ld_desc = ld_match.group(1) if ld_match else ''
        print(f'JSON-LD desc ({len(ld_desc)}): {ld_desc[:200]}')
        
        # Meta description
        meta_match = re.search(r'<meta\s+name="description"\s+content="([^"]*)"', html, re.I)
        meta_desc = meta_match.group(1) if meta_match else ''
        print(f'Meta desc ({len(meta_desc)}): {meta_desc[:200]}')
        
    except Exception as e:
        print(f'Fetch error: {e}')
