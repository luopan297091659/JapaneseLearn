const logger = require('../utils/logger');
const { readAiSettings, saveAiSettingsFile } = require('./adminController');

// 获取当前 AI 配置（每次请求动态读取，方便管理员面板热更新）
function getAiConfig() {
  const settings = readAiSettings();
  return {
    enabled: settings.enabled !== false,
    apiKey: settings.api_key || process.env.AI_API_KEY || '',
    model: settings.model || 'deepseek-chat',
    baseUrl: settings.base_url || 'https://api.deepseek.com/v1',
    provider: settings.provider || 'deepseek',
    dailyLimit: settings.daily_limit || 0,
    alertThreshold: settings.alert_threshold || 80,
  };
}

// 增加用量计数
function trackUsage() {
  const settings = readAiSettings();
  const todayStr = new Date().toISOString().slice(0, 10);
  if (!settings.usage) settings.usage = { today_count: 0, today_date: '', total_count: 0, history: [] };

  if (settings.usage.today_date !== todayStr) {
    // 新的一天，归档昨日数据
    if (settings.usage.today_date && settings.usage.today_count > 0) {
      settings.usage.history.push({ date: settings.usage.today_date, count: settings.usage.today_count });
      // 仅保留最近 90 天
      if (settings.usage.history.length > 90) settings.usage.history = settings.usage.history.slice(-90);
    }
    settings.usage.today_date = todayStr;
    settings.usage.today_count = 0;
  }

  settings.usage.today_count += 1;
  settings.usage.total_count = (settings.usage.total_count || 0) + 1;
  saveAiSettingsFile(settings);

  return { todayCount: settings.usage.today_count, dailyLimit: settings.daily_limit || 0 };
}

// ── AI API 通用请求（OpenAI 兼容格式，支持 DeepSeek / OpenAI / Gemini OpenAI 兼容等）────
async function callAI(prompt, maxTokens = 2048) {
  const config = getAiConfig();

  if (!config.enabled) {
    throw Object.assign(new Error('AI 功能已关闭'), { status: 503 });
  }
  if (!config.apiKey) {
    throw Object.assign(new Error('AI 功能未配置，请在管理面板设置 API Key'), { status: 503 });
  }

  // 检查每日限额
  if (config.dailyLimit > 0) {
    const settings = readAiSettings();
    const todayStr = new Date().toISOString().slice(0, 10);
    const todayCount = settings.usage?.today_date === todayStr ? settings.usage.today_count : 0;
    if (todayCount >= config.dailyLimit) {
      throw Object.assign(new Error('今日 AI 调用次数已达上限，请明天再试'), { status: 429 });
    }
  }

  // OpenAI 兼容格式（DeepSeek / OpenAI / 通义千问 等均支持）
  const baseUrl = config.baseUrl.replace(/\/+$/, '');
  const url = `${baseUrl}/chat/completions`;
  const body = {
    model: config.model,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: maxTokens,
    temperature: 0.3,
  };

  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.apiKey}`,
    },
    body: JSON.stringify(body),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    const errMsg = err?.error?.message || JSON.stringify(err);
    logger.error('AI API error:', res.status, errMsg);
    // 对常见错误码返回友好中文提示
    const statusMsgMap = {
      401: 'API Key 无效，请在管理面板检查配置',
      402: 'AI 账户余额不足，请前往服务商平台充值',
      429: 'AI 请求过于频繁，请稍后再试',
      403: 'API Key 权限不足或已被禁用',
    };
    const friendlyMsg = statusMsgMap[res.status] || ('AI 服务请求失败: ' + errMsg);
    throw Object.assign(new Error(friendlyMsg), { status: res.status >= 500 ? 502 : res.status });
  }

  const data = await res.json();
  const text = data?.choices?.[0]?.message?.content;
  if (!text) throw Object.assign(new Error('AI 返回为空'), { status: 502 });

  // 记录用量
  trackUsage();

  return text;
}

// 从 AI 回复中提取 JSON
function extractJson(text) {
  const match = text.match(/```json\s*([\s\S]*?)```/);
  const raw = match ? match[1].trim() : text.trim();
  return JSON.parse(raw);
}

// ── POST /api/v1/ai/translate ─────────────────────────────────────────────────
async function translate(req, res) {
  const { text, targetLang = 'zh' } = req.body;
  if (!text || !text.trim()) return res.status(400).json({ error: '请提供要翻译的文本' });

  const langMap = { zh: '中文', en: 'English', ko: '韩语' };
  const lang = langMap[targetLang] || '中文';

  try {
    const prompt = `请将以下日语文本翻译为${lang}，翻译要自然通顺。只返回翻译结果，不要其他说明。\n\n${text.trim()}`;
    const result = await callAI(prompt, 1024);
    res.json({ translation: result.trim() });
  } catch (err) {
    const msg = err?.message || 'AI 翻译服务异常';
    logger.error('AI translate error: ' + msg);
    res.status(err?.status || 500).json({ error: msg });
  }
}

// ── POST /api/v1/ai/analyze ──────────────────────────────────────────────────
async function analyze(req, res) {
  const { text } = req.body;
  if (!text || !text.trim()) return res.status(400).json({ error: '请提供要分析的日语文本' });

  try {
    const prompt = `请对以下日语句子进行详细的词法分析，以JSON数组格式返回。每个元素包含：
- "word": 原文词语
- "pos": 词性（日语名称：名詞、動詞、形容詞、副詞、助詞、助動詞、接続詞、感動詞、連体詞、記号）
- "furigana": 假名读音（汉字才需要）
- "romaji": 罗马音
- "meaning": 中文释义

分析要求：
1. 将助动词与对应动词结合，如"食べた"作为一个单词
2. 正确识别时态变化
3. 合理处理助词
4. 如遇换行请用 {"word":"\\n","pos":"改行","furigana":"","romaji":"","meaning":""}

只返回JSON数组，不要markdown包裹。

句子：${text.trim()}`;

    const result = await callAI(prompt, 4096);
    const tokens = extractJson(result);
    res.json({ tokens });
  } catch (err) {
    const msg = err?.message || 'AI 分析服务异常';
    logger.error('AI analyze error: ' + msg);
    if (err instanceof SyntaxError) {
      return res.status(502).json({ error: 'AI 返回格式异常，请重试' });
    }
    res.status(err?.status || 500).json({ error: msg });
  }
}

// ── POST /api/v1/ai/word-detail ──────────────────────────────────────────────
async function wordDetail(req, res) {
  const { word, pos, sentence } = req.body;
  if (!word) return res.status(400).json({ error: '请提供要查询的词语' });

  try {
    const prompt = `请详细解释以下日语词汇，以JSON格式返回：
{
  "word": "${word}",
  "pos": "${pos || ''}",
  "furigana": "假名读音",
  "romaji": "罗马音",
  "dictionaryForm": "辞书形/原形",
  "meaning": "中文释义（简洁）",
  "explanation": "详细解释，包括：\\n1. 词义说明\\n2. 在原句中的用法${sentence ? `\\n3. 在「${sentence}」这句话中的具体含义` : ''}\\n4. 常见搭配或例句"
}

只返回JSON对象，不要markdown包裹。`;

    const result = await callAI(prompt, 2048);
    const detail = extractJson(result);
    res.json(detail);
  } catch (err) {
    const msg = err?.message || 'AI 词汇服务异常';
    logger.error('AI word-detail error: ' + msg);
    if (err instanceof SyntaxError) {
      return res.status(502).json({ error: 'AI 返回格式异常，请重试' });
    }
    res.status(err?.status || 500).json({ error: msg });
  }
}

module.exports = { translate, analyze, wordDetail };
