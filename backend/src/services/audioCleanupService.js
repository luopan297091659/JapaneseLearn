/**
 * Kokoro 音频清理服务
 * 功能：
 * 1. 定时清理过期音频
 * 2. 清理孤立音频（数据库记录已删除）
 * 3. 统计磁盘使用量
 * 4. 实现智能缓存管理
 */

const path = require('path');
const fs = require('fs').promises;
const { Op } = require('sequelize');
const { sequelize } = require('../config/database');
const audioLocalizationService = require('./audioLocalizationService');

const AUDIO_TTL_DAYS = parseInt(process.env.KOKORO_AUDIO_TTL_DAYS || '30', 10);
const CLEANUP_CHECK_INTERVAL = parseInt(process.env.CLEANUP_CHECK_INTERVAL || '21600000', 10); // 6小时
const MAX_AUDIO_STORAGE_GB = parseFloat(process.env.MAX_AUDIO_STORAGE_GB || '10');

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

let cleanupIntervalId = null;
let isCleanupRunning = false;

/**
 * 计算音频过期时间
 */
function calculateExpirationTime(createdAt, ttlDays = AUDIO_TTL_DAYS) {
  const expiresAt = new Date(createdAt);
  expiresAt.setDate(expiresAt.getDate() + ttlDays);
  return expiresAt;
}

/**
 * 执行清理过期音频
 */
async function cleanupExpiredAudio() {
  try {
    const Vocabulary = sequelize.models.Vocabulary;
    const GrammarExample = sequelize.models.GrammarExample;
    const KanaAudio = sequelize.models.KanaAudio;
    
    if (!Vocabulary || !GrammarExample) return 0;

    const now = new Date();
    let totalDeleted = 0;

    // 清理过期的词汇音频 (vocabulary path)
    const expiredVocab = await Vocabulary.findAll({
      where: {
        audio_expires_at: { [Op.lt]: now },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.vocabulary }
      },
      attributes: ['id', 'audio_url'],
      raw: true
    });

    for (const vocab of expiredVocab) {
      if (vocab.audio_url) {
        const filename = path.basename(vocab.audio_url);
        await audioLocalizationService.deleteLocalKokoroAudio(filename, 'vocabulary');
        await Vocabulary.update(
          { audio_url: null, audio_expires_at: null },
          { where: { id: vocab.id } }
        );
        totalDeleted++;
      }
    }

    // 清理过期的语法音频 (grammar path)
    const expiredGrammar = await GrammarExample.findAll({
      where: {
        audio_expires_at: { [Op.lt]: now },
        audio_url: { [Op.like]: AUDIO_URL_PATTERNS.grammar }
      },
      attributes: ['id', 'audio_url'],
      raw: true
    });

    for (const grammar of expiredGrammar) {
      if (grammar.audio_url) {
        const filename = path.basename(grammar.audio_url);
        await audioLocalizationService.deleteLocalKokoroAudio(filename, 'grammar');
        await GrammarExample.update(
          { audio_url: null, audio_expires_at: null },
          { where: { id: grammar.id } }
        );
        totalDeleted++;
      }
    }

    // 清理过期的假名音频 (kana path)
    if (KanaAudio) {
      const expiredKana = await KanaAudio.findAll({
        where: {
          audio_expires_at: { [Op.lt]: now },
          audio_url: { [Op.like]: AUDIO_URL_PATTERNS.kana }
        },
        attributes: ['id', 'audio_url'],
        raw: true
      });

      for (const kana of expiredKana) {
        if (kana.audio_url) {
          const filename = path.basename(kana.audio_url);
          await audioLocalizationService.deleteLocalKokoroAudio(filename, 'kana');
        }
      }
    }

    return totalDeleted;
  } catch (err) {
    console.error('[Cleanup] 清理过期音频失败:', err.message);
    return 0;
  }
}

/**
 * 执行一次完整的清理任务
 */
async function executeCleanup() {
  if (isCleanupRunning) {
    console.log('[Cleanup] 清理任务已在运行中，跳过本次执行');
    return;
  }

  isCleanupRunning = true;
  const startTime = Date.now();

  try {
    console.log(`[Cleanup] 开始清理任务 - ${new Date().toISOString()}`);

    const expiredCount = await cleanupExpiredAudio();
    const orphanedCount = await audioLocalizationService.cleanupOldFiles(AUDIO_TTL_DAYS * 24 * 60 * 60 * 1000);
    const totalSize = await audioLocalizationService.getTotalStorageSize();
    const sizeGB = (totalSize / (1024 * 1024 * 1024)).toFixed(2);

    const duration = Date.now() - startTime;
    console.log(`[Cleanup] 清理完成 - 过期: ${expiredCount}, 孤立: ${orphanedCount}, 总大小: ${sizeGB}GB, 耗时: ${duration}ms`);

    // 检查磁盘使用量是否超限
    if (parseFloat(sizeGB) > MAX_AUDIO_STORAGE_GB) {
      console.warn(`[Cleanup] ⚠️ 磁盘使用量超限: ${sizeGB}GB > ${MAX_AUDIO_STORAGE_GB}GB`);
    }
  } catch (err) {
    console.error('[Cleanup] 清理任务失败:', err);
  } finally {
    isCleanupRunning = false;
  }
}

/**
 * 启动定时清理任务
 */
function startCleanupSchedule() {
  if (cleanupIntervalId) {
    console.log('[Cleanup] 定时清理任务已运行');
    return;
  }

  // 立即执行一次
  executeCleanup().catch(err => console.error('[Cleanup] 初始清理失败:', err));

  // 设置定时任务
  cleanupIntervalId = setInterval(() => {
    executeCleanup().catch(err => console.error('[Cleanup] 定时清理失败:', err));
  }, CLEANUP_CHECK_INTERVAL);

  const intervalMinutes = (CLEANUP_CHECK_INTERVAL / 1000 / 60).toFixed(1);
  console.log(`[Cleanup] ✓ 已启动定时清理任务，检查间隔: ${intervalMinutes} 分钟`);
}

/**
 * 停止定时清理任务
 */
function stopCleanupSchedule() {
  if (cleanupIntervalId) {
    clearInterval(cleanupIntervalId);
    cleanupIntervalId = null;
    console.log('[Cleanup] 定时清理任务已停止');
  }
}

module.exports = {
  calculateExpirationTime,
  startCleanupSchedule,
  stopCleanupSchedule,
  executeCleanup,
  cleanupExpiredAudio
};
