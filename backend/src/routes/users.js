const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { readFeatureTiers, getDailyUsageCount, isActiveMember } = require('../middlewares/membership');
const User = require('../models/User');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const {
  getUserPreferences,
  mergeUserPreferences,
  summarizeUserPreferences,
} = require('../utils/userPreferences');

const avatarDir = path.join(__dirname, '../../uploads/avatars');
if (!fs.existsSync(avatarDir)) fs.mkdirSync(avatarDir, { recursive: true });

async function persistUserPreferences(user, overrides = {}) {
  const preferences = mergeUserPreferences(user, overrides);
  await user.update({
    notification_enabled: preferences.notification_enabled,
    daily_goal_minutes: preferences.daily_goal_minutes,
    preferences_json: JSON.stringify(preferences),
  });
  return preferences;
}

const avatarUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 6 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype && file.mimetype.startsWith('image/')) return cb(null, true);
    cb(new Error('仅支持图片文件上传'));
  },
});

router.get('/profile', authenticate, asyncHandler(async (req, res) => {
  res.json(req.user);
}));

router.put('/profile', authenticate, asyncHandler(async (req, res) => {
  const { username, level, daily_goal_minutes, notification_enabled } = req.body;
  const payload = {};
  if (username !== undefined) payload.username = username;
  if (level !== undefined) payload.level = level;
  await req.user.update(payload);

  if (daily_goal_minutes !== undefined || notification_enabled !== undefined) {
    await persistUserPreferences(req.user, {
      ...(daily_goal_minutes !== undefined ? { daily_goal_minutes } : {}),
      ...(notification_enabled !== undefined ? { notification_enabled } : {}),
    });
  }

  await req.user.reload();
  res.json(req.user);
}));

router.get('/preferences', authenticate, asyncHandler(async (req, res) => {
  const preferences = getUserPreferences(req.user);
  res.json({
    preferences,
    preference_summary: summarizeUserPreferences(preferences),
  });
}));

router.put('/preferences', authenticate, asyncHandler(async (req, res) => {
  const incoming = req.body && typeof req.body.preferences === 'object'
    ? req.body.preferences
    : req.body;
  const preferences = await persistUserPreferences(req.user, incoming || {});
  await req.user.reload();
  res.json({
    user: req.user,
    preferences,
    preference_summary: summarizeUserPreferences(preferences),
  });
}));

router.post('/avatar', authenticate, avatarUpload.single('avatar'), asyncHandler(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: '请上传头像图片' });

  const mimeExt = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/webp': '.webp',
    'image/heic': '.heic',
    'image/heif': '.heif',
  };
  const ext = mimeExt[req.file.mimetype] || path.extname(req.file.originalname || '') || '.jpg';
  const filename = `${uuidv4()}${ext}`;
  const absPath = path.join(avatarDir, filename);

  fs.writeFileSync(absPath, req.file.buffer);
  const avatarUrl = `/uploads/avatars/${filename}`;
  const oldAvatar = req.user.avatar_url;
  await req.user.update({ avatar_url: avatarUrl });

  if (oldAvatar && oldAvatar.startsWith('/uploads/avatars/') && oldAvatar !== avatarUrl) {
    const oldPath = path.join(__dirname, '../..', oldAvatar.replace(/^\//, ''));
    if (fs.existsSync(oldPath)) {
      try { fs.unlinkSync(oldPath); } catch (_) {}
    }
  }

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

// ── GET /usage  获取今日功能用量（供客户端显示剩余额度）──
const DAILY_ACTIVITY_MAP = {
  srs_daily: 'srs_review',
  quiz_meaning_daily: 'quiz',
  listening_daily: 'listening',
  listening_exercise_daily: 'listening_exercise',
  immersion_daily: 'immersion',
  dictionary_daily: 'dictionary',
};

router.get('/usage', authenticate, asyncHandler(async (req, res) => {
  const tiers = readFeatureTiers();
  const isMember = isActiveMember(req.user);
  const usage = {};

  for (const tier of tiers) {
    const entry = { type: tier.type, isMember };
    if (isMember) {
      entry.unlimited = true;
    } else if (tier.type === 'daily_limit') {
      const actType = DAILY_ACTIVITY_MAP[tier.id] || tier.id;
      const used = await getDailyUsageCount(req.user.id, actType);
      entry.used = used;
      entry.limit = tier.free_limit || 0;
      entry.remaining = Math.max(0, entry.limit - used);
    } else if (tier.type === 'limit') {
      entry.limit = tier.free_limit || 0;
    } else if (tier.type === 'blocked') {
      entry.blocked = true;
    } else if (tier.type === 'enum') {
      entry.allowed = tier.free_values || [];
    }
    usage[tier.id] = entry;
  }
  res.json({ usage });
}));

// ── POST /activate-trial  用户自助开通会员体验 ──
const PLANS_FILE = path.join(__dirname, '../../config/membership.json');

function readTrialConfig() {
  try {
    if (fs.existsSync(PLANS_FILE)) {
      const data = JSON.parse(fs.readFileSync(PLANS_FILE, 'utf8'));
      return data.trial || { enabled: true, days: 3, description: '免费体验全部会员功能' };
    }
  } catch { /* ignore */ }
  return { enabled: true, days: 3, description: '免费体验全部会员功能' };
}

router.post('/activate-trial', authenticate, asyncHandler(async (req, res) => {
  const user = req.user;

  // 已经是有效会员不需要体验
  if (isActiveMember(user)) {
    return res.status(400).json({ error: '您已经是会员，无需开通体验' });
  }

  // 已使用过体验
  if (user.trial_activated) {
    return res.status(400).json({ error: '您已使用过会员体验，每个账号仅限一次' });
  }

  const trialConfig = readTrialConfig();
  if (!trialConfig.enabled) {
    return res.status(400).json({ error: '会员体验功能暂未开放' });
  }

  const days = trialConfig.days || 3;
  const expire = new Date();
  expire.setDate(expire.getDate() + days);

  await user.update({
    membership_plan: 'trial',
    membership_expire: expire,
    trial_activated: true,
  });

  res.json({
    ok: true,
    message: `已成功开通 ${days} 天会员体验`,
    membership_plan: 'trial',
    membership_expire: expire.toISOString(),
    trial_days: days,
  });
}));

// ── GET /trial-config  获取体验配置（公开）──
router.get('/trial-config', asyncHandler(async (req, res) => {
  const config = readTrialConfig();
  res.json({
    enabled: !!config.enabled,
    days: config.days || 3,
    description: config.description || '免费体验全部会员功能',
  });
}));

// ── DELETE /account  永久删除账户及所有数据 ──
router.delete('/account', authenticate, asyncHandler(async (req, res) => {
  const { password } = req.body;
  if (!password) {
    return res.status(400).json({ error: '请输入密码以确认删除' });
  }
  if (!(await req.user.validatePassword(password))) {
    const HttpError = require('../utils/httpError');
    throw new HttpError(401, '密码不正确');
  }

  const userId = req.user.id;
  const {
    UserVocabulary, SrsCard, QuizSession, UserProgress,
    StudyPlanDailyTask, StudyPlanCardState, GameScore,
    NewsFavorite, MembershipOrder,
  } = require('../models/index');
  const { ForumPost, ForumReply, ForumLike } = require('../models/Forum');

  // 删除所有用户关联数据
  await Promise.all([
    UserVocabulary.destroy({ where: { user_id: userId } }),
    SrsCard.destroy({ where: { user_id: userId } }),
    QuizSession.destroy({ where: { user_id: userId } }),
    UserProgress.destroy({ where: { user_id: userId } }),
    StudyPlanDailyTask.destroy({ where: { user_id: userId } }),
    StudyPlanCardState.destroy({ where: { user_id: userId } }),
    GameScore.destroy({ where: { user_id: userId } }),
    NewsFavorite.destroy({ where: { user_id: userId } }),
    MembershipOrder.destroy({ where: { user_id: userId } }),
    ForumLike.destroy({ where: { user_id: userId } }),
    ForumReply.destroy({ where: { user_id: userId } }),
    ForumPost.destroy({ where: { user_id: userId } }),
  ]);

  // 删除用户头像文件
  if (req.user.avatar_url && req.user.avatar_url.startsWith('/uploads/avatars/')) {
    const oldPath = path.join(__dirname, '../..', req.user.avatar_url.replace(/^\//, ''));
    if (fs.existsSync(oldPath)) {
      try { fs.unlinkSync(oldPath); } catch (_) {}
    }
  }

  // 删除用户
  await req.user.destroy();

  res.json({ ok: true, message: '账户已永久删除' });
}));

module.exports = router;
