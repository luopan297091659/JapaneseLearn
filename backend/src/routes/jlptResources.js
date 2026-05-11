const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate } = require('../middlewares/auth');
const {
  publicListJlptResourceDirectories,
  publicListJlptResourceFiles,
  publicDownloadJlptResourceFile,
} = require('../controllers/jlptResourceController');

router.use(authenticate);
router.get('/directories', asyncHandler(publicListJlptResourceDirectories));
router.get('/files', asyncHandler(publicListJlptResourceFiles));
router.get('/files/:id/download', asyncHandler(publicDownloadJlptResourceFile));

module.exports = router;
