const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { logActivity, getSummary, getDailyGoals, getStudyPlanProgress, checkin } = require('../controllers/progressController');
const {
	getTodayTask,
	startTodayTask,
	getStudyQueue,
	submitStudyAnswer,
	getReviewEntries,
	finishTodayTask,
} = require('../controllers/studyPlanController');

router.post('/log', authenticate, asyncHandler(logActivity));
router.post('/checkin', authenticate, asyncHandler(checkin));
router.get('/summary', authenticate, asyncHandler(getSummary));
router.get('/daily-goals', authenticate, asyncHandler(getDailyGoals));
router.get('/study-plan-progress', authenticate, asyncHandler(getStudyPlanProgress));
router.get('/study-plan/today', authenticate, asyncHandler(getTodayTask));
router.post('/study-plan/start', authenticate, asyncHandler(startTodayTask));
router.get('/study-plan/queue', authenticate, asyncHandler(getStudyQueue));
router.post('/study-plan/answer', authenticate, asyncHandler(submitStudyAnswer));
router.get('/study-plan/review-entries', authenticate, asyncHandler(getReviewEntries));
router.post('/study-plan/finish', authenticate, asyncHandler(finishTodayTask));

module.exports = router;
