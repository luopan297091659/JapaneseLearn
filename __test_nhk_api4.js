const https = require('https');
const zlib = require('zlib');

function fetch(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Accept-Encoding': 'gzip, deflate',
        ...headers,
      },
    };
    const req = https.get(opts, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (loc.startsWith('/')) loc = `https://${urlObj.hostname}${loc}`;
        console.log('  Redirect to:', loc);
        return fetch(loc, headers).then(resolve, reject);
      }
      const chunks = [];
      res.on('data', d => chunks.push(d));
      res.on('end', () => {
        let body = Buffer.concat(chunks);
        const enc = res.headers['content-encoding'];
        if (enc === 'gzip') {
          try { body = zlib.gunzipSync(body); } catch(e) {}
        } else if (enc === 'deflate') {
          try { body = zlib.inflateSync(body); } catch(e) {}
        }
        resolve({
          status: res.statusCode,
          headers: res.headers,
          body: body.toString('utf8'),
        });
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  // Test 1: Detail endpoint with gzip decompression
  console.log('=== Detail (gzip decoded) ===');
  const r1 = await fetch('https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000/detail.json');
  console.log('Status:', r1.status, 'Body:', r1.body.substring(0, 500));

  // Test 2: Check NHK Easy RSS feed
  console.log('\n=== NHK Easy RSS ===');
  try {
    const r2 = await fetch('https://www3.nhk.or.jp/news/easy/rss/news-easy.xml');
    console.log('Status:', r2.status, 'Len:', r2.body.length);
    console.log('Preview:', r2.body.substring(0, 500));
  } catch(e) { console.log('Error:', e.message); }

  // Test 3: Try NHK Easy article JSON (old API pattern)
  console.log('\n=== NHK Easy Article JSON ===');
  try {
    const r3 = await fetch('https://www3.nhk.or.jp/news/easy/k10015067871000/k10015067871000.json');
    console.log('Status:', r3.status, 'Len:', r3.body.length);
    console.log('Preview:', r3.body.substring(0, 500));
  } catch(e) { console.log('Error:', e.message); }
  
  // Test 4: Try NHK Easy article HTML (old API pattern)
  console.log('\n=== NHK Easy Article HTML ===');
  try {
    const r4 = await fetch('https://www3.nhk.or.jp/news/easy/k10015067871000/k10015067871000.html');
    console.log('Status:', r4.status, 'Len:', r4.body.length);
    console.log('Preview:', r4.body.substring(0, 500));
  } catch(e) { console.log('Error:', e.message); }

  // Test 5: NHK news article with old URL (no redirect)
  console.log('\n=== Old NHK article page ===');
  try {
    const r5 = await fetch('https://www3.nhk.or.jp/news/html/20260306/k10015067871000.html');
    console.log('Status:', r5.status, 'Len:', r5.body.length);
    // Look for article text
    const textBlocks = r5.body.match(/>[^<]{50,}/g);
    if (textBlocks) {
      const jpBlocks = textBlocks.filter(t => /[\u3000-\u9fff]/.test(t));
      jpBlocks.slice(0,5).forEach((b,i) => console.log(`JP Block ${i}:`, b.substring(0, 200)));
    }
  } catch(e) { console.log('Error:', e.message); }
}

main().catch(console.error);
