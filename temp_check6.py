import subprocess, json

urls = [
    'https://www3.nhk.or.jp/news/json/article/k10015075721000.json',
    'https://www3.nhk.or.jp/news/json/k10015075721000.json',
    'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.json',
    'https://www.nhk.or.jp/news/json/article/k10015075721000.json',
    'https://news.web.nhk.or.jp/api/v1/news/k10015075721000',
    'https://www3.nhk.or.jp/news/easy/k10015075721000/k10015075721000.html',
]

for url in urls:
    proc = subprocess.Popen(
        ['curl', '-sL', '-A', 'Mozilla/5.0', '-o', '/dev/null', '-w', '%{http_code} %{content_type} %{size_download}', url],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    out, _ = proc.communicate(timeout=15)
    print('{}: {}'.format(url.split('nhk.or.jp')[1][:60], out.decode('utf-8')))

# Try the NHK internal API pattern
for url in [
    'https://www3.nhk.or.jp/news/json/article/k10015075721000.json',
]:
    proc = subprocess.Popen(
        ['curl', '-sL', '-A', 'Mozilla/5.0', url],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    out, _ = proc.communicate(timeout=15)
    text = out.decode('utf-8')
    print('\n{}'.format(url.split('nhk.or.jp')[1]))
    print('  len:', len(text))
    print('  preview:', text[:500])
