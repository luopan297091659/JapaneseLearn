const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { logActivity, getSummary, getDailyGoals } = require('../controllers/progressController');

router.post('/log', authenticate, asyncHandler(logActivity));
router.get('/summary', authenticate, asyncHandler(getSummary));
router.get('/daily-goals', authenticate, asyncHandler(getDailyGoals));

module.exports = router;
