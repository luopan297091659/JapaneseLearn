const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate, optionalAuthenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { generateQuiz, submitQuiz, getHistory } = require('../controllers/quizController');

// 文法测验用 grammar_quiz_daily 限额，其他用 quiz_meaning_daily
function quizDailyLimitMiddleware() {
  const grammarCheck = checkMembership('grammar_quiz_daily', { countActivityType: 'grammar_quiz' });
  const vocabCheck   = checkMembership('quiz_meaning_daily', { countActivityType: 'quiz' });
  return (req, res, next) => {
    const qt = (req.query.quiz_type || '').toLowerCase();
    return qt === 'grammar' ? grammarCheck(req, res, next) : vocabCheck(req, res, next);
  };
}

router.get('/generate', optionalAuthenticate,
  quizDailyLimitMiddleware(),
  checkMembership('quiz_jlpt_levels', { valueField: 'level', valueSource: 'query' }),
  checkMembership('quiz_count_options', { valueField: 'count', valueSource: 'query' }),
  asyncHandler(generateQuiz));
// 提交也需要区分文法/词汇限额
function quizSubmitLimitMiddleware() {
  const grammarCheck = checkMembership('grammar_quiz_daily', { countActivityType: 'grammar_quiz' });
  const vocabCheck   = checkMembership('quiz_meaning_daily', { countActivityType: 'quiz' });
  return (req, res, next) => {
    const qt = (req.body.quiz_type || '').toLowerCase();
    return qt === 'grammar' ? grammarCheck(req, res, next) : vocabCheck(req, res, next);
  };
}

router.post('/submit', authenticate, quizSubmitLimitMiddleware(), asyncHandler(submitQuiz));
router.get('/history', authenticate, asyncHandler(getHistory));

module.exports = router;
