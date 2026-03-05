const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { search, detail, kanjiDetail } = require('../controllers/dictionaryController');

// Search: GET /api/v1/dictionary/search?q=食べる&page=1
router.get('/search', asyncHandler(search));

// Word detail: GET /api/v1/dictionary/word/食べる
router.get('/word/:word', asyncHandler(detail));

// Kanji detail: GET /api/v1/dictionary/kanji/食
router.get('/kanji/:char', asyncHandler(kanjiDetail));

module.exports = router;
