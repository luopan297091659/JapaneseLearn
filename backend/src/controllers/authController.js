const { body, validationResult } = require('express-validator');
const User = require('../models/User');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('../utils/jwt');
const HttpError = require('../utils/httpError');

const registerValidation = [
  body('username').trim().isLength({ min: 3, max: 50 }).withMessage('Username must be 3-50 chars'),
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 chars'),
];

async function register(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) throw new HttpError(400, errors.array());

  const { username, email, password, level } = req.body;
  const existing = await User.findOne({ where: { email } });
  if (existing) throw new HttpError(409, 'Email already registered');

  const user = await User.create({ username, email, password_hash: password, level: level || 'N5' });
  const accessToken = signAccessToken({ id: user.id, email: user.email });
  const refreshToken = signRefreshToken({ id: user.id });
  res.status(201).json({ user, accessToken, refreshToken });
}

async function login(req, res) {
  const { email, username, password } = req.body;
  // 支持用邮箱或用户名登录
  const { Op } = require('sequelize');
  const identifier = email || username;
  if (!identifier) throw new HttpError(400, 'email or username required');
  const user = await User.findOne({
    where: {
      [Op.or]: [
        { email: identifier },
        { username: identifier },
      ],
    },
  });
  if (!user || !(await user.validatePassword(password))) {
    throw new HttpError(401, 'Invalid credentials');
  }
  const accessToken = signAccessToken({ id: user.id, email: user.email });
  const refreshToken = signRefreshToken({ id: user.id });
  res.json({ user, accessToken, refreshToken });
}

async function refreshToken(req, res) {
  const { refreshToken } = req.body;
  if (!refreshToken) throw new HttpError(400, 'refreshToken required');
  try {
    const decoded = verifyRefreshToken(refreshToken);
    const user = await User.findByPk(decoded.id);
    if (!user) throw new HttpError(401, 'User not found');
    const accessToken = signAccessToken({ id: user.id, email: user.email });
    res.json({ accessToken });
  } catch (err) {
    // ensure we always respond with 401 on failure
    throw new HttpError(401, 'Invalid refresh token');
  }
}

async function getMe(req, res) {
  res.json({ user: req.user });
}

module.exports = { register, login, refreshToken, getMe, registerValidation };
