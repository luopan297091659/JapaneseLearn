const express = require('express');
const router  = express.Router();
const { authenticate } = require('../middlewares/auth');
const { adminAuth }    = require('../middlewares/adminAuth');
const ctrl             = require('../controllers/gameController');

router.post('/score',                authenticate,            ctrl.saveScore);
router.get('/my-progress',           authenticate,            ctrl.getMyProgress);
router.get('/leaderboard',                                    ctrl.getLeaderboard);
router.get('/leaderboard/global',                             ctrl.getGlobalLeaderboard);
router.get('/config',                                         ctrl.getConfig);
router.put('/config',                adminAuth,               ctrl.updateConfig);

module.exports = router;
