const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { optionalAuthenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { list, getById } = require('../controllers/grammarController');

router.get('/', optionalAuthenticate, checkMembership('grammar_lessons'), asyncHandler(list));
router.get('/:id', optionalAuthenticate, checkMembership('grammar_lessons'), asyncHandler(getById));

module.exports = router;
