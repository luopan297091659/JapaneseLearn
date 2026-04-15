/**
 * Kokoro音频管理路由
 * 功能：
 * 1. 音频清理和维护（支持多路径）
 * 2. 统计和监控
 * 3. 管理员操作
 */

const express = require('express');
const router = express.Router();
const { authenticate, requireRole } = require('../middlewares/auth');
const audioLocalizationService = require('../services/audioLocalizationService');
const audioCleanupService = require('../services/audioCleanupService');
const { sequelize } = require('../config/database');
const { Op } = require('sequelize');
const path = require('path');
const fs = require('fs').promises;

// 路径配置（按功能模块）
const AUDIO_PATHS = {
  grammar: path.join(process.cwd(), 'uploads', 'grammar', 'audio'),
  vocabulary: path.join(process.cwd(), 'uploads', 'audio', 'vocab'),
  kana: path.join(process.cwd(), 'uploads', 'audio', 'kana')
};

// URL模式
const AUDIO_URL_PATTERNS = {
  grammar: '/uploads/grammar/audio/%',
  vocabulary: '/uploads/audio/vocab/%',
  kana: '/uploads/audio/kana/%'
};

/**
 * GET /api/v1/kokoro-audio/stats
 * 获取音频统计信息
 */
router.get('/stats', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const Vocabulary = sequelize.models.Vocabulary;
    const GrammarExample = sequelize.models.GrammarExample;
    const KanaAudio = sequelize.models.KanaAudio;

    // 统计各表的音频数据
    const vocabAudioCount = await Vocabulary.count({
      where: { audio_url: { [Op.like]: AUDIO_URL_PATTERNS.vocabulary } }
    });
    const grammarAudioCount = await GrammarExample.count({
      where: { audio_url: { [Op.like]: AUDIO_URL_PATTERNS.grammar } }
    });
    const kanaAudioCount = KanaAudio ? await KanaAudio.count() : 0;

    // 计算磁盘使用量
    const totalSize = await audioLocalizationService.getTotalStorageSize();
    const sizeGB = (totalSize / (1024 * 1024 * 1024)).toFixed(2);

    // 统计过期音频
    const expiredVocabCount = await Vocabulary.count({
      where: {
        audio_expires_at: { [Op.lt]: new Date() },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.vocabulary }
      }
    });

    const expiredGrammarCount = await GrammarExample.count({
      where: {
        audio_expires_at: { [Op.lt]: new Date() },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.grammar }
      }
    });

    res.json({
      success: true,
      stats: {
        diskUsage: {
          bytes: totalSize,
          gb: parseFloat(sizeGB)
        },
        audioCount: {
          vocabulary: vocabAudioCount,
          grammar: grammarAudioCount,
          kana: kanaAudioCount,
          total: vocabAudioCount + grammarAudioCount + kanaAudioCount
        },
        expiredAudio: {
          vocabulary: expiredVocabCount,
          grammar: expiredGrammarCount,
          total: expiredVocabCount + expiredGrammarCount
        }
      }
    });
  } catch (err) {
    console.error('[Kokoro] 统计失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/kokoro-audio/cleanup/expired
 * 手动清理过期音频
 */
router.post('/cleanup/expired', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const Vocabulary = sequelize.models.Vocabulary;
    const GrammarExample = sequelize.models.GrammarExample;

    const now = new Date();
    let deletedCount = 0;

    // 清理过期的词汇音频
    const expiredVocab = await Vocabulary.findAll({
      where: {
        audio_expires_at: { [Op.lt]: now },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.vocabulary }
      },
      attributes: ['id', 'audio_url']
    });

    for (const vocab of expiredVocab) {
      if (vocab.audio_url) {
        const filename = path.basename(vocab.audio_url);
        await audioLocalizationService.deleteLocalKokoroAudio(filename, 'vocabulary');
        await vocab.update({ audio_url: null, audio_expires_at: null });
        deletedCount++;
      }
    }

    // 清理过期的语法音频
    const expiredGrammar = await GrammarExample.findAll({
      where: {
        audio_expires_at: { [Op.lt]: now },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.grammar }
      },
      attributes: ['id', 'audio_url']
    });

    for (const grammar of expiredGrammar) {
      if (grammar.audio_url) {
        const filename = path.basename(grammar.audio_url);
        await audioLocalizationService.deleteLocalKokoroAudio(filename, 'grammar');
        await grammar.update({ audio_url: null, audio_expires_at: null });
        deletedCount++;
      }
    }

    console.log(`[Cleanup] 已清理 ${deletedCount} 个过期音频`);

    res.json({
      success: true,
      message: `已清理 ${deletedCount} 个过期音频`,
      deletedCount
    });
  } catch (err) {
    console.error('[Cleanup] 清理过期音频失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/kokoro-audio/cleanup/orphaned
 * 清理孤立文件（有磁盘文件但无数据库记录）
 */
router.post('/cleanup/orphaned', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const Vocabulary = sequelize.models.Vocabulary;
    const GrammarExample = sequelize.models.GrammarExample;

    // 获取所有有效的音频文件名
    const vocabAudios = await Vocabulary.findAll({
      attributes: ['audio_url'],
      where: { audio_url: { [Op.not]: null } },
      raw: true
    });

    const grammarAudios = await GrammarExample.findAll({
      attributes: ['audio_url'],
      where: { audio_url: { [Op.not]: null } },
      raw: true
    });

    const validFilenames = new Set();
    vocabAudios.forEach(v => {
      if (v.audio_url) validFilenames.add(path.basename(v.audio_url));
    });
    grammarAudios.forEach(g => {
      if (g.audio_url) validFilenames.add(path.basename(g.audio_url));
    });

    // 扫描磁盘上的文件
    const files = await fs.readdir(AUDIO_BASE_PATH);
    let orphanedCount = 0;

    for (const file of files) {
      if (!validFilenames.has(file)) {
        await audioLocalizationService.deleteLocalKokoroAudio(file);
        orphanedCount++;
      }
    }

    console.log(`[Cleanup] 已清理 ${orphanedCount} 个孤立文件`);

    res.json({
      success: true,
      message: `已清理 ${orphanedCount} 个孤立文件`,
      orphanedCount
    });
  } catch (err) {
    console.error('[Cleanup] 清理孤立文件失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/kokoro-audio/delete/:audioFilename
 * 手动删除指定音频
 */
router.post('/delete/:audioFilename', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { audioFilename } = req.params;
    const Vocabulary = sequelize.models.Vocabulary;
    const GrammarExample = sequelize.models.GrammarExample;

    // 删除文件
    const audioType = req.body?.type || 'vocabulary'; // 从请求体获取类型
    const deleted = await audioLocalizationService.deleteLocalKokoroAudio(audioFilename, audioType);

    if (!deleted) {
      return res.status(404).json({ success: false, error: '文件不存在或无权限删除' });
    }

    // 清理数据库记录
    const audioUrl = `${Object.values(AUDIO_URL_PATTERNS)[Object.keys(AUDIO_PATHS).indexOf(audioType)] || '/uploads/audio/vocab/'}${audioFilename}`.replace('%', '');
    await Vocabulary.update(
      { audio_url: null, audio_expires_at: null },
      { where: { audio_url: audioUrl } }
    );
    await GrammarExample.update(
      { audio_url: null, audio_expires_at: null },
      { where: { audio_url: audioUrl } }
    );

    res.json({
      success: true,
      message: '已删除音频及关联数据库记录',
      filename: audioFilename
    });
  } catch (err) {
    console.error('[Kokoro] 删除音频失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
