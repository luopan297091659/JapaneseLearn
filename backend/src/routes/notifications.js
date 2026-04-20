const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { sequelize } = require('../config/database');
const { DataTypes, Op } = require('sequelize');

// ── 模型 ──────────────────────────────────────────
const Notification = sequelize.define('Notification', {
  id:         { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  user_id:    { type: DataTypes.UUID, allowNull: false },
  type:       { type: DataTypes.STRING(40), allowNull: false, comment: 'order_approved|order_rejected|report_resolved|report_rejected|report_replied|xp_award|system' },
  title:      { type: DataTypes.STRING(120), allowNull: false },
  content:    { type: DataTypes.TEXT, allowNull: true },
  ref_type:   { type: DataTypes.STRING(30), allowNull: true, comment: 'order|report|other' },
  ref_id:     { type: DataTypes.STRING(64), allowNull: true },
  extra:      { type: DataTypes.JSON, allowNull: true, comment: '附加信息，如 admin_note / xp_awarded' },
  is_read:    { type: DataTypes.BOOLEAN, defaultValue: false },
  read_at:    { type: DataTypes.DATE, allowNull: true },
}, {
  tableName: 'notifications',
  indexes: [
    { fields: ['user_id'] },
    { fields: ['user_id', 'is_read'] },
    { fields: ['type'] },
  ],
});

Notification.sync({ alter: false }).catch(() => {
  Notification.sync({ force: false }).catch(() => {});
});

// ── 辅助：发通知 ──────────────────────────────────
async function createNotification({ userId, type, title, content, refType, refId, extra }) {
  if (!userId || !type || !title) return null;
  try {
    return await Notification.create({
      user_id: userId,
      type,
      title,
      content: content || null,
      ref_type: refType || null,
      ref_id: refId ? String(refId) : null,
      extra: extra || null,
    });
  } catch (e) {
    // 不阻塞主流程
    return null;
  }
}

// ── 列表 ──────────────────────────────────────────
router.get('/', authenticate, asyncHandler(async (req, res) => {
  const { page = 1, limit = 20, unread_only } = req.query;
  const where = { user_id: req.user.id };
  if (unread_only === '1' || unread_only === 'true') where.is_read = false;
  const offset = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);
  const { rows, count } = await Notification.findAndCountAll({
    where,
    order: [['createdAt', 'DESC']],
    limit: parseInt(limit),
    offset,
  });
  res.json({ data: rows, total: count, page: parseInt(page), limit: parseInt(limit) });
}));

// ── 未读数 ────────────────────────────────────────
router.get('/unread-count', authenticate, asyncHandler(async (req, res) => {
  const count = await Notification.count({ where: { user_id: req.user.id, is_read: false } });
  res.json({ count });
}));

// ── 标已读（单条） ────────────────────────────────
router.post('/:id/read', authenticate, asyncHandler(async (req, res) => {
  const n = await Notification.findOne({ where: { id: req.params.id, user_id: req.user.id } });
  if (!n) return res.status(404).json({ error: '通知不存在' });
  if (!n.is_read) await n.update({ is_read: true, read_at: new Date() });
  res.json({ ok: true });
}));

// ── 全部已读 ──────────────────────────────────────
router.post('/read-all', authenticate, asyncHandler(async (req, res) => {
  await Notification.update(
    { is_read: true, read_at: new Date() },
    { where: { user_id: req.user.id, is_read: false } }
  );
  res.json({ ok: true });
}));

// ── 删除单条 ──────────────────────────────────────
router.delete('/:id', authenticate, asyncHandler(async (req, res) => {
  await Notification.destroy({ where: { id: req.params.id, user_id: req.user.id } });
  res.json({ ok: true });
}));

module.exports = router;
module.exports.Notification = Notification;
module.exports.createNotification = createNotification;
