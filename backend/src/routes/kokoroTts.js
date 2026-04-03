// Kokoro TTS 服务端 API 路由（不需要认证的公开端点）
const express = require('express');
const router = express.Router();
const axios = require('axios');
const { authenticate } = require('../middlewares/auth');

// Kokoro Python 服务地址（与Node后端部署在同一服务器）
const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://localhost:8010';

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
  const { text, voice, emotion, speed } = req.body;
  
  // 基本参数验证
  if (!text || text.trim().length === 0) {
    return res.status(400).json({ error: '文本不能为空' });
  }
  
  try {
    // 代理到 Python Kokoro 服务
    const resp = await axios.post(
      `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
      {
        text: text.trim(),
        voice: voice || 'a',
        emotion: emotion || 'neutral',
        speed: Math.min(Math.max(parseFloat(speed) || 1.0, 0.5), 2.0),
      },
      { timeout: 30000 }  // 合成可能需要较长时间
    );
    
    // 返回 Kokoro 服务的响应
    // 重要：返回可从APP访问的完整URL，而不是localhost
    const publicAudioUrl = process.env.KOKORO_PUBLIC_URL 
      ? `${process.env.KOKORO_PUBLIC_URL}${resp.data.audio_url}`
      : `${KOKORO_SERVICE_URL}${resp.data.audio_url}`.replace('localhost:8010', '139.196.44.6:8010');
    
    res.json({
      audio_url: publicAudioUrl,
      voice: resp.data.voice,
      emotion: resp.data.emotion,
    });
    
    console.log(`TTS合成成功: text_len=${text.trim().length}, voice=${voice}, url=${publicAudioUrl}`);
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
