const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate, optionalAuthenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { generateQuiz, submitQuiz, getHistory } = require('../controllers/quizController');

router.get('/generate', optionalAuthenticate,
  checkMembership('quiz_meaning_daily', { countActivityType: 'quiz' }),
  checkMembership('quiz_jlpt_levels', { valueField: 'level', valueSource: 'query' }),
  checkMembership('quiz_count_options', { valueField: 'count', valueSource: 'query' }),
  asyncHandler(generateQuiz));
router.post('/submit', authenticate, checkMembership('quiz_meaning_daily', { countActivityType: 'quiz' }), asyncHandler(submitQuiz));
router.get('/history', authenticate, asyncHandler(getHistory));

module.exports = router;
