const express = require('express');
const router  = express.Router();
const { authenticate } = require('../middlewares/auth');
const { adminAuth }    = require('../middlewares/adminAuth');
const { checkMembership } = require('../middlewares/membership');
const ctrl             = require('../controllers/gameController');
const { syncTokyoDialogues } = require('../controllers/adminController');

router.post('/score',                authenticate, checkMembership('game_levels'), ctrl.saveScore);
router.get('/my-progress',           authenticate,            ctrl.getMyProgress);
router.get('/life-save',             authenticate,            ctrl.getLifeSave);
router.put('/life-save',             authenticate,            ctrl.putLifeSave);
router.post('/tokyo-dialogues/sync', authenticate,            syncTokyoDialogues);
router.get('/leaderboard',                                    ctrl.getLeaderboard);
router.get('/leaderboard/global',                             ctrl.getGlobalLeaderboard);
router.get('/config',                                         ctrl.getConfig);
router.put('/config',                adminAuth,               ctrl.updateConfig);

module.exports = router;
