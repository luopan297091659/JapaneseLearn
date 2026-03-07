const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { list, getById, nhkList, nhkArticle, nhkCategories,
        listFavorites, addFavorite, removeFavorite, checkFavorite } = require('../controllers/newsController');

router.get('/', asyncHandler(list));
router.get('/nhk/categories', asyncHandler(nhkCategories));
router.get('/nhk', asyncHandler(nhkList));
router.get('/nhk/:id', asyncHandler(nhkArticle));

// ── 收藏 (需登录) ──
router.get('/favorites', authenticate, asyncHandler(listFavorites));
router.get('/favorites/check', authenticate, asyncHandler(checkFavorite));
router.post('/favorites', authenticate, asyncHandler(addFavorite));
router.delete('/favorites', authenticate, asyncHandler(removeFavorite));

router.get('/:id', asyncHandler(getById));

module.exports = router;
