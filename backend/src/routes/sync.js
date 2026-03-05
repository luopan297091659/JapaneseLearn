/**
 * Sync Routes — 客户端用于检测内容版本，决定是否需要刷新词库/文法
 * GET /api/v1/sync/version  — 无需认证，返回当前内容版本号
 */
const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { ContentVersion } = require('../models');

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

module.exports = router;
