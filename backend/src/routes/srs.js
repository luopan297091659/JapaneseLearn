const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { getDueCards, submitReview, addCard, getStats, getCardByRef } = require('../controllers/srsController');

router.get('/due', authenticate, asyncHandler(getDueCards));
router.get('/stats', authenticate, asyncHandler(getStats));
router.get('/card/:ref_id', authenticate, asyncHandler(getCardByRef));
router.post('/add', authenticate, asyncHandler(addCard));
router.post('/review', authenticate, asyncHandler(submitReview));

module.exports = router;
