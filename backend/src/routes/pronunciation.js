const router = require('express').Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');

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

// ── POST /recording  上传发音录音 ──
router.post('/recording', authenticate, upload.single('audio'), asyncHandler(async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '未收到音频文件' });
  }

  const { word, reading, score } = req.body;
  const audioUrl = `/uploads/recordings/${req.file.filename}`;

  // 用 JSON 文件记录元数据（轻量方案，无需新增数据库表）
  const metaDir = path.join(uploadDir, 'meta');
  if (!fs.existsSync(metaDir)) fs.mkdirSync(metaDir, { recursive: true });

  const record = {
    id: uuidv4(),
    user_id: req.user.id,
    word: word || '',
    reading: reading || '',
    score: score ? parseFloat(score) : null,
    audio_url: audioUrl,
    filename: req.file.filename,
    created_at: new Date().toISOString(),
  };

  // 每个用户一个 JSON 文件
  const userFile = path.join(metaDir, `${req.user.id}.json`);
  let records = [];
  if (fs.existsSync(userFile)) {
    try { records = JSON.parse(fs.readFileSync(userFile, 'utf8')); } catch (_) { records = []; }
  }
  records.push(record);

  // 只保留最近 200 条
  if (records.length > 200) {
    const removed = records.splice(0, records.length - 200);
    // 删除旧音频文件
    for (const r of removed) {
      const old = path.join(uploadDir, r.filename);
      if (fs.existsSync(old)) fs.unlinkSync(old);
    }
  }

  fs.writeFileSync(userFile, JSON.stringify(records, null, 2));

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
