const puppeteer = require('puppeteer-core');
(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/chromium-browser',
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--disable-gpu'],
  });
  const page = await browser.newPage();
  await page.setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
  
  console.log('Loading page...');
  await page.goto('https://www3.nhk.or.jp/news/html/20260314/k10015075721000.html', {
    waitUntil: 'networkidle0', timeout: 45000,
  });
  
  // Wait longer for dynamic content
  await new Promise(r => setTimeout(r, 5000));
  
  // Print the top-level div texts to understand structure
  const topDivs = await page.$$eval('body > div > div > div', els =>
    els.map(e => ({ cls: (e.className||'').substring(0,50), text: (e.innerText||'').substring(0,200), len: (e.innerText||'').length }))
      .filter(x => x.len > 50)
  );
  console.log('=== Top divs ===');
  topDivs.forEach(d => console.log(`  .${d.cls} (${d.len}): ${d.text.substring(0,150)}`));
  
  // Get the biggest text element
  const biggest = await page.$eval('._22j9o20', e => e.innerText).catch(() => 'NOT FOUND');
  console.log('\n=== ._22j9o20 content ===');
  console.log(biggest.substring(0, 1000));

  // Check for any element that looks like article body  
  const allText = await page.$eval('body', e => e.innerText);
  console.log('\n=== Full body text length:', allText.length, '===');
  console.log(allText.substring(0, 2000));
  
  // Check if page has any pending API calls
  const urls = await page.evaluate(() => {
    return performance.getEntriesByType('resource')
      .filter(r => r.name.includes('newsarticle') || r.name.includes('api') || r.name.includes('article'))
      .map(r => ({ url: r.name.substring(0, 120), status: r.responseStatus }));
  });
  console.log('\n=== API calls ===');
  urls.forEach(u => console.log(`  ${u.status} ${u.url}`));

  await browser.close();
})().catch(e => { console.error(e.message); process.exit(1); });
