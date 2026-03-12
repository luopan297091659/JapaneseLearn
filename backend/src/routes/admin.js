const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const multer = require('multer');
const path = require('path');
const { adminAuth, superAdminAuth, permissionCheck } = require('../middlewares/adminAuth');
const {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab,
  importVocab, importVocabFile,
  listGrammar, createGrammar, updateGrammar, deleteGrammar, bulkDeleteGrammar,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser, updateUserMembership,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats, getFeatureUsage,
  getMembershipConfig, saveMembershipConfig,
  getFeatureToggles, saveFeatureToggles,
  uploadApp, listAppReleases, downloadApp, deleteAppRelease,
  getAiSettings, saveAiSettings, getAiUsage, resetAiUsage,
  listAdmins, updateAdminPermissions, getAdminInfo,
} = require('../controllers/adminController');

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

// ── App 下载（公开，不需要 adminAuth）──
router.get('/downloadApp/:id', asyncHandler(downloadApp));

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
router.post('/vocabulary/import',      permissionCheck('vocabulary'), asyncHandler(importVocab));
router.post('/vocabulary/import-file', permissionCheck('vocabulary'), upload.single('file'), asyncHandler(importVocabFile));

// 文法管理
router.get('/grammar',        permissionCheck('grammar'), asyncHandler(listGrammar));
router.post('/grammar',       permissionCheck('grammar'), asyncHandler(createGrammar));
router.put('/grammar/:id',    permissionCheck('grammar'), asyncHandler(updateGrammar));
router.delete('/grammar/:id', permissionCheck('grammar'), asyncHandler(deleteGrammar));
router.post('/grammar/bulk-delete', permissionCheck('grammar'), asyncHandler(bulkDeleteGrammar));

// 听力管理
router.get('/tracks',        permissionCheck('tracks'), asyncHandler(listTracks));
router.post('/tracks',       permissionCheck('tracks'), asyncHandler(createTrack));
router.put('/tracks/:id',    permissionCheck('tracks'), asyncHandler(updateTrack));
router.delete('/tracks/:id', permissionCheck('tracks'), asyncHandler(deleteTrack));

// 用户管理
router.get('/users',       permissionCheck('users'), asyncHandler(listUsers));
router.put('/users/:id',   permissionCheck('users'), asyncHandler(updateUser));
router.put('/users/:id/membership', permissionCheck('users'), asyncHandler(updateUserMembership));

// 内容版本
router.get('/content-version',         asyncHandler(getContentVersion));
router.post('/content-version/publish', permissionCheck('sync'), asyncHandler(publishContent));

// 会员套餐配置（仅高级管理员）
router.get('/membership',  permissionCheck('membership'), asyncHandler(getMembershipConfig));
router.post('/membership', superAdminAuth, asyncHandler(saveMembershipConfig));

// 功能开关配置（仅高级管理员）
router.get('/feature-toggles',  superAdminAuth, asyncHandler(getFeatureToggles));
router.post('/feature-toggles', superAdminAuth, asyncHandler(saveFeatureToggles));

// App 管理（仅高级管理员）
router.post('/uploadApp', superAdminAuth, appUpload.single('file'), asyncHandler(uploadApp));
router.get('/listAppReleases', superAdminAuth, asyncHandler(listAppReleases));
router.delete('/app/:id', superAdminAuth, asyncHandler(deleteAppRelease));

// AI 设置（仅高级管理员）
router.get('/ai-settings',       superAdminAuth, asyncHandler(getAiSettings));
router.post('/ai-settings',      superAdminAuth, asyncHandler(saveAiSettings));
router.get('/ai-usage',          superAdminAuth, asyncHandler(getAiUsage));
router.post('/ai-usage/reset',   superAdminAuth, asyncHandler(resetAiUsage));

// 管理员权限管理（仅高级管理员）
router.get('/admins',             superAdminAuth, asyncHandler(listAdmins));
router.put('/admins/:id/permissions', superAdminAuth, asyncHandler(updateAdminPermissions));

module.exports = router;
