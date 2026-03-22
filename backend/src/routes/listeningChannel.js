const router = require('express').Router();
const asyncHandler = require('../utils/asyncHandler');
const { authenticate, optionalAuthenticate } = require('../middlewares/auth');
const {
	listChannels,
	getChannelVideos,
	listUserChannels,
	createUserChannel,
	deleteUserChannel,
} = require('../controllers/listeningChannelController');

// 公开接口 —— 不需要登录
router.get('/', optionalAuthenticate, asyncHandler(listChannels));

// 用户自定义频道（仅当前用户）
router.get('/my/channels', authenticate, asyncHandler(listUserChannels));
router.post('/my/channels', authenticate, asyncHandler(createUserChannel));
router.delete('/my/channels/:id', authenticate, asyncHandler(deleteUserChannel));

router.get('/:id', asyncHandler(getChannelVideos));

module.exports = router;
