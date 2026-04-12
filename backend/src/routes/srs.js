const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { getDueCards, submitReview, addCard, getStats, getCardByRef, resetCards, removeCard } = require('../controllers/srsController');

router.get('/due', authenticate, asyncHandler(getDueCards));
router.get('/stats', authenticate, asyncHandler(getStats));
router.get('/card/:ref_id', authenticate, asyncHandler(getCardByRef));
router.post('/add', authenticate, asyncHandler(addCard));
router.post('/review', authenticate, checkMembership('srs_daily', { countActivityType: 'srs_review' }), asyncHandler(submitReview));
router.delete('/reset', authenticate, asyncHandler(resetCards));
router.delete('/card/:id', authenticate, asyncHandler(removeCard));

module.exports = router;
