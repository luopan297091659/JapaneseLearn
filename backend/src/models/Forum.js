const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

// ────────── 论坛分类 ──────────
const ForumCategory = sequelize.define('ForumCategory', {
  id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
  name: { type: DataTypes.STRING(100), allowNull: false },
  description: { type: DataTypes.STRING(500), allowNull: true },
  icon: { type: DataTypes.STRING(10), allowNull: true, defaultValue: '💬' },
  sort_order: { type: DataTypes.INTEGER, defaultValue: 0 },
}, { tableName: 'forum_categories' });

// ────────── 论坛帖子 ──────────
const ForumPost = sequelize.define('ForumPost', {
  id: { type: DataTypes.CHAR(36), defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.CHAR(36), allowNull: false },
  category_id: { type: DataTypes.INTEGER, allowNull: false },
  title: { type: DataTypes.STRING(200), allowNull: false },
  content: { type: DataTypes.TEXT('long'), allowNull: false },
  view_count: { type: DataTypes.INTEGER, defaultValue: 0 },
  reply_count: { type: DataTypes.INTEGER, defaultValue: 0 },
  like_count: { type: DataTypes.INTEGER, defaultValue: 0 },
  is_pinned: { type: DataTypes.BOOLEAN, defaultValue: false },
  is_locked: { type: DataTypes.BOOLEAN, defaultValue: false },
  last_reply_at: { type: DataTypes.DATE, allowNull: true },
  last_reply_user_id: { type: DataTypes.CHAR(36), allowNull: true },
}, { tableName: 'forum_posts' });

// ────────── 论坛回复 ──────────
const ForumReply = sequelize.define('ForumReply', {
  id: { type: DataTypes.CHAR(36), defaultValue: DataTypes.UUIDV4, primaryKey: true },
  post_id: { type: DataTypes.CHAR(36), allowNull: false },
  user_id: { type: DataTypes.CHAR(36), allowNull: false },
  content: { type: DataTypes.TEXT, allowNull: false },
  like_count: { type: DataTypes.INTEGER, defaultValue: 0 },
  reply_to_id: { type: DataTypes.CHAR(36), allowNull: true, comment: '引用回复ID' },
}, { tableName: 'forum_replies' });

// ────────── 点赞记录 ──────────
const ForumLike = sequelize.define('ForumLike', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  user_id: { type: DataTypes.CHAR(36), allowNull: false },
  target_type: { type: DataTypes.ENUM('post', 'reply'), allowNull: false },
  target_id: { type: DataTypes.CHAR(36), allowNull: false },
}, {
  tableName: 'forum_likes',
  indexes: [{ unique: true, fields: ['user_id', 'target_type', 'target_id'] }],
});

// ────────── Associations ──────────
const User = require('./User');

ForumPost.belongsTo(User, { foreignKey: 'user_id', as: 'author' });
ForumPost.belongsTo(ForumCategory, { foreignKey: 'category_id', as: 'category' });
ForumPost.hasMany(ForumReply, { foreignKey: 'post_id', as: 'replies' });
ForumCategory.hasMany(ForumPost, { foreignKey: 'category_id', as: 'posts' });

ForumReply.belongsTo(User, { foreignKey: 'user_id', as: 'author' });
ForumReply.belongsTo(ForumPost, { foreignKey: 'post_id', as: 'post' });

ForumLike.belongsTo(User, { foreignKey: 'user_id' });

module.exports = { ForumCategory, ForumPost, ForumReply, ForumLike };
