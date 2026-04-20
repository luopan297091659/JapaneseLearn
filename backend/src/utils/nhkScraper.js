/**
 * NHK 新闻内容增强
 * 使用 NHK Content API 获取更完整的元数据和文章信息
 */
const https = require('https');
const http = require('http');

// ── 简易 HTTP GET ──────────────────────────────────────────────────────
function httpGet(url, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    const opts = {
      timeout,
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; JapaneseLearnApp/1.0)' },
    };
    const req = mod.get(url, opts, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return httpGet(res.headers.location, timeout).then(resolve, reject);
      }
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
  });
}

/**
 * 从 NHK Content API 获取文章元数据
 * @param {string} articleId - 格式: YYYYMMDD-kXXXXXXXXXXX 或 kXXXXXXXXXXX
 * @returns {object|null}
 */
async function fetchNhkMetadata(articleId) {
  // 转换 ID: 20260306-k10015067871000 → na-k10015067871000
  let nhkId;
  if (articleId.match(/^\d{8}-/)) {
    nhkId = 'na-' + articleId.replace(/^\d{8}-/, '');
  } else if (articleId.startsWith('k')) {
    nhkId = 'na-' + articleId;
  } else {
    nhkId = articleId.startsWith('na-') ? articleId : 'na-' + articleId;
  }
  // NHK API 需要 na-kXXXXX000 格式
  if (!/000$/.test(nhkId) && /^na-k\d+$/.test(nhkId) && nhkId.length < 25) {
    nhkId += '000';
  }

  try {
    const url = `https://api.web.nhk/r8/t/newsarticle/na/${nhkId}.json`;
    const json = await httpGet(url);
    const data = JSON.parse(json);
    return {
      title: data.headline || data.name || '',
      description: data.description || data.abstract || '',
      image: data.image?.medium?.url || data.image?.icon?.url || '',
      canonical: data.canonical || '',
      datePublished: data.datePublished || '',
      genre: data.genre || [],
    };
  } catch (_) {
    return null;
  }
}

/**
 * 根据文章 ID 构造 NHK 文章 URL（旧格式，会重定向到新站）
 */
function buildArticleUrl(articleId) {
  return `https://www3.nhk.or.jp/news/html/${articleId.replace('-', '/')}.html`;
}

module.exports = {
  fetchNhkMetadata,
  buildArticleUrl,
};
