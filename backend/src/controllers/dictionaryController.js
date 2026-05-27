const https = require('https');
const { Op } = require('sequelize');
const { sequelize } = require('../config/database');
const { DictEntry, DictTransCache, SharedVocabCard, SharedVocabDeck } = require('../models');
const logger = require('../utils/logger');

// ─── AI 翻译辅助 ────────────────────────────────────────────────────────────
let _callAI = null;
function getCallAI() {
  if (!_callAI) {
    try { _callAI = require('./aiController').callAI; }
    catch { _callAI = false; }
  }
  return _callAI || null;
}

/**
 * 用 AI 把英文释义翻译成中文，并缓存到 dict_trans_cache
 * 输入：{word, reading, meaning_en}
 * 返回：中文释义字符串 或 null
 */
async function translateWithAI(word, reading, meaningEn) {
  if (!meaningEn) return null;
  const callAI = getCallAI();
  if (!callAI) return null;

  // 先查缓存
  try {
    const cached = await DictTransCache.findOne({
      where: { word: word || '', reading: reading || '' },
    });
    if (cached && cached.meaning_zh) return cached.meaning_zh;
  } catch (e) { /* 忽略 */ }

  // AI 翻译
  try {
    const prompt = `你是日语词典翻译助手。请将以下日语单词的英文释义翻译成简洁准确的中文释义。
单词: ${word || ''}（${reading || ''}）
英文释义: ${meaningEn}

要求:
1. 只返回中文释义，多个义项用"；"分隔
2. 保持简洁，每个义项不超过15个字
3. 不要添加额外说明`;

    const result = await callAI(prompt, 512);
    const zh = result.trim();
    if (zh) {
      // 写入缓存
      await DictTransCache.upsert({
        word: word || '',
        reading: reading || '',
        meaning_en: meaningEn.substring(0, 1000),
        meaning_zh: zh,
      }).catch(() => {});
      return zh;
    }
  } catch (err) {
    logger.warn('AI translate dict error:', err.message);
  }
  return null;
}

// ─── 判断查询类型 ────────────────────────────────────────────────────────────
function isChinese(str) {
  const hasCJK = /[\u4e00-\u9fff]/.test(str);
  const hasKana = /[\u3040-\u309f\u30a0-\u30ff]/.test(str);
  return hasCJK && !hasKana;
}

function isKana(str) {
  return /^[\u3040-\u309f\u30a0-\u30ff\u30fc\u3005ー]+$/.test(str);
}

// ─── 本地 JMdict 搜索 ────────────────────────────────────────────────────────

/**
 * 从 dict_entries 表搜索
 * 支持: 日文汉字 / 假名 / 英文 / 中文
 * 排序: 精确匹配 > 前缀匹配 > 模糊匹配，同级按 priority DESC
 */
async function searchLocal(query, limit = 30) {
  const q = query.trim();
  if (!q) return [];

  try {
    let where;
    // 用 CASE WHEN 计算相关性分数：精确匹配=100, 前缀匹配=50, 模糊匹配=10
    let relevanceExpr;

    if (isChinese(q)) {
      where = {
        [Op.or]: [
          { meaning_zh: { [Op.like]: `%${q}%` } },
          { kanji: q },
        ],
      };
      relevanceExpr = sequelize.literal(
        `(CASE WHEN kanji = ${sequelize.escape(q)} THEN 100 ` +
        `WHEN meaning_zh LIKE ${sequelize.escape(q + '%')} THEN 50 ` +
        `ELSE 10 END)`
      );
    } else if (isKana(q)) {
      where = {
        [Op.or]: [
          { reading: q },
          { reading: { [Op.like]: `${q}%` } },
        ],
      };
      relevanceExpr = sequelize.literal(
        `(CASE WHEN reading = ${sequelize.escape(q)} THEN 100 ` +
        `WHEN reading LIKE ${sequelize.escape(q + '%')} THEN 50 ` +
        `ELSE 10 END)`
      );
    } else if (/^[a-zA-Z\s]+$/.test(q)) {
      where = { meaning_en: { [Op.like]: `%${q}%` } };
      relevanceExpr = sequelize.literal(
        `(CASE WHEN meaning_en LIKE ${sequelize.escape(q)} THEN 100 ` +
        `WHEN meaning_en LIKE ${sequelize.escape(q + '%')} THEN 50 ` +
        `ELSE 10 END)`
      );
    } else {
      // 日文汉字 / 混合: 增加 reading 前缀匹配
      where = {
        [Op.or]: [
          { kanji: q },
          { kanji: { [Op.like]: `${q}%` } },
          { reading: q },
          { reading: { [Op.like]: `${q}%` } },
          { meaning_zh: { [Op.like]: `%${q}%` } },
        ],
      };
      relevanceExpr = sequelize.literal(
        `(CASE WHEN kanji = ${sequelize.escape(q)} THEN 100 ` +
        `WHEN reading = ${sequelize.escape(q)} THEN 90 ` +
        `WHEN kanji LIKE ${sequelize.escape(q + '%')} THEN 50 ` +
        `WHEN reading LIKE ${sequelize.escape(q + '%')} THEN 40 ` +
        `ELSE 10 END)`
      );
    }

    const rows = await DictEntry.findAll({
      where,
      attributes: {
        include: [[relevanceExpr, '_relevance']],
      },
      order: [
        [sequelize.literal('_relevance'), 'DESC'],
        ['priority', 'DESC'],
      ],
      limit,
    });

    return rows.map(r => dictEntryToResult(r));
  } catch (err) {
    logger.warn('Local dict search error:', err.message);
    return [];
  }
}

/**
 * 本地精确查找（用于详情页和缓存注入）
 */
async function lookupLocal(word, reading) {
  const conditions = [];
  if (word) conditions.push({ kanji: word });
  if (reading) conditions.push({ reading });
  if (conditions.length === 0) return null;

  try {
    const row = await DictEntry.findOne({
      where: { [Op.or]: conditions },
      order: [['priority', 'DESC']],
    });
    return row;
  } catch { return null; }
}

async function searchSharedLocal(query, limit = 20) {
  const q = query.trim();
  if (!q) return [];

  try {
    const escaped = sequelize.escape(q);
    const rows = await SharedVocabCard.findAll({
      where: {
        [Op.or]: [
          { word: { [Op.like]: `%${q}%` } },
          { reading: { [Op.like]: `%${q}%` } },
          { meaning_zh: { [Op.like]: `%${q}%` } },
          { meaning_en: { [Op.like]: `%${q}%` } },
        ],
      },
      include: [{
        model: SharedVocabDeck,
        as: 'deck',
        attributes: ['id', 'title', 'visibility', 'status'],
        where: { status: 'published', visibility: { [Op.ne]: 'private' } },
      }],
      order: [
        [sequelize.literal(`CASE
          WHEN SharedVocabCard.word = ${escaped} THEN 0
          WHEN SharedVocabCard.reading = ${escaped} THEN 1
          WHEN SharedVocabCard.meaning_zh = ${escaped} THEN 2
          WHEN SharedVocabCard.meaning_en = ${escaped} THEN 3
          WHEN SharedVocabCard.word LIKE CONCAT(${escaped}, '%') THEN 4
          WHEN SharedVocabCard.reading LIKE CONCAT(${escaped}, '%') THEN 5
          WHEN SharedVocabCard.meaning_zh LIKE CONCAT(${escaped}, '%') THEN 6
          WHEN SharedVocabCard.meaning_en LIKE CONCAT(${escaped}, '%') THEN 7
          ELSE 20
        END`), 'ASC'],
        ['sort_order', 'ASC'],
        ['created_at', 'DESC'],
      ],
      limit,
    });
    return rows.map(sharedCardToResult);
  } catch (err) {
    logger.warn('Shared vocab dict search error:', err.message);
    return [];
  }
}

function normalizeJlptTag(level) {
  if (!level) return [];
  const text = String(level).toUpperCase();
  return ['N5', 'N4', 'N3', 'N2', 'N1'].includes(text) ? [`jlpt-${text.toLowerCase()}`] : [];
}

function sharedCardToResult(row) {
  const card = row.toJSON ? row.toJSON() : row;
  const pos = card.part_of_speech ? [card.part_of_speech] : [];
  return {
    slug: card.word || card.reading,
    url: '',
    is_common: true,
    tags: card.deck?.title ? [`shared:${card.deck.title}`] : ['shared'],
    jlpt: normalizeJlptTag(card.jlpt_level),
    japanese: [{ word: card.word, reading: card.reading || card.word }],
    word: card.word || card.reading,
    reading: card.reading || '',
    meanings: [{
      parts_of_speech: pos,
      english_definitions: card.meaning_en ? [card.meaning_en] : [],
      chinese_definitions: card.meaning_zh ? [card.meaning_zh] : [],
      tags: [], restrictions: [], antonyms: [], source: [], info: [], links: [],
    }],
    example_sentence: card.example_sentence,
    example_reading: card.example_reading,
    example_meaning_zh: card.example_meaning_zh,
    example_audio_url: card.example_audio_url,
    audio_url: card.audio_url,
    attribution: {},
    source: 'shared',
  };
}

function rankDictionaryResult(entry, query) {
  const q = String(query || '').trim();
  if (!q) return 100;
  const word = entry.word || '';
  const reading = entry.reading || '';
  const meanings = (entry.meanings || [])
    .flatMap(m => [...(m.chinese_definitions || []), ...(m.english_definitions || [])])
    .join('; ');
  if (word === q) return 0;
  if (reading === q) return 1;
  if (meanings === q) return 2;
  if (word.startsWith(q)) return 4;
  if (reading.startsWith(q)) return 5;
  if (meanings.startsWith(q)) return 6;
  if (word.includes(q)) return 10;
  if (reading.includes(q)) return 11;
  if (meanings.includes(q)) return 12;
  return 100;
}

function extractJson(text) {
  const fenceMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenceMatch) return JSON.parse(fenceMatch[1].trim());
  const jsonStart = text.search(/[\[{]/);
  if (jsonStart >= 0) {
    const candidate = text.slice(jsonStart);
    const lastBracket = Math.max(candidate.lastIndexOf(']'), candidate.lastIndexOf('}'));
    if (lastBracket >= 0) return JSON.parse(candidate.slice(0, lastBracket + 1));
  }
  return JSON.parse(text.trim());
}

async function lookupWithAI(query) {
  const q = String(query || '').trim();
  if (!q) return null;
  const callAI = getCallAI();
  if (!callAI) return null;

  try {
    const prompt = `你是日语词典助手。系统词库和外部辞书都没有查到「${q}」，请判断它是否可能是日语单词、短语、变形、外来语、专有名词或用户输入的近似词。

请只返回 JSON 对象，不要 markdown：
{
  "word": "标准词形或原输入",
  "reading": "假名读音，不确定则为空",
  "meaning_zh": "中文释义，多个义项用；分隔",
  "meaning_en": "English meaning, optional",
  "part_of_speech": "noun|verb|adjective|adverb|particle|conjunction|interjection|expression|proper noun|other",
  "jlpt": "",
  "is_confident": true,
  "note": "如果是推测、变形或可能拼写错误，简短说明"
}

要求：
1. 如果完全不像日语或无法判断，is_confident 设为 false，但仍给出可能解释或提示。
2. meaning_zh 必须有内容。
3. 不要编造不存在的确定出处。`;

    const result = await callAI(prompt, 1024);
    const detail = extractJson(result);
    const meaningZh = String(detail.meaning_zh || detail.meaning || detail.explanation || '').trim();
    if (!meaningZh) return null;
    const word = String(detail.word || q).trim() || q;
    const reading = String(detail.reading || detail.furigana || '').trim();
    const pos = String(detail.part_of_speech || detail.pos || 'other').trim();
    const note = String(detail.note || '').trim();
    const jlpt = String(detail.jlpt || '').trim().toLowerCase();

    return {
      slug: word,
      url: '',
      is_common: false,
      tags: detail.is_confident === false ? ['AI推测'] : ['AI'],
      jlpt: /^n[1-5]$/.test(jlpt) ? [`jlpt-${jlpt}`] : [],
      japanese: [{ word, reading }],
      word,
      reading,
      meanings: [{
        parts_of_speech: pos ? [pos] : [],
        english_definitions: detail.meaning_en ? [String(detail.meaning_en)] : [],
        chinese_definitions: [meaningZh],
        tags: [], restrictions: [], antonyms: [], source: [], info: note ? [note] : [], links: [],
      }],
      attribution: {},
      source: 'ai',
    };
  } catch (err) {
    logger.warn('AI dict fallback error:', err.message);
    return null;
  }
}

// ─── 清理 reading 中的括号 ──────────────────────────────────────────────────────
/**
 * 去除 reading 中的 [] 或【】 括号
 * 例如: "[しゃいん]" -> "しゃいん", "社員[しゃいん]" -> "社員しゃいん"
 */
function cleanReading(reading) {
  if (!reading) return '';
  return reading.replace(/[\[\【]/g, '').replace(/[\]\】]/g, '');
}

/**
 * 将 DictEntry 数据库行转为前端兼容的结果格式
 */
function dictEntryToResult(row) {
  const meanings = [];
  const enParts = (row.meaning_en || '').split('；');
  const zhParts = (row.meaning_zh || '').split('；');
  const posArr = (row.pos || '').split('; ').filter(Boolean);

  // 每个义项组
  const maxLen = Math.max(enParts.length, 1);
  for (let i = 0; i < maxLen; i++) {
    meanings.push({
      parts_of_speech: i === 0 ? posArr : [],
      english_definitions: enParts[i] ? [enParts[i]] : [],
      chinese_definitions: zhParts[i] ? [zhParts[i]] : (zhParts[0] ? [zhParts[0]] : []),
      tags: [], restrictions: [], antonyms: [], source: [], info: [], links: [],
    });
  }

  const cleanedReading = cleanReading(row.reading || '');
  
  return {
    slug: row.kanji || cleanedReading,
    url: '',
    is_common: row.priority >= 4,
    tags: [],
    jlpt: row.jlpt ? [`jlpt-n${row.jlpt}`] : [],
    japanese: [{ word: row.kanji, reading: cleanedReading }],
    word: row.kanji || cleanedReading,
    reading: cleanedReading,
    meanings,
    attribution: {},
    source: 'local',
  };
}

// ─── Jisho.org 备用 ──────────────────────────────────────────────────────────

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
  const cleanedReading = cleanReading(japanese[0]?.reading || '');
  return {
    slug: entry.slug,
    url: `https://jisho.org/word/${entry.slug}`,
    is_common: entry.is_common || false,
    tags: entry.tags || [],
    jlpt: entry.jlpt || [],
    japanese: japanese.map(j => ({ word: j.word, reading: cleanReading(j.reading || '') })),
    word: japanese[0]?.word || entry.slug,
    reading: cleanedReading,
    meanings: senses.map(s => ({
      parts_of_speech: s.parts_of_speech || [],
      english_definitions: s.english_definitions || [],
      chinese_definitions: [],
      tags: s.tags || [],
      restrictions: s.restrictions || [],
      antonyms: s.antonyms || [],
      source: s.source || [],
      info: s.info || [],
      links: s.links || [],
    })),
    attribution: entry.attribution || {},
    source: 'jisho',
  };
}

// ─── API Handlers ────────────────────────────────────────────────────────────

/**
 * 搜索  GET /api/v1/dictionary/search?q=...&page=1&lang=zh
 *
 * 优先级：JMdict 本地 → Jisho 在线补充 → AI 翻译中文
 */
async function search(req, res) {
  const { q, page = 1, lang = 'en' } = req.query;
  if (!q || q.trim().length === 0) {
    return res.status(400).json({ error: 'Query parameter "q" is required' });
  }

  try {
    // 1. 本地 JMdict 搜索
    let results = await searchLocal(q, 30);
    const sharedResults = await searchSharedLocal(q, 20);
    if (sharedResults.length > 0) {
      results = results.concat(sharedResults);
    }
    let source = 'local';

    // 2. 如果本地结果不足，用 Jisho 补充
    if (results.length < 3) {
      try {
        const keyword = encodeURIComponent(q.trim());
        const jishoData = await fetchJisho(
          `https://jisho.org/api/v1/search/words?keyword=${keyword}&page=${page}`
        );
        const jishoResults = (jishoData.data || []).map(normalizeJishoEntry);

        // 去重合并
        const seenWords = new Set(results.map(r => `${r.word}|${r.reading}`));
        for (const entry of jishoResults) {
          const key = `${entry.word}|${entry.reading}`;
          if (!seenWords.has(key)) {
            // 尝试从本地补中文释义
            const localRow = await lookupLocal(entry.word, entry.reading);
            if (localRow && localRow.meaning_zh) {
              entry.meanings.forEach(m => {
                m.chinese_definitions = [localRow.meaning_zh];
              });
              entry.source = 'local+jisho';
            }
            results.push(entry);
            seenWords.add(key);
          }
        }
        if (jishoResults.length > 0) source = 'local+jisho';
      } catch (jishoErr) {
        // Jisho 失败不影响本地结果
        if (results.length === 0) {
          logger.warn('Jisho fallback also failed:', jishoErr.message);
        }
      }
    }

    // 3. 对缺少中文释义的结果，尝试 AI 翻译（仅前 5 条，避免大量 AI 调用）
    const needTranslate = results
      .filter(r => (!r.meanings[0]?.chinese_definitions?.length ||
                    r.meanings[0].chinese_definitions[0] === '') &&
                    r.meanings[0]?.english_definitions?.length > 0)
      .slice(0, 5);

    if (needTranslate.length > 0) {
      await Promise.all(needTranslate.map(async (entry) => {
        const allEn = entry.meanings.map(m => m.english_definitions.join(', ')).filter(Boolean).join('; ');
        const zh = await translateWithAI(entry.word, entry.reading, allEn);
        if (zh) {
          entry.meanings.forEach(m => {
            if (!m.chinese_definitions || m.chinese_definitions.length === 0 || m.chinese_definitions[0] === '') {
              m.chinese_definitions = [zh];
            }
          });
        }
      }));
    }

    // 4. 去重：按 word|reading 去掉重复条目
    if (results.length === 0) {
      const aiResult = await lookupWithAI(q);
      if (aiResult) {
        results.push(aiResult);
        source = 'ai';
      }
    }

    results.sort((a, b) => rankDictionaryResult(a, q) - rankDictionaryResult(b, q));

    const deduped = [];
    const seenKeys = new Set();
    for (const entry of results) {
      const key = `${entry.word}|${entry.reading}`;
      if (!seenKeys.has(key)) {
        seenKeys.add(key);
        deduped.push(entry);
      }
    }

    res.json({ total: deduped.length, data: deduped, source });
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
    // 先查本地
    const localRow = await lookupLocal(word, null);
    if (localRow) {
      const entry = dictEntryToResult(localRow);
      // 如果没有中文释义，尝试 AI 翻译
      if (!localRow.meaning_zh && localRow.meaning_en) {
        const zh = await translateWithAI(localRow.kanji, localRow.reading, localRow.meaning_en);
        if (zh) {
          entry.meanings.forEach(m => { m.chinese_definitions = [zh]; });
        }
      }
      return res.json(entry);
    }

    // 本地无结果，fallback Jisho
    const keyword = encodeURIComponent(word);
    let raw = null;
    try {
      const jishoData = await fetchJisho(`https://jisho.org/api/v1/search/words?keyword=${keyword}`);
      raw = jishoData.data && jishoData.data.length > 0 ? jishoData.data[0] : null;
    } catch (jishoErr) {
      logger.warn('Jisho detail fallback failed:', jishoErr.message);
    }
    if (!raw) {
      const aiEntry = await lookupWithAI(word);
      if (aiEntry) return res.json(aiEntry);
      return res.status(404).json({ error: 'Word not found' });
    }

    const entry = normalizeJishoEntry(raw);
    // AI 翻译
    const allEn = entry.meanings.map(m => m.english_definitions.join(', ')).filter(Boolean).join('; ');
    const zh = await translateWithAI(entry.word, entry.reading, allEn);
    if (zh) {
      entry.meanings.forEach(m => { m.chinese_definitions = [zh]; });
    }
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

module.exports = { search, detail, kanjiDetail };
