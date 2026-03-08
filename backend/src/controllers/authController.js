const { body, validationResult } = require('express-validator');
const crypto = require('crypto');
const User = require('../models/User');
const { signAccessToken, signRefreshToken, verifyRefreshToken } = require('../utils/jwt');
const HttpError = require('../utils/httpError');

const registerValidation = [
  body('username').trim()
    .isLength({ min: 3, max: 50 }).withMessage('用户名长度需在 3-50 个字符之间')
    .matches(/^[\u4e00-\u9fa5a-zA-Z0-9_]+$/).withMessage('用户名只能包含中文、英文字母、数字和下划线'),
  body('email').isEmail().withMessage('请输入有效的邮箱地址').normalizeEmail(),
  body('password').isLength({ min: 8 }).withMessage('密码长度至少 8 位'),
];

async function register(req, res) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    const msgs = errors.array().map(e => e.msg).join('；');
    throw new HttpError(400, msgs);
  }

  const { username, email, password, level } = req.body;
  const existing = await User.findOne({ where: { email } });
  if (existing) throw new HttpError(409, '该邮箱已被注册');

  const platform = req.body.platform === 'app' ? 'app' : 'web';
  const loginToken = crypto.randomUUID();
  const user = await User.create({ username, email, password_hash: password, level: level || 'N5', [`${platform}_login_token`]: loginToken });
  const accessToken = signAccessToken({ id: user.id, email: user.email, loginToken, platform });
  const refreshToken = signRefreshToken({ id: user.id, loginToken, platform });
  res.status(201).json({ user, accessToken, refreshToken });
}

async function login(req, res) {
  const { email, username, password } = req.body;
  // 支持用邮箱或用户名登录
  const { Op } = require('sequelize');
  const identifier = email || username;
  if (!identifier) throw new HttpError(400, '请输入邮箱或用户名');
  if (!password) throw new HttpError(400, '请输入密码');
  const user = await User.findOne({
    where: {
      [Op.or]: [
        { email: identifier },
        { username: identifier },
      ],
    },
  });
  if (!user) {
    throw new HttpError(401, '该账号不存在，请检查邮箱或用户名');
  }
  if (!(await user.validatePassword(password))) {
    throw new HttpError(401, '密码错误，请重新输入');
  }
  const platform = req.body.platform === 'app' ? 'app' : 'web';
  const loginToken = crypto.randomUUID();
  await user.update({ [`${platform}_login_token`]: loginToken });
  const accessToken = signAccessToken({ id: user.id, email: user.email, loginToken, platform });
  const refreshToken = signRefreshToken({ id: user.id, loginToken, platform });
  res.json({ user, accessToken, refreshToken });
}

async function refreshToken(req, res) {
  const { refreshToken } = req.body;
  if (!refreshToken) throw new HttpError(400, 'refreshToken required');
  try {
    const decoded = verifyRefreshToken(refreshToken);
    const user = await User.findByPk(decoded.id);
    if (!user) throw new HttpError(401, 'User not found');
    // 校验登录令牌是否仍有效（未被其他设备顶替）
    const platform = decoded.platform || 'web';
    const field = platform === 'app' ? 'app_login_token' : 'web_login_token';
    if (decoded.loginToken && user[field] !== decoded.loginToken) {
      return res.status(401).json({ error: 'SESSION_REPLACED', message: '你的账号已在其他设备登录' });
    }
    const accessToken = signAccessToken({ id: user.id, email: user.email, loginToken: decoded.loginToken, platform });
    res.json({ accessToken });
  } catch (err) {
    if (err.status) throw err;
    throw new HttpError(401, 'Invalid refresh token');
  }
}

async function getMe(req, res) {
  res.json({ user: req.user });
}

module.exports = { register, login, refreshToken, getMe, registerValidation };
