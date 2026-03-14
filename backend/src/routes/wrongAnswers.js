/**
 * Wrong Answers Routes — 错题集同步 API
 * POST   /api/v1/wrong-answers/sync   — 上传本地错题并获取服务端所有错题
 * DELETE /api/v1/wrong-answers/:id     — 删除单条错题
 * DELETE /api/v1/wrong-answers         — 按来源清空错题 (?source=quiz|listening|game|all)
 */
const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { sequelize } = require('../config/database');
const { DataTypes } = require('sequelize');

// ── 模型定义（轻量，直接内联） ──────────────────────────────
const WrongAnswer = sequelize.define('WrongAnswer', {
  id:            { type: DataTypes.BIGINT,  primaryKey: true, autoIncrement: true },
  user_id:       { type: DataTypes.UUID,    allowNull: false },
  source:        { type: DataTypes.STRING(20), allowNull: false, comment: 'quiz | listening | game' },
  game_type:     { type: DataTypes.STRING(20), allowNull: true },
  level:         { type: DataTypes.INTEGER,    allowNull: true },
  question:      { type: DataTypes.TEXT,    allowNull: false },
  your_answer:   { type: DataTypes.TEXT,    allowNull: true },
  correct_answer:{ type: DataTypes.TEXT,    allowNull: true },
  explanation:   { type: DataTypes.TEXT,    allowNull: true },
  answered_at:   { type: DataTypes.DATE,    allowNull: false, defaultValue: DataTypes.NOW },
}, {
  tableName: 'wrong_answers',
  timestamps: false,
  indexes: [{ fields: ['user_id', 'source'] }],
});

// 首次启动时创建表（不影响已有数据）
WrongAnswer.sync({ alter: false }).catch(() => {
  WrongAnswer.sync({ force: false }).catch(() => {});
});

// ── 同步接口 ──────────────────────────────────────
// 客户端将本地新增的错题上传，服务端返回全量列表
router.post('/sync', authenticate, asyncHandler(async (req, res) => {
  const userId = req.user.id;
  const items = req.body.items;

  // 批量插入客户端新增的错题
  if (Array.isArray(items) && items.length > 0) {
    const rows = items.slice(0, 200).map(w => ({
      user_id:        userId,
      source:         String(w.source || 'quiz').substring(0, 20),
      game_type:      w.gameType ? String(w.gameType).substring(0, 20) : null,
      level:          w.level != null ? parseInt(w.level, 10) || null : null,
      question:       String(w.question || '').substring(0, 2000),
      your_answer:    w.yourAnswer != null ? String(w.yourAnswer).substring(0, 500) : null,
      correct_answer: w.correctAnswer != null ? String(w.correctAnswer).substring(0, 500) : null,
      explanation:    w.explanation != null ? String(w.explanation).substring(0, 2000) : null,
      answered_at:    w.time ? new Date(w.time) : new Date(),
    }));
    await WrongAnswer.bulkCreate(rows, { ignoreDuplicates: true });
  }

  // 限制最多保留 500 条
  const total = await WrongAnswer.count({ where: { user_id: userId } });
  if (total > 500) {
    const oldest = await WrongAnswer.findAll({
      where: { user_id: userId },
      order: [['answered_at', 'ASC']],
      limit: total - 500,
      attributes: ['id'],
    });
    if (oldest.length) {
      await WrongAnswer.destroy({ where: { id: oldest.map(r => r.id) } });
    }
  }

  // 返回全量列表
  const all = await WrongAnswer.findAll({
    where: { user_id: userId },
    order: [['answered_at', 'DESC']],
    limit: 500,
  });

  res.json({
    ok: true,
    data: all.map(r => ({
      id:            r.id,
      source:        r.source,
      gameType:      r.game_type,
      level:         r.level,
      question:      r.question,
      yourAnswer:    r.your_answer,
      correctAnswer: r.correct_answer,
      explanation:   r.explanation,
      time:          r.answered_at,
    })),
  });
}));

// ── 删除单条 ──
router.delete('/:id', authenticate, asyncHandler(async (req, res) => {
  const deleted = await WrongAnswer.destroy({
    where: { id: req.params.id, user_id: req.user.id },
  });
  res.json({ ok: true, deleted });
}));

// ── 按来源清空 ──
router.delete('/', authenticate, asyncHandler(async (req, res) => {
  const source = req.query.source || 'all';
  const where = { user_id: req.user.id };
  if (source !== 'all') where.source = source;
  const deleted = await WrongAnswer.destroy({ where });
  res.json({ ok: true, deleted });
}));

module.exports = router;
