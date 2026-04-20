/**
 * Stripe Payment Routes
 * POST /api/v1/stripe/create-checkout-session — 创建 Stripe Checkout 会话（需登录）
 * POST /api/v1/stripe/webhook                 — Stripe Webhook 回调（无需登录）
 * GET  /api/v1/stripe/session-status          — 查询支付状态（需登录）
 */
const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const User = require('../models/User');
const logger = require('../utils/logger');
const HttpError = require('../utils/httpError');
const path = require('path');
const fs = require('fs');

// ── Stripe 初始化（从 config/membership.json 读取，管理员面板配置）──
function getPaymentConfig() {
  const plansFile = path.join(__dirname, '../../config/membership.json');
  try {
    if (fs.existsSync(plansFile)) {
      const config = JSON.parse(fs.readFileSync(plansFile, 'utf8'));
      return config.payment || {};
    }
  } catch { /* ignore */ }
  return {};
}

function getStripe() {
  const payment = getPaymentConfig();
  const key = payment.stripe_secret_key;
  if (!key || !payment.stripe_enabled) throw new HttpError(500, 'Stripe 未启用或未配置');
  return require('stripe')(key);
}

function getStripeConfig() {
  const payment = getPaymentConfig();
  return {
    currency: payment.stripe_currency || 'cny',
    webhookSecret: payment.stripe_webhook_secret || '',
  };
}

// 读取会员套餐配置
function readPlans() {
  const plansFile = path.join(__dirname, '../../config/membership.json');
  try {
    if (fs.existsSync(plansFile)) {
      const config = JSON.parse(fs.readFileSync(plansFile, 'utf8'));
      if (Array.isArray(config.plans)) return config.plans;
    }
  } catch { /* ignore */ }
  return [
    { id: 'monthly', name: '月度会员', price: 18, period: 'month', enabled: true },
    { id: 'yearly', name: '年度会员', price: 128, period: 'year', enabled: true },
    { id: 'lifetime', name: '终身会员', price: 398, period: 'forever', enabled: false },
  ];
}

// 计算到期时间
function calcExpire(period) {
  const now = new Date();
  switch (period) {
    case 'month':   return new Date(now.setMonth(now.getMonth() + 1));
    case 'year':    return new Date(now.setFullYear(now.getFullYear() + 1));
    case 'forever': return new Date('2099-12-31');
    default:        return new Date(now.setMonth(now.getMonth() + 1));
  }
}

// 会员等级（越高越尊贵）——只允许升级到更高等级
const PLAN_RANK = { monthly: 1, yearly: 2, lifetime: 3 };
function isActiveMembership(user) {
  if (!user || !user.membership_plan || user.membership_plan === 'free' || user.membership_plan === 'trial') return false;
  if (user.membership_plan === 'lifetime') return true;
  if (!user.membership_expire) return false;
  return new Date(user.membership_expire) > new Date();
}

// ── 创建 Checkout Session ──
router.post('/create-checkout-session', authenticate, asyncHandler(async (req, res) => {
  const stripe = getStripe();
  const { planId } = req.body;
  if (!planId) throw new HttpError(400, '请选择套餐');

  const plans = readPlans();
  const plan = plans.find(p => p.id === planId && p.enabled !== false && p.id !== 'free');
  if (!plan) throw new HttpError(400, '无效的套餐');

  // 会员等级检查：不允许购买同等/低于当前等级的套餐
  const user = await User.findByPk(req.user.id);
  if (isActiveMembership(user)) {
    const userRank = PLAN_RANK[user.membership_plan] || 0;
    const targetRank = PLAN_RANK[plan.id] || 0;
    if (targetRank && userRank && targetRank <= userRank) {
      const msg = user.membership_plan === plan.id
        ? '您已是该套餐会员'
        : '您当前的会员等级高于该套餐，无法降级';
      throw new HttpError(400, msg);
    }
  }

  // 价格转为分（Stripe 以最小货币单位计费）
  const unitAmount = Math.round(plan.price * 100);
  const { currency } = getStripeConfig();

  const session = await stripe.checkout.sessions.create({
    payment_method_types: ['card'],
    mode: 'payment',
    line_items: [{
      price_data: {
        currency: currency,
        product_data: {
          name: `言旅会员 — ${plan.name}`,
          description: plan.description || `${plan.name}，解锁全部功能`,
        },
        unit_amount: unitAmount,
      },
      quantity: 1,
    }],
    metadata: {
      user_id: req.user.id,
      plan_id: plan.id,
      plan_period: plan.period,
    },
    success_url: `${process.env.BASE_URL || req.protocol + '://' + req.get('host')}/membership?status=success&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${process.env.BASE_URL || req.protocol + '://' + req.get('host')}/membership?status=cancel`,
  });

  res.json({ ok: true, url: session.url, sessionId: session.id });
}));

// ── 查询支付状态 ──
router.get('/session-status', authenticate, asyncHandler(async (req, res) => {
  const stripe = getStripe();
  const { session_id } = req.query;
  if (!session_id) throw new HttpError(400, 'session_id required');

  const session = await stripe.checkout.sessions.retrieve(session_id);
  res.json({
    ok: true,
    status: session.payment_status,
    plan_id: session.metadata?.plan_id,
  });
}));

// ── Webhook（Stripe 签名验证）──
// 注意：此路由不能使用 express.json() 中间件，需要 raw body
// 单独导出，在 app.js 中用 express.raw() 挂载
async function stripeWebhook(req, res) {
  try {
    const stripe = getStripe();
    const sig = req.headers['stripe-signature'];
    const { webhookSecret } = getStripeConfig();

    let event;
    try {
      event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
    } catch (err) {
      logger.error(`Stripe webhook signature verification failed: ${err.message}`);
      return res.status(400).json({ error: 'Webhook signature verification failed' });
    }

    // 处理 checkout.session.completed 事件
    if (event.type === 'checkout.session.completed') {
      const session = event.data.object;
      if (session.payment_status === 'paid') {
        const { user_id, plan_id, plan_period } = session.metadata || {};
        if (user_id && plan_id) {
          try {
            const user = await User.findByPk(user_id);
            if (user) {
              // 终身会员不可被降级，同时避免为终身会员叠加日期造成溢出
              if (user.membership_plan === 'lifetime') {
                logger.warn(`Stripe payment ignored (already lifetime): user=${user_id}, plan=${plan_id}`);
              } else if (plan_id === 'lifetime') {
                await user.update({
                  membership_plan: 'lifetime',
                  membership_expire: new Date('2099-12-31'),
                });
                logger.info(`Stripe payment success: user=${user_id}, plan=lifetime`);
              } else {
                let expire = calcExpire(plan_period);
                // 如果已有会员且未过期，从当前到期日延长
                if (user.membership_expire && new Date(user.membership_expire) > new Date()) {
                  const currentExpire = new Date(user.membership_expire);
                  const extension = expire.getTime() - Date.now();
                  expire = new Date(currentExpire.getTime() + extension);
                }
                await user.update({
                  membership_plan: plan_id,
                  membership_expire: expire,
                });
                logger.info(`Stripe payment success: user=${user_id}, plan=${plan_id}, expire=${expire.toISOString()}`);
              }
            }
          } catch (err) {
            logger.error(`Failed to activate membership after payment: ${err.message}`);
          }
        }
      }
    }

    res.json({ received: true });
  } catch (err) {
    logger.error(`Stripe webhook error: ${err.message}`);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
}

module.exports = { router, stripeWebhook };
