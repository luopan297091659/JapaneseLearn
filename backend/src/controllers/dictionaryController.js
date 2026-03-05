const https = require('https');
const { sequelize } = require('../config/database');
const logger = require('../utils/logger');

// 简单内存缓存：避免相同词重复查库 / 重复翻译
const _zhCache = new Map(); // key: word, value: [{chinese_definitions, parts_of_speech}]

/**
 * 从本地词库查找中文释义
 * 匹配逻辑：word 或 reading 精确匹配 (slug 兜底)
 */
async function lookupChineseFromDb(word, reading) {
  const targets = [word, reading].filter(Boolean);
  if (targets.length === 0) return null;

  const cacheKey = targets[0];
  if (_zhCache.has(cacheKey)) return _zhCache.get(cacheKey);

  try {
    const placeholders = targets.map(() => '?').join(',');
    const [rows] = await sequelize.query(
      `SELECT word, reading, meaning_zh, meaning_en, part_of_speech
       FROM vocabularies
       WHERE word IN (${placeholders}) OR reading IN (${placeholders})
       LIMIT 5`,
      { replacements: [...targets, ...targets] }
    );
    if (!rows || rows.length === 0) {
      _zhCache.set(cacheKey, null);
      return null;
    }
    // 合并所有匹配行的中文释义
    const senses = rows.map(r => ({
      chinese_definitions: r.meaning_zh ? [r.meaning_zh] : [],
      parts_of_speech: r.part_of_speech ? [r.part_of_speech] : [],
    })).filter(s => s.chinese_definitions.length > 0);

    const result = senses.length > 0 ? senses : null;
    _zhCache.set(cacheKey, result);
    return result;
  } catch (err) {
    logger.warn('Dictionary DB lookup error:', err.message);
    return null;
  }
}

/**
 * 代理 Jisho.org 在线词典 API（纯网络查询，无本地数据库依赖）
 * GET /api/v1/dictionary/search?q=...&page=1&lang=zh
 */
async function search(req, res) {
  const { q, page = 1, lang = 'en' } = req.query;
  if (!q || q.trim().length === 0) {
    return res.status(400).json({ error: 'Query parameter "q" is required' });
  }

  const keyword = encodeURIComponent(q.trim());
  const jishoUrl = `https://jisho.org/api/v1/search/words?keyword=${keyword}&page=${page}`;

  try {
    const jishoData = await fetchJisho(jishoUrl);
    let results = (jishoData.data || []).map(normalizeJishoEntry);

    // 如果请求中文，尝试从本地词库注入 chinese_definitions
    if (lang === 'zh' && results.length > 0) {
      results = await Promise.all(results.map(async (entry) => {
        const zhSenses = await lookupChineseFromDb(entry.word, entry.reading);
        if (!zhSenses) return entry;
        // 将中文释义合并到 meanings 对应位置（索引对齐，超出部分忽略）
        const mergedMeanings = entry.meanings.map((m, i) => ({
          ...m,
          chinese_definitions: (zhSenses[i] ?? zhSenses[0]).chinese_definitions,
        }));
        return { ...entry, meanings: mergedMeanings };
      }));
    }

    res.json({ total: results.length, data: results, source: 'jisho' });
  } catch (err) {
    logger.error('Dictionary search error:', err.message);
    res.status(503).json({ error: 'Dictionary service unavailable', detail: err.message });
  }
}

/**
 * 单词详情  GET /api/v1/dictionary/word/:word
 */
async function detail(req, res) {
  const { word } = req.params;
  try {
    const keyword = encodeURIComponent(word);
    const jishoData = await fetchJisho(`https://jisho.org/api/v1/search/words?keyword=${keyword}`);
    const entry = jishoData.data && jishoData.data.length > 0
      ? normalizeJishoEntry(jishoData.data[0])
      : null;
    if (!entry) return res.status(404).json({ error: 'Word not found' });
    res.json(entry);
  } catch (err) {
    res.status(503).json({ error: 'Dictionary service unavailable', detail: err.message });
  }
}

/**
 * 汉字详情查询  GET /api/v1/dictionary/kanji/:char
 */
async function kanjiDetail(req, res) {
  const { char } = req.params;
  if (!char || [...char].length !== 1) {
    return res.status(400).json({ error: 'Provide exactly one kanji character' });
  }
  try {
    const keyword = encodeURIComponent(`#kanji ${char}`);
    const data = await fetchJisho(`https://jisho.org/api/v1/search/words?keyword=${keyword}`);
    res.json(data);
  } catch (err) {
    res.status(503).json({ error: 'Kanji lookup failed', detail: err.message });
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function fetchJisho(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, {
      timeout: 10000,
      headers: { 'User-Agent': 'JapaneseLearnApp/1.0' },
    }, (resp) => {
      let data = '';
      resp.on('data', chunk => { data += chunk; });
      resp.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('Invalid JSON from Jisho')); }
      });
    });
    req.on('error', reject);
    req.on('timeout', () => { req.destroy(); reject(new Error('Jisho request timeout')); });
  });
}

function normalizeJishoEntry(entry) {
  const japanese = entry.japanese || [];
  const senses = entry.senses || [];
  const attribution = entry.attribution || {};

  return {
    slug: entry.slug,
    url: `https://jisho.org/word/${entry.slug}`,
    is_common: entry.is_common || false,
    tags: entry.tags || [],
    jlpt: entry.jlpt || [],
    // Reading / writing variants
    japanese: japanese.map(j => ({ word: j.word, reading: j.reading })),
    // Primary (first) form
    word: japanese[0]?.word || entry.slug,
    reading: japanese[0]?.reading || '',
    // All meanings / senses
    meanings: senses.map(s => ({
      parts_of_speech: s.parts_of_speech || [],
      english_definitions: s.english_definitions || [],
      tags: s.tags || [],
      restrictions: s.restrictions || [],
      antonyms: s.antonyms || [],
      source: s.source || [],
      info: s.info || [],
      links: s.links || [],
    })),
    attribution,
    source: 'jisho',
  };
}

module.exports = { search, detail, kanjiDetail };
