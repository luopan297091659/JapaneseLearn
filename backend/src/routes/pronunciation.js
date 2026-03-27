const router = require('express').Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const { checkMembership } = require('../middlewares/membership');
const { callAI } = require('../controllers/aiController');

// ── 上传目录 ──
const uploadDir = path.join(__dirname, '../../uploads/recordings');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

// ── Multer 配置 ──
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname) || '.webm';
    cb(null, `${uuidv4()}${ext}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (_req, file, cb) => {
    const allowed = ['.webm', '.m4a', '.mp3', '.wav', '.ogg', '.mp4', '.aac'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowed.includes(ext)) return cb(null, true);
    cb(new Error('不支持的音频格式'));
  },
});

function saveUserRecordingMeta(userId, record) {
  const metaDir = path.join(uploadDir, 'meta');
  if (!fs.existsSync(metaDir)) fs.mkdirSync(metaDir, { recursive: true });

  const userFile = path.join(metaDir, `${userId}.json`);
  let records = [];
  if (fs.existsSync(userFile)) {
    try { records = JSON.parse(fs.readFileSync(userFile, 'utf8')); } catch (_) { records = []; }
  }
  records.push(record);

  if (records.length > 200) {
    const removed = records.splice(0, records.length - 200);
    for (const r of removed) {
      const old = path.join(uploadDir, r.filename);
      if (fs.existsSync(old)) fs.unlinkSync(old);
    }
  }

  fs.writeFileSync(userFile, JSON.stringify(records, null, 2));
}

function calcFallbackScore(target, recognized) {
  if (!target || !recognized) return 0;
  const a = Array.from(String(target).trim());
  const b = Array.from(String(recognized).trim());
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 0;
  let matches = 0;
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i += 1) {
    if (a[i] === b[i]) matches += 1;
  }
  return Math.round((matches / maxLen) * 100);
}

function parseAiJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(String(text).trim());
  } catch (_) {
    // ignore
  }
  const fence = String(text).match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence && fence[1]) {
    try {
      return JSON.parse(fence[1].trim());
    } catch (_) {
      // ignore
    }
  }
  const first = String(text).indexOf('{');
  const last = String(text).lastIndexOf('}');
  if (first >= 0 && last > first) {
    try {
      return JSON.parse(String(text).slice(first, last + 1));
    } catch (_) {
      return null;
    }
  }
  return null;
}

// ── POST /score  AI 文本评分（供发音/听力录音后调用）──
router.post('/score', authenticate, asyncHandler(async (req, res) => {
  const targetText = String(req.body?.target_text || '').trim();
  const recognizedText = String(req.body?.recognized_text || '').trim();
  const referenceReading = String(req.body?.reference_reading || '').trim();
  const mode = String(req.body?.mode || 'pronunciation').trim();

  if (!targetText || !recognizedText) {
    return res.status(400).json({ error: '缺少 target_text 或 recognized_text' });
  }

  const fallbackBase = calcFallbackScore(targetText, recognizedText);
  const fallbackAlt = referenceReading ? calcFallbackScore(referenceReading, recognizedText) : 0;
  const fallbackScore = Math.max(fallbackBase, fallbackAlt);

  const fallbackFeedback = fallbackScore >= 90
    ? '发音非常准确，继续保持。'
    : fallbackScore >= 75
      ? '整体不错，注意少量音节的清晰度。'
      : fallbackScore >= 55
        ? '有进步空间，建议放慢语速并重复练习。'
        : '与目标差异较大，建议先听原音再跟读。';

  try {
    const prompt = `你是日语口语评分助手。请根据“目标文本”和“识别文本”给出0-100分评分，并输出简短中文反馈（不超过50字）。\n\n`
      + `模式: ${mode}\n`
      + `目标文本: ${targetText}\n`
      + `目标读音(可选): ${referenceReading || '无'}\n`
      + `识别文本: ${recognizedText}\n\n`
      + '仅返回 JSON：{"score": number, "feedback": "string"}';

    const aiText = await callAI(prompt, 300);
    const parsed = parseAiJson(aiText);
    const rawScore = Number(parsed?.score);
    const safeScore = Number.isFinite(rawScore)
      ? Math.max(0, Math.min(100, Math.round(rawScore)))
      : fallbackScore;
    const feedback = String(parsed?.feedback || fallbackFeedback).trim() || fallbackFeedback;

    return res.json({ success: true, source: 'ai', score: safeScore, feedback });
  } catch (_) {
    return res.json({
      success: true,
      source: 'fallback',
      score: fallbackScore,
      feedback: fallbackFeedback,
    });
  }
}));

// ── POST /recording  上传发音录音 ──
router.post('/recording', authenticate, checkMembership('pronunciation'), upload.single('audio'), asyncHandler(async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '未收到音频文件' });
  }

  const { word, reading, score } = req.body;
  const audioUrl = `/uploads/recordings/${req.file.filename}`;

  const record = {
    id: uuidv4(),
    user_id: req.user.id,
    mode: 'pronunciation',
    word: word || '',
    reading: reading || '',
    score: score ? parseFloat(score) : null,
    audio_url: audioUrl,
    filename: req.file.filename,
    created_at: new Date().toISOString(),
  };

  saveUserRecordingMeta(req.user.id, record);

  res.json({ success: true, recording: record });
}));

// ── POST /listening-recording  上传听力学习录音（免费可用）──
router.post('/listening-recording', authenticate, upload.single('audio'), asyncHandler(async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '未收到音频文件' });
  }

  const { sentence, reading, score } = req.body;
  const audioUrl = `/uploads/recordings/${req.file.filename}`;

  const record = {
    id: uuidv4(),
    user_id: req.user.id,
    mode: 'listening',
    word: sentence || '',
    reading: reading || '',
    score: score ? parseFloat(score) : null,
    audio_url: audioUrl,
    filename: req.file.filename,
    created_at: new Date().toISOString(),
  };

  saveUserRecordingMeta(req.user.id, record);

  res.json({ success: true, recording: record });
}));

// ── GET /recordings  获取用户录音列表 ──
router.get('/recordings', authenticate, asyncHandler(async (req, res) => {
  const userFile = path.join(uploadDir, 'meta', `${req.user.id}.json`);
  let records = [];
  if (fs.existsSync(userFile)) {
    try { records = JSON.parse(fs.readFileSync(userFile, 'utf8')); } catch (_) { records = []; }
  }
  // 最新的在前
  records.reverse();
  res.json({ recordings: records });
}));

// ── DELETE /recording/:id  删除录音 ──
router.delete('/recording/:id', authenticate, asyncHandler(async (req, res) => {
  const userFile = path.join(uploadDir, 'meta', `${req.user.id}.json`);
  if (!fs.existsSync(userFile)) {
    return res.status(404).json({ error: '录音不存在' });
  }

  let records = [];
  try { records = JSON.parse(fs.readFileSync(userFile, 'utf8')); } catch (_) { records = []; }

  const idx = records.findIndex(r => r.id === req.params.id);
  if (idx === -1) {
    return res.status(404).json({ error: '录音不存在' });
  }

  // 删除音频文件
  const audioFile = path.join(uploadDir, records[idx].filename);
  if (fs.existsSync(audioFile)) fs.unlinkSync(audioFile);

  records.splice(idx, 1);
  fs.writeFileSync(userFile, JSON.stringify(records, null, 2));

  res.json({ success: true });
}));

module.exports = router;
