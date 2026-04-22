const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const jwt = require('jsonwebtoken');
const { ToolUsageLog } = require('../models');

const ALLOWED_TOOLS = new Set([
  'screenshot-generator',
  'kokoro-tts',
  'tools-home',
]);
const ALLOWED_ACTIONS = new Set(['open', 'generate', 'export', 'play', 'click']);

// 解析可选 JWT（不强制登录）
function tryGetUserId(req) {
  try {
    const auth = req.headers.authorization || '';
    if (!auth.startsWith('Bearer ')) return null;
    const decoded = jwt.verify(auth.slice(7), process.env.JWT_SECRET);
    return decoded?.id || decoded?.userId || null;
  } catch (_) {
    return null;
  }
}

// POST /api/v1/tools/track  { tool_id, action?, meta? }
router.post('/track', asyncHandler(async (req, res) => {
  const { tool_id, action, meta } = req.body || {};
  if (!tool_id || !ALLOWED_TOOLS.has(String(tool_id))) {
    return res.status(400).json({ error: 'invalid tool_id' });
  }
  const act = ALLOWED_ACTIONS.has(String(action)) ? action : 'open';
  const ip = (req.headers['x-forwarded-for'] || req.ip || '').toString().split(',')[0].trim().slice(0, 60);
  const ua = (req.headers['user-agent'] || '').toString().slice(0, 300);
  const referer = (req.headers.referer || req.headers.referrer || '').toString().slice(0, 500);
  const userId = tryGetUserId(req);
  let safeMeta = null;
  if (meta && typeof meta === 'object') {
    try {
      const s = JSON.stringify(meta);
      if (s.length <= 2000) safeMeta = meta;
    } catch (_) { /* ignore */ }
  }
  await ToolUsageLog.create({
    tool_id, action: act, user_id: userId, ip, user_agent: ua, referer, meta: safeMeta,
  });
  res.json({ ok: true });
}));

module.exports = router;
