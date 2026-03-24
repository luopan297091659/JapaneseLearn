/**
 * Sync Routes — 客户端用于检测内容版本，决定是否需要刷新词库/文法
 * GET /api/v1/sync/version  — 无需认证，返回当前内容版本号
 * GET /api/v1/sync/features — 无需认证，返回功能开关状态
 * GET /api/v1/sync/tiers    — 无需认证，返回功能分级配置
 */
const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { ContentVersion } = require('../models');
const path = require('path');
const fs = require('fs');

router.get('/version', asyncHandler(async (req, res) => {
  let cv = await ContentVersion.findByPk(1);
  if (!cv) {
    cv = await ContentVersion.create({
      id: 1, version: 1, vocab_version: 1, grammar_version: 1, updated_at_ts: Date.now(),
    });
  }
  res.json({
    version: cv.version,
    vocab_version: cv.vocab_version,
    grammar_version: cv.grammar_version,
    updated_at_ts: cv.updated_at_ts,
  });
}));

// ── 功能开关（公开接口，web/mobile 客户端使用）──
router.get('/features', asyncHandler(async (req, res) => {
  const togglesFile = path.join(__dirname, '../../config/feature_toggles.json');
  let data;
  try {
    if (fs.existsSync(togglesFile)) {
      data = JSON.parse(fs.readFileSync(togglesFile, 'utf8'));
    }
  } catch { /* ignore */ }
  if (!data || !Array.isArray(data.features)) {
    // return all enabled by default
    data = { features: [], updated_at: null };
  }
  // return platform-appropriate flags
  const platform = req.query.platform || 'web'; // 'web' or 'mobile'
  const features = {};
  data.features.forEach(f => {
    features[f.id] = platform === 'mobile' ? !!f.mobile : !!f.web;
  });
  res.json({ ok: true, platform, features, updated_at: data.updated_at });
}));

// ── 功能分级配置（公开接口，客户端获取免费/会员功能差异）──
router.get('/tiers', asyncHandler(async (req, res) => {
  const tiersFile = path.join(__dirname, '../../config/feature_tiers.json');
  let data;
  try {
    if (fs.existsSync(tiersFile)) {
      data = JSON.parse(fs.readFileSync(tiersFile, 'utf8'));
    }
  } catch { /* ignore */ }
  if (!data || !Array.isArray(data.tiers)) {
    data = { tiers: [], updated_at: null };
  }
  res.json({ ok: true, tiers: data.tiers, updated_at: data.updated_at });
}));

// ── 会员套餐配置（公开接口，客户端获取最新价格）──
router.get('/membership-plans', asyncHandler(async (req, res) => {
  const plansFile = path.join(__dirname, '../../config/membership.json');
  let config;
  try {
    if (fs.existsSync(plansFile)) {
      config = JSON.parse(fs.readFileSync(plansFile, 'utf8'));
    }
  } catch { /* ignore */ }
  if (!config || !Array.isArray(config.plans)) {
    config = {
      plans: [
        { id: 'monthly', name: '月度会员', price: 18, period: 'month', enabled: true },
        { id: 'yearly', name: '年度会员', price: 128, period: 'year', enabled: true },
        { id: 'lifetime', name: '终身会员', price: 398, period: 'forever', enabled: false },
      ],
    };
  }
  // Only return enabled plans with safe fields
  const plans = config.plans
    .filter(p => p.id !== 'free')
    .map(p => ({
      id: p.id,
      name: p.name,
      price: p.price,
      period: p.period,
      enabled: p.enabled !== false,
      features: p.features || [],
      description: p.description || '',
    }));
  res.json({ ok: true, plans });
}));

module.exports = router;
