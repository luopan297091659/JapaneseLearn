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

const { isActiveMember } = require('../middlewares/membership');

async function getMe(req, res) {
  const user = req.user;
  const userJson = user.toJSON ? user.toJSON() : { ...user };
  // 附加会员状态
  userJson.is_member = isActiveMember(user);
  // 附加试用信息
  userJson.is_trial = user.membership_plan === 'trial';
  userJson.trial_activated = !!user.trial_activated;
  if (user.membership_expire) {
    const expire = new Date(user.membership_expire);
    const now = new Date();
    // 按日历天计算剩余天数（去掉时分秒，避免 ceil 导致首日不递减）
    const expireDay = new Date(expire.getFullYear(), expire.getMonth(), expire.getDate());
    const todayDay  = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    userJson.membership_days_left = Math.max(0, Math.round((expireDay - todayDay) / (1000 * 60 * 60 * 24)));
  }
  res.json({ user: userJson });
}

// ── Password Reset ─────────────────────────────────────────────────────
const PasswordResetCode = require('../models/PasswordResetCode');
const { sendResetCode } = require('../services/emailService');

async function forgotPassword(req, res) {
  const { email } = req.body;
  if (!email) throw new HttpError(400, '请输入邮箱');
  const user = await User.findOne({ where: { email } });
  if (!user) throw new HttpError(404, '该邮箱尚未注册');

  // 限频：同一邮箱 60 秒内只能发一次
  const recent = await PasswordResetCode.findOne({
    where: { email, used: false, expires_at: { [require('sequelize').Op.gt]: new Date(Date.now() - 60 * 1000) } },
    order: [['createdAt', 'DESC']],
  });
  if (recent) throw new HttpError(429, '请求过于频繁，请稍后再试');

  const code = String(Math.floor(100000 + Math.random() * 900000));
  await PasswordResetCode.create({ email, code, expires_at: new Date(Date.now() + 10 * 60 * 1000) });
  await sendResetCode(email, code);
  res.json({ message: '验证码已发送至邮箱' });
}

async function verifyResetCode(req, res) {
  const { email, code } = req.body;
  if (!email || !code) throw new HttpError(400, '参数不完整');
  const record = await PasswordResetCode.findOne({
    where: { email, code, used: false, expires_at: { [require('sequelize').Op.gt]: new Date() } },
    order: [['createdAt', 'DESC']],
  });
  if (!record) throw new HttpError(400, '验证码无效或已过期');
  res.json({ valid: true });
}

async function resetPassword(req, res) {
  const { email, code, newPassword } = req.body;
  if (!email || !code || !newPassword) throw new HttpError(400, '参数不完整');
  if (newPassword.length < 8) throw new HttpError(400, '密码长度至少 8 位');

  const record = await PasswordResetCode.findOne({
    where: { email, code, used: false, expires_at: { [require('sequelize').Op.gt]: new Date() } },
    order: [['createdAt', 'DESC']],
  });
  if (!record) throw new HttpError(400, '验证码无效或已过期');

  const user = await User.findOne({ where: { email } });
  if (!user) throw new HttpError(404, '用户不存在');

  await user.update({ password_hash: newPassword });
  await record.update({ used: true });
  // 标记该邮箱所有未使用验证码为已用
  await PasswordResetCode.update({ used: true }, { where: { email, used: false } });
  res.json({ message: '密码重置成功' });
}

// ── Login with Code ─────────────────────────────────────────────────────
const { sendLoginCode: _sendLoginCode } = require('../services/emailService');

async function sendCodeForLogin(req, res) {
  const { email } = req.body;
  if (!email) throw new HttpError(400, '请输入邮箱');
  const user = await User.findOne({ where: { email } });
  if (!user) throw new HttpError(404, '该邮箱尚未注册');

  const { Op } = require('sequelize');
  const recent = await PasswordResetCode.findOne({
    where: { email, used: false, expires_at: { [Op.gt]: new Date(Date.now() - 60 * 1000) } },
    order: [['created_at', 'DESC']],
  });
  if (recent) throw new HttpError(429, '请求过于频繁，请稍后再试');

  const code = String(Math.floor(100000 + Math.random() * 900000));
  await PasswordResetCode.create({ email, code, expires_at: new Date(Date.now() + 10 * 60 * 1000) });
  await _sendLoginCode(email, code);
  res.json({ message: '验证码已发送至邮箱' });
}

async function loginWithCode(req, res) {
  const { email, code } = req.body;
  if (!email || !code) throw new HttpError(400, '参数不完整');
  const { Op } = require('sequelize');
  const record = await PasswordResetCode.findOne({
    where: { email, code, used: false, expires_at: { [Op.gt]: new Date() } },
    order: [['created_at', 'DESC']],
  });
  if (!record) throw new HttpError(400, '验证码无效或已过期');

  const user = await User.findOne({ where: { email } });
  if (!user) throw new HttpError(404, '用户不存在');

  await record.update({ used: true });
  const platform = req.body.platform === 'app' ? 'app' : 'web';
  const loginToken = crypto.randomUUID();
  await user.update({ [`${platform}_login_token`]: loginToken });
  const accessToken = signAccessToken({ id: user.id, email: user.email, loginToken, platform });
  const refreshToken = signRefreshToken({ id: user.id, loginToken, platform });
  res.json({ user, accessToken, refreshToken });
}

module.exports = { register, login, refreshToken, getMe, registerValidation, forgotPassword, verifyResetCode, resetPassword, sendCodeForLogin, loginWithCode };
