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
    req.isSuperAdmin = user.admin_level === 'super_admin';
    try { req.adminPermissions = user.permissions ? JSON.parse(user.permissions) : null; } catch { req.adminPermissions = null; }
    next();
  } catch (err) {
    return res.status(401).json({ error: '令牌无效或已过期' });
  }
}

function superAdminAuth(req, res, next) {
  if (!req.isSuperAdmin) {
    return res.status(403).json({ error: '权限不足，需要高级管理员权限' });
  }
  next();
}

function permissionCheck(permKey) {
  return (req, res, next) => {
    if (req.isSuperAdmin) return next();
    if (req.adminPermissions && req.adminPermissions.includes(permKey)) return next();
    return res.status(403).json({ error: `权限不足，缺少「${permKey}」权限` });
  };
}

module.exports = { adminAuth, superAdminAuth, permissionCheck };
