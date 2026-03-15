const puppeteer = require('puppeteer-core');
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/chromium-browser',
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });
  const page = await browser.newPage();
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
  await page.goto('https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html', {
    waitUntil: 'networkidle2', timeout: 30000,
  });
  await new Promise(r => setTimeout(r, 3000));

  // Get all paragraph texts
  const ps = await page.$$eval('p', els => els.map(e => e.innerText).filter(t => t.length > 10));
  console.log('P tags count:', ps.length);
  ps.slice(0, 15).forEach((p, i) => console.log(`  [${i}] (${p.length}) ${p.substring(0, 150)}`));

  // Try to get main content
  const mainText = await page.$eval('main', e => e.innerText).catch(() => null);
  if (mainText) {
    console.log('\nMain text length:', mainText.length);
    console.log(mainText.substring(0, 500));
  }

  // Try article selector
  const artText = await page.$eval('article', e => e.innerText).catch(() => null);
  if (artText) {
    console.log('\nArticle text length:', artText.length);
    console.log(artText.substring(0, 500));
  }

  // Try various class selectors
  for (const sel of ['[class*="detail-body"]', '[class*="detail-main"]', '[class*="content--detail"]', 'section[class*="module"]']) {
    const text = await page.$eval(sel, e => e.innerText).catch(() => null);
    if (text && text.length > 50) {
      console.log(`\nSelector "${sel}": ${text.length} chars`);
      console.log(text.substring(0, 300));
    }
  }

  // Get rendered HTML body classes to understand the structure
  const bodyClasses = await page.$$eval('[class]', els => {
    return els.map(e => ({tag: e.tagName, cls: e.className, textLen: (e.innerText||'').length}))
      .filter(x => x.textLen > 100 && typeof x.cls === 'string' && x.cls.length > 0)
      .sort((a, b) => b.textLen - a.textLen)
      .slice(0, 15);
  });
  console.log('\n=== Elements with text > 100 chars ===');
  bodyClasses.forEach(x => console.log(`  ${x.tag} .${x.cls.substring(0,60)} => ${x.textLen} chars`));

  await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
