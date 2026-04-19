// Kokoro TTS 服务端 API 路由（不需要认证的公开端点）
const express = require('express');
const router = express.Router();
const axios = require('axios');
const { authenticate } = require('../middlewares/auth');
const { sequelize } = require('../config/database');

// Kokoro Python 服务地址（与Node后端部署在同一服务器）
const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';

// ─── 公开端点：获取可用人声列表 ────────────────────────────────────────
router.get('/voices', async (req, res) => {
  try {
    const resp = await axios.get(`${KOKORO_SERVICE_URL}/api/v1/tts/voices`, {
      timeout: 5000,
    });
    res.json(resp.data);
  } catch (error) {
    console.error('获取Kokoro人声列表失败:', error.message);
    res.status(503).json({ error: 'Kokoro service unavailable' });
  }
});

// ─── 公开端点：Kokoro TTS 合成（客户端直接调用） ────────────────────────
router.post('/kokoro-speak', async (req, res) => {
  const { text, voice, emotion, engine, speed } = req.body;
  
  // 基本参数验证
  if (!text || text.trim().length === 0) {
    return res.status(400).json({ error: '文本不能为空' });
  }
  
  try {
    // 获取管理员配置的默认参数
    let defaultVoice = 'a';
    let defaultEmotion = 'neutral';
    let defaultEngine = 'edge-tts';
    let defaultSpeed = 1.0;
    
    try {
      const kv = await sequelize.models.AppConfig?.findOne({
        where: { key: 'kokoro_tts_settings' }
      });
      if (kv && kv.value) {
        const kokoroConfig = JSON.parse(kv.value);
        defaultVoice = kokoroConfig.default_voice || 'a';
        defaultEmotion = kokoroConfig.default_emotion || 'neutral';
        defaultEngine = kokoroConfig.default_engine || 'edge-tts';
        defaultSpeed = kokoroConfig.default_speed || 1.0;
      }
    } catch (_) {}
    
    // 代理到 Python Kokoro 服务
    const resp = await axios.post(
      `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
      {
        text: text.trim(),
        voice: voice || defaultVoice,
        emotion: emotion || defaultEmotion,
        engine: engine || defaultEngine,
        speed: Math.min(Math.max(parseFloat(speed) || defaultSpeed, 0.5), 2.0),
      },
      { timeout: 30000 }  // 合成可能需要较长时间
    );
    
    // 返回 Kokoro 服务的响应
    // 重要：返回相对路径，让APP通过8002的代理来访问，而不是直接访问8010
    // APP侧会根据kokoroTtsUrl的基地址自动拼接为：https://139.196.44.6:8002/api/v1/tts/kokoro/audio/xxx.wav
    res.json({
      audio_url: resp.data.audio_url,  // 返回相对路径：/api/v1/tts/kokoro/audio/{filename}
      voice: resp.data.voice,
      emotion: resp.data.emotion,
    });
    
    console.log(`TTS合成成功: text_len=${text.trim().length}, voice=${voice || defaultVoice}, emotion=${emotion || defaultEmotion}, engine=${engine || defaultEngine}, speed=${speed || defaultSpeed}`);
  } catch (error) {
    console.error('Kokoro TTS 合成失败:', error.message);
    
    // 根据错误类型返回不同的状态码
    if (error.code === 'ECONNREFUSED') {
      res.status(503).json({ error: 'Kokoro service not available', code: 'KOKORO_UNAVAILABLE' });
    } else if (error.response?.status) {
      res.status(error.response.status).json(error.response.data);
    } else {
      res.status(500).json({ error: 'TTS synthesis failed' });
    }
  }
});

// ─── 公开端点：代理获取Kokoro音频文件 ────────────────────────────────────────
// APP通过8002访问音频，而不是直接访问8010
// 路径：/api/v1/tts/kokoro/audio/{filename} → 代理到 8010:/api/v1/tts/kokoro/audio/{filename}
router.get('/kokoro/audio/:filename', async (req, res) => {
  const { filename } = req.params;
  
  // 安全检查：防止路径遍历攻击，支持 .wav 和 .mp3
  if (!filename.match(/^kokoro_[a-f0-9]{32}\.(wav|mp3)$/)) {
    return res.status(400).json({ error: 'Invalid audio filename format' });
  }
  
  try {
    const audioResponse = await axios.get(
      `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro/audio/${filename}`,
      { responseType: 'arraybuffer', timeout: 5000 }
    );
    
    const contentType = filename.endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav';
    res.set('Content-Type', contentType);
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(audioResponse.data);
    
    console.log(`音频代理成功: ${filename}`);
  } catch (error) {
    console.error(`音频代理失败 [${filename}]:`, error.message);
    if (error.response?.status === 404) {
      res.status(404).json({ error: 'Audio file not found' });
    } else {
      res.status(503).json({ error: 'Failed to retrieve audio from Kokoro service' });
    }
  }
});

// ─── 管理员端点：批量生成Kokoro音频 ─────────────────────────────────────
// 用途：为语法例句、单词例句等批量生成音频
// 请求体: { texts: ['文本1', '文本2', ...], voice: 'a', emotion: 'neutral', engine: 'edge-tts', speed: 1.0 }
// 响应: { results: [{text, audio_url, success, error}, ...], failed: 0, success: 0, total: 0 }
router.post('/batch-generate', authenticate, async (req, res) => {
  const { texts, voice, emotion, engine, speed } = req.body;
  
  // 参数验证
  if (!Array.isArray(texts) || texts.length === 0) {
    return res.status(400).json({ error: 'texts must be non-empty array' });
  }
  
  if (texts.length > 100) {
    return res.status(400).json({ error: 'texts array too large (max 100)' });
  }
  
  // 获取默认配置
  let defaultVoice = 'a';
  let defaultEmotion = 'neutral';
  let defaultEngine = 'edge-tts';
  let defaultSpeed = 1.0;
  
  try {
    const kv = await sequelize.models.AppConfig?.findOne({
      where: { key: 'kokoro_tts_settings' }
    });
    if (kv && kv.value) {
      const config = JSON.parse(kv.value);
      defaultVoice = config.default_voice || 'a';
      defaultEmotion = config.default_emotion || 'neutral';
      defaultEngine = config.default_engine || 'edge-tts';
      defaultSpeed = config.default_speed || 1.0;
    }
  } catch (_) {}
  
  const results = [];
  let successCount = 0;
  let failCount = 0;
  
  // 串行处理 - 避免并发过多导致服务过载
  for (let i = 0; i < texts.length; i++) {
    const text = texts[i];
    if (!text || text.trim().length === 0) {
      results.push({
        index: i,
        text: text,
        audio_url: null,
        success: false,
        error: 'Empty text'
      });
      failCount++;
      continue;
    }
    
    try {
      const resp = await axios.post(
        `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
        {
          text: text.trim(),
          voice: voice || defaultVoice,
          emotion: emotion || defaultEmotion,
          engine: engine || defaultEngine,
          speed: Math.min(Math.max(parseFloat(speed) || defaultSpeed, 0.5), 2.0),
        },
        { timeout: 30000 }
      );
      
      results.push({
        index: i,
        text: text,
        audio_url: resp.data.audio_url,
        success: true,
        error: null
      });
      successCount++;
      
      // 避免过于频繁的请求 - 短暂延迟
      if (i < texts.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    } catch (error) {
      console.error(`[KokoroAudio] Batch generation failed for text ${i}:`, error.message);
      results.push({
        index: i,
        text: text,
        audio_url: null,
        success: false,
        error: error.message || 'TTS synthesis failed'
      });
      failCount++;
    }
  }
  
  res.json({
    success: failCount === 0,
    results,
    summary: {
      total: texts.length,
      success: successCount,
      failed: failCount
    }
  });
});

// ─── 公开端点：健康检查 ────────────────────────────────────────
router.get('/health', async (req, res) => {
  try {
    const resp = await axios.get(`${KOKORO_SERVICE_URL}/health`, { timeout: 3000 });
    res.json({
      status: 'ok',
      kokoro: resp.data,
    });
  } catch (error) {
    res.status(503).json({
      status: 'error',
      kokoro_available: false,
      error: error.message,
    });
  }
});

module.exports = router;
