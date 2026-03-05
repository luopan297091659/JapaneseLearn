const { GrammarLesson, GrammarExample } = require('../models');

async function list(req, res) {
  const { level, page = 1, limit = 20 } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await GrammarLesson.findAndCountAll({
      where, limit: parseInt(limit), offset,
      include: [{ model: GrammarExample, as: 'examples' }],
      order: [['order_index', 'ASC']],
    });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getById(req, res) {
  try {
    const lesson = await GrammarLesson.findByPk(req.params.id, {
      include: [{ model: GrammarExample, as: 'examples' }],
    });
    if (!lesson) return res.status(404).json({ error: 'Not found' });
    res.json(lesson);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { list, getById };
