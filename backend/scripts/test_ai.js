// Quick test: can Node.js fetch reach DeepSeek?
const fs = require('fs');
const path = require('path');
const https = require('https');

const cfgPath = path.join(__dirname, '../config/ai_settings.json');
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
console.log('Config:', JSON.stringify({ provider: cfg.provider, base_url: cfg.base_url, model: cfg.model, has_key: !!cfg.api_key }, null, 2));

// Test 1: built-in https module
const url = new URL(cfg.base_url + '/chat/completions');
console.log('\n--- Test https module to', url.href, '---');
const postData = JSON.stringify({ model: cfg.model, messages: [{ role: 'user', content: 'Hi' }], max_tokens: 10 });
const req = https.request({
  hostname: url.hostname,
  port: 443,
  path: url.pathname,
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + cfg.api_key,
    'Content-Length': Buffer.byteLength(postData)
  }
}, (res) => {
  let body = '';
  res.on('data', d => body += d);
  res.on('end', () => {
    console.log('https status:', res.statusCode);
    console.log('https body:', body.substring(0, 300));
  });
});
req.on('error', e => console.log('https error:', e.message));
req.write(postData);
req.end();

// Test 2: fetch (Node 18 experimental)
console.log('\n--- Test fetch ---');
fetch(cfg.base_url + '/chat/completions', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + cfg.api_key
  },
  body: postData
}).then(r => {
  console.log('fetch status:', r.status);
  return r.text();
}).then(t => {
  console.log('fetch body:', t.substring(0, 300));
}).catch(e => {
  console.log('fetch error:', e.message);
  console.log('fetch cause:', e.cause);
});
