const express = require('express');
const router = express.Router();
const { authenticate } = require('../middlewares/auth');
const aiController = require('../controllers/aiController');

// 所有 AI 路由都需要登录
router.use(authenticate);

router.post('/translate', aiController.translate);
router.post('/analyze', aiController.analyze);
router.post('/word-detail', aiController.wordDetail);

module.exports = router;
