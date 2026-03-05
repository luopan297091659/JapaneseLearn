// ── 强制进程时区为东京时间（JST, UTC+9）────────────────────────────────────
// 必须在 require('dotenv') 之前设置，确保 new Date() / Date.now() 均基于 JST
process.env.TZ = process.env.TZ || 'Asia/Tokyo';

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const path = require('path');
const fs = require('fs');
const http = require('http');
const https = require('https');

const { sequelize } = require('./config/database');
const logger = require('./utils/logger');

// Routes
const authRoutes = require('./routes/auth');
const userRoutes = require('./routes/users');
const vocabularyRoutes = require('./routes/vocabulary');
const grammarRoutes = require('./routes/grammar');
const srsRoutes = require('./routes/srs');
const quizRoutes = require('./routes/quiz');
const listenRoutes = require('./routes/listening');
const newsRoutes = require('./routes/news');
const progressRoutes = require('./routes/progress');
const dictionaryRoutes = require('./routes/dictionary');
const ankiRoutes = require('./routes/anki');
const adminRoutes = require('./routes/admin');
const syncRoutes  = require('./routes/sync');
const gameRoutes  = require('./routes/game');

const app = express();

// Security
app.use(helmet());

// Admin panel 需要内联脚本，覆盖 helmet 默认的严格 CSP
app.use('/admin', (_req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'unsafe-inline'; style-src 'self' https: 'unsafe-inline'; img-src 'self' data:; font-src 'self' https: data:; connect-src 'self'"
  );
  next();
});

// Web 前端同样需要内联脚本/样式的 CSP
app.use('/app', (_req, res, next) => {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'self'; script-src 'self' 'unsafe-inline'; script-src-attr 'unsafe-inline'; style-src 'self' https: 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' https: data:; media-src 'self' https:; connect-src 'self'"
  );
  next();
});

app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  credentials: true,
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 200,
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

// Body parsing
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Logging
app.use(morgan('combined', { stream: { write: (msg) => logger.info(msg.trim()) } }));

// API 请求日志（写入 api_logs 表，用于流量监控）
const { apiLogger } = require('./middlewares/apiLogger');
app.use(apiLogger);

// Static files (audio, images)
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));
// Admin panel static files
app.use('/admin', express.static(path.join(__dirname, '../public/admin')));
app.get('/admin', (req, res) => res.sendFile(path.join(__dirname, '../public/admin/index.html')));
// Web frontend static files
app.use('/app', express.static(path.join(__dirname, '../public/app')));
app.get('/app', (req, res) => res.sendFile(path.join(__dirname, '../public/app/index.html')));

// API Routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/vocabulary', vocabularyRoutes);
app.use('/api/v1/grammar', grammarRoutes);
app.use('/api/v1/srs', srsRoutes);
app.use('/api/v1/quiz', quizRoutes);
app.use('/api/v1/listening', listenRoutes);
app.use('/api/v1/news', newsRoutes);
app.use('/api/v1/progress', progressRoutes);
app.use('/api/v1/dictionary', dictionaryRoutes);
app.use('/api/v1/anki', ankiRoutes);
app.use('/api/v1/admin', adminRoutes);
app.use('/api/v1/sync', syncRoutes);
app.use('/api/v1/game', gameRoutes);

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Global error handler
app.use((err, req, res, next) => {
  logger.error(err.stack);
  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
  });
});

// Start server
const PORT = process.env.PORT || 8002;

async function start() {
  try {
    await sequelize.authenticate();
    logger.info('Database connection established.');
    // 生产环境只做 "CREATE TABLE IF NOT EXISTS"，不执行任何 ALTER
    // 如需新增字段请手动执行 SQL migration
    await sequelize.sync({ alter: { drop: false } }); // 自动添加新列，但不删除现有列/数据

    const certPath = process.env.SSL_CERT_PATH || './certs/cert.pem';
    const keyPath  = process.env.SSL_KEY_PATH  || './certs/key.pem';

    if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
      // HTTPS mode
      const credentials = {
        cert: fs.readFileSync(certPath),
        key:  fs.readFileSync(keyPath),
      };
      https.createServer(credentials, app).listen(PORT, () => {
        logger.info(`HTTPS Server running on port ${PORT}`);
      });
    } else {
      // HTTP fallback（开发环境证书未生成时）
      logger.warn('SSL cert not found, falling back to HTTP. Run scripts/gen_cert.ps1 to generate certificates.');
      http.createServer(app).listen(PORT, () => {
        logger.info(`HTTP Server running on port ${PORT} (no SSL)`);
      });
    }
  } catch (err) {
    logger.error('Failed to start server:', err);
    process.exit(1);
  }
}

start();

module.exports = app;
