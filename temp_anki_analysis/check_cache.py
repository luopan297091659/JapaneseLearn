import json
c = json.load(open('translation_cache.json', 'r', encoding='utf-8'))
print(f"Meanings cached: {len(c.get('meanings', {}))}")
print(f"Examples cached: {len(c.get('examples', {}))}")
