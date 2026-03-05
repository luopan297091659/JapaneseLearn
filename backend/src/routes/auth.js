const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { register, login, refreshToken, getMe, registerValidation } = require('../controllers/authController');
const { authenticate } = require('../middlewares/auth');

router.post('/register', registerValidation, asyncHandler(register));
router.post('/login', asyncHandler(login));
router.post('/refresh', asyncHandler(refreshToken));
router.get('/me', authenticate, asyncHandler(getMe));

module.exports = router;
