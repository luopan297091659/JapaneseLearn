import subprocess
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     'cat /tmp/jmdict_import.log'],
    capture_output=True, text=True, timeout=30
)
print("=== STDOUT (last 3000 chars) ===")
print(r.stdout[-3000:])
print("=== STDERR (last 1000 chars) ===")
print(r.stderr[-1000:] if r.stderr else 'none')
print("=== RETURN CODE ===")
print(r.returncode)
