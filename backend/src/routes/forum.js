const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const forum = require('../controllers/forumController');

// 公开接口（可选认证，用于检测点赞状态）
const optionalAuth = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    try {
      const { verifyAccessToken } = require('../utils/jwt');
      const User = require('../models/User');
      const decoded = verifyAccessToken(authHeader.split(' ')[1]);
      req.user = await User.findByPk(decoded.id);
    } catch (_) { /* 忽略无效 token */ }
  }
  next();
};

// 分类
router.get('/categories', asyncHandler(forum.getCategories));

// 帖子列表
router.get('/posts', optionalAuth, asyncHandler(forum.getPosts));

// 帖子详情
router.get('/posts/:id', optionalAuth, asyncHandler(forum.getPost));

// 帖子回复
router.get('/posts/:id/replies', optionalAuth, asyncHandler(forum.getReplies));

// 需要登录的接口
router.post('/posts', authenticate, asyncHandler(forum.createPost));
router.put('/posts/:id', authenticate, asyncHandler(forum.updatePost));
router.delete('/posts/:id', authenticate, asyncHandler(forum.deletePost));
router.post('/posts/:id/replies', authenticate, asyncHandler(forum.createReply));
router.delete('/posts/:id/replies/:replyId', authenticate, asyncHandler(forum.deleteReply));
router.post('/like', authenticate, asyncHandler(forum.toggleLike));

module.exports = router;
