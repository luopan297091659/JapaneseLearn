const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { register, login, refreshToken, getMe, registerValidation, forgotPassword, verifyResetCode, resetPassword, sendCodeForLogin, loginWithCode } = require('../controllers/authController');
const { authenticate } = require('../middlewares/auth');

router.post('/register', registerValidation, asyncHandler(register));
router.post('/login', asyncHandler(login));
router.post('/refresh', asyncHandler(refreshToken));
router.get('/me', authenticate, asyncHandler(getMe));
router.post('/forgot-password', asyncHandler(forgotPassword));
router.post('/verify-reset-code', asyncHandler(verifyResetCode));
router.post('/reset-password', asyncHandler(resetPassword));
router.post('/send-login-code', asyncHandler(sendCodeForLogin));
router.post('/login-with-code', asyncHandler(loginWithCode));

module.exports = router;
