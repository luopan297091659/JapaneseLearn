/**
 * Apple App Store Server Notifications V2 处理
 *
 * 文档: https://developer.apple.com/documentation/appstoreservernotifications
 *
 * Apple 会向我们配置的 webhook 发送 POST，body 形如:
 *   { "signedPayload": "<JWS>" }
 *
 * 解码 JWS 得到 responseBodyV2DecodedPayload，其中:
 *   - notificationType:  DID_RENEW / DID_FAIL_TO_RENEW / EXPIRED / REFUND / REVOKE / ...
 *   - subtype:           BILLING_RETRY / VOLUNTARY / AUTO_RENEW_DISABLED / ...
 *   - data.signedTransactionInfo: 内含 productId / originalTransactionId / expiresDate ...
 *   - data.signedRenewalInfo:     内含 autoRenewStatus / autoRenewProductId ...
 *
 * 注意:
 *   - 当前实现只校验 JWS 签名（ES256 / leaf 公钥），未做完整 x5c 链 → Apple Root CA 校验。
 *     生产建议补充链校验，或引入官方库 app-store-server-library。
 *   - webhook 端点必须无需鉴权。
 */
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');
const logger = require('../utils/logger');
const User = require('../models/User');
const { MembershipOrder } = require('../models/index');

const PLANS_FILE = path.join(__dirname, '../../config/membership.json');

function readPlans() {
  try {
    const cfg = JSON.parse(fs.readFileSync(PLANS_FILE, 'utf8'));
    return (cfg.plans || []).filter(p => p.id !== 'free');
  } catch {
    return [];
  }
}

/** 解析 + 验证一个 JWS（ES256），返回 payload 对象 */
function decodeAndVerifyJWS(jws) {
  if (typeof jws !== 'string' || jws.split('.').length !== 3) {
    throw new Error('Invalid JWS format');
  }
  const [headerB64, payloadB64, sigB64] = jws.split('.');

  const header = JSON.parse(Buffer.from(headerB64, 'base64url').toString('utf8'));
  if (header.alg !== 'ES256') throw new Error(`Unsupported alg: ${header.alg}`);
  if (!Array.isArray(header.x5c) || header.x5c.length === 0) {
    throw new Error('Missing x5c chain in JWS header');
  }

  // 用 leaf 证书的公钥验签
  const leafCert = new crypto.X509Certificate(Buffer.from(header.x5c[0], 'base64'));
  const signingInput = Buffer.from(`${headerB64}.${payloadB64}`);
  const signature = Buffer.from(sigB64, 'base64url');

  const ok = crypto.verify(
    'SHA256',
    signingInput,
    { key: leafCert.publicKey, dsaEncoding: 'ieee-p1363' },
    signature,
  );
  if (!ok) throw new Error('JWS signature verification failed');

  // 简单校验签发者是 Apple（防止伪造证书）
  const subject = leafCert.subject || '';
  const issuer = leafCert.issuer || '';
  if (!issuer.includes('Apple')) {
    throw new Error(`Untrusted JWS issuer: ${issuer}`);
  }
  // 校验有效期
  const now = Date.now();
  if (now < Date.parse(leafCert.validFrom) || now > Date.parse(leafCert.validTo)) {
    throw new Error('Leaf certificate not in validity period');
  }
  // TODO: 完整 x5c → Apple Root CA 链校验

  void subject;
  return JSON.parse(Buffer.from(payloadB64, 'base64url').toString('utf8'));
}

/** 找到与 productId 对应的套餐 */
function findPlanByProductId(productId) {
  if (!productId) return null;
  return readPlans().find(p => p.apple_product_id === productId) || null;
}

/** 根据 originalTransactionId 找到这条订阅最近的本系统用户 */
async function findUserByOriginalTx(originalTransactionId) {
  if (!originalTransactionId) return null;
  // 优先: 之前已记录该 originalTransactionId 的订单
  let order = await MembershipOrder.findOne({
    where: { apple_original_transaction_id: originalTransactionId },
    order: [['createdAt', 'DESC']],
  });
  if (order) return User.findByPk(order.user_id);

  // 回退: 通过 transaction_id 匹配（首单可能没有 original_transaction_id）
  order = await MembershipOrder.findOne({
    where: { apple_transaction_id: originalTransactionId },
    order: [['createdAt', 'DESC']],
  });
  if (order) return User.findByPk(order.user_id);

  return null;
}

/** 处理一次解码后的通知 payload */
async function handleDecodedNotification(payload) {
  const notificationType = payload.notificationType;
  const subtype = payload.subtype || null;
  const data = payload.data || {};
  const env = data.environment || payload.environment || null;

  let txInfo = {};
  let renewalInfo = {};
  try {
    if (data.signedTransactionInfo) {
      txInfo = decodeAndVerifyJWS(data.signedTransactionInfo);
    }
  } catch (e) {
    logger.warn(`[AppleNotif] decode signedTransactionInfo failed: ${e.message}`);
  }
  try {
    if (data.signedRenewalInfo) {
      renewalInfo = decodeAndVerifyJWS(data.signedRenewalInfo);
    }
  } catch (e) {
    logger.warn(`[AppleNotif] decode signedRenewalInfo failed: ${e.message}`);
  }

  const productId = txInfo.productId || renewalInfo.autoRenewProductId;
  const originalTx = txInfo.originalTransactionId || renewalInfo.originalTransactionId;
  const txId = txInfo.transactionId || null;
  const expiresAt = txInfo.expiresDate ? new Date(txInfo.expiresDate) : null;
  const autoRenew = typeof renewalInfo.autoRenewStatus === 'number'
    ? renewalInfo.autoRenewStatus === 1
    : null;

  logger.info(
    `[AppleNotif] type=${notificationType} subtype=${subtype || '-'} ` +
    `product=${productId || '-'} originalTx=${originalTx || '-'} expires=${expiresAt?.toISOString() || '-'}`
  );

  if (!originalTx) {
    logger.warn('[AppleNotif] no originalTransactionId, skip');
    return { ok: true, skipped: true };
  }

  const user = await findUserByOriginalTx(originalTx);
  if (!user) {
    logger.warn(`[AppleNotif] no user matched for originalTx=${originalTx}`);
    return { ok: true, skipped: true };
  }
  const plan = findPlanByProductId(productId);

  // 写一条审计订单（除 TEST 外）
  if (notificationType !== 'TEST') {
    await MembershipOrder.create({
      user_id: user.id,
      plan_id: plan?.id || productId || 'unknown',
      amount: plan?.price || 0,
      currency: 'cny',
      channel: 'apple_iap',
      status: ['DID_RENEW'].includes(notificationType) ? 'paid'
        : (notificationType === 'REFUND' ? 'refunded' : 'paid'),
      apple_transaction_id: txId,
      apple_original_transaction_id: originalTx,
      apple_environment: env,
      apple_expires_at: expiresAt,
      apple_auto_renew_status: autoRenew,
      apple_notification_type: subtype ? `${notificationType}:${subtype}` : notificationType,
      paid_at: txInfo.purchaseDate ? new Date(txInfo.purchaseDate) : new Date(),
      expire_at: expiresAt,
    });
  }

  // 根据通知类型更新用户会员状态
  switch (notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
    case 'DID_CHANGE_RENEWAL_PREF':
    case 'OFFER_REDEEMED':
    case 'PRICE_INCREASE': // 仅信息性
      if (expiresAt && plan) {
        await user.update({
          membership_plan: plan.id,
          membership_expire: expiresAt,
        });
      }
      break;

    case 'DID_CHANGE_RENEWAL_STATUS':
      // 用户开/关自动续费，本次到期前仍然有效，不改 expire
      logger.info(`[AppleNotif] user=${user.id} autoRenew=${autoRenew}`);
      break;

    case 'DID_FAIL_TO_RENEW':
      // 进入计费重试期，subtype=GRACE_PERIOD 时仍有效；不主动降级，等 EXPIRED
      break;

    case 'EXPIRED':
      // 订阅彻底到期。若当前 expire 仍指向此订阅（<=Apple expiresAt），则降级
      if (expiresAt && new Date(user.membership_expire || 0) <= expiresAt) {
        await user.update({ membership_expire: expiresAt });
      }
      break;

    case 'REFUND':
    case 'REVOKE':
      // 立即降级（如果当前会员就是这条订阅）
      if (user.membership_plan === plan?.id) {
        await user.update({ membership_expire: new Date() });
      }
      break;

    case 'TEST':
      logger.info('[AppleNotif] TEST notification received');
      break;

    default:
      logger.info(`[AppleNotif] unhandled type ${notificationType}`);
  }

  return { ok: true };
}

/** Express handler 入口：req.body = { signedPayload } */
async function handleAppleNotification(req, res) {
  try {
    const signed = req.body?.signedPayload;
    if (!signed) {
      return res.status(400).json({ error: 'missing signedPayload' });
    }
    const payload = decodeAndVerifyJWS(signed);
    await handleDecodedNotification(payload);
    return res.status(200).json({ ok: true });
  } catch (err) {
    logger.error(`[AppleNotif] handler error: ${err.message}`);
    // 返回 5xx 让 Apple 重试
    return res.status(500).json({ error: err.message });
  }
}

module.exports = {
  handleAppleNotification,
  decodeAndVerifyJWS, // 导出供测试
};
