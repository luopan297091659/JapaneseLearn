const { verifyAccessToken } = require('../utils/jwt');
const User = require('../models/User');

async function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid authorization header' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = verifyAccessToken(token);
    const user = await User.findByPk(decoded.id);
    if (!user || !user.is_active) {
      return res.status(401).json({ error: 'User not found or inactive' });
    }
    // 多端登录校验：检查 JWT 中的 loginToken 是否与数据库一致
    if (decoded.loginToken) {
      const platform = decoded.platform || 'web';
      const field = platform === 'app' ? 'app_login_token' : 'web_login_token';
      if (user[field] !== decoded.loginToken) {
        return res.status(401).json({ error: 'SESSION_REPLACED', message: '你的账号已在其他设备登录' });
      }
    }
    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = { authenticate };
