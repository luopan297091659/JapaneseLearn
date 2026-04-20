const https = require('https');

function fetch(url) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const opts = { hostname: urlObj.hostname, path: urlObj.pathname, timeout: 15000, headers: { 'User-Agent': 'Mozilla/5.0' } };
    const req = https.get(opts, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        let loc = res.headers.location;
        if (loc.startsWith('/')) loc = `https://${urlObj.hostname}${loc}`;
        return fetch(loc).then(resolve, reject);
      }
      const c = [];
      res.on('data', d => c.push(d));
      res.on('end', () => resolve({ status: res.statusCode, body: Buffer.concat(c).toString('utf8') }));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

async function main() {
  // Fetch actual NHK RSS feed
  console.log('=== Fetching NHK RSS (cat0) ===');
  const r = await fetch('https://www3.nhk.or.jp/rss/news/cat0.xml');
  console.log('Status:', r.status, 'Len:', r.body.length);
  
  // Parse first 3 items and show their descriptions
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let m;
  while ((m = itemRegex.exec(r.body)) !== null && items.length < 3) {
    const block = m[1];
    const title = (block.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || '';
    const desc = (block.match(/<description>([\s\S]*?)<\/description>/) || [])[1] || '';
    const link = (block.match(/<link>([\s\S]*?)<\/link>/) || [])[1] || '';
    items.push({ title: title.replace(/<!\[CDATA\[|\]\]>/g, ''), desc: desc.replace(/<!\[CDATA\[|\]\]>/g, ''), link });
  }
  
  items.forEach((item, i) => {
    console.log(`\n--- Item ${i+1} ---`);
    console.log('Title:', item.title.trim());
    console.log('Link:', item.link.trim());
    console.log('Desc length:', item.desc.trim().length);
    console.log('Description:', item.desc.trim());
  });
}

main().catch(console.error);
