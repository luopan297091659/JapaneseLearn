/**
 * 音频管理服务
 * 支持音频上传、生成URL、删除等操作
 */
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');

// 音频上传目录
const AUDIO_DIR = path.join(__dirname, '../../uploads/audio');
if (!fs.existsSync(AUDIO_DIR)) {
  fs.mkdirSync(AUDIO_DIR, { recursive: true });
}

// 音频存储配置
const audioStorage = multer.diskStorage({
  destination: (_req, _file, cb) => {
    cb(null, AUDIO_DIR);
  },
  filename: (_req, file, cb) => {
    const ext = path.extname(file.originalname);
    const filename = `${uuidv4()}${ext}`;
    cb(null, filename);
  },
});

const audioUpload = multer({
  storage: audioStorage,
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB per file
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    const allowedExts = ['.mp3', '.wav', '.m4a', '.aac', '.flac'];
    if (allowedExts.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error(`不支持的音频格式: ${ext}`));
    }
  },
});

/**
 * 获取音频URL
 * @param {string} filename - 文件名
 * @returns {string} - 完整的音频URL
 */
function getAudioUrl(filename) {
  if (!filename) return null;
  return `/audio/${filename}`;
}

/**
 * 删除音频文件
 * @param {string} filename - 文件名
 */
function deleteAudioFile(filename) {
  if (!filename) return;
  const filePath = path.join(AUDIO_DIR, filename);
  try {
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
  } catch (err) {
    console.error(`删除音频文件失败: ${filename}`, err);
  }
}

/**
 * 提取文件名从URL
 * @param {string} url - 音频URL
 * @returns {string} - 文件名
 */
function extractFilenameFromUrl(url) {
  if (!url) return null;
  if (url.startsWith('/audio/')) {
    return url.slice('/audio/'.length);
  }
  return url;
}

module.exports = {
  audioUpload,
  AUDIO_DIR,
  getAudioUrl,
  deleteAudioFile,
  extractFilenameFromUrl,
};
