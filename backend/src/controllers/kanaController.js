/**
 * 五十音管理控制器
 * 功能：
 * 1. 管理五十音字符数据
 * 2. 生成和管理音频
 * 3. 追踪用户学习进度
 */

const { v4: uuidv4 } = require('uuid');
const { Op } = require('sequelize');
const { sequelize } = require('../config/database');

const KanaCategory = sequelize.models.KanaCategory;
const KanaCharacter = sequelize.models.KanaCharacter;
const KanaAudio = sequelize.models.KanaAudio;
const UserKanaProgress = sequelize.models.UserKanaProgress;

/**
 * 获取所有五十音分类
 */
async function listKanaCategories(req, res) {
  try {
    if (!KanaCategory) {
      console.warn('[Kana] KanaCategory模型未初始化');
      return res.json({ success: true, data: [], message: '假名分类未初始化' });
    }

    const categories = await KanaCategory.findAll({
      order: [['order_index', 'ASC']],
      raw: true
    });

    console.log(`[Kana] 返回 ${categories.length} 个分类`);

    res.json({
      success: true,
      data: categories,
      count: categories.length
    });
  } catch (err) {
    console.error('[Kana] 获取分类失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
}

/**
 * 为所有假名生成Kokoro音频（一键生成）
 */
async function generateKanaAudioBatch(req, res) {
  try {
    const audioLocalizationService = require('../services/audioLocalizationService');
    const audioCleanupService = require('../services/audioCleanupService');
    
    if (!KanaCharacter || !KanaAudio) {
      return res.status(400).json({ success: false, error: '五十音表未初始化' });
    }
    
    const { categories = [] } = req.body;
    
    console.log('[Kana Audio] 开始一键生成五十音音频...');
    
    // 获取需要音频的假名
    let where = { is_obsolete: 0 };
    if (categories.length > 0) {
      where.category_id = { [Op.in]: categories };
    }
    
    const kanas = await KanaCharacter.findAll({
      where,
      include: [{
        model: KanaAudio,
        as: 'audios',
        where: { audio_type: 'standard' },
        required: false
      }],
      raw: false
    });
    
    // 过滤出无音频的假名
    const kanasNeedingAudio = kanas.filter(k => !k.audios || k.audios.length === 0);
    
    if (kanasNeedingAudio.length === 0) {
      return res.json({
        success: true,
        message: '所有假名都已有音频',
        generated: 0,
        total: 0
      });
    }
    
    // 构建文本列表用于批量生成
    const axios = require('axios');
    const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
    
    const texts = kanasNeedingAudio.map(k => k.hiragana).filter(t => t);
    
    try {
      console.log(`[Kana Audio] 调用Kokoro API生成 ${texts.length} 条音频...`);
      
      const timeoutMs = Math.max(30000, texts.length * 2000 + 10000);
      const resp = await axios.post(
        `${KOKORO_SERVICE_URL}/api/v1/tts/batch-generate`,
        { texts, voice: 'a', emotion: 'neutral', engine: 'edge-tts', speed: 1.0 },
        { timeout: timeoutMs }
      );
      
      const results = resp.data.results || [];
      console.log(`[Kana Audio] Kokoro返回 ${results.length} 条结果，正在下载并本地化...`);
      
      // 提取所有成功的音频URL用于下载
      const successfulAudioUrls = results
        .filter(r => r.success && r.audio_url)
        .map(r => r.audio_url);
      
      // 批量下载并本地化音频到 /uploads/audio/kana/ 目录
      const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(successfulAudioUrls, 'kana');
      const localizationMap = new Map(localizationResults.map(r => [r.originalUrl, r.localPath]));
      
      let successCount = 0;
      const now = new Date();
      const expiresAt = audioCleanupService.calculateExpirationTime(now, 30);
      
      for (let i = 0; i < kanasNeedingAudio.length && i < results.length; i++) {
        const kana = kanasNeedingAudio[i];
        const result = results[i];
        
        if (result && result.success && result.audio_url) {
          const localPath = localizationMap.get(result.audio_url);
          if (localPath) {
            try {
              await KanaAudio.create({
                id: uuidv4(),
                kana_character_id: kana.id,
                audio_type: 'standard',
                audio_url: localPath,
                audio_expires_at: expiresAt
              });
              successCount++;
            } catch (dbErr) {
              console.error(`[Kana Audio] 保存音频数据失败 [${kana.romaji}]:`, dbErr.message);
            }
          }
        }
      }
      
      res.json({
        success: true,
        message: `成功生成 ${successCount}/${texts.length} 个假名音频`,
        generated: successCount,
        total: texts.length
      });
    } catch (apiErr) {
      console.error('[Kana Audio] Kokoro API调用失败:', apiErr.message);
      
      if (apiErr.code === 'ECONNABORTED' || apiErr.message.includes('timeout')) {
        res.status(504).json({ error: '音频生成超时' });
      } else {
        res.status(503).json({ error: 'Kokoro TTS 服务不可用: ' + apiErr.message });
      }
    }
  } catch (err) {
    console.error('[Kana Audio] 批量生成失败:', err);
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
}

/**
 * 获取用户的五十音学习进度
 */
async function getUserKanaProgress(req, res) {
  try {
    if (!UserKanaProgress) {
      return res.json({
        success: true,
        data: [],
        summary: { total: 0, mastered: 0, learning: 0, avgCorrectRate: 0 }
      });
    }

    const { userId } = req.params;
    const { categoryId } = req.query;

    let where = { user_id: userId };
    if (categoryId && parseInt(categoryId)) {
      where.category_id = parseInt(categoryId);
    }

    const progress = await UserKanaProgress.findAll({
      where,
      order: [['updated_at', 'DESC']],
      include: [{
        model: KanaCharacter,
        as: 'character',
        attributes: ['id', 'hiragana', 'katakana', 'romaji', 'stroke_count']
      }],
      raw: false
    });

    if (!progress || progress.length === 0) {
      return res.json({
        success: true,
        data: [],
        summary: {
          total: 0,
          mastered: 0,
          learning: 0,
          avgCorrectRate: 0,
          message: '暂无学习记录，请开始学习'
        }
      });
    }

    const masteredCount = progress.filter(p => p.is_mastered).length;
    const totalCount = progress.length;
    const avgCorrectRate = totalCount > 0
      ? (progress.reduce((sum, p) => sum + (p.correct_rate || 0), 0) / totalCount * 100).toFixed(1)
      : 0;

    res.json({
      success: true,
      data: progress,
      summary: {
        total: totalCount,
        mastered: masteredCount,
        learning: totalCount - masteredCount,
        avgCorrectRate: parseFloat(avgCorrectRate),
        masteryPercentage: ((masteredCount / totalCount) * 100).toFixed(1)
      }
    });
  } catch (err) {
    console.error('[Kana] 获取进度失败:', err);
    res.status(500).json({ success: false, error: err.message });
  }
}

module.exports = {
  listKanaCategories,
  generateKanaAudioBatch,
  getUserKanaProgress
};
