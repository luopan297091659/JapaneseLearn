const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const multer = require('multer');
const path = require('path');
const { adminAuth, superAdminAuth, permissionCheck } = require('../middlewares/adminAuth');
const { audioUpload } = require('../services/audioService');
const {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab, generateVocabExamplesKokoroAudio, deduplicateVocab, fixVocabReadings,
  importVocab, importVocabFile,
  listGrammar, getGrammar, createGrammar, updateGrammar, deleteGrammar, bulkDeleteGrammar, generateGrammarExamplesKokoroAudio, importGrammarApkg, generateGrammarExampleAudio,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser, updateUserMembership, resetUserPassword,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats, getFeatureUsage,
  listKana, batchGenerateKanaAudio, getKanaList, getKanaById, createKanaItem, updateKanaItem, deleteKanaItem, bulkDeleteKanaItems,  // ✅ 五十音CRUD
  getMembershipConfig, saveMembershipConfig,
  getFeatureToggles, saveFeatureToggles,
  getFeatureTiers, saveFeatureTiers,
  uploadApp, listAppReleases, publishAppRelease, getLatestAppRelease, downloadApp, deleteAppRelease,
  getAiSettings, saveAiSettings, getAiUsage, resetAiUsage,
  getKokoroSettings, saveKokoroSettings,
  listAdmins, updateAdminPermissions, getAdminInfo,
  listReports, getReport, updateReport, deleteReport,
  getStudyPlanStats,
  generateSingleAudio,
  listOrders, reviewOrder, uploadQrCode,
  getEmailSettings, saveEmailSettings, testEmailSettings,
} = require('../controllers/adminController');
const {
  adminListChannels, adminCreateChannel, adminUpdateChannel, adminDeleteChannel, adminRefreshChannel,
} = require('../controllers/listeningChannelController');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 50 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (['.txt', '.csv', '.tsv'].includes(ext)) return cb(null, true);
    cb(new Error('仅支持 .txt / .csv / .tsv 格式'));
  },
});

const fs = require('fs');
const appUploadDir = path.join(__dirname, '../../uploads/app');
if (!fs.existsSync(appUploadDir)) fs.mkdirSync(appUploadDir, { recursive: true });

const appUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, appUploadDir),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname);
      cb(null, `app_${Date.now()}${ext}`);
    },
  }),
  limits: { fileSize: 500 * 1024 * 1024 }, // 500MB
});

// apkg 文件上传（Anki 导出包）
const imageUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (file.mimetype.startsWith('image/')) return cb(null, true);
    cb(new Error('仅支持图片格式'));
  },
});

const apkgUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 200 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ext === '.apkg') return cb(null, true);
    cb(new Error('仅支持 .apkg 格式'));
  },
});

// ── App 下载（公开，不需要 adminAuth）──
router.get('/downloadApp/:id', asyncHandler(downloadApp));
router.get('/app/latest', asyncHandler(getLatestAppRelease));

// 所有 admin 路由都需要管理员身份
router.use(adminAuth);

// 管理员信息（返回当前管理员权限等级和权限列表）
router.get('/admin-info', asyncHandler(getAdminInfo));

// 仪表板
router.get('/dashboard', asyncHandler(getDashboard));

// ── 统计分析（支持 ?grain=day|month|year&start=YYYY-MM-DD&end=YYYY-MM-DD）──
router.get('/stats/traffic',  permissionCheck('stats'), asyncHandler(getTrafficStats));
router.get('/stats/users',    permissionCheck('stats'), asyncHandler(getUserStats));
router.get('/stats/behavior', permissionCheck('stats'), asyncHandler(getBehaviorStats));
router.get('/stats/feature-usage', permissionCheck('stats'), asyncHandler(getFeatureUsage));

// 词汇管理
router.get('/vocabulary',              permissionCheck('vocabulary'), asyncHandler(listVocab));
router.post('/vocabulary',             permissionCheck('vocabulary'), asyncHandler(createVocab));
router.put('/vocabulary/:id',          permissionCheck('vocabulary'), asyncHandler(updateVocab));
router.delete('/vocabulary/:id',       permissionCheck('vocabulary'), asyncHandler(deleteVocab));
router.post('/vocabulary/bulk-delete', permissionCheck('vocabulary'), asyncHandler(bulkDeleteVocab));
router.post('/vocabulary/generate-kokoro-audio', permissionCheck('vocabulary'), asyncHandler(generateVocabExamplesKokoroAudio));
router.post('/vocabulary/deduplicate', permissionCheck('vocabulary'), asyncHandler(deduplicateVocab));
router.post('/vocabulary/fix-readings', permissionCheck('vocabulary'), asyncHandler(fixVocabReadings));
router.post('/vocabulary/import',      permissionCheck('vocabulary'), asyncHandler(importVocab));
router.post('/vocabulary/import-file', permissionCheck('vocabulary'), upload.single('file'), asyncHandler(importVocabFile));

// 音频管理
router.post('/audio/upload', permissionCheck('vocabulary'), audioUpload.single('audio'), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: '未找到音频文件' });
  }
  const audioUrl = `/audio/${req.file.filename}`;
  res.json({ filename: req.file.filename, url: audioUrl, size: req.file.size });
});

// 语法管理
router.get('/grammar',        permissionCheck('grammar'), asyncHandler(listGrammar));
router.get('/grammar/:id',    permissionCheck('grammar'), asyncHandler(getGrammar));
router.post('/grammar',       permissionCheck('grammar'), asyncHandler(createGrammar));
router.put('/grammar/:id',    permissionCheck('grammar'), asyncHandler(updateGrammar));
router.delete('/grammar/:id', permissionCheck('grammar'), asyncHandler(deleteGrammar));
router.post('/grammar/bulk-delete', permissionCheck('grammar'), asyncHandler(bulkDeleteGrammar));
router.post('/grammar/generate-kokoro-audio', permissionCheck('grammar'), asyncHandler(generateGrammarExamplesKokoroAudio));
router.post('/grammar/import-apkg', permissionCheck('grammar'), apkgUpload.single('file'), asyncHandler(importGrammarApkg));
router.post('/grammar/:lessonId/examples/:exId/generate-audio', permissionCheck('grammar'), asyncHandler(generateGrammarExampleAudio));

// 听力管理
router.get('/tracks',        permissionCheck('tracks'), asyncHandler(listTracks));
router.post('/tracks',       permissionCheck('tracks'), asyncHandler(createTrack));
router.put('/tracks/:id',    permissionCheck('tracks'), asyncHandler(updateTrack));
router.delete('/tracks/:id', permissionCheck('tracks'), asyncHandler(deleteTrack));

// 用户管理
router.get('/users',       permissionCheck('users'), asyncHandler(listUsers));
router.put('/users/:id',   permissionCheck('users'), asyncHandler(updateUser));
router.put('/users/:id/membership', permissionCheck('users'), asyncHandler(updateUserMembership));
router.put('/users/:id/password', superAdminAuth, asyncHandler(resetUserPassword));

// 内容版本
router.get('/content-version',         asyncHandler(getContentVersion));
router.post('/content-version/publish', permissionCheck('sync'), asyncHandler(publishContent));

// 会员套餐配置（仅高级管理员）
router.get('/membership',  permissionCheck('membership'), asyncHandler(getMembershipConfig));
router.post('/membership', superAdminAuth, asyncHandler(saveMembershipConfig));

// 订单管理
router.get('/orders', permissionCheck('membership'), asyncHandler(listOrders));
router.put('/orders/:id/review', permissionCheck('membership'), asyncHandler(reviewOrder));
router.post('/qrcode/upload', superAdminAuth, imageUpload.single('qrcode'), asyncHandler(uploadQrCode));

// 功能开关配置（仅高级管理员）
router.get('/feature-toggles',  superAdminAuth, asyncHandler(getFeatureToggles));
router.post('/feature-toggles', superAdminAuth, asyncHandler(saveFeatureToggles));

// 功能分级配置（仅高级管理员）
router.get('/feature-tiers',  superAdminAuth, asyncHandler(getFeatureTiers));
router.post('/feature-tiers', superAdminAuth, asyncHandler(saveFeatureTiers));

// App 管理（仅高级管理员）
router.post('/uploadApp', superAdminAuth, appUpload.single('file'), asyncHandler(uploadApp));
router.get('/listAppReleases', superAdminAuth, asyncHandler(listAppReleases));
router.post('/app/:id/publish', superAdminAuth, asyncHandler(publishAppRelease));
router.delete('/app/:id', superAdminAuth, asyncHandler(deleteAppRelease));

// AI 设置（仅高级管理员）
router.get('/ai-settings',       superAdminAuth, asyncHandler(getAiSettings));
router.post('/ai-settings',      superAdminAuth, asyncHandler(saveAiSettings));
router.get('/ai-usage',          superAdminAuth, asyncHandler(getAiUsage));
router.post('/ai-usage/reset',   superAdminAuth, asyncHandler(resetAiUsage));

// 频道管理（磨耳朵）
router.get('/channels',           permissionCheck('tracks'), asyncHandler(adminListChannels));
router.post('/channels',          permissionCheck('tracks'), asyncHandler(adminCreateChannel));
router.put('/channels/:id',       permissionCheck('tracks'), asyncHandler(adminUpdateChannel));
router.delete('/channels/:id',    permissionCheck('tracks'), asyncHandler(adminDeleteChannel));
router.post('/channels/:id/refresh', permissionCheck('tracks'), asyncHandler(adminRefreshChannel));

// 管理员权限管理（仅高级管理员）
router.get('/admins',             superAdminAuth, asyncHandler(listAdmins));
router.put('/admins/:id/permissions', superAdminAuth, asyncHandler(updateAdminPermissions));

// 用户报错管理
router.get('/reports',        permissionCheck('reports'), asyncHandler(listReports));
router.get('/reports/:id',    permissionCheck('reports'), asyncHandler(getReport));
router.put('/reports/:id',    permissionCheck('reports'), asyncHandler(updateReport));
router.delete('/reports/:id', permissionCheck('reports'), asyncHandler(deleteReport));

// 学习计划管理
router.get('/study-plan/stats', permissionCheck('stats'), asyncHandler(getStudyPlanStats));

// Kokoro TTS 配置管理
router.get('/settings/kokoro',  adminAuth, asyncHandler(getKokoroSettings));
router.post('/settings/kokoro', permissionCheck('settings'), asyncHandler(saveKokoroSettings));

// 邮件 SMTP 配置管理
router.get('/settings/email',       superAdminAuth, asyncHandler(getEmailSettings));
router.post('/settings/email',      superAdminAuth, asyncHandler(saveEmailSettings));
router.post('/settings/email/test', superAdminAuth, asyncHandler(testEmailSettings));

// 五十音管理 - 具体路由必须在参数化路由之前
router.post('/kana/batch-audio',         permissionCheck('vocabulary'), asyncHandler(batchGenerateKanaAudio));

// 通用单条TTS生成（持久化）
router.post('/tts/generate-single',      permissionCheck('vocabulary'), asyncHandler(generateSingleAudio));
router.post('/kana/bulk-delete',         permissionCheck('vocabulary'), asyncHandler(bulkDeleteKanaItems));
router.get('/kana',                      permissionCheck('vocabulary'), asyncHandler(getKanaList));
router.get('/kana/:id',                  permissionCheck('vocabulary'), asyncHandler(getKanaById));
router.post('/kana',                     permissionCheck('vocabulary'), asyncHandler(createKanaItem));
router.put('/kana/:id',                  permissionCheck('vocabulary'), asyncHandler(updateKanaItem));
router.delete('/kana/:id',               permissionCheck('vocabulary'), asyncHandler(deleteKanaItem));

module.exports = router;
