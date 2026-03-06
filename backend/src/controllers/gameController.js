const { Op } = require('sequelize');
const { sequelize } = require('../config/database');
const { GameScore, GameConfig } = require('../models');

// POST /api/v1/game/score  (auth required)
async function saveScore(req, res) {
  try {
    const { level_num, score, accuracy, max_combo, questions_answered, passed, speed_ms } = req.body;
    await GameScore.create({
      user_id: req.user.id,
      username: req.user.username || req.user.email || 'Unknown',
      level_num:           Math.max(1, Number(level_num)           || 1),
      score:               Math.max(0, Number(score)               || 0),
      accuracy:            Math.min(100, Math.max(0, Number(accuracy) || 0)),
      max_combo:           Math.max(0, Number(max_combo)           || 0),
      questions_answered:  Math.max(0, Number(questions_answered)  || 0),
      passed: !!passed,
      base_speed_ms: Math.max(100, Math.min(10000, Number(speed_ms) || 2000)),
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
// rating = SUM(score) * 5000 / AVG(base_speed_ms)  — 越快越高
async function getGlobalLeaderboard(req, res) {
  // 尝试速度加权排行，若列不存在则降级为普通排行
  async function queryWithSpeed() {
    return GameScore.findAll({
      where: { passed: true },
      attributes: [
        'user_id', 'username',
        [sequelize.fn('MAX', sequelize.col('level_num')),  'max_level'],
        [sequelize.fn('SUM', sequelize.col('score')),      'total_score'],
        [sequelize.fn('MAX', sequelize.col('max_combo')),  'best_combo'],
        [sequelize.fn('COUNT', sequelize.col('id')),       'levels_cleared'],
        [sequelize.fn('ROUND', sequelize.fn('AVG', sequelize.col('base_speed_ms')), 0), 'avg_speed_ms'],
        [sequelize.literal(
          'ROUND(SUM(score) * 5000.0 / AVG(COALESCE(base_speed_ms, 2000)), 0)'
        ), 'rating'],
      ],
      group:  ['user_id', 'username'],
      order:  [[sequelize.literal('ROUND(SUM(score) * 5000.0 / AVG(COALESCE(base_speed_ms, 2000)), 0)'), 'DESC']],
      limit: 30,
    });
  }
  async function queryBasic() {
    return GameScore.findAll({
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
  }
  try {
    try {
      const rows = await queryWithSpeed();
      return res.json({ ok: true, data: rows.map(r => r.toJSON()) });
    } catch (colErr) {
      if (colErr.message && colErr.message.includes('base_speed_ms')) {
        // 列尚未迁移，降级为基础排行
        const rows = await queryBasic();
        return res.json({ ok: true, data: rows.map(r => r.toJSON()) });
      }
      throw colErr;
    }
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

// GET /api/v1/game/my-progress  (auth required)
// 从 GameScore 表推导当前用户将占进度：每关最佳成绩 + 解锁到几关
async function getMyProgress(req, res) {
  try {
    const rows = await GameScore.findAll({
      where: { user_id: req.user.id, passed: true },
      attributes: [
        'level_num',
        [sequelize.fn('MAX', sequelize.col('score')),    'best_score'],
        [sequelize.fn('MAX', sequelize.col('max_combo')), 'best_combo'],
        [sequelize.fn('MAX', sequelize.col('accuracy')), 'best_acc'],
      ],
      group: ['level_num'],
      order: [['level_num', 'ASC']],
      raw: true,
    });
    let maxPassedLevel = 0;
    const byLevel = {};
    rows.forEach(r => {
      const lv  = Number(r.level_num);
      if (lv > maxPassedLevel) maxPassedLevel = lv;
      const acc   = Number(r.best_acc)   || 0;
      const stars = acc >= 100 ? 3 : acc >= 70 ? 2 : 1;
      byLevel[lv] = { score: Number(r.best_score) || 0, stars, combo: Number(r.best_combo) || 0 };
    });
    res.json({ ok: true, unlocked_to: maxPassedLevel + 1, level_scores: byLevel });
  } catch (e) {
    res.status(500).json({ error: e.message });
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

module.exports = { saveScore, getLeaderboard, getGlobalLeaderboard, getConfig, updateConfig, getMyProgress };
