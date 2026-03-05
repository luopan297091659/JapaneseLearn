const { Op } = require('sequelize');
const { v4: uuidv4 } = require('uuid');
const { Vocabulary } = require('../models');

async function list(req, res) {
  const { level, category, q, part_of_speech, page = 1, limit = 20 } = req.query;
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

  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await Vocabulary.findAndCountAll({
      where, limit: parseInt(limit), offset, order: [['jlpt_level', 'ASC'], ['word', 'ASC']],
    });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getById(req, res) {
  try {
    const vocab = await Vocabulary.findByPk(req.params.id);
    if (!vocab) return res.status(404).json({ error: 'Not found' });
    res.json(vocab);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getByLevel(req, res) {
  try {
    const words = await Vocabulary.findAll({
      where: { jlpt_level: req.params.level },
      limit: 100,
      order: [['word', 'ASC']],
    });
    res.json(words);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── Bulk import (from client-side Anki parser) ───────────────────────────────
async function bulkImport(req, res) {
  const {
    cards,
    deck_name    = 'Anki Import',
    jlpt_level   = 'N3',
    part_of_speech = 'other',
  } = req.body;

  if (!Array.isArray(cards) || cards.length === 0) {
    return res.status(400).json({ error: 'cards 数组不能为空' });
  }

  const VALID_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
  const VALID_POS    = ['noun','verb','adjective','adverb','particle','conjunction','interjection','other'];
  const safeLevel = VALID_LEVELS.includes(jlpt_level) ? jlpt_level : 'N3';
  const safePos   = VALID_POS.includes(part_of_speech) ? part_of_speech : 'other';

  const rows = cards
    .filter(c => c.word && String(c.word).trim())
    .map(c => ({
      id:              uuidv4(),
      word:            String(c.word).substring(0, 100),
      reading:         (c.reading ? String(c.reading) : String(c.word)).substring(0, 200),
      meaning_zh:      (c.meaning_zh ? String(c.meaning_zh) : (c.meaning_en ? String(c.meaning_en) : '-')).substring(0, 1000),
      meaning_en:      c.meaning_en  ? String(c.meaning_en).substring(0, 1000)  : null,
      example_sentence:c.example_sentence ? String(c.example_sentence).substring(0, 2000) : null,
      audio_url:       c.audio_url && (String(c.audio_url).startsWith('/uploads/') || String(c.audio_url).startsWith('http'))
                       ? String(c.audio_url).substring(0, 500) : null,
      part_of_speech:  safePos,
      jlpt_level:      safeLevel,
      category:        String(deck_name).substring(0, 50),
      tags:            JSON.stringify({ source: 'anki', deck: deck_name }),
    }));

  if (rows.length === 0) {
    return res.status(400).json({ error: '没有找到有效卡片' });
  }

  const CHUNK = 500;
  let imported = 0, failed = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const chunk = rows.slice(i, i + CHUNK);
    try {
      await Vocabulary.bulkCreate(chunk, { ignoreDuplicates: true });
      imported += chunk.length;
    } catch {
      failed += chunk.length;
    }
  }

  res.json({ success: true, imported, failed, total: rows.length, deck_name });
}

module.exports = { list, getById, getByLevel, bulkImport };
