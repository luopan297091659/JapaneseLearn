const { NewsArticle } = require('../models');
const { Op } = require('sequelize');

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

module.exports = { list, getById };
