const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { isActiveMember } = require('../middlewares/membership');
const {
  publicListJlptPapers,
  publicGetJlptPaper,
  submitJlptPaper,
} = require('../controllers/jlptExamController');

function requireJlptMember(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'LOGIN_REQUIRED', message: '请先登录后再使用 JLPT 模拟测验' });
  }
  if (req.user.role === 'admin' || isActiveMember(req.user)) {
    return next();
  }
  return res.status(403).json({ error: 'MEMBERSHIP_REQUIRED', message: 'JLPT 模拟测验仅限会员使用' });
}

router.get('/papers', authenticate, requireJlptMember, asyncHandler(publicListJlptPapers));
router.get('/papers/:slug', authenticate, requireJlptMember, asyncHandler(publicGetJlptPaper));
router.post('/papers/:slug/submit', authenticate, requireJlptMember, asyncHandler(submitJlptPaper));

module.exports = router;