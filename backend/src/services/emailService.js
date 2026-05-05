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
  const todayStart = new Date();
  todayStart.setHours(0, 0, 0, 0);
  const count = await PasswordResetCode.count({ where: { createdAt: { [Op.gte]: todayStart } } });
  if (count >= (cfg.daily_limit || 200)) {
    throw new Error('\u4eca\u65e5\u90ae\u4ef6\u53d1\u9001\u5df2\u8fbe\u4e0a\u9650\uff0c\u8bf7\u660e\u65e5\u518d\u8bd5');
  }
}

async function createTransporter() {
  const cfg = await getEmailConfig();
  if (!cfg.smtp_user || !cfg.smtp_pass) {
    throw new Error('\u90ae\u4ef6\u670d\u52a1\u672a\u914d\u7f6e\uff0c\u8bf7\u8054\u7cfb\u7ba1\u7406\u5458');
  }
  await checkDailyLimit(cfg);
  return {
    cfg,
    transporter: nodemailer.createTransport({
      host: cfg.smtp_host,
      port: cfg.smtp_port,
      secure: true,
      auth: { user: cfg.smtp_user, pass: cfg.smtp_pass },
    }),
  };
}

async function sendResetCode(to, code) {
  const { cfg, transporter } = await createTransporter();
  await transporter.sendMail({
    from: `"\u8a00\u65c5 Kotabi" <${cfg.smtp_user}>`,
    to,
    subject: '\u3010\u8a00\u65c5 Kotabi\u3011\u5bc6\u7801\u91cd\u7f6e\u9a8c\u8bc1\u7801',
    text:
      `\u8a00\u65c5 Kotabi - \u5bc6\u7801\u91cd\u7f6e\n\n` +
      `\u60a8\u6b63\u5728\u91cd\u7f6e\u5bc6\u7801\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a${code}\n\n` +
      `\u9a8c\u8bc1\u7801 1 \u5206\u949f\u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002\n` +
      `\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002`,
    html: `
      <div style="max-width:480px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#8B4513;">\u8a00\u65c5 Kotabi - \u5bc6\u7801\u91cd\u7f6e</h2>
        <p>\u60a8\u6b63\u5728\u91cd\u7f6e\u5bc6\u7801\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#8B4513;
                    background:#FFF5EE;padding:16px 24px;border-radius:8px;text-align:center;margin:16px 0;">
          ${code}
        </div>
        <p>\u9a8c\u8bc1\u7801 <strong>1 \u5206\u949f</strong> \u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002</p>
        <p style="color:#999;font-size:12px;margin-top:24px;">\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002</p>
      </div>
    `,
  });
}

async function sendLoginCode(to, code) {
  const { cfg, transporter } = await createTransporter();
  await transporter.sendMail({
    from: `"\u8a00\u65c5 Kotabi" <${cfg.smtp_user}>`,
    to,
    subject: '\u3010\u8a00\u65c5 Kotabi\u3011\u767b\u5f55\u9a8c\u8bc1\u7801',
    text:
      `\u8a00\u65c5 Kotabi - \u9a8c\u8bc1\u7801\u767b\u5f55\n\n` +
      `\u60a8\u6b63\u5728\u4f7f\u7528\u9a8c\u8bc1\u7801\u767b\u5f55\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a${code}\n\n` +
      `\u9a8c\u8bc1\u7801 1 \u5206\u949f\u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002\n` +
      `\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002`,
    html: `
      <div style="max-width:480px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#8B4513;">\u8a00\u65c5 Kotabi - \u9a8c\u8bc1\u7801\u767b\u5f55</h2>
        <p>\u60a8\u6b63\u5728\u4f7f\u7528\u9a8c\u8bc1\u7801\u767b\u5f55\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#8B4513;
                    background:#FFF5EE;padding:16px 24px;border-radius:8px;text-align:center;margin:16px 0;">
          ${code}
        </div>
        <p>\u9a8c\u8bc1\u7801 <strong>1 \u5206\u949f</strong> \u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002</p>
        <p style="color:#999;font-size:12px;margin-top:24px;">\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002</p>
      </div>
    `,
  });
}

async function sendRegisterCode(to, code) {
  const { cfg, transporter } = await createTransporter();
  await transporter.sendMail({
    from: `"\u8a00\u65c5 Kotabi" <${cfg.smtp_user}>`,
    to,
    subject: '\u3010\u8a00\u65c5 Kotabi\u3011\u6ce8\u518c\u9a8c\u8bc1\u7801',
    text:
      `\u8a00\u65c5 Kotabi - \u90ae\u7bb1\u6ce8\u518c\u9a8c\u8bc1\n\n` +
      `\u60a8\u6b63\u5728\u6ce8\u518c\u8a00\u65c5 Kotabi \u8d26\u53f7\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a${code}\n\n` +
      `\u9a8c\u8bc1\u7801 1 \u5206\u949f\u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002\n` +
      `\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002`,
    html: `
      <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
        \u8a00\u65c5 Kotabi \u6ce8\u518c\u9a8c\u8bc1\u7801\uff1a${code}
      </div>
      <div style="max-width:480px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#8B4513;">\u8a00\u65c5 Kotabi - \u90ae\u7bb1\u6ce8\u518c\u9a8c\u8bc1</h2>
        <p>\u60a8\u6b63\u5728\u6ce8\u518c\u8a00\u65c5 Kotabi \u8d26\u53f7\uff0c\u9a8c\u8bc1\u7801\u4e3a\uff1a</p>
        <div style="font-size:32px;font-weight:bold;letter-spacing:8px;color:#8B4513;
                    background:#FFF5EE;padding:16px 24px;border-radius:8px;text-align:center;margin:16px 0;">
          ${code}
        </div>
        <p>\u9a8c\u8bc1\u7801 <strong>1 \u5206\u949f</strong> \u5185\u6709\u6548\uff0c\u8bf7\u52ff\u6cc4\u9732\u7ed9\u4ed6\u4eba\u3002</p>
        <p style="color:#999;font-size:12px;margin-top:24px;">\u5982\u975e\u672c\u4eba\u64cd\u4f5c\uff0c\u8bf7\u5ffd\u7565\u6b64\u90ae\u4ef6\u3002</p>
      </div>
    `,
  });
}

async function sendOrderNotification(recipients, orderInfo) {
  if (!recipients || !recipients.length) return;

  const cfg = await getEmailConfig();
  if (!cfg.smtp_user || !cfg.smtp_pass) return;

  const transporter = nodemailer.createTransport({
    host: cfg.smtp_host,
    port: cfg.smtp_port,
    secure: true,
    auth: { user: cfg.smtp_user, pass: cfg.smtp_pass },
  });

  const channelMap = {
    qrcode_alipay: '\u652f\u4ed8\u5b9d\u4e8c\u7ef4\u7801',
    qrcode_wechat: '\u5fae\u4fe1\u4e8c\u7ef4\u7801',
    stripe: 'Stripe \u94f6\u884c\u5361',
    apple_iap: 'Apple IAP',
    apple_iap_failed: 'Apple IAP \u5931\u8d25\u8865\u5355',
    refund_request: '\u9000\u6b3e\u7533\u8bf7',
  };
  const channelLabel = channelMap[orderInfo.channel] || orderInfo.channel;
  const time = new Date(orderInfo.createdAt).toLocaleString('zh-CN', { timeZone: 'Asia/Shanghai' });

  const proofHtml = orderInfo.proofUrl
    ? `<p><strong>\u652f\u4ed8\u622a\u56fe\uff1a</strong><br><img src="${orderInfo.proofUrl}" style="max-width:300px;border-radius:8px;margin-top:8px;" alt="\u652f\u4ed8\u622a\u56fe"></p>`
    : '';

  await transporter.sendMail({
    from: `"\u8a00\u65c5 Kotabi" <${cfg.smtp_user}>`,
    to: recipients.join(','),
    subject: `\u3010\u8a00\u65c5\u3011\u65b0\u8ba2\u5355\u5f85\u5ba1\u6838 - ${orderInfo.userName} / ${orderInfo.planName}`,
    html: `
      <div style="max-width:560px;margin:0 auto;font-family:sans-serif;color:#333;">
        <h2 style="color:#F59E0B;border-bottom:2px solid #FEF3C7;padding-bottom:12px;">\u65b0\u8ba2\u5355\u5f85\u5ba1\u6838</h2>
        <table style="width:100%;border-collapse:collapse;margin:16px 0;">
          <tr><td style="padding:8px 0;color:#6b7280;width:100px;">\u8ba2\u5355\u53f7</td><td style="padding:8px 0;font-weight:600;">${orderInfo.orderId}</td></tr>
          <tr><td style="padding:8px 0;color:#6b7280;">\u7528\u6237</td><td style="padding:8px 0;">${orderInfo.userName} (${orderInfo.userEmail})</td></tr>
          <tr><td style="padding:8px 0;color:#6b7280;">\u5957\u9910</td><td style="padding:8px 0;font-weight:600;">${orderInfo.planName}</td></tr>
          <tr><td style="padding:8px 0;color:#6b7280;">\u91d1\u989d</td><td style="padding:8px 0;font-weight:600;color:#F59E0B;">\u00a5${orderInfo.amount}</td></tr>
          <tr><td style="padding:8px 0;color:#6b7280;">\u652f\u4ed8\u65b9\u5f0f</td><td style="padding:8px 0;">${channelLabel}</td></tr>
          <tr><td style="padding:8px 0;color:#6b7280;">\u63d0\u4ea4\u65f6\u95f4</td><td style="padding:8px 0;">${time}</td></tr>
        </table>
        ${proofHtml}
        <p style="margin-top:20px;">
          <a href="${process.env.BASE_URL || 'https://your-domain.com'}/admin#orders"
             style="display:inline-block;padding:10px 24px;background:#F59E0B;color:#fff;border-radius:8px;text-decoration:none;font-weight:700;">
            \u524d\u5f80\u5ba1\u6838
          </a>
        </p>
        <p style="color:#999;font-size:12px;margin-top:24px;">\u6b64\u90ae\u4ef6\u7531\u7cfb\u7edf\u81ea\u52a8\u53d1\u9001\uff0c\u8bf7\u52ff\u56de\u590d\u3002</p>
      </div>
    `,
  });
}

module.exports = { sendResetCode, sendLoginCode, sendRegisterCode, sendOrderNotification };
