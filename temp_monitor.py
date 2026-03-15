import subprocess, time

def ssh_cmd(cmd, timeout=30):
    r = subprocess.run(
        ['plink', '-batch',
         '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
         '-pw', 'Xiaoyun@123', '-P', '22',
         'root@139.196.44.6', cmd],
        capture_output=True, timeout=timeout
    )
    return r.stdout.decode('utf-8','replace'), r.returncode

# Kill any existing import
ssh_cmd("pkill -f 'import_jmdict' 2>/dev/null; sleep 1; echo killed")

# Start import in background
out, rc = ssh_cmd(
    'cd /home/japanese-learn/backend && nohup node scripts/import_jmdict.js /tmp/JMdict.gz > /tmp/jmdict_import.log 2>&1 & sleep 1 && echo "PID=$(pgrep -f import_jmdict)" && head -5 /tmp/jmdict_import.log'
)
print(f"Start: {out.strip()}")

# Wait and poll
for i in range(30):
    time.sleep(10)
    out, rc = ssh_cmd("tail -5 /tmp/jmdict_import.log && echo '---' && pgrep -f import_jmdict >/dev/null 2>&1 && echo RUNNING || echo DONE")
    print(f"\n[{(i+1)*10}s] {out.strip()}")
    if 'DONE' in out:
        # Get full output
        print("\n=== Full import log ===")
        out, _ = ssh_cmd("cat /tmp/jmdict_import.log")
        print(out)
        break
