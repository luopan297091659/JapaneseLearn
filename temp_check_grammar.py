import subprocess, json

result = subprocess.run(
    ['plink', '-batch', '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', 'root@139.196.44.6',
     '''ls /opt/japanese-learn/backend/src/utils/'''],
    capture_output=True, text=True, encoding='utf-8'
)
print("STDOUT:", result.stdout[:2000])
print("STDERR:", result.stderr[:200])
