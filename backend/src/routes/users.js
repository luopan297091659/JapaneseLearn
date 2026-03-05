const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const User = require('../models/User');

router.get('/profile', authenticate, asyncHandler(async (req, res) => {
  res.json(req.user);
}));

router.put('/profile', authenticate, asyncHandler(async (req, res) => {
  const { username, level, daily_goal_minutes, notification_enabled } = req.body;
  await req.user.update({ username, level, daily_goal_minutes, notification_enabled });
  res.json(req.user);
}));

router.put('/change-password', authenticate, asyncHandler(async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!(await req.user.validatePassword(currentPassword))) {
    const HttpError = require('../utils/httpError');
    throw new HttpError(401, 'Incorrect current password');
  }
  await req.user.update({ password_hash: newPassword });
  res.json({ message: 'Password updated' });
}));

module.exports = router;
