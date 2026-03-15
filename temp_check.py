import json
f = open('/tmp/nhk_test.json')
d = json.load(f)
a = d['data'][0]
print('id:', a['id'])
print('body_len:', len(a.get('body', '')))
print('body_first500:', a.get('body', '')[:500])
