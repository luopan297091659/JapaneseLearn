const { GrammarLesson, GrammarExample } = require('../models');

// 级别总数缓存（grammar_lessons 不常变，缓存5分钟）
const _countCache = {};
const COUNT_TTL = 5 * 60 * 1000;

async function getLevelCount(level) {
  const now = Date.now();
  if (_countCache[level] && now - _countCache[level].ts < COUNT_TTL) {
    return _countCache[level].count;
  }
  const count = await GrammarLesson.count({ where: { jlpt_level: level } });
  _countCache[level] = { count, ts: now };
  return count;
}

async function list(req, res) {
  const { level, page = 1, limit = 20 } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  const pg = parseInt(page);
  const lim = Math.min(parseInt(limit), 100);
  const offset = (pg - 1) * lim;
  try {
    // 用缓存的 count 代替 findAndCountAll 的双查询
    const total = level ? await getLevelCount(level) : await GrammarLesson.count({ where });
    const rows = await GrammarLesson.findAll({
      where, limit: lim, offset,
      attributes: ['id', 'title', 'title_zh', 'jlpt_level', 'pattern', 'explanation_zh', 'order_index'],
      order: [['order_index', 'ASC']],
    });
    res.json({ total, page: pg, limit: lim, data: rows });
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
