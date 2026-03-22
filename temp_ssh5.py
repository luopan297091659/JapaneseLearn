import subprocess
# Check if JMdict JSON format is available and try downloading it
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     # Strip DOCTYPE from JMdict to make SAX work, or download jmdict-simplified JSON
     r"""cd /tmp && wget -q 'https://github.com/scriptin/jmdict-simplified/releases/download/3.6.1%2B20250228133515/jmdict-all-3.6.1+20250228133515.json.tgz' -O jmdict.json.tgz 2>&1 && ls -la jmdict.json.tgz && echo '---DOWNLOAD OK---' || echo '---DOWNLOAD FAILED---'"""],
    capture_output=True, timeout=120
)
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'wb') as f:
    f.write(r.stdout)
    f.write(b'\n---STDERR---\n')
    f.write(r.stderr or b'none')
print(r.stdout.decode('utf-8','replace'))
