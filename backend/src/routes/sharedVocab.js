const router = require('express').Router();
const { authenticate, optionalAuthenticate } = require('../middlewares/auth');
const asyncHandler = require('../utils/asyncHandler');
const {
  createDeck,
  listPublicDecks,
  listMyDecks,
  getDeckDetail,
  updateDeck,
  deleteDeck,
  importDeck,
} = require('../controllers/sharedVocabController');

// 公开词库广场
router.get('/decks', optionalAuthenticate, asyncHandler(listPublicDecks));

// 我的已发布/草稿词库
router.get('/my/decks', authenticate, asyncHandler(listMyDecks));

// 发布共享词库：body = { title, description, cover_url|cover_image_base64, source_type, tags, cards: [...] }
router.post('/decks', authenticate, asyncHandler(createDeck));

// 词库详情，可带 ?cards=0 只取元信息
router.get('/decks/:id', optionalAuthenticate, asyncHandler(getDeckDetail));

// 更新元信息
router.patch('/decks/:id', authenticate, asyncHandler(updateDeck));

// 软删除/下架
router.delete('/decks/:id', authenticate, asyncHandler(deleteDeck));

// 导入他人词库：返回词库和所有卡片，并增加 import_count
router.post('/decks/:id/import', authenticate, asyncHandler(importDeck));

module.exports = router;
