const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { sequelize } = require('../config/database');
const { DataTypes } = require('sequelize');

// ── 模型定义 ──────────────────────────────────────
const UserReport = sequelize.define('UserReport', {
  id:           { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  user_id:      { type: DataTypes.UUID, allowNull: false },
  username:     { type: DataTypes.STRING(100), allowNull: true },
  ref_type:     { type: DataTypes.STRING(20), allowNull: false, comment: 'vocabulary | grammar' },
  ref_id:       { type: DataTypes.UUID, allowNull: false, comment: '单词或语法ID' },
  ref_title:    { type: DataTypes.STRING(200), allowNull: true, comment: '单词/语法名称' },
  issue_type:   { type: DataTypes.STRING(30), allowNull: false, comment: '发音错误|词义错误|词组错误|动词词性错误|例句错误|其他' },
  description:  { type: DataTypes.TEXT, allowNull: true },
  status:       { type: DataTypes.STRING(20), defaultValue: 'pending', comment: 'pending|resolved|rejected' },
  admin_reply:  { type: DataTypes.TEXT, allowNull: true },
}, {
  tableName: 'user_reports',
  indexes: [
    { fields: ['user_id'] },
    { fields: ['ref_type', 'ref_id'] },
    { fields: ['status'] },
  ],
});

UserReport.sync({ alter: false }).catch(() => {
  UserReport.sync({ force: false }).catch(() => {});
});

// ── 用户提交报错 ──────────────────────────────────
router.post('/', authenticate, asyncHandler(async (req, res) => {
  const { ref_type, ref_id, ref_title, issue_type, description } = req.body;
  if (!ref_type || !ref_id || !issue_type) {
    return res.status(400).json({ error: '缺少必要参数' });
  }
  const report = await UserReport.create({
    user_id: req.user.id,
    username: req.user.username,
    ref_type,
    ref_id,
    ref_title: ref_title || '',
    issue_type,
    description: description || '',
  });
  res.json({ success: true, id: report.id });
}));

// ── 用户查看自己的报错历史 ───────────────────────
router.get('/mine', authenticate, asyncHandler(async (req, res) => {
  const list = await UserReport.findAll({
    where: { user_id: req.user.id },
    order: [['createdAt', 'DESC']],
    limit: 50,
  });
  res.json(list);
}));

module.exports = router;
module.exports.UserReport = UserReport;
