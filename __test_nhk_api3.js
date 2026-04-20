const https = require('https');

function fetch(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      path: urlObj.pathname + urlObj.search,
      timeout: 15000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
        'Accept': 'application/json',
        'Accept-Encoding': 'identity',
        'Accept-Language': 'ja,en;q=0.9',
        'Origin': 'https://news.web.nhk',
        'Referer': 'https://news.web.nhk/',
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
  // Test 1: detail endpoint with proper headers
  console.log('=== Detail with NHK Origin ===');
  const r1 = await fetch('https://api.web.nhk/r8/t/newsarticle/na/na-k10015067871000/detail.json');
  console.log('Status:', r1.status, 'Body:', r1.body.substring(0, 300));

  // Test 2: Try the new NHK Easy endpoint
  console.log('\n=== NHK Easy article list ===');
  try {
    const r2 = await fetch('https://api.web.nhk/r8/t/newsarticle/ne/list.json');
    console.log('Status:', r2.status, 'Len:', r2.body.length);
    if (r2.status === 200) {
      const data = JSON.parse(r2.body);
      console.log('Keys:', Object.keys(data));
      console.log('Preview:', JSON.stringify(data).substring(0, 500));
    } else {
      console.log('Body:', r2.body.substring(0, 300));
    }
  } catch(e) { console.log('Error:', e.message); }

  // Test 3: Try NHK regular news list API
  console.log('\n=== NHK news list API ===');
  try {
    const r3 = await fetch('https://api.web.nhk/r8/t/playlist/na/news-nwa-politics-nationwide-20260306.json');
    console.log('Status:', r3.status, 'Len:', r3.body.length);
    if (r3.status === 200) {
      const data = JSON.parse(r3.body);
      console.log('Keys:', Object.keys(data));
      if (data.items) console.log('Items:', data.items.length);
      console.log('Preview:', JSON.stringify(data).substring(0, 800));
    } else {
      console.log('Body:', r3.body.substring(0, 300));
    }
  } catch(e) { console.log('Error:', e.message); }
  
  // Test 4: Try the top news list 
  console.log('\n=== NHK top news list ===');
  try {
    const r4 = await fetch('https://api.web.nhk/r8/t/playlist/na/news-nwa-topnews.json');
    console.log('Status:', r4.status, 'Len:', r4.body.length);
    if (r4.status === 200) {
      const data = JSON.parse(r4.body);
      // Check first article for body content
      if (data.items && data.items[0]) {
        const item = data.items[0];
        console.log('First item keys:', Object.keys(item));
        console.log('First item headline:', item.headline || item.name);
        console.log('First item description:', (item.description || '').substring(0, 200));
      }
    }
  } catch(e) { console.log('Error:', e.message); }

  // Test 5: NHK Easy article content
  console.log('\n=== NHK Easy specific ===');
  try {
    const r5 = await fetch('https://api.web.nhk/r8/t/newsarticle/ne/ne-k10015067871000.json');
    console.log('Status:', r5.status);
    if (r5.status === 200) console.log('Body:', r5.body.substring(0, 500));
    else console.log('Body:', r5.body.substring(0, 200));
  } catch(e) { console.log('Error:', e.message); }
}

main().catch(console.error);
