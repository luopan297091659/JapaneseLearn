/**
 * Payment Routes — Apple IAP 验证 + 二维码收款截图上传
 *
 * POST /api/v1/payment/apple/verify     — 验证 Apple IAP 收据
 * POST /api/v1/payment/qrcode/submit    — 提交二维码付款截图
 * GET  /api/v1/payment/qrcode/config    — 获取收款二维码配置
 * GET  /api/v1/payment/orders           — 用户查询自己的订单
 * GET  /api/v1/payment/plans            — 获取可用套餐（含平台信息）
 */
const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { isActiveMember } = require('../middlewares/membership');
const User = require('../models/User');
const { MembershipOrder } = require('../models/index');
const logger = require('../utils/logger');
const HttpError = require('../utils/httpError');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const { sendOrderNotification } = require('../services/emailService');
const { handleAppleNotification } = require('../services/appleNotifications');

// ── Apple App Store Server Notifications V2 webhook ──────────────────────────
// 必须无需鉴权，URL 在 App Store Connect 的 App Information 中配置
router.post('/apple/notifications', asyncHandler(handleAppleNotification));

// ── 配置读取 ─────────────────────────────────────────────────────────────────
const PLANS_FILE = path.join(__dirname, '../../config/membership.json');

function readConfig() {
  try {
    if (fs.existsSync(PLANS_FILE)) {
      return JSON.parse(fs.readFileSync(PLANS_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  return { plans: [], payment: {}, notice: '' };
}

function readPlans() {
  const config = readConfig();
  return (config.plans || []).filter(p => p.enabled !== false && p.id !== 'free');
}

function calcExpire(period, baseDate) {
  const now = baseDate ? new Date(baseDate) : new Date();
  switch (period) {
    case 'month':   return new Date(now.setMonth(now.getMonth() + 1));
    case 'year':    return new Date(now.setFullYear(now.getFullYear() + 1));
    case 'forever': return new Date('2099-12-31');
    default:        return new Date(now.setMonth(now.getMonth() + 1));
  }
}

async function activateMembership(userId, planId, period, orderId) {
  const user = await User.findByPk(userId);
  if (!user) throw new HttpError(404, '用户不存在');

  const expire = calcExpire(period);
  // 如果当前还在会员有效期内，叠加时长
  if (user.membership_expire && new Date(user.membership_expire) > new Date()) {
    const currentExpire = new Date(user.membership_expire);
    const extension = expire.getTime() - Date.now();
    expire.setTime(currentExpire.getTime() + extension);
  }

  await user.update({
    membership_plan: planId,
    membership_expire: expire,
  });

  if (orderId) {
    await MembershipOrder.update(
      { status: 'paid', paid_at: new Date(), expire_at: expire },
      { where: { id: orderId } },
    );
  }

  logger.info(`Membership activated: user=${userId}, plan=${planId}, expire=${expire.toISOString()}`);
  return expire;
}

// ── GET /plans — 获取可用套餐 ─────────────────────────────────────────────────
router.get('/plans', asyncHandler(async (req, res) => {
  const config = readConfig();
  const plans = (config.plans || []).filter(p => p.enabled !== false);
  const payment = config.payment || {};
  res.json({
    plans: plans.map(p => ({
      id: p.id,
      name: p.name,
      price: p.price,
      period: p.period,
      description: p.description,
      features: p.features,
      apple_product_id: p.apple_product_id || null,
    })),
    channels: {
      apple_iap: !!payment.apple_iap_enabled,
      stripe: !!payment.stripe_enabled,
      qrcode_alipay: !!payment.alipay_enabled && !!payment.alipay_qr_url,
      qrcode_wechat: !!payment.wechat_enabled && !!payment.wechat_qr_url,
    },
    notice: config.notice || '',
  });
}));

// ── Apple IAP 收据验证 ───────────────────────────────────────────────────────
router.post('/apple/verify', authenticate, asyncHandler(async (req, res) => {
  const { receipt_data, plan_id, transaction_id } = req.body;
  console.log('[apple/verify] user=%s plan=%s tx=%s receiptLen=%s receiptHead=%s',
    req.user?.id, plan_id, transaction_id,
    receipt_data ? receipt_data.length : 0,
    receipt_data ? String(receipt_data).substring(0, 24) : '');
  if (!receipt_data || !plan_id) throw new HttpError(400, '缺少收据或套餐信息');

  const plans = readPlans();
  const plan = plans.find(p => p.id === plan_id);
  if (!plan) throw new HttpError(400, '无效的套餐');

  const config = readConfig();
  const payment = config.payment || {};
  if (!payment.apple_iap_enabled) throw new HttpError(400, 'Apple IAP 未启用');

  // 防止重复
  if (transaction_id) {
    const existing = await MembershipOrder.findOne({
      where: { apple_transaction_id: transaction_id, status: 'paid' },
    });
    if (existing) {
      return res.json({ ok: true, message: '此交易已处理', already_processed: true });
    }
  }

  // 检测收据格式：StoreKit 2 (JWS, "eyJ..." 开头) 或 StoreKit 1 (base64 PKCS7, "MII..." 开头)
  const isJws = typeof receipt_data === 'string' && receipt_data.startsWith('eyJ') && receipt_data.split('.').length === 3;
  let verified;
  if (isJws) {
    console.log('[apple/verify] detected StoreKit 2 JWS receipt, parsing payload');
    verified = parseJwsTransaction(receipt_data);
  } else {
    verified = await verifyAppleReceipt(receipt_data, payment.apple_shared_secret);
  }
  if (!verified.valid) {
    throw new HttpError(400, verified.error || 'Apple 收据验证失败');
  }

  // 检查 product_id 匹配
  const matchedTx = verified.latestTransaction;
  if (matchedTx && plan.apple_product_id && matchedTx.product_id !== plan.apple_product_id) {
    throw new HttpError(400, '收据产品ID与套餐不匹配');
  }

  // 创建订单并激活
  const expiresAtMs = matchedTx?.expires_date_ms ? Number(matchedTx.expires_date_ms) : null;
  const order = await MembershipOrder.create({
    user_id: req.user.id,
    plan_id: plan.id,
    amount: plan.price,
    currency: 'cny',
    channel: 'apple_iap',
    status: 'paid',
    apple_transaction_id: transaction_id || matchedTx?.transaction_id || null,
    apple_original_transaction_id: matchedTx?.original_transaction_id || transaction_id || null,
    apple_environment: verified.receipt?.environment || null,
    apple_expires_at: expiresAtMs ? new Date(expiresAtMs) : null,
    apple_receipt: receipt_data.substring(0, 500), // 只存截断，避免存大量数据
    paid_at: new Date(),
  });

  const expire = await activateMembership(req.user.id, plan.id, plan.period, order.id);

  res.json({
    ok: true,
    message: '会员已开通',
    membership_plan: plan.id,
    membership_expire: expire.toISOString(),
  });
}));

// Apple 收据验证（App Store / Sandbox）
async function verifyAppleReceipt(receiptData, sharedSecret) {
  const https = require('https');

  async function postToApple(url, body) {
    return new Promise((resolve, reject) => {
      const data = JSON.stringify(body);
      const urlObj = new URL(url);
      const options = {
        hostname: urlObj.hostname,
        path: urlObj.pathname,
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) },
      };
      const req = https.request(options, (res) => {
        let body = '';
        res.on('data', c => body += c);
        res.on('end', () => {
          try { resolve(JSON.parse(body)); } catch { reject(new Error('Apple response parse error')); }
        });
      });
      req.on('error', reject);
      req.write(data);
      req.end();
    });
  }

  const payload = {
    'receipt-data': receiptData,
    ...(sharedSecret ? { password: sharedSecret } : {}),
  };

  // 先尝试生产环境
  let result = await postToApple('https://buy.itunes.apple.com/verifyReceipt', payload);
  console.log('[apple/verify] production status=%s env=%s', result.status, result.environment || result.receipt?.environment);

  // status 21007 = sandbox receipt sent to production, retry with sandbox
  // 部分沙箱账号生产端返回 21002，同样回退沙箱重试
  if (result.status === 21007 || result.status === 21002 || result.status === 21008) {
    console.log('[apple/verify] retrying sandbox endpoint due to status=%s', result.status);
    const sandboxResult = await postToApple('https://sandbox.itunes.apple.com/verifyReceipt', payload);
    console.log('[apple/verify] sandbox status=%s env=%s', sandboxResult.status, sandboxResult.environment || sandboxResult.receipt?.environment);
    if (sandboxResult.status === 0) {
      result = sandboxResult;
    } else if (result.status === 21002) {
      // 生产为 21002 且沙箱也失败，以沙箱错误为准
      result = sandboxResult;
    }
  }

  if (result.status !== 0) {
    const desc = APPLE_STATUS_DESC[result.status] || '未知错误';
    return { valid: false, error: `Apple 验证失败 status=${result.status}（${desc}）` };
  }

  // 获取最新交易
  const inApp = result.receipt?.in_app || [];
  const latest = result.latest_receipt_info || inApp;
  const latestTx = Array.isArray(latest) && latest.length > 0
    ? latest.sort((a, b) => (b.purchase_date_ms || 0) - (a.purchase_date_ms || 0))[0]
    : null;

  return {
    valid: true,
    latestTransaction: latestTx,
    receipt: result.receipt,
  };
}

// Apple 验证状态码 https://developer.apple.com/documentation/appstorereceipts/status
const APPLE_STATUS_DESC = {
  21000: '请求不是 POST',
  21002: '收据数据格式错误或已损坏',
  21003: '收据未能验证',
  21004: 'shared secret 与产品不匹配',
  21005: 'Apple 收据服务器暂时不可用',
  21006: '收据有效但订阅已过期',
  21007: '沙箱收据发送到了生产环境',
  21008: '生产收据发送到了沙箱环境',
  21010: '收据无授权',
};

// 解析 StoreKit 2 JWS 收据（App Store Server JWS Signed Transaction）
// JWS 由 Apple 服务器签发，结构 header.payload.signature，payload 是 base64url 编码的 JSON
// 字段参考: https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload
function parseJwsTransaction(jws) {
  try {
    const parts = String(jws).split('.');
    if (parts.length !== 3) return { valid: false, error: 'JWS 格式错误（非3段）' };
    const payloadJson = Buffer.from(parts[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8');
    const payload = JSON.parse(payloadJson);
    console.log('[apple/verify] JWS payload productId=%s tx=%s origTx=%s env=%s expiresMs=%s',
      payload.productId, payload.transactionId, payload.originalTransactionId, payload.environment, payload.expiresDate);
    return {
      valid: true,
      latestTransaction: {
        product_id: payload.productId,
        transaction_id: payload.transactionId,
        original_transaction_id: payload.originalTransactionId,
        purchase_date_ms: payload.purchaseDate,
        expires_date_ms: payload.expiresDate, // 非订阅可能没有
      },
      receipt: { environment: payload.environment },
    };
  } catch (e) {
    console.error('[apple/verify] JWS parse error:', e.message);
    return { valid: false, error: 'JWS 解析失败：' + e.message };
  }
}

// ── 二维码收款配置 ───────────────────────────────────────────────────────────
router.get('/qrcode/config', asyncHandler(async (req, res) => {
  const config = readConfig();
  const payment = config.payment || {};
  const plans = (config.plans || []).filter(p => p.enabled !== false && p.id !== 'free');

  // 将相对路径转为完整 URL
  const baseUrl = `${req.protocol}://${req.get('host')}`;
  const toAbsolute = (url) => {
    if (!url) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return baseUrl + url;
  };

  res.json({
    alipay: payment.alipay_enabled && payment.alipay_qr_url ? {
      enabled: true,
      qr_url: toAbsolute(payment.alipay_qr_url),
    } : { enabled: false },
    wechat: payment.wechat_enabled && payment.wechat_qr_url ? {
      enabled: true,
      qr_url: toAbsolute(payment.wechat_qr_url),
    } : { enabled: false },
    plans: plans.map(p => ({ id: p.id, name: p.name, price: p.price, period: p.period })),
  });
}));

// ── 二维码付款截图上传 ──────────────────────────────────────────────────────
const proofDir = path.join(__dirname, '../../uploads/payment_proofs');
if (!fs.existsSync(proofDir)) fs.mkdirSync(proofDir, { recursive: true });

const proofUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 8 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype && file.mimetype.startsWith('image/')) return cb(null, true);
    cb(new Error('仅支持图片文件'));
  },
});

router.post('/qrcode/submit', authenticate, proofUpload.single('proof'), asyncHandler(async (req, res) => {
  if (!req.file) throw new HttpError(400, '请上传付款截图');
  const { plan_id, channel, user_note } = req.body;
  if (!plan_id) throw new HttpError(400, '请选择套餐');
  if (!['qrcode_alipay', 'qrcode_wechat', 'qrcode_bank', 'apple_iap_failed'].includes(channel)) {
    throw new HttpError(400, '无效的支付渠道');
  }

  const plans = readPlans();
  const plan = plans.find(p => p.id === plan_id);
  if (!plan) throw new HttpError(400, '无效的套餐');

  // 检查是否有待审核订单
  const pendingCount = await MembershipOrder.count({
    where: { user_id: req.user.id, status: 'pending', channel: ['qrcode_alipay', 'qrcode_wechat', 'qrcode_bank', 'apple_iap_failed'] },
  });
  if (pendingCount >= 3) throw new HttpError(400, '您有太多待审核订单，请等待管理员处理');

  // 保存截图
  const ext = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' }[req.file.mimetype] || '.jpg';
  const filename = `${uuidv4()}${ext}`;
  fs.writeFileSync(path.join(proofDir, filename), req.file.buffer);
  const proofUrl = `/uploads/payment_proofs/${filename}`;

  const order = await MembershipOrder.create({
    user_id: req.user.id,
    plan_id: plan.id,
    amount: plan.price,
    currency: 'cny',
    channel,
    status: 'pending',
    proof_image_url: proofUrl,
    user_note: (user_note || '').toString().slice(0, 1000) || null,
  });

  // 异步发送邮件通知，不阻塞响应
  try {
    const cfg = readConfig();
    const noti = cfg.notification || {};
    if (noti.order_email_enabled && noti.order_email_recipients && noti.order_email_recipients.length) {
      const baseUrl = `${req.protocol}://${req.get('host')}`;
      sendOrderNotification(noti.order_email_recipients, {
        orderId: order.id,
        userName: req.user.nickname || req.user.username || '未知',
        userEmail: req.user.email || '',
        planName: plan.name || plan.id,
        amount: plan.price,
        channel,
        createdAt: order.createdAt,
        proofUrl: proofUrl ? `${baseUrl}${proofUrl}` : null,
      }).catch(err => logger.error('发送订单通知邮件失败:', err));
    }
  } catch (e) { /* ignore notification errors */ }

  res.json({
    ok: true,
    message: '付款截图已提交，请等待管理员审核',
    order_id: order.id,
    status: 'pending',
  });
}));

// ── 用户查询自己的订单 ──────────────────────────────────────────────────────
router.get('/orders', authenticate, asyncHandler(async (req, res) => {
  const orders = await MembershipOrder.findAll({
    where: { user_id: req.user.id },
    order: [['createdAt', 'DESC']],
    limit: 20,
  });
  res.json({ orders });
}));
// ── 退款申请（仅首次订阅 7 天内可申请） ─────────────────────────
router.post('/refund/apply', authenticate, asyncHandler(async (req, res) => {
  const { reason } = req.body || {};
  if (!reason || !String(reason).trim()) throw new HttpError(400, '请填写退款原因');

  // 取最近一笔 paid 订单
  const lastPaid = await MembershipOrder.findOne({
    where: { user_id: req.user.id, status: 'paid' },
    order: [['paid_at', 'DESC']],
  });
  if (!lastPaid || !lastPaid.paid_at) throw new HttpError(400, '未找到可退款的订单');

  const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
  const elapsed = Date.now() - new Date(lastPaid.paid_at).getTime();
  if (elapsed > sevenDaysMs) {
    throw new HttpError(400, '超过 7 天退款期限，无法申请退款');
  }

  // 防重复：已有 pending 退款记录则拒绝
  const dup = await MembershipOrder.findOne({
    where: { user_id: req.user.id, channel: 'refund_request', status: 'pending' },
  });
  if (dup) throw new HttpError(400, '您已有退款申请在处理中');

  // 创建一条 refund_request 工单（复用订单表）
  const order = await MembershipOrder.create({
    user_id: req.user.id,
    plan_id: lastPaid.plan_id,
    amount: lastPaid.amount,
    currency: lastPaid.currency,
    channel: 'refund_request',
    status: 'pending',
    admin_note: `[退款申请] 原订单=${lastPaid.id}\n原因：${String(reason).slice(0, 500)}`,
  });

  // 邮件通知管理员
  try {
    const cfg = readConfig();
    const noti = cfg.notification || {};
    if (noti.order_email_enabled && noti.order_email_recipients && noti.order_email_recipients.length) {
      sendOrderNotification(noti.order_email_recipients, {
        orderId: order.id,
        userName: req.user.nickname || req.user.username || '未知',
        userEmail: req.user.email || '',
        planName: `退款申请：${lastPaid.plan_id}`,
        amount: lastPaid.amount,
        channel: 'refund_request',
        createdAt: order.createdAt,
        proofUrl: null,
      }).catch(err => logger.error('发送退款邮件失败:', err));
    }
  } catch (e) { /* ignore */ }

  res.json({
    ok: true,
    message: '退款申请已提交，我们将在 3 个工作日内处理',
    order_id: order.id,
  });
}));
module.exports = router;
