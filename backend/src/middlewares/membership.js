/**
 * Membership Middleware — 会员功能分级权限检查
 * 
 * 检查用户会员状态，判断是否有权限使用特定功能。
 * 支持四种限制类型：
 * - blocked: 免费用户完全不可用
 * - daily_limit: 免费用户有每日使用次数限制
 * - limit: 免费用户有总量限制（如语法只能看前N课）
 * - enum: 免费用户只能使用部分选项值
 */
const path = require('path');
const fs = require('fs');
const { UserProgress } = require('../models');
const { Op } = require('sequelize');

const TIERS_FILE = path.join(__dirname, '../../config/feature_tiers.json');

// 默认分级配置，与 feature_tiers.json 一致
const DEFAULT_TIERS = [
  { id: 'grammar_lessons', type: 'limit', free_limit: 5 },
  { id: 'srs_daily', type: 'daily_limit', free_limit: 30 },
  { id: 'immersion_daily', type: 'daily_limit', free_limit: 3 },
  { id: 'ai_features', type: 'blocked' },
  { id: 'pronunciation', type: 'blocked' },
  { id: 'anki_import', type: 'blocked' },
  { id: 'game_levels', type: 'limit', free_limit: 5 },
  { id: 'quiz_meaning_daily', type: 'daily_limit', free_limit: 10 },
  { id: 'quiz_reading_daily', type: 'daily_limit', free_limit: 10 },
  { id: 'quiz_jlpt_levels', type: 'enum', free_values: ['N5', 'N4'] },
  { id: 'quiz_count_options', type: 'enum', free_values: [10] },
  { id: 'kana_writing_modes', type: 'enum', free_values: ['basic'] },
  { id: 'flashcard_levels', type: 'enum', free_values: ['N5'] },
  { id: 'anki_quiz', type: 'blocked' },
  { id: 'wrong_answers', type: 'blocked' },
  { id: 'dictionary_daily', type: 'daily_limit', free_limit: 20 },
  { id: 'news_limit', type: 'limit', free_limit: 5 },
];

/** 读取分级配置 */
function readFeatureTiers() {
  try {
    if (fs.existsSync(TIERS_FILE)) {
      const data = JSON.parse(fs.readFileSync(TIERS_FILE, 'utf8'));
      return data.tiers || DEFAULT_TIERS;
    }
  } catch { /* ignore */ }
  return DEFAULT_TIERS;
}

/** 获取指定功能的分级规则 */
function getTierRule(featureId) {
  const tiers = readFeatureTiers();
  return tiers.find(t => t.id === featureId) || null;
}

/** 判断用户是否为有效会员 */
function isActiveMember(user) {
  if (!user) return false;
  if (!user.membership_plan || user.membership_plan === 'free') return false;
  // 永久会员无过期时间
  if (!user.membership_expire) return true;
  // 试用/会员统一判断过期时间
  return new Date(user.membership_expire) > new Date();
}

/** 获取今日起止时间 */
function todayRange() {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  return { start, end };
}

/**
 * 检查免费用户每日使用次数
 * @param {string} userId
 * @param {string} activityType - UserProgress 中的 activity_type
 * @returns {Promise<number>} 今日已使用次数
 */
async function getDailyUsageCount(userId, activityType) {
  const { start, end } = todayRange();
  const count = await UserProgress.count({
    where: {
      user_id: userId,
      activity_type: activityType,
      createdAt: { [Op.gte]: start, [Op.lt]: end },
    },
  });
  return count;
}

/**
 * 会员功能检查中间件工厂
 * @param {string} featureId - feature_tiers.json 中的 id
 * @param {object} [options]
 * @param {string} [options.countActivityType] - 用于统计每日使用次数的 activity_type
 * @param {string} [options.valueField] - 请求中需要校验的字段名（用于 enum 类型）
 * @param {string} [options.valueSource] - 'query' | 'body'，默认 'query'
 */
function checkMembership(featureId, options = {}) {
  return async (req, res, next) => {
    const user = req.user;
    // 未登录用户跳过检查（公开接口）
    if (!user) return next();
    // 管理员跳过检查
    if (user.role === 'admin') return next();
    // 有效会员跳过检查
    if (isActiveMember(user)) return next();

    const rule = getTierRule(featureId);
    if (!rule) return next(); // 无规则的功能默认放行

    switch (rule.type) {
      case 'blocked':
        return res.status(403).json({
          error: 'MEMBERSHIP_REQUIRED',
          feature: featureId,
          message: `此功能需要会员才能使用`,
        });

      case 'daily_limit': {
        const actType = options.countActivityType || featureId;
        const used = await getDailyUsageCount(user.id, actType);
        const limit = rule.free_limit || 0;
        if (used >= limit) {
          return res.status(403).json({
            error: 'DAILY_LIMIT_REACHED',
            feature: featureId,
            used,
            limit,
            message: `今日免费额度已用完（${used}/${limit}），升级会员可无限使用`,
          });
        }
        // 将剩余额度注入 req 供后续使用
        req.tierRemaining = limit - used;
        req.tierLimit = limit;
        return next();
      }

      case 'limit': {
        // limit 类型在具体路由中检查（如语法只返回前N条）
        req.tierLimit = rule.free_limit || 0;
        return next();
      }

      case 'enum': {
        const source = options.valueSource === 'body' ? req.body : req.query;
        const field = options.valueField;
        if (field && source[field]) {
          const val = source[field];
          const allowed = rule.free_values || [];
          if (!allowed.includes(val) && !allowed.includes(Number(val))) {
            return res.status(403).json({
              error: 'MEMBERSHIP_REQUIRED',
              feature: featureId,
              allowed,
              requested: val,
              message: `免费用户仅支持 ${allowed.join('/')}，升级会员可解锁全部`,
            });
          }
        }
        req.tierAllowed = rule.free_values || [];
        return next();
      }

      default:
        return next();
    }
  };
}

module.exports = {
  checkMembership,
  isActiveMember,
  readFeatureTiers,
  getTierRule,
  getDailyUsageCount,
};
