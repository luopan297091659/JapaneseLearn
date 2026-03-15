import subprocess, time

# Run import directly, wait up to 10 minutes
print("Starting import...")
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cd /home/japanese-learn/backend && timeout 300 node scripts/import_jmdict.js /tmp/JMdict.gz 2>&1; echo EXIT=$?'],
    capture_output=True, timeout=360
)
out = r.stdout.decode('utf-8', 'replace')
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'w', encoding='utf-8') as f:
    f.write(out)
# Print last 2000 chars
print(f"Total output: {len(out)} bytes")
print("Last 2000 chars:")
print(out[-2000:])
print(f"\nRetcode: {r.returncode}")
