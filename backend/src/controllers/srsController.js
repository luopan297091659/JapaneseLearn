const { Op } = require('sequelize');
const { SrsCard, Vocabulary, GrammarLesson } = require('../models');
const { sm2 } = require('../utils/srs');

// Get cards due today for user
async function getDueCards(req, res) {
  const today = new Date().toISOString().split('T')[0];
  try {
    const cards = await SrsCard.findAll({
      where: {
        user_id: req.user.id,
        due_date: { [Op.lte]: today },
      },
      limit: parseInt(req.query.limit) || 20,
    });

    // Batch lookup instead of N+1
    const vocabIds = cards.filter(c => c.card_type === 'vocabulary').map(c => c.ref_id);
    const grammarIds = cards.filter(c => c.card_type !== 'vocabulary').map(c => c.ref_id);

    const [vocabs, grammars] = await Promise.all([
      vocabIds.length > 0 ? Vocabulary.findAll({ where: { id: vocabIds } }) : [],
      grammarIds.length > 0 ? GrammarLesson.findAll({ where: { id: grammarIds } }) : [],
    ]);

    const vocabMap = new Map(vocabs.map(v => [v.id, v]));
    const grammarMap = new Map(grammars.map(g => [g.id, g]));

    const enriched = cards.map(card => {
      const content = card.card_type === 'vocabulary'
        ? vocabMap.get(card.ref_id) || null
        : grammarMap.get(card.ref_id) || null;
      return { ...card.toJSON(), content };
    });

    res.json({ due_count: enriched.length, cards: enriched });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Submit review result
async function submitReview(req, res) {
  const { card_id, quality } = req.body; // quality: 0-5
  if (quality < 0 || quality > 5) return res.status(400).json({ error: 'Quality must be 0-5' });

  try {
    const card = await SrsCard.findOne({ where: { id: card_id, user_id: req.user.id } });
    if (!card) return res.status(404).json({ error: 'Card not found' });

    const updates = sm2(card, quality);
    await card.update(updates);
    res.json({ card, next_review: updates.due_date });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Add vocabulary to SRS deck
async function addCard(req, res) {
  const { ref_id, card_type = 'vocabulary' } = req.body;
  try {
    const [card, created] = await SrsCard.findOrCreate({
      where: { user_id: req.user.id, ref_id, card_type },
      defaults: {
        user_id: req.user.id,
        ref_id,
        card_type,
        due_date: new Date().toISOString().split('T')[0],
      },
    });
    res.status(created ? 201 : 200).json({ card, created });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Stats
async function getStats(req, res) {
  try {
    const total = await SrsCard.count({ where: { user_id: req.user.id } });
    const today = new Date().toISOString().split('T')[0];
    const due = await SrsCard.count({ where: { user_id: req.user.id, due_date: { [Op.lte]: today } } });
    const graduated = await SrsCard.count({ where: { user_id: req.user.id, is_graduated: true } });
    res.json({ total, due_today: due, graduated, learning: total - graduated });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// Get SRS card for a specific ref_id (to check status + get card_id for review)
async function getCardByRef(req, res) {
  const { ref_id } = req.params;
  try {
    const card = await SrsCard.findOne({
      where: { user_id: req.user.id, ref_id, card_type: 'vocabulary' },
    });
    if (!card) return res.status(404).json({ error: 'Not in SRS' });
    res.json(card);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { getDueCards, submitReview, addCard, getStats, getCardByRef };
