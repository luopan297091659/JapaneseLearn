import subprocess, time, os, sys

# Ensure plink is findable
os.environ['PATH'] = os.environ.get('PATH','') + r';C:\Program Files\PuTTY'

def ssh_cmd(cmd, timeout=30):
    try:
        r = subprocess.run(
            ['plink', '-batch',
             '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
             '-pw', 'Xiaoyun@123', '-P', '22',
             'root@139.196.44.6', cmd],
            capture_output=True, timeout=timeout
        )
        return r.stdout.decode('utf-8','replace').strip(), r.returncode
    except Exception as e:
        return f'ERROR: {e}', -1

print("Step 1: Kill existing import...", flush=True)
out, rc = ssh_cmd("pkill -f 'import_jmdict' 2>/dev/null; sleep 1; echo killed")
print(f"  {out}", flush=True)

print("Step 2: Start import...", flush=True)
out, rc = ssh_cmd(
    'cd /home/japanese-learn/backend && nohup node scripts/import_jmdict.js /tmp/JMdict.gz > /tmp/jmdict_import.log 2>&1 & sleep 2 && echo "PID=$(pgrep -f import_jmdict)" && head -5 /tmp/jmdict_import.log'
)
print(f"  {out}", flush=True)

print("Step 3: Monitoring...", flush=True)
for i in range(30):
    time.sleep(10)
    out, rc = ssh_cmd("tail -5 /tmp/jmdict_import.log 2>&1; pgrep -f import_jmdict >/dev/null 2>&1 && echo STATUS=RUNNING || echo STATUS=DONE")
    print(f"  [{(i+1)*10}s] {out}", flush=True)
    if 'STATUS=DONE' in out:
        print("\n=== Full log ===", flush=True)
        out, _ = ssh_cmd("cat /tmp/jmdict_import.log", timeout=30)
        print(out, flush=True)
        break

print("\nFinished.", flush=True)
