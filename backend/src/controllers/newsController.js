const { NewsArticle, NewsFavorite } = require('../models');
const { Op } = require('sequelize');
const https = require('https');
const http  = require('http');

// ── 简易 HTTP GET（返回 Promise<string>）──────────────────────────────────
function httpGet(url, timeout = 15000) {
  return new Promise((resolve, reject) => {
    const mod = url.startsWith('https') ? https : http;
    const opts = {
      timeout,
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; JapaneseLearnApp/1.0)',
      },
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

// ── NHK RSS 新闻列表缓存 ────────────────────────────────────────────────
const NHK_TTL = 30 * 60 * 1000; // 30 分钟
const _nhkRssCache = {};

const NHK_CATEGORIES = {
  '0': '総合',   '1': '社会',   '3': '科学・文化',
  '4': '政治',   '5': '経済',   '6': '国際',   '7': 'スポーツ',
};

function parseRssItems(xml) {
  const items = [];
  const itemRegex = /<item>([\s\S]*?)<\/item>/gi;
  let m;
  while ((m = itemRegex.exec(xml)) !== null) {
    const block = m[1];
    const title = (block.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || '';
    const link  = (block.match(/<link>([\s\S]*?)<\/link>/) || [])[1] || '';
    const pub   = (block.match(/<pubDate>([\s\S]*?)<\/pubDate>/) || [])[1] || '';
    const desc  = (block.match(/<description>([\s\S]*?)<\/description>/) || [])[1] || '';

    // 从链接提取文章 ID，格式: /news/html/YYYYMMDD/kXXXXX.html → YYYYMMDD-kXXXXX
    const idMatch = link.match(/\/news\/html\/(\d{8})\/([a-zA-Z0-9]+)\.html/);
    const id = idMatch ? `${idMatch[1]}-${idMatch[2]}` : link;

    items.push({
      id,
      title: title.replace(/<!\[CDATA\[|\]\]>/g, '').trim(),
      description: desc.replace(/<!\[CDATA\[|\]\]>/g, '').trim(),
      link,
      publishedAt: pub ? new Date(pub).toISOString() : null,
      source: 'NHK',
    });
  }
  return items;
}

async function fetchNhkRss(category = '0') {
  const now = Date.now();
  const cacheKey = `cat${category}`;
  if (_nhkRssCache[cacheKey] && now - _nhkRssCache[cacheKey].at < NHK_TTL) {
    return _nhkRssCache[cacheKey].data;
  }

  const url = `https://www3.nhk.or.jp/rss/news/cat${category}.xml`;
  const xml = await httpGet(url);
  const articles = parseRssItems(xml);

  _nhkRssCache[cacheKey] = { data: articles, at: now };
  return articles;
}

// ── DB 新闻 ──────────────────────────────────────────────────────────────
async function list(req, res) {
  const { difficulty, q, page = 1, limit = 10 } = req.query;
  const where = {};
  if (difficulty) where.difficulty = difficulty;
  if (q) where.title = { [Op.like]: `%${q}%` };
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await NewsArticle.findAndCountAll({
      where, limit: parseInt(limit), offset,
      attributes: ['id', 'title', 'image_url', 'published_at', 'source', 'difficulty'],
      order: [['published_at', 'DESC']],
    });
    res.json({ total: count, data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getById(req, res) {
  try {
    const article = await NewsArticle.findByPk(req.params.id);
    if (!article) return res.status(404).json({ error: 'Not found' });
    res.json(article);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ── NHK RSS 代理 ─────────────────────────────────────────────────────────
async function nhkList(req, res) {
  try {
    const category = req.query.category || '0';
    // 白名单校验分类
    if (!NHK_CATEGORIES[category]) {
      return res.status(400).json({ error: 'Invalid category. Valid: ' + Object.keys(NHK_CATEGORIES).join(',') });
    }
    const articles = await fetchNhkRss(category);
    res.json({ total: articles.length, data: articles, category: NHK_CATEGORIES[category] });
  } catch (err) {
    res.status(502).json({ error: 'Failed to fetch NHK news: ' + err.message });
  }
}

async function nhkArticle(req, res) {
  const rawId = req.params.id;
  // 白名单校验: 格式为 YYYYMMDD-kXXXXX
  if (!/^[\d]{8}-[a-zA-Z0-9]+$/.test(rawId)) {
    return res.status(400).json({ error: 'Invalid news ID' });
  }
  try {
    const url = `https://www3.nhk.or.jp/news/html/${rawId.replace('-', '/')}.html`;
    const html = await httpGet(url);

    // 从 JSON-LD 提取标题、描述、图片
    let title = '', description = '', image = '';
    const ldRegex = /<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
    let ldm;
    while ((ldm = ldRegex.exec(html)) !== null) {
      try {
        const obj = JSON.parse(ldm[1]);
        if (obj['@type'] === 'NewsArticle') {
          title = obj.headline || '';
          description = obj.description || '';
          if (obj.image && obj.image[0]) image = obj.image[0].url || '';
        }
      } catch (_) { /* ignore JSON parse errors */ }
    }

    // 兜底：从 meta 标签提取
    if (!description) {
      const metaMatch = html.match(/<meta\s+name="description"\s+content="([^"]*)"/i);
      if (metaMatch) description = metaMatch[1];
    }
    if (!title) {
      const titleMatch = html.match(/<title>([^<]*)<\/title>/);
      if (titleMatch) title = titleMatch[1].replace(/\s*\|.*$/, '').trim();
    }

    res.json({ id: rawId, title, description, image, body: description, link: url });
  } catch (err) {
    res.status(502).json({ error: 'Failed to fetch article: ' + err.message });
  }
}

async function nhkCategories(req, res) {
  res.json(NHK_CATEGORIES);
}

// ── 收藏功能 ─────────────────────────────────────────────────────────────
async function listFavorites(req, res) {
  const favorites = await NewsFavorite.findAll({
    where: { user_id: req.user.id },
    order: [['createdAt', 'DESC']],
  });
  res.json({ total: favorites.length, data: favorites });
}

async function addFavorite(req, res) {
  const { news_type, news_id, title, description, image_url, link, source, published_at } = req.body;
  if (!news_type || !news_id || !title) {
    return res.status(400).json({ error: 'news_type, news_id, title are required' });
  }
  if (!['db', 'nhk'].includes(news_type)) {
    return res.status(400).json({ error: 'news_type must be db or nhk' });
  }
  const [fav, created] = await NewsFavorite.findOrCreate({
    where: { user_id: req.user.id, news_type, news_id },
    defaults: { user_id: req.user.id, news_type, news_id, title, description, image_url, link, source, published_at },
  });
  res.status(created ? 201 : 200).json(fav);
}

async function removeFavorite(req, res) {
  const { news_type, news_id } = req.body;
  if (!news_type || !news_id) {
    return res.status(400).json({ error: 'news_type and news_id are required' });
  }
  const count = await NewsFavorite.destroy({
    where: { user_id: req.user.id, news_type, news_id },
  });
  res.json({ removed: count > 0 });
}

async function checkFavorite(req, res) {
  const { news_type, news_id } = req.query;
  if (!news_type || !news_id) return res.json({ favorited: false });
  const exists = await NewsFavorite.findOne({
    where: { user_id: req.user.id, news_type, news_id },
  });
  res.json({ favorited: !!exists });
}

module.exports = { list, getById, nhkList, nhkArticle, nhkCategories, listFavorites, addFavorite, removeFavorite, checkFavorite };
