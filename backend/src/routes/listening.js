const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { optionalAuthenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { list, getById } = require('../controllers/listeningController');
const { getExercises, getStats } = require('../controllers/listeningExerciseController');

// 听力练习题目接口（放在 /:id 之前，避免路径冲突）
router.get('/exercise', optionalAuthenticate, checkMembership('immersion_daily', { countActivityType: 'listening' }), asyncHandler(getExercises));
router.get('/exercise/stats', asyncHandler(getStats));

router.get('/', asyncHandler(list));
router.get('/:id', optionalAuthenticate, checkMembership('immersion_daily', { countActivityType: 'listening' }), asyncHandler(getById));

module.exports = router;
