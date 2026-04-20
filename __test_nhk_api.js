const https = require('https');

function fetch(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        ...headers,
      },
    };
    const req = https.get(opts, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (loc.startsWith('/')) loc = `https://${urlObj.hostname}${loc}`;
        return fetch(loc, headers).then(resolve, reject);
      }
      const chunks = [];
      res.on('data', d => chunks.push(d));
      res.on('end', () => resolve({
        status: res.statusCode,
        headers: res.headers,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  // Test 1: Fetch NHK article page with RSC header
  console.log('=== Test 1: Fetch with RSC header ===');
  try {
    const r1 = await fetch('https://www3.nhk.or.jp/news/html/20260306/k10015067871000.html', {
      'RSC': '1',
      'Next-Router-State-Tree': '%5B%22%22%5D',
    });
    console.log('Status:', r1.status, 'Len:', r1.body.length);
    console.log('Content-Type:', r1.headers['content-type']);
    console.log('Body preview:', r1.body.substring(0, 1000));
  } catch (e) { console.log('Error:', e.message); }

  // Test 2: Try NHK accountless auth
  console.log('\n=== Test 2: NHK accountless auth ===');
  try {
    const r2 = await fetch('https://r.authz.ac1.nhk/token', {});
    console.log('Status:', r2.status, 'Body:', r2.body.substring(0, 500));
  } catch (e) { console.log('Error:', e.message); }

  // Test 3: Try fetching article from NHK content API
  console.log('\n=== Test 3: NHK content API ===');
  try {
    const r3 = await fetch('https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000.json');
    console.log('Status:', r3.status, 'Body:', r3.body.substring(0, 500));
  } catch (e) { console.log('Error:', e.message); }
}

main().catch(console.error);
