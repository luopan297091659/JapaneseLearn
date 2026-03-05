const router = require('express').Router();
const { authenticate } = require('../middlewares/auth');
const { upload, previewImport, importAnki, serverImport, listAnkiDecks } = require('../controllers/ankiController');
const asyncHandler = require('../utils/asyncHandler');

// 预览：服务端解析文件并返回字段信息 + 样本数据（不写 DB）
router.post('/preview', authenticate, upload.single('file'), asyncHandler(previewImport));

// 客户端上报式导入（移动端 Anki 解析后提交）
router.post('/import', authenticate, upload.single('file'), asyncHandler(importAnki));

// 管理后台服务端直接导入（支持词汇 + 语法 + 音频提取）
router.post('/server-import', authenticate, upload.single('file'), asyncHandler(serverImport));

// 列出已导入的牌组
router.get('/decks', authenticate, asyncHandler(listAnkiDecks));

module.exports = router;
