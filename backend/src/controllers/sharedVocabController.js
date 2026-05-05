const fs = require('fs');
const path = require('path');
const { Op } = require('sequelize');
const { v4: uuidv4 } = require('uuid');
const { sequelize } = require('../config/database');
const { SharedVocabDeck, SharedVocabCard } = require('../models');
const User = require('../models/User');

const MAX_CARDS_PER_DECK = 10000;
const MAX_COVER_BYTES = 3 * 1024 * 1024;
const UPLOAD_COVER_DIR = path.join(__dirname, '../../uploads/shared-vocab-covers');

function ensureCoverDir() {
  fs.mkdirSync(UPLOAD_COVER_DIR, { recursive: true });
}

function clampText(value, max, fallback = '') {
  const text = value == null ? fallback : String(value).trim();
  return text.length > max ? text.slice(0, max) : text;
}

function normalizeTags(tags) {
  if (!Array.isArray(tags)) return [];
  return tags
    .map(tag => clampText(tag, 30))
    .filter(Boolean)
    .slice(0, 20);
}

function normalizeSourceType(value) {
  const allowed = new Set(['manual', 'apkg', 'csv', 'txt', 'tsv', 'paste', 'legacy']);
  return allowed.has(value) ? value : 'manual';
}

function normalizeVisibility(value) {
  const allowed = new Set(['private', 'public', 'unlisted']);
  return allowed.has(value) ? value : 'public';
}

function normalizeAudioUrl(value) {
  const url = clampText(value, 500);
  if (!url) return null;
  if (url.startsWith('/uploads/') || url.startsWith('/audio/') || url.startsWith('http://') || url.startsWith('https://')) {
    return url;
  }
  return null;
}

function inferLevel(cards, fallback) {
  if (fallback) return clampText(fallback, 10);
  const counts = new Map();
  for (const card of cards) {
    const level = clampText(card.jlpt_level || card.jlptLevel, 10);
    if (!level) continue;
    counts.set(level, (counts.get(level) || 0) + 1);
  }
  let best = '';
  let bestCount = 0;
  for (const [level, count] of counts.entries()) {
    if (count > bestCount) {
      best = level;
      bestCount = count;
    }
  }
  return best || null;
}

function normalizeCards(cards) {
  if (!Array.isArray(cards)) return [];
  return cards.slice(0, MAX_CARDS_PER_DECK).map((card, index) => {
    const word = clampText(card.word, 100);
    const meaningZh = clampText(card.meaning_zh || card.meaningZh, 2000);
    if (!word || !meaningZh) return null;
    return {
      deck_name: clampText(card.deck_name || card.deckName, 300) || null,
      word,
      reading: clampText(card.reading, 200, word),
      meaning_zh: meaningZh,
      meaning_en: clampText(card.meaning_en || card.meaningEn, 2000) || null,
      example_sentence: clampText(card.example_sentence || card.exampleSentence, 3000) || null,
      example_reading: clampText(card.example_reading || card.exampleReading, 1000) || null,
      example_meaning_zh: clampText(card.example_meaning_zh || card.exampleMeaningZh, 2000) || null,
      example_audio_url: normalizeAudioUrl(card.example_audio_url || card.exampleAudioUrl),
      audio_url: normalizeAudioUrl(card.audio_url || card.audioUrl),
      part_of_speech: clampText(card.part_of_speech || card.partOfSpeech, 50, 'other') || 'other',
      jlpt_level: clampText(card.jlpt_level || card.jlptLevel, 10) || null,
      sort_order: Number.isInteger(card.sort_order) ? card.sort_order : index,
      meta_json: card.meta_json || card.metaJson || null,
    };
  }).filter(Boolean);
}

function saveBase64Cover(base64) {
  if (!base64 || typeof base64 !== 'string') return null;
  const match = base64.match(/^data:image\/(png|jpe?g|webp);base64,(.+)$/i);
  if (!match) throw Object.assign(new Error('封面格式仅支持 png / jpg / webp base64'), { status: 400 });
  const ext = match[1].toLowerCase().replace('jpeg', 'jpg');
  const buffer = Buffer.from(match[2], 'base64');
  if (buffer.length > MAX_COVER_BYTES) {
    throw Object.assign(new Error('封面图片不能超过 3MB'), { status: 400 });
  }
  ensureCoverDir();
  const filename = `${uuidv4()}.${ext}`;
  fs.writeFileSync(path.join(UPLOAD_COVER_DIR, filename), buffer);
  return `/uploads/shared-vocab-covers/${filename}`;
}

async function serializeDeck(deck, { includeOwner = true } = {}) {
  const data = deck.toJSON ? deck.toJSON() : deck;
  if (!includeOwner) return data;
  const owner = await User.findByPk(data.owner_user_id, { attributes: ['id', 'username', 'avatar_url'] });
  return {
    ...data,
    owner: owner ? owner.toJSON() : null,
  };
}

async function createDeck(req, res) {
  const userId = req.user.id;
  const body = req.body || {};
  const cards = normalizeCards(body.cards);
  if (!cards.length) return res.status(400).json({ error: '请至少提供 1 张有效卡片' });

  const title = clampText(body.title || body.name || body.deck_name, 120);
  if (!title) return res.status(400).json({ error: '请提供词库名称' });

  const coverUrl = body.cover_url || saveBase64Cover(body.cover_image_base64 || body.coverBase64);
  const sourceType = normalizeSourceType(body.source_type || body.sourceType);
  const visibility = normalizeVisibility(body.visibility);
  const status = visibility === 'private' ? 'draft' : 'published';

  const deck = await sequelize.transaction(async (transaction) => {
    const created = await SharedVocabDeck.create({
      owner_user_id: userId,
      title,
      description: clampText(body.description, 5000) || null,
      cover_url: coverUrl || null,
      source_type: sourceType,
      jlpt_level: inferLevel(cards, body.jlpt_level || body.jlptLevel),
      tags: normalizeTags(body.tags),
      card_count: cards.length,
      visibility,
      status,
      meta_json: body.meta_json || body.metaJson || null,
    }, { transaction });

    await SharedVocabCard.bulkCreate(cards.map(card => ({ ...card, deck_id: created.id })), { transaction });
    return created;
  });

  res.status(201).json({ deck: await serializeDeck(deck) });
}

async function listPublicDecks(req, res) {
  const page = Math.max(parseInt(req.query.page || '1', 10), 1);
  const limit = Math.min(Math.max(parseInt(req.query.limit || '20', 10), 1), 50);
  const offset = (page - 1) * limit;
  const q = clampText(req.query.q, 100);
  const level = clampText(req.query.level, 10);
  const sourceType = clampText(req.query.source_type || req.query.sourceType, 20);

  const where = { visibility: 'public', status: 'published' };
  if (q) {
    where[Op.or] = [
      { title: { [Op.like]: `%${q}%` } },
      { description: { [Op.like]: `%${q}%` } },
    ];
  }
  if (level) where.jlpt_level = level;
  if (sourceType) where.source_type = normalizeSourceType(sourceType);

  const { count, rows } = await SharedVocabDeck.findAndCountAll({
    where,
    order: [['created_at', 'DESC']],
    limit,
    offset,
  });

  const decks = await Promise.all(rows.map(deck => serializeDeck(deck)));
  res.json({ decks, total: count, page, limit });
}

async function listMyDecks(req, res) {
  const rows = await SharedVocabDeck.findAll({
    where: { owner_user_id: req.user.id, status: { [Op.ne]: 'archived' } },
    order: [['created_at', 'DESC']],
  });
  res.json({ decks: rows.map(row => row.toJSON()) });
}

async function getDeckDetail(req, res) {
  const deck = await SharedVocabDeck.findByPk(req.params.id);
  if (!deck || deck.status === 'archived') return res.status(404).json({ error: '词库不存在' });
  const isOwner = req.user && req.user.id === deck.owner_user_id;
  if (deck.visibility === 'private' && !isOwner) return res.status(404).json({ error: '词库不存在' });

  const includeCards = req.query.cards !== '0';
  const result = await serializeDeck(deck);
  if (includeCards) {
    const limit = Math.min(Math.max(parseInt(req.query.limit || '500', 10), 1), 2000);
    const page = Math.max(parseInt(req.query.page || '1', 10), 1);
    const cards = await SharedVocabCard.findAll({
      where: { deck_id: deck.id },
      order: [['sort_order', 'ASC'], ['created_at', 'ASC']],
      limit,
      offset: (page - 1) * limit,
    });
    result.cards = cards.map(card => card.toJSON());
    result.cards_page = page;
    result.cards_limit = limit;
  }
  res.json({ deck: result });
}

async function updateDeck(req, res) {
  const deck = await SharedVocabDeck.findByPk(req.params.id);
  if (!deck || deck.status === 'archived') return res.status(404).json({ error: '词库不存在' });
  if (deck.owner_user_id !== req.user.id) return res.status(403).json({ error: '只能编辑自己的词库' });

  const body = req.body || {};
  const patch = {};
  if (body.title != null || body.name != null) patch.title = clampText(body.title || body.name, 120);
  if (body.description !== undefined) patch.description = clampText(body.description, 5000) || null;
  if (body.cover_url !== undefined) patch.cover_url = clampText(body.cover_url, 500) || null;
  if (body.cover_image_base64 || body.coverBase64) patch.cover_url = saveBase64Cover(body.cover_image_base64 || body.coverBase64);
  if (body.tags !== undefined) patch.tags = normalizeTags(body.tags);
  if (body.visibility !== undefined) {
    patch.visibility = normalizeVisibility(body.visibility);
    patch.status = patch.visibility === 'private' ? 'draft' : 'published';
  }
  if (body.jlpt_level !== undefined || body.jlptLevel !== undefined) patch.jlpt_level = clampText(body.jlpt_level || body.jlptLevel, 10) || null;
  if (body.meta_json !== undefined || body.metaJson !== undefined) patch.meta_json = body.meta_json || body.metaJson || null;

  await deck.update(patch);
  res.json({ deck: await serializeDeck(deck, { includeOwner: false }) });
}

async function deleteDeck(req, res) {
  const deck = await SharedVocabDeck.findByPk(req.params.id);
  if (!deck || deck.status === 'archived') return res.status(404).json({ error: '词库不存在' });
  if (deck.owner_user_id !== req.user.id) return res.status(403).json({ error: '只能删除自己的词库' });
  await deck.update({ status: 'archived' });
  res.json({ success: true });
}

async function importDeck(req, res) {
  const deck = await SharedVocabDeck.findByPk(req.params.id);
  if (!deck || deck.status !== 'published' || deck.visibility === 'private') {
    return res.status(404).json({ error: '词库不存在' });
  }
  await deck.increment('import_count');
  const cards = await SharedVocabCard.findAll({
    where: { deck_id: deck.id },
    order: [['sort_order', 'ASC'], ['created_at', 'ASC']],
  });
  res.json({
    deck: await serializeDeck(await deck.reload()),
    cards: cards.map(card => card.toJSON()),
  });
}

module.exports = {
  createDeck,
  listPublicDecks,
  listMyDecks,
  getDeckDetail,
  updateDeck,
  deleteDeck,
  importDeck,
};
