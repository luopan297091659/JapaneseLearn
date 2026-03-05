const { ListeningTrack } = require('../models');

async function list(req, res) {
  const { level, category, page = 1, limit = 20 } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  if (category) where.category = category;
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await ListeningTrack.findAndCountAll({
      where, limit: parseInt(limit), offset, order: [['created_at', 'DESC']],
    });
    res.json({ total: count, data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getById(req, res) {
  try {
    const track = await ListeningTrack.findByPk(req.params.id);
    if (!track) return res.status(404).json({ error: 'Not found' });
    await track.increment('play_count');
    res.json(track);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { list, getById };
