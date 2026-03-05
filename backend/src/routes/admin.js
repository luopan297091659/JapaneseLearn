const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const multer = require('multer');
const path = require('path');
const { adminAuth } = require('../middlewares/adminAuth');
const {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab,
  importVocab, importVocabFile,
  listGrammar, createGrammar, updateGrammar, deleteGrammar,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats,
  getMembershipConfig, saveMembershipConfig,
  uploadApp, listAppReleases, downloadApp,
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

// 仪表板
router.get('/dashboard', asyncHandler(getDashboard));

// ── 统计分析（支持 ?grain=day|month|year&start=YYYY-MM-DD&end=YYYY-MM-DD）──
router.get('/stats/traffic',  asyncHandler(getTrafficStats));
router.get('/stats/users',    asyncHandler(getUserStats));
router.get('/stats/behavior', asyncHandler(getBehaviorStats));

// 词汇管理
router.get('/vocabulary',              asyncHandler(listVocab));
router.post('/vocabulary',             asyncHandler(createVocab));
router.put('/vocabulary/:id',          asyncHandler(updateVocab));
router.delete('/vocabulary/:id',       asyncHandler(deleteVocab));
router.post('/vocabulary/bulk-delete', asyncHandler(bulkDeleteVocab));
router.post('/vocabulary/import',      asyncHandler(importVocab));
router.post('/vocabulary/import-file', upload.single('file'), asyncHandler(importVocabFile));

// 文法管理
router.get('/grammar',        asyncHandler(listGrammar));
router.post('/grammar',       asyncHandler(createGrammar));
router.put('/grammar/:id',    asyncHandler(updateGrammar));
router.delete('/grammar/:id', asyncHandler(deleteGrammar));

// 听力管理
router.get('/tracks',        asyncHandler(listTracks));
router.post('/tracks',       asyncHandler(createTrack));
router.put('/tracks/:id',    asyncHandler(updateTrack));
router.delete('/tracks/:id', asyncHandler(deleteTrack));

// 用户管理
router.get('/users',       asyncHandler(listUsers));
router.put('/users/:id',   asyncHandler(updateUser));

// 内容版本
router.get('/content-version',         asyncHandler(getContentVersion));
router.post('/content-version/publish', asyncHandler(publishContent));

// 会员套餐配置
router.get('/membership',  asyncHandler(getMembershipConfig));
router.post('/membership', asyncHandler(saveMembershipConfig));

// App 管理
router.post('/uploadApp', appUpload.single('file'), asyncHandler(uploadApp));
router.get('/listAppReleases', asyncHandler(listAppReleases));

module.exports = router;
