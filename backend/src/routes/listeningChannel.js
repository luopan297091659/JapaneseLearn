const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { listChannels, getChannelVideos } = require('../controllers/listeningChannelController');

// 公开接口 —— 不需要登录
router.get('/', asyncHandler(listChannels));
router.get('/:id', asyncHandler(getChannelVideos));

module.exports = router;
