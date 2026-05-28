const express = require('express');
const router = express.Router();
const { authenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const aiController = require('../controllers/aiController');

// 所有 AI 路由都需要登录
router.use(authenticate);

router.post('/translate', checkMembership('ai_features'), aiController.translate);
router.post('/analyze', checkMembership('ai_features'), aiController.analyze);
router.post('/sentence-analysis', checkMembership('ai_features'), aiController.sentenceAnalysis);
router.post('/word-detail', checkMembership('ai_features'), aiController.wordDetail);

module.exports = router;
