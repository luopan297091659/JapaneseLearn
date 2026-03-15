$env:PATH = $env:PATH + ";C:\Program Files\PuTTY"
$hk = "SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg"
$pw = "Xiaoyun@123"

# Start import in background on server
$out = & plink -batch -hostkey $hk -pw $pw -P 22 root@139.196.44.6 "pkill -f import_jmdict 2>/dev/null; cd /home/japanese-learn/backend; nohup node scripts/import_jmdict.js /tmp/JMdict.gz > /tmp/jmdict_import.log 2>&1 &" 2>&1
Write-Host "Import started" -ForegroundColor Green

# Wait and check
for ($i = 1; $i -le 30; $i++) {
    Start-Sleep -Seconds 10
    $log = & plink -batch -hostkey $hk -pw $pw -P 22 root@139.196.44.6 "tail -3 /tmp/jmdict_import.log; pgrep -f import_jmdict >/dev/null 2>&1 && echo RUNNING || echo FINISHED" 2>&1
    $logStr = $log -join "`n"
    Write-Host "[$($i*10)s] $logStr"
    if ($logStr -match "FINISHED") {
        Write-Host "`n=== Final log ===" -ForegroundColor Cyan
        $full = & plink -batch -hostkey $hk -pw $pw -P 22 root@139.196.44.6 "cat /tmp/jmdict_import.log" 2>&1
        $full | ForEach-Object { Write-Host $_ }
        break
    }
}
