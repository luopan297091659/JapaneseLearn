const { verifyAccessToken } = require('../utils/jwt');
const User = require('../models/User');

async function adminAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: '未授权' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const decoded = verifyAccessToken(token);
    const user = await User.findByPk(decoded.id);
    if (!user || !user.is_active) return res.status(401).json({ error: '用户不存在或已停用' });
    if (user.role !== 'admin') return res.status(403).json({ error: '权限不足，需要管理员权限' });
    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: '令牌无效或已过期' });
  }
}

module.exports = { adminAuth };
