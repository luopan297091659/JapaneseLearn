import subprocess
r = subprocess.run(
    ['plink', '-batch',
     '-hostkey', 'SHA256:ySCdPD8LyDCmPPcUT7OjO6r+c0RUwBLMU/UWlOA9GHg',
     '-pw', 'Xiaoyun@123', '-P', '22',
     'root@139.196.44.6',
     """cd /home/japanese-learn/backend && node -e "
const fs = require('fs');
const {createGunzip} = require('zlib');
const sax = require('sax');
const parser = sax.createStream(true, {trim: true});
let count = 0;
let errors = [];
parser.on('opentag', (n) => { if(n.name==='entry') count++; });
parser.on('error', (e) => {
  errors.push(e.message.substring(0,100));
  parser._parser.error = null;
  parser._parser.resume();
});
parser.on('end', () => {
  console.log('entries:', count);
  console.log('errors:', errors.length);
  if(errors.length>0) console.log('first errors:', errors.slice(0,3));
});
const input = fs.createReadStream('/tmp/JMdict.gz').pipe(createGunzip());
input.pipe(parser);
input.on('error', (e) => console.log('input error:', e.message));
" 2>&1"""],
    capture_output=True, timeout=120
)
with open(r'd:\PROJECT\JapaneseLearn\import_result.txt', 'wb') as f:
    f.write(r.stdout)
    f.write(b'\n---STDERR---\n')
    f.write(r.stderr or b'none')
print(r.stdout.decode('utf-8','replace'))
