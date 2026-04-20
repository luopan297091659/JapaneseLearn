const https = require('https');

function fetch(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      timeout: 15000,
      headers: { 'User-Agent': 'Mozilla/5.0', ...headers },
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
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

function fetchPost(url, body, headers = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const postData = typeof body === 'string' ? body : JSON.stringify(body);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      method: 'POST',
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData),
        ...headers,
      },
    };
    const req = https.request(opts, (res) => {
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
    req.write(postData);
    req.end();
  });
}

async function main() {
  const endpoints = [
    'https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000/detail.json',
    'https://api.web.nhk/r8/t/newsarticle-detail/na/na-k10015067871000.json',
    'https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000.json?include=body',
    'https://api.web.nhk/r8/c/newsarticle/na/na-k10015067871000.json',
    'https://api.web.nhk/r8/p/newsarticle/na/na-k10015067871000.json',
  ];

  for (const url of endpoints) {
    try {
      const r = await fetch(url);
      console.log(`${url}\n  Status: ${r.status}, Len: ${r.body.length}`);
      if (r.status === 200) {
        const data = JSON.parse(r.body);
        // Check for body-related fields
        const keys = Object.keys(data);
        const bodyKeys = keys.filter(k => /body|content|text|detail|article|html/i.test(k));
        console.log('  Keys:', keys.join(', '));
        if (bodyKeys.length) console.log('  Body keys:', bodyKeys);
        if (data.body) console.log('  Body:', (typeof data.body === 'string' ? data.body : JSON.stringify(data.body)).substring(0, 300));
      } else {
        console.log('  Body:', r.body.substring(0, 200));
      }
    } catch (e) {
      console.log(`${url}\n  Error: ${e.message}`);
    }
    console.log('');
  }

  // Try getting NHK accountless token
  console.log('=== Try accountless auth ===');
  try {
    const r = await fetchPost('https://r.authz.ac1.nhk/v1/token', {});
    console.log('Status:', r.status, 'Body:', r.body.substring(0, 500));
  } catch (e) { console.log('Error:', e.message); }
  
  // Try another auth endpoint pattern
  console.log('\n=== Try auth token endpoint ===');
  try {
    const r = await fetchPost('https://a.authz.ac1.nhk/v1/token', {});
    console.log('Status:', r.status, 'Body:', r.body.substring(0, 500));
  } catch (e) { console.log('Error:', e.message); }
}

main().catch(console.error);
