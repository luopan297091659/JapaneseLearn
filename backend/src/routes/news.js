const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate, optionalAuthenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { list, getById, nhkList, nhkArticle, nhkCategories, nhkHistory,
        listFavorites, addFavorite, removeFavorite, checkFavorite } = require('../controllers/newsController');

router.get('/', optionalAuthenticate, checkMembership('news_limit'), asyncHandler(list));
router.get('/nhk/categories', asyncHandler(nhkCategories));
router.get('/nhk/history', asyncHandler(nhkHistory));
router.get('/nhk', asyncHandler(nhkList));
router.get('/nhk/:id', optionalAuthenticate, checkMembership('news_limit'), asyncHandler(nhkArticle));

// ── 收藏 (需登录) ──
router.get('/favorites', authenticate, asyncHandler(listFavorites));
router.get('/favorites/check', authenticate, asyncHandler(checkFavorite));
router.post('/favorites', authenticate, asyncHandler(addFavorite));
router.delete('/favorites', authenticate, asyncHandler(removeFavorite));

router.get('/:id', optionalAuthenticate, checkMembership('news_limit'), asyncHandler(getById));

module.exports = router;
