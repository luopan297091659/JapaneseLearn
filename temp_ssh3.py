import subprocess
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cd /home/japanese-learn/backend && npm ls sax 2>&1 && node -e "require(\'sax\'); console.log(\'SAX OK\')" 2>&1'],
    capture_output=True, timeout=30
)
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'wb') as f:
    f.write(r.stdout)
    f.write(b'\n---STDERR---\n')
    f.write(r.stderr or b'none')
print(r.stdout.decode('utf-8','replace'))
