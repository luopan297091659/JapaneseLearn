const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { list, getById } = require('../controllers/newsController');

router.get('/', asyncHandler(list));
router.get('/:id', asyncHandler(getById));

module.exports = router;
