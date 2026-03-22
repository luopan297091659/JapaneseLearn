import subprocess

# Upload updated import script
r1 = subprocess.run(
    ['pscp', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     r'd:\PROJECT\JapaneseLearn\backend\scripts\import_jmdict.js',
     'root@139.196.44.6:/home/japanese-learn/backend/scripts/import_jmdict.js'],
    capture_output=True, timeout=30
)
print('Upload:', 'OK' if r1.returncode == 0 else 'FAILED')
print(r1.stdout.decode('utf-8','replace'))

# Run import
print('\n--- Running import ---')
r2 = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cd /home/japanese-learn/backend && node scripts/import_jmdict.js /tmp/JMdict.gz 2>&1'],
    capture_output=True, timeout=600
)
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'wb') as f:
    f.write(r2.stdout)
print(r2.stdout.decode('utf-8','replace'))
print(f'\nReturn code: {r2.returncode}')
