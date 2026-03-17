const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { list, getById, getByLevel, getIdsByLevel, bulkImport, listUserVocab, listUserDecks, deleteUserDeck } = require('../controllers/vocabularyController');

router.get('/', asyncHandler(list));
router.get('/level/:level', asyncHandler(getByLevel));
router.get('/level/:level/ids', asyncHandler(getIdsByLevel));
router.get('/:id', asyncHandler(getById));

// 客户端解析 Anki 后批量导入
router.post('/bulk', authenticate, asyncHandler(bulkImport));

// 用户词库（Anki 导入的个人词汇）
router.get('/user/list', authenticate, asyncHandler(listUserVocab));
router.get('/user/decks', authenticate, asyncHandler(listUserDecks));
router.post('/user/deck/delete', authenticate, asyncHandler(deleteUserDeck));

module.exports = router;
