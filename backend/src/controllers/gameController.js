const { Op } = require('sequelize');
const { sequelize } = require('../config/database');
const { GameScore, GameConfig } = require('../models');

// POST /api/v1/game/score  (auth required)
async function saveScore(req, res) {
  try {
    const { level_num, score, accuracy, max_combo, questions_answered, passed } = req.body;
    await GameScore.create({
      user_id: req.user.id,
      username: req.user.username || req.user.email || 'Unknown',
      level_num:           Math.max(1, Number(level_num)           || 1),
      score:               Math.max(0, Number(score)               || 0),
      accuracy:            Math.min(100, Math.max(0, Number(accuracy) || 0)),
      max_combo:           Math.max(0, Number(max_combo)           || 0),
      questions_answered:  Math.max(0, Number(questions_answered)  || 0),
      passed: !!passed,
    });
    res.json({ ok: true });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

// GET /api/v1/game/leaderboard?level=1  (public)
async function getLeaderboard(req, res) {
  const level = Math.max(1, parseInt(req.query.level) || 1);
  try {
    const rows = await GameScore.findAll({
      where: { level_num: level, passed: true },
      attributes: [
        'username',
        [sequelize.fn('MAX', sequelize.col('score')),              'best_score'],
        [sequelize.fn('MAX', sequelize.col('max_combo')),          'best_combo'],
        [sequelize.fn('ROUND', sequelize.fn('AVG', sequelize.col('accuracy')), 0), 'avg_acc'],
        [sequelize.fn('COUNT', sequelize.col('id')),              'plays'],
      ],
      group:  ['user_id', 'username'],
      order:  [[sequelize.fn('MAX', sequelize.col('score')), 'DESC']],
      limit:  20,
    });
    res.json({ ok: true, data: rows.map(r => r.toJSON()) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

// GET /api/v1/game/leaderboard/global  (public)
async function getGlobalLeaderboard(req, res) {
  try {
    const rows = await GameScore.findAll({
      where: { passed: true },
      attributes: [
        'user_id', 'username',
        [sequelize.fn('MAX', sequelize.col('level_num')),  'max_level'],
        [sequelize.fn('SUM', sequelize.col('score')),      'total_score'],
        [sequelize.fn('MAX', sequelize.col('max_combo')),  'best_combo'],
        [sequelize.fn('COUNT', sequelize.col('id')),       'levels_cleared'],
      ],
      group:  ['user_id', 'username'],
      order: [
        [sequelize.fn('MAX', sequelize.col('level_num')), 'DESC'],
        [sequelize.fn('SUM', sequelize.col('score')),     'DESC'],
      ],
      limit: 30,
    });
    res.json({ ok: true, data: rows.map(r => r.toJSON()) });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

// GET /api/v1/game/config  (public)
async function getConfig(req, res) {
  try {
    const cfgs = await GameConfig.findAll();
    const obj  = { max_levels: '10' };
    cfgs.forEach(c => { obj[c.config_key] = c.config_value; });
    res.json({ ok: true, config: obj });
  } catch (e) {
    res.json({ ok: true, config: { max_levels: '10' } });
  }
}

// PUT /api/v1/game/config  (admin only; uses adminAuth middleware in route)
async function updateConfig(req, res) {
  try {
    const ml = Math.max(1, Math.min(30, parseInt(req.body.max_levels) || 10));
    await GameConfig.upsert({
      config_key:   'max_levels',
      config_value: String(ml),
      updated_by:   req.user?.username || 'admin',
    });
    res.json({ ok: true, max_levels: ml });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

module.exports = { saveScore, getLeaderboard, getGlobalLeaderboard, getConfig, updateConfig };
