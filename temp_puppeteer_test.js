#!/usr/bin/env node
// Test: use puppeteer-core to render NHK article and extract body
const puppeteer = require('puppeteer-core');

(async () => {
  const url = 'https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html';
  console.log('Launching browser...');
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/chromium-browser',
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });
  
  try {
    const page = await browser.newPage();
    await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    console.log('Loading page...');
    await page.goto(url, { waitUntil: 'networkidle2', timeout: 30000 });
    
    // Wait a bit more for React to render
    await page.waitForTimeout(2000);
    
    // Try to find article body via various selectors
    const selectors = [
      'article',
      '[class*="content--detail"]',
      '[class*="body"]',
      '[class*="module--detail"]',
      'section',
      'main',
      '.content--detail-body',
      '.module--content',
    ];
    
    for (const sel of selectors) {
      const el = await page.$(sel);
      if (el) {
        const text = await el.evaluate(e => e.innerText);
        if (text && text.length > 50) {
          console.log(`\nSelector "${sel}": ${text.length} chars`);
          console.log(text.substring(0, 500));
          console.log('...');
        }
      }
    }
    
    // Also try to get all <p> tags text
    const paragraphs = await page.$$eval('p', els => 
      els.map(e => e.innerText).filter(t => t.length > 10)
    );
    console.log(`\n\n=== <p> tags with text > 10 chars: ${paragraphs.length} ===`);
    for (const p of paragraphs.slice(0, 20)) {
      console.log(`  [${p.length}] ${p.substring(0, 100)}`);
    }
    
  } finally {
    await browser.close();
  }
})().catch(e => { console.error(e.message); process.exit(1); });
