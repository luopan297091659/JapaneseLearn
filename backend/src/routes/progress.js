const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { logActivity, getSummary } = require('../controllers/progressController');

router.post('/log', authenticate, asyncHandler(logActivity));
router.get('/summary', authenticate, asyncHandler(getSummary));

module.exports = router;
