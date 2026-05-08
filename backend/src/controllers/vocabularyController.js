const { Op, Sequelize } = require('sequelize');
const { v4: uuidv4 } = require('uuid');
const { Vocabulary, UserVocabulary, SharedVocabCard, SharedVocabDeck } = require('../models');

// 从 word 字段中提取假名读音，如 "吉[よし]野[の]山[やま]" → "よしのやま"
function extractReading(word) {
  const w = String(word);
  const brackets = w.match(/\[([^\]]*)\]/g);
  if (brackets && brackets.length > 0) {
    return brackets.map(b => b.slice(1, -1)).join('');
  }
  return w;
}

// 每日更新的随机种子，保证分页一致性
const _dailySeed = () => Math.floor(Date.now() / 86400000);

async function list(req, res) {
  const { level, category, q, part_of_speech, page = 1, limit = 20 } = req.query;
  const pageNum = Math.max(parseInt(page, 10) || 1, 1);
  const limitNum = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 200);
  const where = {};
  if (level) where.jlpt_level = level;
  if (category) where.category = category;
  if (part_of_speech) where.part_of_speech = part_of_speech;
  if (q) {
    where[Op.or] = [
      { word: { [Op.like]: `%${q}%` } },
      { reading: { [Op.like]: `%${q}%` } },
      { meaning_zh: { [Op.like]: `%${q}%` } },
      { meaning_en: { [Op.like]: `%${q}%` } },
    ];
  }

  // N5 数据中排除与 N4 相同的词条（word + reading）
  if (level === 'N5') {
    const ands = Array.isArray(where[Op.and]) ? where[Op.and] : [];
    ands.push(Sequelize.literal(
      "NOT EXISTS (SELECT 1 FROM vocabulary v4 WHERE v4.jlpt_level = 'N4' AND v4.word = Vocabulary.word AND COALESCE(v4.reading, '') = COALESCE(Vocabulary.reading, ''))"
    ));
    where[Op.and] = ands;
  }

  const offset = (pageNum - 1) * limitNum;
  try {
    // 有搜索时按字母序，无搜索时按每日随机序（避免接头接尾词聚集在前面）
    let order = [['jlpt_level', 'ASC'], Sequelize.literal(`RAND(${_dailySeed()})`)];
    if (q) {
      const escaped = Vocabulary.sequelize.escape(String(q).trim());
      order = [
        [Sequelize.literal(`CASE
          WHEN word = ${escaped} THEN 0
          WHEN reading = ${escaped} THEN 1
          WHEN meaning_zh = ${escaped} THEN 2
          WHEN meaning_en = ${escaped} THEN 3
          WHEN word LIKE CONCAT(${escaped}, '%') THEN 4
          WHEN reading LIKE CONCAT(${escaped}, '%') THEN 5
          WHEN meaning_zh LIKE CONCAT(${escaped}, '%') THEN 6
          WHEN meaning_en LIKE CONCAT(${escaped}, '%') THEN 7
          ELSE 20
        END`), 'ASC'],
        ['jlpt_level', 'ASC'],
        ['word', 'ASC'],
      ];
    }
    const { count, rows } = await Vocabulary.findAndCountAll({
      where, limit: limitNum, offset, order,
    });
    let data = rows.map(row => row.toJSON());
    let total = count;
    if (q && !category && pageNum === 1) {
      const shared = await searchSharedCards(String(q).trim(), { level, partOfSpeech: part_of_speech, limit: limitNum });
      data = mergeVocabularyResults(data, shared).slice(0, limitNum);
      total += shared.length;
    }
    res.json({ total, page: pageNum, limit: limitNum, data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getById(req, res) {
  try {
    const vocab = await Vocabulary.findByPk(req.params.id);
    if (vocab) return res.json(vocab);
    const shared = await SharedVocabCard.findOne({
      where: { id: req.params.id },
      include: [{
        model: SharedVocabDeck,
        as: 'deck',
        attributes: ['id', 'title', 'visibility', 'status'],
        where: { status: 'published', visibility: { [Op.ne]: 'private' } },
      }],
    });
    if (!shared) return res.status(404).json({ error: 'Not found' });
    res.json(sharedCardToVocabulary(shared));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

function normalizeJlpt(level) {
  if (!level) return 'N5';
  const text = String(level).toUpperCase();
  return ['N5', 'N4', 'N3', 'N2', 'N1'].includes(text) ? text : 'N5';
}

function sharedCardToVocabulary(card) {
  const raw = card.toJSON ? card.toJSON() : card;
  const exampleSentences = raw.example_sentences || (raw.example_sentence ? [{
    jp: raw.example_sentence,
    reading: raw.example_reading,
    zh: raw.example_meaning_zh,
    audio_url: raw.example_audio_url,
  }] : null);

  return {
    id: raw.id,
    word: raw.word,
    reading: raw.reading || raw.word,
    meaning_zh: raw.meaning_zh,
    meaning_en: raw.meaning_en,
    part_of_speech: raw.part_of_speech || 'other',
    part_of_speech_raw: null,
    jlpt_level: normalizeJlpt(raw.jlpt_level),
    audio_url: raw.audio_url,
    image_url: null,
    category: raw.deck?.title || raw.deck_name || null,
    example_sentence: raw.example_sentence,
    example_reading: raw.example_reading,
    example_meaning_zh: raw.example_meaning_zh,
    example_audio_url: raw.example_audio_url,
    example_sentences: exampleSentences,
    tags: raw.deck?.title ? { source: 'shared_vocab', deck: raw.deck.title } : { source: 'shared_vocab' },
  };
}

async function searchSharedCards(query, { level, partOfSpeech, limit }) {
  if (!query) return [];
  const escaped = SharedVocabCard.sequelize.escape(query);
  const where = {
    [Op.or]: [
      { word: { [Op.like]: `%${query}%` } },
      { reading: { [Op.like]: `%${query}%` } },
      { meaning_zh: { [Op.like]: `%${query}%` } },
      { meaning_en: { [Op.like]: `%${query}%` } },
    ],
  };
  if (level) where.jlpt_level = level;
  if (partOfSpeech) where.part_of_speech = partOfSpeech;

  const rows = await SharedVocabCard.findAll({
    where,
    include: [{
      model: SharedVocabDeck,
      as: 'deck',
      attributes: ['id', 'title', 'visibility', 'status'],
      where: { status: 'published', visibility: { [Op.ne]: 'private' } },
    }],
    order: [
      [Sequelize.literal(`CASE
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
  return rows.map(sharedCardToVocabulary);
}

function mergeVocabularyResults(primary, secondary) {
  const merged = [];
  const seen = new Set();
  for (const item of [...primary, ...secondary]) {
    const key = `${item.word || ''}|${item.reading || ''}|${item.meaning_zh || ''}`;
    if (seen.has(key)) continue;
    seen.add(key);
    merged.push(item);
  }
  return merged;
}

async function getByLevel(req, res) {
  try {
    const { Sequelize } = require('sequelize');
    const limit = Math.min(parseInt(req.query.limit) || 100, 200);
    const words = await Vocabulary.findAll({
      where: { jlpt_level: req.params.level },
      limit,
      order: Sequelize.fn('RAND'),
    });
    res.json(words);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getIdsByLevel(req, res) {
  try {
    const where = { jlpt_level: req.params.level };
    if (req.params.level === 'N5') {
      where[Op.and] = [
        Sequelize.literal(
          "NOT EXISTS (SELECT 1 FROM vocabulary v4 WHERE v4.jlpt_level = 'N4' AND v4.word = Vocabulary.word AND COALESCE(v4.reading, '') = COALESCE(Vocabulary.reading, ''))"
        ),
      ];
    }
    const rows = await Vocabulary.findAll({
      where,
      attributes: ['id'],
      order: [Sequelize.literal(`RAND(${_dailySeed()})`)],
    });
    res.json(rows.map(r => r.id));
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── Bulk import (from client-side Anki parser → user_vocabulary) ─────────────
async function bulkImport(req, res) {
  const {
    cards,
    deck_name    = 'Anki Import',
    jlpt_level,
    part_of_speech = 'other',
  } = req.body;

  if (!Array.isArray(cards) || cards.length === 0) {
    return res.status(400).json({ error: 'cards 数组不能为空' });
  }

  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: '未登录' });

  const VALID_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
  const VALID_POS    = ['noun','verb','adjective','adverb','particle','conjunction','interjection','other'];
  const safeLevel = VALID_LEVELS.includes(jlpt_level) ? jlpt_level : null;
  const safePos   = VALID_POS.includes(part_of_speech) ? part_of_speech : 'other';

  const rows = cards
    .filter(c => c.word && String(c.word).trim())
    .map(c => ({
      id:              c.id || uuidv4(),
      user_id:         userId,
      word:            String(c.word).substring(0, 100),
      reading:         (c.reading ? String(c.reading) : extractReading(c.word)).substring(0, 200),
      meaning_zh:      (c.meaning_zh ? String(c.meaning_zh) : (c.meaning_en ? String(c.meaning_en) : '-')).substring(0, 1000),
      meaning_en:      c.meaning_en  ? String(c.meaning_en).substring(0, 1000)  : null,
      example_sentence:c.example_sentence ? String(c.example_sentence).substring(0, 2000) : null,
      example_audio_url:c.example_audio_url && (String(c.example_audio_url).startsWith('/uploads/') || String(c.example_audio_url).startsWith('/audio/') || String(c.example_audio_url).startsWith('http'))
                       ? String(c.example_audio_url).substring(0, 500) : null,
      audio_url:       c.audio_url && (String(c.audio_url).startsWith('/uploads/') || String(c.audio_url).startsWith('/audio/') || String(c.audio_url).startsWith('http'))
                       ? String(c.audio_url).substring(0, 500) : null,
      part_of_speech:  safePos,
      jlpt_level:      VALID_LEVELS.includes(c.jlpt_level) ? c.jlpt_level : safeLevel,
      deck_name:       String(deck_name).substring(0, 100),
      source:          'anki',
      tags:            { deck: deck_name },
    }));

  if (rows.length === 0) {
    return res.status(400).json({ error: '没有找到有效卡片' });
  }

  const CHUNK = 500;
  let imported = 0, failed = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const chunk = rows.slice(i, i + CHUNK);
    try {
      await UserVocabulary.bulkCreate(chunk, { ignoreDuplicates: true });
      imported += chunk.length;
    } catch {
      failed += chunk.length;
    }
  }

  res.json({ success: true, imported, failed, total: rows.length, deck_name });
}

// ─── 用户词库列表 ───────────────────────────────────────────────────────────
async function listUserVocab(req, res) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: '未登录' });

  const { deck_name, level, q, page = 1, limit = 30 } = req.query;
  const where = { user_id: userId };
  if (deck_name) where.deck_name = deck_name;
  if (level) where.jlpt_level = level;
  if (q) {
    where[Op.or] = [
      { word: { [Op.like]: `%${q}%` } },
      { reading: { [Op.like]: `%${q}%` } },
      { meaning_zh: { [Op.like]: `%${q}%` } },
    ];
  }

  try {
    const { count, rows } = await UserVocabulary.findAndCountAll({
      where,
      limit: Math.min(parseInt(limit), 200),
      offset: (parseInt(page) - 1) * parseInt(limit),
      order: [['created_at', 'DESC']],
    });
    res.json({ total: count, page: parseInt(page), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 用户牌组列表 ───────────────────────────────────────────────────────────
async function listUserDecks(req, res) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: '未登录' });

  try {
    const { sequelize } = require('../models');
    const [rows] = await sequelize.query(`
      SELECT deck_name, COUNT(*) AS card_count,
             MIN(created_at) AS first_import, MAX(created_at) AS last_import
      FROM user_vocabulary
      WHERE user_id = :userId
      GROUP BY deck_name
      ORDER BY last_import DESC
    `, { replacements: { userId } });
    res.json(rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 删除用户牌组 ───────────────────────────────────────────────────────────
async function deleteUserDeck(req, res) {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: '未登录' });

  const { deck_name } = req.body;
  if (!deck_name) return res.status(400).json({ error: '缺少 deck_name' });

  try {
    const count = await UserVocabulary.destroy({
      where: { user_id: userId, deck_name },
    });
    res.json({ deleted: count, message: `已删除牌组「${deck_name}」的 ${count} 张卡片` });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { list, getById, getByLevel, getIdsByLevel, bulkImport, listUserVocab, listUserDecks, deleteUserDeck };
