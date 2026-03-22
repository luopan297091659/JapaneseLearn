import subprocess

# Run import in background via nohup on the server
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cd /home/japanese-learn/backend && nohup node scripts/import_jmdict.js /tmp/JMdict.gz > /tmp/jmdict_import.log 2>&1 & echo PID=$!'],
    capture_output=True, timeout=30
)
print(r.stdout.decode('utf-8','replace'))
print(f'Retcode: {r.returncode}')
