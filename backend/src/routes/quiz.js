const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { generateQuiz, submitQuiz, getHistory } = require('../controllers/quizController');

router.get('/generate', asyncHandler(generateQuiz));
router.post('/submit', authenticate, asyncHandler(submitQuiz));
router.get('/history', authenticate, asyncHandler(getHistory));

module.exports = router;
