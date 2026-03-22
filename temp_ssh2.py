import subprocess, sys
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cat /tmp/jmdict_import.log'],
    capture_output=True, timeout=30
)
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'wb') as f:
    f.write(r.stdout)
    f.write(b'\n---STDERR---\n')
    f.write(r.stderr or b'none')
    f.write(f'\n---RETCODE: {r.returncode}---\n'.encode())
print(f"Written {len(r.stdout)} bytes to import_result.txt, retcode={r.returncode}")
