import subprocess

# Check node version and test basic gzip + readline
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     r"""node -v && node -e "
const fs = require('fs');
const {createGunzip} = require('zlib');
const readline = require('readline');
async function test() {
  let input = fs.createReadStream('/tmp/JMdict.gz').pipe(createGunzip());
  const rl = readline.createInterface({input, crlfDelay: Infinity});
  let lines = 0, entityCount = 0, entryCount = 0;
  for await (const line of rl) {
    lines++;
    if (line.includes('<!ENTITY')) entityCount++;
    if (line.trim() === '<entry>') entryCount++;
    if (lines <= 5 || lines % 100000 === 0) console.log('L'+lines+': '+line.substring(0,80));
    if (entryCount >= 3) break;
  }
  rl.close();
  console.log('Total lines read:', lines);
  console.log('Entities:', entityCount);
  console.log('Entries:', entryCount);
}
test().catch(e => console.error('ERROR:', e.message));
" 2>&1"""],
    capture_output=True, timeout=60
)
out = r.stdout.decode('utf-8','replace')
print(out)
print(f'Retcode: {r.returncode}')
