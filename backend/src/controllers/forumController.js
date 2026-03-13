const { Op } = require('sequelize');
const { ForumCategory, ForumPost, ForumReply, ForumLike } = require('../models/Forum');
const User = require('../models/User');
const HttpError = require('../utils/httpError');

// ── 分类 ──

async function getCategories(req, res) {
  const categories = await ForumCategory.findAll({
    order: [['sort_order', 'ASC']],
    attributes: {
      include: [
        [ForumCategory.sequelize.literal(
          '(SELECT COUNT(*) FROM forum_posts WHERE forum_posts.category_id = ForumCategory.id)'
        ), 'post_count'],
      ],
    },
  });
  res.json({ categories });
}

// ── 帖子列表 ──

async function getPosts(req, res) {
  const { category_id, page = 1, limit = 20, search } = req.query;
  const where = {};
  if (category_id) where.category_id = category_id;
  if (search) {
    where.title = { [Op.like]: `%${search}%` };
  }

  const offset = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);
  const { count, rows } = await ForumPost.findAndCountAll({
    where,
    include: [
      { model: User, as: 'author', attributes: ['id', 'username', 'avatar_url'] },
      { model: ForumCategory, as: 'category', attributes: ['id', 'name', 'icon'] },
    ],
    order: [['is_pinned', 'DESC'], ['last_reply_at', 'DESC'], ['createdAt', 'DESC']],
    limit: parseInt(limit),
    offset,
  });
  res.json({ posts: rows, total: count, page: parseInt(page), limit: parseInt(limit) });
}

// ── 帖子详情 ──

async function getPost(req, res) {
  const post = await ForumPost.findByPk(req.params.id, {
    include: [
      { model: User, as: 'author', attributes: ['id', 'username', 'avatar_url'] },
      { model: ForumCategory, as: 'category', attributes: ['id', 'name', 'icon'] },
    ],
  });
  if (!post) throw new HttpError(404, '帖子不存在');

  // 增加浏览次数
  await post.increment('view_count');

  // 检查当前用户是否点赞
  let liked = false;
  if (req.user) {
    const like = await ForumLike.findOne({
      where: { user_id: req.user.id, target_type: 'post', target_id: post.id },
    });
    liked = !!like;
  }

  res.json({ post, liked });
}

// ── 创建帖子 ──

async function createPost(req, res) {
  const { title, content, category_id } = req.body;
  if (!title || !content) throw new HttpError(400, '标题和内容不能为空');
  if (!category_id) throw new HttpError(400, '请选择分类');

  const category = await ForumCategory.findByPk(category_id);
  if (!category) throw new HttpError(400, '分类不存在');

  const post = await ForumPost.create({
    user_id: req.user.id,
    category_id,
    title: title.trim(),
    content: content.trim(),
    last_reply_at: new Date(),
  });

  res.status(201).json({ post });
}

// ── 编辑帖子 ──

async function updatePost(req, res) {
  const post = await ForumPost.findByPk(req.params.id);
  if (!post) throw new HttpError(404, '帖子不存在');
  if (post.user_id !== req.user.id && req.user.role !== 'admin') {
    throw new HttpError(403, '无权编辑此帖子');
  }

  const { title, content, category_id } = req.body;
  if (title) post.title = title.trim();
  if (content) post.content = content.trim();
  if (category_id) post.category_id = category_id;
  await post.save();

  res.json({ post });
}

// ── 删除帖子 ──

async function deletePost(req, res) {
  const post = await ForumPost.findByPk(req.params.id);
  if (!post) throw new HttpError(404, '帖子不存在');
  if (post.user_id !== req.user.id && req.user.role !== 'admin') {
    throw new HttpError(403, '无权删除此帖子');
  }

  await ForumReply.destroy({ where: { post_id: post.id } });
  await ForumLike.destroy({ where: { target_type: 'post', target_id: post.id } });
  await post.destroy();

  res.json({ message: '帖子已删除' });
}

// ── 回复列表 ──

async function getReplies(req, res) {
  const { page = 1, limit = 30 } = req.query;
  const offset = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);

  const { count, rows } = await ForumReply.findAndCountAll({
    where: { post_id: req.params.id },
    include: [
      { model: User, as: 'author', attributes: ['id', 'username', 'avatar_url'] },
    ],
    order: [['createdAt', 'ASC']],
    limit: parseInt(limit),
    offset,
  });

  // 获取当前用户的点赞状态
  let likedIds = [];
  if (req.user) {
    const likes = await ForumLike.findAll({
      where: {
        user_id: req.user.id,
        target_type: 'reply',
        target_id: { [Op.in]: rows.map(r => r.id) },
      },
      attributes: ['target_id'],
    });
    likedIds = likes.map(l => l.target_id);
  }

  const replies = rows.map(r => ({
    ...r.toJSON(),
    liked: likedIds.includes(r.id),
  }));

  res.json({ replies, total: count, page: parseInt(page), limit: parseInt(limit) });
}

// ── 创建回复 ──

async function createReply(req, res) {
  const { content, reply_to_id } = req.body;
  if (!content) throw new HttpError(400, '回复内容不能为空');

  const post = await ForumPost.findByPk(req.params.id);
  if (!post) throw new HttpError(404, '帖子不存在');
  if (post.is_locked) throw new HttpError(403, '帖子已锁定，无法回复');

  const reply = await ForumReply.create({
    post_id: post.id,
    user_id: req.user.id,
    content: content.trim(),
    reply_to_id: reply_to_id || null,
  });

  await post.increment('reply_count');
  await post.update({ last_reply_at: new Date(), last_reply_user_id: req.user.id });

  const result = await ForumReply.findByPk(reply.id, {
    include: [{ model: User, as: 'author', attributes: ['id', 'username', 'avatar_url'] }],
  });

  res.status(201).json({ reply: result });
}

// ── 删除回复 ──

async function deleteReply(req, res) {
  const reply = await ForumReply.findByPk(req.params.replyId);
  if (!reply) throw new HttpError(404, '回复不存在');
  if (reply.user_id !== req.user.id && req.user.role !== 'admin') {
    throw new HttpError(403, '无权删除此回复');
  }

  const post = await ForumPost.findByPk(reply.post_id);
  await ForumLike.destroy({ where: { target_type: 'reply', target_id: reply.id } });
  await reply.destroy();
  if (post) await post.decrement('reply_count');

  res.json({ message: '回复已删除' });
}

// ── 点赞/取消点赞 ──

async function toggleLike(req, res) {
  const { target_type, target_id } = req.body;
  if (!['post', 'reply'].includes(target_type)) throw new HttpError(400, '无效的点赞类型');

  const existing = await ForumLike.findOne({
    where: { user_id: req.user.id, target_type, target_id },
  });

  if (existing) {
    await existing.destroy();
    if (target_type === 'post') {
      await ForumPost.decrement('like_count', { where: { id: target_id } });
    } else {
      await ForumReply.decrement('like_count', { where: { id: target_id } });
    }
    res.json({ liked: false });
  } else {
    await ForumLike.create({ user_id: req.user.id, target_type, target_id });
    if (target_type === 'post') {
      await ForumPost.increment('like_count', { where: { id: target_id } });
    } else {
      await ForumReply.increment('like_count', { where: { id: target_id } });
    }
    res.json({ liked: true });
  }
}

// ── 初始化默认分类 ──

async function seedCategories() {
  const count = await ForumCategory.count();
  if (count === 0) {
    await ForumCategory.bulkCreate([
      { name: '学习交流', description: '日语学习相关的讨论和交流', icon: '📚', sort_order: 1 },
      { name: '考试经验', description: 'JLPT、NAT等日语考试经验分享', icon: '📝', sort_order: 2 },
      { name: '资源分享', description: '学习资源、教材、工具推荐', icon: '🔗', sort_order: 3 },
      { name: '日本文化', description: '日本文化、动漫、旅行等话题', icon: '🗾', sort_order: 4 },
      { name: '问答求助', description: '遇到问题？在这里寻求帮助', icon: '❓', sort_order: 5 },
      { name: '自由讨论', description: '畅所欲言，水区', icon: '💬', sort_order: 6 },
    ]);
  }
}

module.exports = {
  getCategories, getPosts, getPost, createPost, updatePost, deletePost,
  getReplies, createReply, deleteReply, toggleLike, seedCategories,
};
