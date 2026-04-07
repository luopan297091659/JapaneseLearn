/**
 * 五十音API路由
 */

const express = require('express');
const router = express.Router();
const { authenticate, requireRole } = require('../middlewares/auth');
const kanaController = require('../controllers/kanaController');
const { sequelize } = require('../config/database');

// 公开端点：获取分类
router.get('/categories', async (req, res) => {
  await kanaController.listKanaCategories(req, res);
});

// 公开端点：获取所有假名的音频URL映射（character -> audio_url）
router.get('/audio-map', async (req, res) => {
  try {
    const Kana = sequelize.models.Kana;
    if (!Kana) {
      return res.json({ success: true, data: {} });
    }
    const kanas = await Kana.findAll({
      where: { audio_url: { [require('sequelize').Op.not]: null } },
      attributes: ['character', 'audio_url'],
      raw: true,
    });
    const map = {};
    for (const k of kanas) {
      if (k.audio_url) map[k.character] = k.audio_url;
    }
    res.json({ success: true, data: map });
  } catch (err) {
    console.error('[Kana] 获取音频映射失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// 管理员端点：一键生成音频
router.post('/admin/generate-audio', authenticate, requireRole('admin'), async (req, res) => {
  await kanaController.generateKanaAudioBatch(req, res);
});

// 用户端点：获取学习进度
router.get('/user/:userId/progress', authenticate, async (req, res) => {
  const requesterId = req.user?.id;
  const targetUserId = req.params.userId;
  
  if (requesterId !== targetUserId && req.user?.role !== 'admin') {
    return res.status(403).json({ success: false, error: 'Permission denied' });
  }
  
  await kanaController.getUserKanaProgress(req, res);
});

module.exports = router;
