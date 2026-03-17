const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { readFeatureTiers, getDailyUsageCount, isActiveMember } = require('../middlewares/membership');
const User = require('../models/User');
const path = require('path');
const fs = require('fs');

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

// ── GET /usage  获取今日功能用量（供客户端显示剩余额度）──
const DAILY_ACTIVITY_MAP = {
  srs_daily: 'srs_review',
  quiz_meaning_daily: 'quiz',
  immersion_daily: 'listening',
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

module.exports = router;
