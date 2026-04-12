const nodemailer = require('nodemailer');

async function getEmailConfig() {
  try {
    const { sequelize } = require('../config/database');
    const AppConfig = sequelize.models.AppConfig;
    const kv = await AppConfig?.findOne({ where: { key: 'email_settings' } });
    if (kv) return JSON.parse(kv.value);
  } catch (_) {}
  return {
    smtp_host: process.env.SMTP_HOST || 'smtp.aliyun.com',
    smtp_port: parseInt(process.env.SMTP_PORT || '465', 10),
    smtp_user: process.env.SMTP_USER || '',
    smtp_pass: process.env.SMTP_PASS || '',
    daily_limit: 200,
  };
}

async function checkDailyLimit(cfg) {
  const PasswordResetCode = require('../models/PasswordResetCode');
  const { Op } = require('sequelize');
  const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);
  const count = await PasswordResetCode.count({ where: { createdAt: { [Op.gte]: todayStart } } });
  if (count >= (cfg.daily_limit || 200)) {
    throw new Error('今日邮件发送已达上限，请明日再试');
  }
}

async function sendResetCode(to, code) {
  const cfg = await getEmailConfig();
  if (!cfg.smtp_user || !cfg.smtp_pass) {
    throw new Error('邮件服务未配置，请联系管理员');
  }
  await checkDailyLimit(cfg);
  const transporter = nodemailer.createTransport({
    host: cfg.smtp_host, port: cfg.smtp_port, secure: true,
    auth: { user: cfg.smtp_user, pass: cfg.smtp_pass },
  });
  await transporter.sendMail({
    from: `"言旅 Kotabi" <${cfg.smtp_user}>`,
    to,
    subject: '【言旅 Kotabi】密码重置验证码',
    html: `
      <div style="max-width:480px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#8B4513;">言旅 Kotabi — 密码重置</h2>
        <p>您正在重置密码，验证码为：</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#8B4513;
                    background:#FFF5EE;padding:16px 24px;border-radius:8px;text-align:center;margin:16px 0;">
          ${code}
        </div>
        <p>验证码 <strong>10 分钟</strong>内有效，请勿泄露给他人。</p>
        <p style="color:#999;font-size:12px;margin-top:24px;">如非本人操作，请忽略此邮件。</p>
      </div>
    `,
  });
}

async function sendLoginCode(to, code) {
  const cfg = await getEmailConfig();
  if (!cfg.smtp_user || !cfg.smtp_pass) {
    throw new Error('邮件服务未配置，请联系管理员');
  }
  await checkDailyLimit(cfg);
  const transporter = nodemailer.createTransport({
    host: cfg.smtp_host, port: cfg.smtp_port, secure: true,
    auth: { user: cfg.smtp_user, pass: cfg.smtp_pass },
  });
  await transporter.sendMail({
    from: `"言旅 Kotabi" <${cfg.smtp_user}>`,
    to,
    subject: '【言旅 Kotabi】登录验证码',
    html: `
      <div style="max-width:480px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#8B4513;">言旅 Kotabi — 验证码登录</h2>
        <p>您正在使用验证码登录，验证码为：</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#8B4513;
                    background:#FFF5EE;padding:16px 24px;border-radius:8px;text-align:center;margin:16px 0;">
          ${code}
        </div>
        <p>验证码 <strong>10 分钟</strong>内有效，请勿泄露给他人。</p>
        <p style="color:#999;font-size:12px;margin-top:24px;">如非本人操作，请忽略此邮件。</p>
      </div>
    `,
  });
}

module.exports = { sendResetCode, sendLoginCode };
