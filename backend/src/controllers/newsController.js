const { NewsArticle, NewsFavorite, NhkNewsCache } = require('../models');
const { Op } = require('sequelize');
const https = require('https');
const http  = require('http');
const { fetchNhkMetadata, buildArticleUrl } = require('../utils/nhkScraper');

// ── 简易 HTTP GET（返回 Promise<string>）──────────────────────────────────
function httpGet(url, timeout = 8000) {
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
const NHK_FAIL_TTL = 5 * 60 * 1000; // 失败后 5 分钟内不再重试
const _nhkFailCache = {};

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
  // 如果最近刚失败过，跳过重试避免重复超时
  if (_nhkFailCache[cacheKey] && now - _nhkFailCache[cacheKey] < NHK_FAIL_TTL) {
    throw new Error('NHK暂时不可达，跳过重试');
  }

  try {
    const url = `https://www3.nhk.or.jp/rss/news/cat${category}.xml`;
    const xml = await httpGet(url);
    const articles = parseRssItems(xml);
    _nhkRssCache[cacheKey] = { data: articles, at: now };
    delete _nhkFailCache[cacheKey];
    return articles;
  } catch (err) {
    _nhkFailCache[cacheKey] = now;
    throw err;
  }
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
    // 异步持久化到数据库（不阻塞响应），并限制每个分类最多 20 条
    setImmediate(async () => {
      try {
        for (const a of articles) {
          // 仅保存有足够内容的新闻（description >= 50字符）
          if (!a.description || a.description.length < 50) continue;
          await NhkNewsCache.findOrCreate({
            where: { nhk_id: a.id },
            defaults: {
              nhk_id: a.id,
              title: a.title,
              description: a.description,
              body: a.description, // RSS description 作为正文（最完整的可用来源）
              link: a.link,
              category,
              published_at: a.publishedAt ? new Date(a.publishedAt) : null,
            },
          });
        }
        // 清理旧文章：每个分类只保留最新 20 条
        const allInCat = await NhkNewsCache.findAll({
          where: { category },
          order: [['published_at', 'DESC']],
          attributes: ['id'],
        });
        if (allInCat.length > 20) {
          const idsToDelete = allInCat.slice(20).map(r => r.id);
          await NhkNewsCache.destroy({ where: { id: idsToDelete } });
        }
      } catch (_) { /* ignore persist errors */ }
    });
    res.json({ total: articles.length, data: articles, category: NHK_CATEGORIES[category] });
  } catch (err) {
    res.status(502).json({ error: 'Failed to fetch NHK news: ' + err.message });
  }
}

// ── NHK 历史新闻（分页）──────────────────────────────────────────────
async function nhkHistory(req, res) {
  const { category, page = 1, limit = 20 } = req.query;
  const where = {};
  if (category && NHK_CATEGORIES[category]) where.category = category;
  const offset = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);
  try {
    const { count, rows } = await NhkNewsCache.findAndCountAll({
      where,
      limit: Math.min(50, parseInt(limit)),
      offset,
      order: [['published_at', 'DESC']],
    });
    const data = rows.map(r => ({
      id: r.nhk_id,
      title: r.title,
      description: r.description,
      body: r.body || '',
      imageUrl: r.image_url || '',
      link: r.link,
      publishedAt: r.published_at ? r.published_at.toISOString() : null,
      source: 'NHK',
    }));
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function nhkArticle(req, res) {
  const rawId = req.params.id;
  // 白名单校验: 格式为 YYYYMMDD-kXXXXX 或 kXXXXX
  if (!/^([\d]{8}-)?[a-zA-Z0-9]+$/.test(rawId)) {
    return res.status(400).json({ error: 'Invalid news ID' });
  }

  // 先查缓存
  let cached = null;
  try { cached = await NhkNewsCache.findOne({ where: { nhk_id: rawId } }); } catch (_) {}

  // 构造文章链接
  const articleLink = buildArticleUrl(rawId);

  // 1) 如果缓存有数据且 body 足够长（已有完整内容），立即返回
  if (cached && cached.body && cached.body.length > 200) {
    return res.json({
      id: rawId,
      title: cached.title || '',
      description: cached.description || '',
      image: cached.image_url || '',
      body: cached.body,
      link: articleLink,
    });
  }

  // 2) 尝试从 NHK Content API 获取元数据
  const meta = await fetchNhkMetadata(rawId);

  if (cached) {
    // 有缓存但 body 不够长，用 API 数据补充
    const bestDesc = (meta?.description && meta.description.length > (cached.description || '').length)
      ? meta.description : (cached.description || '');
    const result = {
      id: rawId,
      title: meta?.title || cached.title || '',
      description: bestDesc,
      image: meta?.image || cached.image_url || '',
      body: cached.body || bestDesc,
      link: articleLink,
    };
    // 后台更新缓存
    if (meta) {
      setImmediate(async () => {
        try {
          await NhkNewsCache.update({
            title: meta.title || undefined,
            description: meta.description || undefined,
            image_url: meta.image || undefined,
            body: bestDesc.length > (cached.body || '').length ? bestDesc : undefined,
          }, { where: { nhk_id: rawId } });
        } catch (_) {}
      });
    }
    return res.json(result);
  }

  // 3) 完全无缓存，用 API 数据 + 旧 HTML 抓取
  if (meta) {
    const result = {
      id: rawId,
      title: meta.title,
      description: meta.description,
      image: meta.image,
      body: meta.description,
      link: articleLink,
    };
    // 后台保存到缓存
    setImmediate(async () => {
      try {
        await NhkNewsCache.findOrCreate({
          where: { nhk_id: rawId },
          defaults: {
            nhk_id: rawId,
            title: meta.title,
            description: meta.description,
            body: meta.description,
            image_url: meta.image,
            link: articleLink,
            published_at: meta.datePublished ? new Date(meta.datePublished) : null,
          },
        });
      } catch (_) {}
    });
    return res.json(result);
  }

  // 4) API 也失败，回退到旧的 HTML 抓取
  try {
    const html = await httpGet(articleLink);
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
      } catch (_) {}
    }
    if (!description) {
      const metaMatch = html.match(/<meta\s+name="description"\s+content="([^"]*)"/i);
      if (metaMatch) description = metaMatch[1];
    }
    if (!title) {
      const titleMatch = html.match(/<title>([^<]*)<\/title>/);
      if (titleMatch) title = titleMatch[1].replace(/\s*\|.*$/, '').trim();
    }
    res.json({ id: rawId, title, description, image, body: description, link: articleLink });
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

module.exports = { list, getById, nhkList, nhkArticle, nhkCategories, nhkHistory, listFavorites, addFavorite, removeFavorite, checkFavorite };
