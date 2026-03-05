/**
 * API 请求日志中间件
 * 异步写入 api_logs 表，不阻塞响应
 * 跳过：/admin 静态资源、/uploads、/health
 */
const { ApiLog } = require('../models');

const SKIP_PREFIXES = ['/uploads', '/health', '/admin'];

function apiLogger(req, res, next) {
  // 跳过不需要记录的路径
  if (SKIP_PREFIXES.some(p => req.path.startsWith(p))) return next();

  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    // 异步写，不 await，不影响响应
    ApiLog.create({
      method: req.method.substring(0, 10),
      path: (req.originalUrl || req.path).substring(0, 500),
      status_code: res.statusCode,
      response_time_ms: ms,
      user_id: req.user?.id || null,
      ip: (req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '').toString().substring(0, 60),
      user_agent: (req.headers['user-agent'] || '').substring(0, 300),
    }).catch(() => {}); // 静默失败，不影响业务
  });
  next();
}

module.exports = { apiLogger };
