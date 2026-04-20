const https = require('https');

function fetch(url) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      timeout: 15000,
      headers: { 'User-Agent': 'Mozilla/5.0' },
    };
    const req = https.get(opts, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (loc.startsWith('/')) loc = `https://${urlObj.hostname}${loc}`;
        return fetch(loc).then(resolve, reject);
      }
      const chunks = [];
      res.on('data', d => chunks.push(d));
      res.on('end', () => resolve({
        status: res.statusCode,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  // Fetch full article from NHK content API
  const r = await fetch('https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000.json');
  const data = JSON.parse(r.body);
  
  console.log('=== Top-level keys ===');
  console.log(Object.keys(data));
  
  console.log('\n=== Key fields ===');
  console.log('type:', data.type);
  console.log('headline:', data.headline);
  console.log('description:', (data.description || '').substring(0, 200));
  
  // Check for body/content/text fields
  const bodyFields = ['body', 'content', 'text', 'articleBody', 'abstract', 'detail'];
  for (const f of bodyFields) {
    if (data[f]) {
      const val = typeof data[f] === 'string' ? data[f] : JSON.stringify(data[f]);
      console.log(`\n${f} (len=${val.length}):`, val.substring(0, 500));
    }
  }
  
  // Print full JSON (first 5000 chars)
  console.log('\n=== Full JSON (first 5000) ===');
  console.log(JSON.stringify(data, null, 2).substring(0, 5000));
}

main().catch(console.error);
