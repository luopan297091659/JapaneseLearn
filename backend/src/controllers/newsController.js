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
  '0': '総合',   '1': '社会',   '2': '文化・エンタメ', '3': '科学・医療',
  '4': '政治',   '5': '経済',   '6': '国際',   '7': 'スポーツ',
};

function decodeXml(value = '') {
  return value
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&#x([\da-f]+);/gi, (_, code) => String.fromCodePoint(parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(parseInt(code, 10)))
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&apos;|&#39;/g, "'")
    .replace(/&amp;/g, '&').trim();
}

function xmlValue(block, name) {
  const escapedName = name.replace(':', '\\:');
  const match = block.match(new RegExp(`<${escapedName}\\b[^>]*>([\\s\\S]*?)<\\/${escapedName}\\s*>`, 'i'));
  return match ? decodeXml(match[1]) : '';
}

function xmlLink(block) {
  const link = block.match(/<link\b([^>]*)>([\s\S]*?)<\/link\s*>/i);
  if (link) return decodeXml(link[2] || link[1].match(/href=["']([^"']+)["']/i)?.[1] || '');
  return decodeXml(block.match(/<link\b[^>]*href=["']([^"']+)["'][^>]*\/?\s*>/i)?.[1] || '');
}

function parseRssItems(xml) {
  const items = [];
  const itemRegex = /<(?:item|entry)\b[^>]*>([\s\S]*?)<\/(?:item|entry)\s*>/gi;
  let m;
  while ((m = itemRegex.exec(xml)) !== null) {
    const block = m[1];
    const title = xmlValue(block, 'title');
    const link = xmlLink(block) || xmlValue(block, 'guid') || xmlValue(block, 'id');
    const pub = xmlValue(block, 'pubDate') || xmlValue(block, 'published') ||
      xmlValue(block, 'updated') || xmlValue(block, 'dc:date') || xmlValue(block, 'date');
    const desc = xmlValue(block, 'description') || xmlValue(block, 'summary') || xmlValue(block, 'content');

    // 旧 RSS 使用带日期的 /news/html/... 链接，新 feed 使用 /newsweb/na/na-k...。
    const oldIdMatch = link.match(/\/news\/html\/(\d{8})\/([a-zA-Z0-9]+)\.html/i);
    const idSource = link || xmlValue(block, 'guid') || xmlValue(block, 'id');
    const modernIdMatch = idSource.match(/(?:^|\/)(?:na-)?(k\d+|nd-[a-z\d]+)(?:[/?#]|$)/i) ||
      idSource.match(/\b(?:na-)?(k\d+|nd-[a-z\d]+)\b/i);
    const id = oldIdMatch ? `${oldIdMatch[1]}-${oldIdMatch[2]}` : modernIdMatch ? modernIdMatch[1] : link;
    const publishedAt = pub && !Number.isNaN(Date.parse(pub)) ? new Date(pub).toISOString() : null;

    items.push({
      id,
      title,
      description: desc,
      link,
      publishedAt,
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
    // NHK moved its current news feeds to NHK ONE in 2026; the old www3 feed
    // stopped receiving new items. Keep it as a fallback for feed outages.
    let xml;
    let lastError;
    for (const url of [
      `https://news.web.nhk/n-data/conf/na/rss/cat${category}.xml`,
      `https://www3.nhk.or.jp/rss/news/cat${category}.xml`,
    ]) {
      try {
        xml = await httpGet(url);
        if (parseRssItems(xml).length) break;
        lastError = new Error('NHK feed returned no articles');
        xml = null;
      } catch (err) { lastError = err; }
    }
    if (!xml) throw lastError || new Error('NHK feed unavailable');
    const articles = parseRssItems(xml);
    if (!articles.length) throw new Error('NHK feed returned no articles');
    _nhkRssCache[cacheKey] = { data: articles, at: now };
    delete _nhkFailCache[cacheKey];
    return articles;
  } catch (err) {
    _nhkFailCache[cacheKey] = now;
    throw err;
  }
}

async function syncNhkCategory(category = '0') {
  const articles = await fetchNhkRss(category);
  for (const a of articles) {
    if (!a.id || !a.title) continue;
    // Older runs stored the whole NHK URL as nhk_id when they did not
    // recognize the newer nd-* identifiers. Repair those rows in place.
    const legacy = a.link && a.link !== a.id
      ? await NhkNewsCache.findOne({ where: { nhk_id: a.link } })
      : null;
    if (legacy) {
      const canonical = await NhkNewsCache.findOne({ where: { nhk_id: a.id } });
      if (canonical) await legacy.destroy();
      else await legacy.update({ nhk_id: a.id });
    }
    const [cached] = await NhkNewsCache.findOrCreate({
      where: { nhk_id: a.id },
      defaults: {
        nhk_id: a.id,
        title: a.title,
        description: a.description || '',
        body: a.description || '',
        link: a.link,
        category,
        published_at: a.publishedAt ? new Date(a.publishedAt) : null,
      },
    });
    if (cached) {
      await cached.update({
        title: a.title,
        description: a.description || '',
        body: (cached.body || '').length > (a.description || '').length
          ? cached.body : (a.description || ''),
        link: a.link,
        category,
        published_at: a.publishedAt ? new Date(a.publishedAt) : cached.published_at,
      });
    }
  }

  // Keep the cache bounded while preserving the newest articles.
  const allInCat = await NhkNewsCache.findAll({
    where: { category },
    order: [['published_at', 'DESC']],
    attributes: ['id'],
  });
  if (allInCat.length > 20) {
    await NhkNewsCache.destroy({ where: { id: allInCat.slice(20).map(r => r.id) } });
  }
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
    const articles = await syncNhkCategory(category);
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
    // Older clients only request history; refresh its feed on the first page
    // so they receive new NHK ONE articles without a client release.
    if (parseInt(page) <= 1) {
      try {
        const categoryToSync = category && NHK_CATEGORIES[category] ? category : '0';
        await syncNhkCategory(categoryToSync);
      } catch (_) { /* serve the last cached history if NHK is unavailable */ }
    }
    const { count, rows } = await NhkNewsCache.findAndCountAll({
      where,
      limit: Math.min(50, parseInt(limit)),
      offset,
      order: [['published_at', 'DESC']],
    });
    const data = rows.map(r => ({
      id: /^https?:\/\//i.test(r.nhk_id)
        ? (r.link.match(/\/(?:na\/)?(nd-[a-z\d]+|na-k\d+)/i)?.[1]?.replace(/^na-/, '') || r.nhk_id)
        : r.nhk_id,
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
  if (!/^(?:[\d]{8}-[a-zA-Z0-9]+|k\d+|nd-[a-zA-Z0-9]+)$/i.test(rawId)) {
    return res.status(400).json({ error: 'Invalid news ID' });
  }

  // 先查缓存
  let cached = null;
  try {
    cached = await NhkNewsCache.findOne({ where: { nhk_id: rawId } });
    if (!cached && rawId.startsWith('nd-')) {
      cached = await NhkNewsCache.findOne({
        where: { link: { [Op.like]: `%/${rawId}` } },
      });
    }
  } catch (_) {}

  // 构造文章链接
  const articleLink = cached?.link || buildArticleUrl(rawId);

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
  const meta = rawId.startsWith('nd-') ? null : await fetchNhkMetadata(rawId);

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
