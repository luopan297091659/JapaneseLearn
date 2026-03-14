/**
 * Admin Controller
 * 仪表板统计、词库管理、文法管理、听力管理、用户管理、内容版本同步
 */
const { Op, fn, col, literal } = require('sequelize');
const { sequelize } = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const User = require('../models/User');
const {
  Vocabulary, GrammarLesson, GrammarExample,
  ListeningTrack, UserProgress, ContentVersion, ApiLog,
  QuizSession, SrsCard,
  AppRelease, MembershipPlan,
} = require('../models');
// utilities used across controllers
const { stripHtml } = require('../services/ankiService');

/** 创建带状态码的错误 */
function apiError(message, status = 400, code) {
  const err = new Error(message);
  err.status = status;
  if (code) err.code = code;
  return err;
}

// ─── 工具：版本号递增 ─────────────────────────────────────────────────────────
async function bumpVersion(field = 'version') {
  try {
    let cv = await ContentVersion.findByPk(1);
    if (!cv) {
      cv = await ContentVersion.create({ id: 1, version: 1, vocab_version: 1, grammar_version: 1, updated_at_ts: Date.now() });
    }
    const updates = { [field]: cv[field] + 1, version: cv.version + 1, updated_at_ts: Date.now() };
    await cv.update(updates);
  } catch (e) { /* ignore */ }
}

// ─── 仪表板统计 ───────────────────────────────────────────────────────────────
async function getDashboard(req, res) {
  try {
    const [vocabCount, grammarCount, trackCount, userCount, recentUsers, grammarExampleCount] = await Promise.all([
      Vocabulary.count(),
      GrammarLesson.count(),
      ListeningTrack.count(),
      User.count(),
      User.findAll({ order: [['createdAt', 'DESC']], limit: 5, attributes: ['id', 'username', 'email', 'level', 'role', 'createdAt'] }),
      GrammarExample.count(),
    ]);

    // 词汇按JLPT级别分组
    const vocabByLevel = await Vocabulary.findAll({
      attributes: ['jlpt_level', [sequelize.fn('COUNT', '*'), 'cnt']],
      group: ['jlpt_level'],
      raw: true,
    });

    // 近7天活跃用户
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 3600 * 1000);
    const activeUsers = await UserProgress.count({
      distinct: true, col: 'user_id',
      where: { createdAt: { [Op.gte]: sevenDaysAgo } },
    });

    let cv = await ContentVersion.findByPk(1);
    if (!cv) cv = { version: 1, vocab_version: 1, grammar_version: 1 };

    res.json({
      vocabCount, grammarCount, trackCount, userCount, activeUsers, grammarExampleCount,
      vocabByLevel: Object.fromEntries(vocabByLevel.map(r => [r.jlpt_level, parseInt(r.cnt)])),
      recentUsers,
      contentVersion: cv,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 词汇管理 ─────────────────────────────────────────────────────────────────
async function listVocab(req, res) {
  const { level, q, page = 1, limit = 30, category } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  if (category) where.category = category;
  if (q) {
    where[Op.or] = [
      { word: { [Op.like]: `%${q}%` } },
      { reading: { [Op.like]: `%${q}%` } },
      { meaning_zh: { [Op.like]: `%${q}%` } },
    ];
  }
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await Vocabulary.findAndCountAll({
      where, limit: parseInt(limit), offset,
      order: [['jlpt_level', 'ASC'], ['word', 'ASC']],
    });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function createVocab(req, res) {
  try {
    const vocab = await Vocabulary.create({ id: uuidv4(), ...req.body });
    await bumpVersion('vocab_version');
    res.status(201).json(vocab);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

async function updateVocab(req, res) {
  try {
    const vocab = await Vocabulary.findByPk(req.params.id);
    if (!vocab) return res.status(404).json({ error: 'Not found' });
    await vocab.update(req.body);
    await bumpVersion('vocab_version');
    res.json(vocab);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

async function deleteVocab(req, res) {
  try {
    const vocab = await Vocabulary.findByPk(req.params.id);
    if (!vocab) return res.status(404).json({ error: 'Not found' });
    await vocab.destroy();
    await bumpVersion('vocab_version');
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 批量删除词汇 ──────────────────────────────────────────────────────────────
async function bulkDeleteVocab(req, res) {
  const { ids } = req.body;
  if (!Array.isArray(ids) || ids.length === 0) return res.status(400).json({ error: 'ids 不能为空' });
  try {
    const count = await Vocabulary.destroy({ where: { id: { [Op.in]: ids } } });
    await bumpVersion('vocab_version');
    res.json({ deleted: count });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── Anki / CSV 批量导入词汇 ──────────────────────────────────────────────────
// reuse shared html stripping from ankiService (imported above)

async function importVocab(req, res) {
  const { cards, deck_name = 'Admin Import', jlpt_level = 'N3', part_of_speech = 'other', overwrite = false } = req.body;

  if (!Array.isArray(cards) || cards.length === 0) {
    return res.status(400).json({ error: 'cards 数组不能为空' });
  }

  const VALID_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];
  const VALID_POS = ['noun', 'verb', 'adjective', 'adverb', 'particle', 'conjunction', 'interjection', 'other'];
  const safeLevel = VALID_LEVELS.includes(jlpt_level) ? jlpt_level : 'N3';
  const safePos   = VALID_POS.includes(part_of_speech) ? part_of_speech : 'other';

  const rows = cards.filter(c => c.word && String(c.word).trim()).map(c => ({
    id: uuidv4(),
    word: stripHtml(String(c.word)).substring(0, 100),
    reading: stripHtml(c.reading ? String(c.reading) : String(c.word)).substring(0, 200),
    meaning_zh: stripHtml(c.meaning_zh || c.meaning_en || '-').substring(0, 1000),
    meaning_en: c.meaning_en ? stripHtml(String(c.meaning_en)).substring(0, 1000) : null,
    example_sentence: c.example_sentence ? stripHtml(String(c.example_sentence)).substring(0, 2000) : null,
    part_of_speech: safePos,
    jlpt_level: safeLevel,
    category: String(deck_name).substring(0, 50),
    tags: JSON.stringify({ source: 'admin_import', deck: deck_name }),
  }));

  if (rows.length === 0) return res.status(400).json({ error: '没有找到有效卡片' });

  const CHUNK = 500;
  let imported = 0, failed = 0;
  for (let i = 0; i < rows.length; i += CHUNK) {
    const chunk = rows.slice(i, i + CHUNK);
    try {
      if (overwrite) {
        await Vocabulary.bulkCreate(chunk, { updateOnDuplicate: ['word', 'reading', 'meaning_zh', 'meaning_en', 'example_sentence', 'part_of_speech', 'jlpt_level', 'category'] });
      } else {
        await Vocabulary.bulkCreate(chunk, { ignoreDuplicates: true });
      }
      imported += chunk.length;
    } catch { failed += chunk.length; }
  }
  await bumpVersion('vocab_version');
  res.json({ imported, failed, total: rows.length });
}

// ─── 文件上传导入 (txt/csv/tsv) ───────────────────────────────────────────────
async function importVocabFile(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });
  const { deck_name = 'File Import', jlpt_level = 'N3', part_of_speech = 'other' } = req.body;

  try {
    const content = req.file.buffer.toString('utf-8');
    const ext = path.extname(req.file.originalname).toLowerCase();
    const lines = content.split(/\r?\n/).filter(l => l.trim() && !l.startsWith('#'));

    const sep = (ext === '.csv') ? ',' : '\t';
    const cards = [];

    for (const line of lines) {
      const parts = line.split(sep);
      if (parts.length < 2) continue;
      cards.push({
        word: parts[0]?.trim(),
        meaning_zh: parts[1]?.trim(),
        reading: parts[2]?.trim() || parts[0]?.trim(),
        meaning_en: parts[3]?.trim() || null,
        example_sentence: parts[4]?.trim() || null,
      });
    }

    req.body = { cards, deck_name, jlpt_level, part_of_speech };
    return importVocab(req, res);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 文法管理 ─────────────────────────────────────────────────────────────────
async function listGrammar(req, res) {
  const { level, q, page = 1, limit = 30 } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  if (q) {
    where[Op.or] = [
      { title: { [Op.like]: `%${q}%` } },
      { pattern: { [Op.like]: `%${q}%` } },
      { explanation_zh: { [Op.like]: `%${q}%` } },
    ];
  }
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await GrammarLesson.findAndCountAll({
      where, limit: parseInt(limit), offset,
      include: [{ model: GrammarExample, as: 'examples' }],
      order: [['jlpt_level', 'ASC'], ['order_index', 'ASC']],
    });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function createGrammar(req, res) {
  const t = await sequelize.transaction();
  try {
    const { examples = [], ...lessonData } = req.body;
    const lesson = await GrammarLesson.create({ id: uuidv4(), ...lessonData }, { transaction: t });
    for (const ex of examples) {
      await GrammarExample.create({ id: uuidv4(), grammar_lesson_id: lesson.id, ...ex }, { transaction: t });
    }
    await t.commit();
    await bumpVersion('grammar_version');
    const full = await GrammarLesson.findByPk(lesson.id, { include: [{ model: GrammarExample, as: 'examples' }] });
    res.status(201).json(full);
  } catch (err) {
    await t.rollback();
    res.status(400).json({ error: err.message });
  }
}

async function updateGrammar(req, res) {
  const t = await sequelize.transaction();
  try {
    const lesson = await GrammarLesson.findByPk(req.params.id, { transaction: t });
    if (!lesson) { await t.rollback(); return res.status(404).json({ error: 'Not found' }); }
    const { examples, ...lessonData } = req.body;
    await lesson.update(lessonData, { transaction: t });
    if (Array.isArray(examples)) {
      await GrammarExample.destroy({ where: { grammar_lesson_id: lesson.id }, transaction: t });
      for (const ex of examples) {
        await GrammarExample.create({ id: uuidv4(), grammar_lesson_id: lesson.id, ...ex }, { transaction: t });
      }
    }
    await t.commit();
    await bumpVersion('grammar_version');
    const full = await GrammarLesson.findByPk(lesson.id, { include: [{ model: GrammarExample, as: 'examples' }] });
    res.json(full);
  } catch (err) {
    await t.rollback();
    res.status(400).json({ error: err.message });
  }
}

async function deleteGrammar(req, res) {
  try {
    const lesson = await GrammarLesson.findByPk(req.params.id);
    if (!lesson) return res.status(404).json({ error: 'Not found' });
    await GrammarExample.destroy({ where: { grammar_lesson_id: lesson.id } });
    await lesson.destroy();
    await bumpVersion('grammar_version');
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function bulkDeleteGrammar(req, res) {
  const { ids } = req.body;
  if (!Array.isArray(ids) || ids.length === 0) return res.status(400).json({ error: 'ids 不能为空' });
  try {
    await GrammarExample.destroy({ where: { grammar_lesson_id: { [Op.in]: ids } } });
    const count = await GrammarLesson.destroy({ where: { id: { [Op.in]: ids } } });
    await bumpVersion('grammar_version');
    res.json({ deleted: count });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 听力管理 ─────────────────────────────────────────────────────────────────
async function listTracks(req, res) {
  const { level, q, page = 1, limit = 30 } = req.query;
  const where = {};
  if (level) where.jlpt_level = level;
  if (q) where[Op.or] = [{ title: { [Op.like]: `%${q}%` } }, { title_zh: { [Op.like]: `%${q}%` } }];
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await ListeningTrack.findAndCountAll({ where, limit: parseInt(limit), offset, order: [['createdAt', 'DESC']] });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function createTrack(req, res) {
  try {
    const track = await ListeningTrack.create({ id: uuidv4(), ...req.body });
    res.status(201).json(track);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

async function updateTrack(req, res) {
  try {
    const track = await ListeningTrack.findByPk(req.params.id);
    if (!track) return res.status(404).json({ error: 'Not found' });
    await track.update(req.body);
    res.json(track);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

async function deleteTrack(req, res) {
  try {
    const track = await ListeningTrack.findByPk(req.params.id);
    if (!track) return res.status(404).json({ error: 'Not found' });
    await track.destroy();
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 用户管理 ─────────────────────────────────────────────────────────────────
async function listUsers(req, res) {
  const { q, page = 1, limit = 30, role } = req.query;
  const where = {};
  if (role) where.role = role;
  if (q) {
    where[Op.or] = [
      { username: { [Op.like]: `%${q}%` } },
      { email: { [Op.like]: `%${q}%` } },
    ];
  }
  const offset = (parseInt(page) - 1) * parseInt(limit);
  try {
    const { count, rows } = await User.findAndCountAll({
      where, limit: parseInt(limit), offset,
      order: [['createdAt', 'DESC']],
      attributes: { exclude: ['password_hash'] },
    });
    res.json({ total: count, page: parseInt(page), limit: parseInt(limit), data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function updateUser(req, res) {
  try {
    const user = await User.findByPk(req.params.id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    const { is_active, role, level, daily_goal_minutes } = req.body;
    const updates = {};
    if (is_active !== undefined) updates.is_active = is_active;
    if (role !== undefined) updates.role = role;
    if (level !== undefined) updates.level = level;
    if (daily_goal_minutes !== undefined) updates.daily_goal_minutes = daily_goal_minutes;
    await user.update(updates);
    res.json({ id: user.id, username: user.username, email: user.email, role: user.role, is_active: user.is_active });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

// ─── 给用户绑定/修改会员 ────────────────────────────────────────────────────
async function updateUserMembership(req, res) {
  try {
    const user = await User.findByPk(req.params.id);
    if (!user) return res.status(404).json({ error: '用户不存在' });
    const { membership_plan, membership_expire } = req.body;
    const updates = {};
    if (membership_plan !== undefined) updates.membership_plan = membership_plan || null;
    if (membership_expire !== undefined) updates.membership_expire = membership_expire || null;
    await user.update(updates);
    res.json({ ok: true, id: user.id, username: user.username, membership_plan: user.membership_plan, membership_expire: user.membership_expire });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

// ─── 管理员权限管理 ──────────────────────────────────────────────────────────
const ADMIN_PERMISSIONS = [
  { key: 'vocabulary', name: '词汇管理', icon: '📚' },
  { key: 'grammar', name: '文法管理', icon: '📖' },
  { key: 'tracks', name: '听力管理', icon: '🎧' },
  { key: 'users', name: '用户管理', icon: '👥' },
  { key: 'stats', name: '数据分析', icon: '📈' },
  { key: 'membership', name: '会员配置', icon: '👑' },
  { key: 'sync', name: '内容同步', icon: '🔄' },
];

async function getAdminInfo(req, res) {
  const user = req.user;
  const isSuperAdmin = user.admin_level === 'super_admin';
  let permissions = null;
  try { permissions = user.permissions ? JSON.parse(user.permissions) : null; } catch { permissions = null; }
  res.json({
    ok: true,
    admin_level: user.admin_level || 'admin',
    is_super_admin: isSuperAdmin,
    permissions: isSuperAdmin ? ADMIN_PERMISSIONS.map(p => p.key) : (permissions || []),
    all_permissions: ADMIN_PERMISSIONS,
  });
}

async function listAdmins(req, res) {
  try {
    const admins = await User.findAll({
      where: { role: 'admin' },
      attributes: { exclude: ['password_hash'] },
      order: [['createdAt', 'ASC']],
    });
    res.json({ data: admins.map(a => ({ ...a.toJSON(), permissions_parsed: (() => { try { return a.permissions ? JSON.parse(a.permissions) : []; } catch { return []; } })() })), all_permissions: ADMIN_PERMISSIONS });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function updateAdminPermissions(req, res) {
  try {
    const admin = await User.findByPk(req.params.id);
    if (!admin) return res.status(404).json({ error: '管理员不存在' });
    if (admin.role !== 'admin') return res.status(400).json({ error: '该用户不是管理员' });
    if (admin.admin_level === 'super_admin') return res.status(400).json({ error: '不能修改高级管理员的权限' });
    const { permissions, admin_level } = req.body;
    const updates = {};
    if (Array.isArray(permissions)) {
      const validKeys = ADMIN_PERMISSIONS.map(p => p.key);
      const filtered = permissions.filter(p => validKeys.includes(p));
      updates.permissions = JSON.stringify(filtered);
    }
    if (admin_level !== undefined) updates.admin_level = admin_level;
    await admin.update(updates);
    res.json({ ok: true, id: admin.id, username: admin.username, admin_level: admin.admin_level, permissions: updates.permissions || admin.permissions });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

// ─── 内容版本管理 ─────────────────────────────────────────────────────────────
async function getContentVersion(req, res) {
  try {
    let cv = await ContentVersion.findByPk(1);
    if (!cv) cv = await ContentVersion.create({ id: 1, version: 1, vocab_version: 1, grammar_version: 1, updated_at_ts: Date.now() });
    res.json(cv);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function publishContent(req, res) {
  try {
    const { type = 'all' } = req.body; // 'vocab' | 'grammar' | 'all'
    let cv = await ContentVersion.findByPk(1);
    if (!cv) cv = await ContentVersion.create({ id: 1, version: 1, vocab_version: 1, grammar_version: 1, updated_at_ts: Date.now() });
    const updates = { version: cv.version + 1, updated_at_ts: Date.now() };
    if (type === 'vocab' || type === 'all') updates.vocab_version = cv.vocab_version + 1;
    if (type === 'grammar' || type === 'all') updates.grammar_version = cv.grammar_version + 1;
    await cv.update(updates);
    res.json({ ok: true, ...updates });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 统计辅助 ──────────────────────────────────────────────────────────────────
/**
 * 将 grain / start / end / date 参数归一化为 { grain, start, end }
 * grain: 'day' | 'month' | 'year'
 * 默认：过去 30 天 / day
 */
function resolveRange(query) {
  const grain  = ['day', 'month', 'year'].includes(query.grain) ? query.grain : 'day';
  let start, end;

  if (query.start && query.end) {
    start = new Date(query.start);
    end   = new Date(query.end);
    // end 取当天末尾
    end.setHours(23, 59, 59, 999);
  } else if (query.date) {
    // 单日
    start = new Date(query.date);
    end   = new Date(query.date);
    end.setHours(23, 59, 59, 999);
  } else {
    // 默认：最近 30 天
    end   = new Date();
    start = new Date(Date.now() - 29 * 86400000);
    start.setHours(0, 0, 0, 0);
  }

  if (isNaN(start) || isNaN(end)) {
    end   = new Date();
    start = new Date(Date.now() - 29 * 86400000);
  }

  return { grain, start, end };
}

/** MySQL DATE_FORMAT 格式串 */
function grainFormat(grain) {
  if (grain === 'month') return '%Y-%m';
  if (grain === 'year')  return '%Y';
  return '%Y-%m-%d';
}

// ─── 流量统计（API 请求量、响应时间、错误率）─────────────────────────────────
async function getTrafficStats(req, res) {
  try {
    const { grain, start, end } = resolveRange(req.query);
    const fmt = grainFormat(grain);

    let periodRows = [], statusDist = [], slowTop = [], hotPaths = [];
    // 按时间粒度聚合
    periodRows = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period,
              COUNT(*)                              AS total,
              SUM(status_code >= 400)               AS errors,
              ROUND(AVG(response_time_ms), 1)       AS avg_ms,
              MAX(response_time_ms)                 AS max_ms
       FROM api_logs
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period
       ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 状态码分布（整个区间）
    statusDist = await sequelize.query(
      `SELECT status_code, COUNT(*) AS count
       FROM api_logs
       WHERE created_at BETWEEN :start AND :end
       GROUP BY status_code
       ORDER BY count DESC LIMIT 20`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 最慢接口 Top10
    slowTop = await sequelize.query(
      `SELECT path, COUNT(*) AS cnt,
              ROUND(AVG(response_time_ms), 1) AS avg_ms,
              MAX(response_time_ms) AS max_ms
       FROM api_logs
       WHERE created_at BETWEEN :start AND :end
         AND response_time_ms IS NOT NULL
       GROUP BY path
       ORDER BY avg_ms DESC LIMIT 10`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 请求量 Top10 路径
    hotPaths = await sequelize.query(
      `SELECT path, COUNT(*) AS cnt
       FROM api_logs
       WHERE created_at BETWEEN :start AND :end
       GROUP BY path
       ORDER BY cnt DESC LIMIT 10`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    res.json({ grain, start, end, period: periodRows, statusDist, slowTop, hotPaths });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 用户统计（注册趋势、活跃度、级别分布）────────────────────────────────────
async function getUserStats(req, res) {
  try {
    const { grain, start, end } = resolveRange(req.query);
    const fmt = grainFormat(grain);

    // 注册趋势
    const regTrend = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period, COUNT(*) AS count
       FROM users
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 活跃用户趋势（有学习记录的唯一用户数）
    const activeTrend = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period, COUNT(DISTINCT user_id) AS count
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 全量：级别分布（尝试从 level 列，若不存在则返回空）
    let levelDist = [];
    try {
      levelDist = await sequelize.query(
        `SELECT COALESCE(level, '未设置') AS current_level, COUNT(*) AS count FROM users GROUP BY current_level ORDER BY count DESC`,
        { type: sequelize.QueryTypes.SELECT }
      );
    } catch (_e) { levelDist = []; }

    // 全量：连续打卡天数分布（尝试 streak_days 列，若不存在则返回空）
    let streakDist = [];
    try {
      streakDist = await sequelize.query(
        `SELECT
           CASE WHEN streak_days = 0       THEN '0天'
                WHEN streak_days <= 3      THEN '1-3天'
                WHEN streak_days <= 7      THEN '4-7天'
                WHEN streak_days <= 30     THEN '8-30天'
                ELSE '30天+'
           END AS bucket,
           COUNT(*) AS count
         FROM users GROUP BY bucket`,
        { type: sequelize.QueryTypes.SELECT }
      );
    } catch (_e) { streakDist = []; }

    // 区间内新增 vs 活跃汇总
    const [newUsers, activeUsers] = await Promise.all([
      sequelize.query(
        `SELECT COUNT(*) AS cnt FROM users WHERE created_at BETWEEN :start AND :end`,
        { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
      ).then(r => parseInt(r[0]?.cnt || 0)),
      sequelize.query(
        `SELECT COUNT(DISTINCT user_id) AS cnt FROM user_progress WHERE created_at BETWEEN :start AND :end`,
        { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
      ).then(r => parseInt(r[0]?.cnt || 0)),
    ]);

    res.json({ grain, start, end, regTrend, activeTrend, levelDist, streakDist, newUsers, activeUsers });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 行为统计（学习类型分布、测验得分趋势、SRS 复习趋势）────────────────────
async function getBehaviorStats(req, res) {
  try {
    const { grain, start, end } = resolveRange(req.query);
    const fmt = grainFormat(grain);

    // 学习行为按类型趋势
    const activityTrend = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period,
              activity_type,
              COUNT(*) AS count,
              SUM(duration_seconds) AS total_sec,
              SUM(xp_earned) AS total_xp
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period, activity_type
       ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 测验得分趋势
    const quizTrend = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period,
              COUNT(*) AS sessions,
              ROUND(AVG(score_percent), 1) AS avg_score,
              SUM(correct_count) AS correct,
              SUM(total_questions) AS total_q
       FROM quiz_sessions
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // SRS 复习趋势
    const srsTrend = await sequelize.query(
      `SELECT DATE_FORMAT(last_reviewed_at, :fmt) AS period,
              COUNT(*) AS reviews
       FROM srs_cards
       WHERE last_reviewed_at BETWEEN :start AND :end
       GROUP BY period ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 行为类型在整个区间内的总量分布
    const activityDist = await sequelize.query(
      `SELECT activity_type, COUNT(*) AS count, SUM(duration_seconds) AS total_sec
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY activity_type ORDER BY count DESC`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 每日平均学习时长（分钟）
    const dailyStudy = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS period,
              ROUND(SUM(duration_seconds) / GREATEST(COUNT(DISTINCT user_id), 1) / 60, 1) AS avg_min
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period ORDER BY period ASC`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    res.json({ grain, start, end, activityTrend, quizTrend, srsTrend, activityDist, dailyStudy });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 功能使用频率分析（按功能/时长统计）──────────────────────────────────────
async function getFeatureUsage(req, res) {
  try {
    const { grain, start, end } = resolveRange(req.query);
    const fmt = grainFormat(grain);

    // 各功能总使用次数 + 总时长 + 独立用户数
    const featureSummary = await sequelize.query(
      `SELECT activity_type,
              COUNT(*) AS usage_count,
              COUNT(DISTINCT user_id) AS unique_users,
              COALESCE(SUM(duration_seconds), 0) AS total_seconds,
              ROUND(COALESCE(AVG(duration_seconds), 0), 1) AS avg_seconds
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY activity_type
       ORDER BY usage_count DESC`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 各功能使用趋势
    const featureTrend = await sequelize.query(
      `SELECT DATE_FORMAT(created_at, :fmt) AS period,
              activity_type,
              COUNT(*) AS count
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY period, activity_type
       ORDER BY period ASC`,
      { replacements: { fmt, start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 用户维度：每个用户最常用功能 Top10
    const userTopFeatures = await sequelize.query(
      `SELECT u.username, up.activity_type, COUNT(*) AS cnt,
              COALESCE(SUM(up.duration_seconds), 0) AS total_sec
       FROM user_progress up
       JOIN users u ON u.id = up.user_id
       WHERE up.created_at BETWEEN :start AND :end
       GROUP BY u.username, up.activity_type
       ORDER BY cnt DESC
       LIMIT 30`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    // 时段分布（小时维度）
    const hourlyDist = await sequelize.query(
      `SELECT HOUR(created_at) AS hour, COUNT(*) AS count
       FROM user_progress
       WHERE created_at BETWEEN :start AND :end
       GROUP BY hour
       ORDER BY hour ASC`,
      { replacements: { start, end }, type: sequelize.QueryTypes.SELECT }
    );

    res.json({ grain, start, end, featureSummary, featureTrend, userTopFeatures, hourlyDist });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── 会员套餐配置（存储于 backend/config/membership.json）────────────────────
const PLANS_FILE = path.join(__dirname, '../../config/membership.json');
// ─── 功能开关配置（存储于 backend/config/feature_toggles.json）────────────
const TOGGLES_FILE = path.join(__dirname, '../../config/feature_toggles.json');
// ─── AI 设置配置（存储于 backend/config/ai_settings.json）────────────────────
const AI_SETTINGS_FILE = path.join(__dirname, '../../config/ai_settings.json');

const DEFAULT_FEATURE_TOGGLES = {
  features: [
    { id: 'vocabulary',    name: '单词学习', icon: '📖', web: true,  mobile: true  },
    { id: 'grammar',       name: '语法学习', icon: '📝', web: true,  mobile: true  },
    { id: 'listening',     name: '听力材料', icon: '🎧', web: true,  mobile: true  },
    { id: 'listening-exercise', name: '听力练习', icon: '👂', web: true,  mobile: true  },
    { id: 'srs',           name: 'SRS复习',  icon: '🗂️', web: true,  mobile: true  },
    { id: 'flashcard',     name: '闪卡练习', icon: '🃏', web: true,  mobile: true  },
    { id: 'gojuon',        name: '五十音',   icon: '🔤', web: true,  mobile: true  },
    { id: 'pronunciation', name: 'AI发音',   icon: '🎤', web: true,  mobile: true  },
    { id: 'game',          name: '助词方块', icon: '🎮', web: true,  mobile: true  },
    { id: 'game-verbs',    name: '动词方块', icon: '🎮', web: true,  mobile: true  },
    { id: 'quiz',          name: '单词随机测验', icon: '✏️', web: true,  mobile: true  },
    { id: 'todofuken',     name: '都道府県', icon: '🗾', web: true,  mobile: true  },
    { id: 'dictionary',    name: '辞书检索', icon: '🔍', web: true,  mobile: true  },
    { id: 'news',          name: 'NHK新闻',  icon: '📰', web: true,  mobile: true  },
    { id: 'anki',          name: 'Anki导入', icon: '📥', web: true,  mobile: true  },
  ],
  updated_at: null,
};

function readFeatureToggles() {
  try {
    if (fs.existsSync(TOGGLES_FILE)) {
      return JSON.parse(fs.readFileSync(TOGGLES_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  return JSON.parse(JSON.stringify(DEFAULT_FEATURE_TOGGLES));
}

async function getFeatureToggles(req, res) {
  res.json({ ok: true, ...readFeatureToggles() });
}

async function saveFeatureToggles(req, res) {
  try {
    const current = readFeatureToggles();
    const { features } = req.body;
    if (Array.isArray(features)) {
      current.features = features.map(f => ({
        id: String(f.id || ''),
        name: String(f.name || ''),
        icon: String(f.icon || ''),
        web: !!f.web,
        mobile: !!f.mobile,
      }));
    }
    current.updated_at = new Date().toISOString();
    const dir = path.dirname(TOGGLES_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(TOGGLES_FILE, JSON.stringify(current, null, 2), 'utf8');
    res.json({ ok: true, ...current });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}
const DEFAULT_MEMBERSHIP = {
  plans: [
    { id: 'free',     name: '免费版',   price: 0,   period: 'forever', description: '基础学习功能，适合入门用户',   features: ['词汇浏览 (每天50词)', '文法课程', '每日限制50道练习题'], enabled: true  },
    { id: 'monthly',  name: '月度会员', price: 18,  period: 'month',   description: '完整功能解锁，按月计费，随时取消', features: ['无限练习题', 'SRS 间隔复习', '听力课程', '离线下载'], enabled: true  },
    { id: 'yearly',   name: '年度会员', price: 128, period: 'year',    description: '全功能 + 年度优惠，比月付省41%',  features: ['无限练习题', 'SRS 间隔复习', '听力课程', '离线下载', '专属客服'], enabled: true  },
    { id: 'lifetime', name: '终身会员', price: 398, period: 'forever', description: '一次购买永久使用，含未来所有新功能', features: ['全功能永久解锁', '未来新功能免费', '专属客服', '专属徽章'], enabled: false },
  ],
  payment: {
    alipay_enabled: false,
    alipay_appid: '',
    alipay_notify_url: '',
    wechat_enabled: false,
    wechat_appid: '',
    wechat_mchid: '',
    wechat_notify_url: '',
  },
  notice: '',
};

function readMembershipConfig() {
  try {
    if (fs.existsSync(PLANS_FILE)) {
      return JSON.parse(fs.readFileSync(PLANS_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  return JSON.parse(JSON.stringify(DEFAULT_MEMBERSHIP)); // deep clone
}

async function getMembershipConfig(req, res) {
  const config = readMembershipConfig();
  // 如果数据库有数据，补充 bound_features
  try {
    await MembershipPlan.sync();
    const dbPlans = await MembershipPlan.findAll({ order: [['sort_order', 'ASC']] });
    if (dbPlans.length) {
      const dbMap = {};
      dbPlans.forEach(p => { dbMap[p.plan_id] = p; });
      config.plans.forEach(p => {
        if (dbMap[p.id]) {
          p.bound_features = dbMap[p.id].bound_features || [];
        }
      });
    }
  } catch { /* table may not exist yet */ }
  res.json(config);
}

async function saveMembershipConfig(req, res) {
  try {
    const current = readMembershipConfig();
    const { plans, payment, notice } = req.body;
    if (Array.isArray(plans)) current.plans = plans;
    if (payment && typeof payment === 'object') current.payment = { ...current.payment, ...payment };
    if (notice !== undefined) current.notice = String(notice);
    const dir = path.dirname(PLANS_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(PLANS_FILE, JSON.stringify(current, null, 2), 'utf8');

    // 同步到数据库
    if (Array.isArray(plans)) {
      await MembershipPlan.sync();
      const existingIds = (await MembershipPlan.findAll({ attributes: ['plan_id'] })).map(r => r.plan_id);
      const newIds = plans.map(p => String(p.id));
      // 删除数据库中已被移除的套餐
      const toDelete = existingIds.filter(id => !newIds.includes(id));
      if (toDelete.length) await MembershipPlan.destroy({ where: { plan_id: toDelete } });
      // upsert 所有套餐
      for (let i = 0; i < plans.length; i++) {
        const p = plans[i];
        await MembershipPlan.upsert({
          plan_id: String(p.id),
          name: String(p.name || ''),
          price: parseFloat(p.price) || 0,
          period: String(p.period || 'month'),
          description: String(p.description || ''),
          features: p.features || [],
          bound_features: p.bound_features || [],
          enabled: !!p.enabled,
          sort_order: i,
        });
      }
    }

    res.json({ ok: true, ...current });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── App 上传 ──────────────────────────────────────────────────────────────
async function uploadApp(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });
  const { version, platform, changelog } = req.body;
  if (!version || !platform) return res.status(400).json({ error: '缺少版本号或平台' });
  // multer diskStorage 已自动保存文件，req.file.filename 即磁盘文件名
  const fileUrl = `/uploads/app/${req.file.filename}`;
  const app = await AppRelease.create({
    version,
    platform,
    file_url: fileUrl,
    changelog: changelog || null,
  });
  res.json({ ok: true, app });
}

// ─── 获取所有 App 版本 ─────────────────────────────────────────────────────
async function listAppReleases(req, res) {
  const { platform } = req.query;
  const where = platform ? { platform } : {};
  const list = await AppRelease.findAll({ where, order: [['upload_time', 'DESC']] });
  res.json({ data: list });
}

// ─── 下载计数 + 重定向文件 ───────────────────────────────────────────────────
async function downloadApp(req, res) {
  const { id } = req.params;
  const app = await AppRelease.findByPk(id);
  if (!app) return res.status(404).json({ error: '未找到该版本' });
  app.download_count += 1;
  await app.save();
  // 重定向到实际文件，浏览器/App 直接下载
  res.redirect(app.file_url);
}

// ─── 删除 App 版本 ─────────────────────────────────────────────────────────
async function deleteAppRelease(req, res) {
  try {
    const app = await AppRelease.findByPk(req.params.id);
    if (!app) return res.status(404).json({ error: '未找到该版本' });
    // 删除磁盘文件
    if (app.file_url) {
      const filePath = path.join(__dirname, '../../', app.file_url);
      if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
    }
    await app.destroy();
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ─── AI 设置 ──────────────────────────────────────────────────────────────
const DEFAULT_AI_SETTINGS = {
  enabled: true,
  provider: 'deepseek',
  api_key: '',
  base_url: 'https://api.deepseek.com/v1',
  model: 'deepseek-chat',
  daily_limit: 1000,
  alert_threshold: 80,
  usage: { today_count: 0, today_date: '', total_count: 0, history: [] },
  updated_at: null,
};

function readAiSettings() {
  try {
    if (fs.existsSync(AI_SETTINGS_FILE)) {
      return JSON.parse(fs.readFileSync(AI_SETTINGS_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  return JSON.parse(JSON.stringify(DEFAULT_AI_SETTINGS));
}

function saveAiSettingsFile(data) {
  const dir = path.dirname(AI_SETTINGS_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(AI_SETTINGS_FILE, JSON.stringify(data, null, 2), 'utf8');
}

async function getAiSettings(req, res) {
  const settings = readAiSettings();
  // 遮掩 API key（仅返回末尾 4 位）
  const rawKey = settings.api_key || settings.gemini_api_key || '';
  if (rawKey) {
    settings.api_key_masked = rawKey.length > 4 ? '****' + rawKey.slice(-4) : '****';
    settings.has_key = true;
  } else {
    settings.api_key_masked = '';
    settings.has_key = false;
  }
  delete settings.api_key;
  delete settings.gemini_api_key; // 不返回原始 key
  // 检查用量告警
  const usage = settings.usage || {};
  const todayStr = new Date().toISOString().slice(0, 10);
  const todayCount = usage.today_date === todayStr ? usage.today_count : 0;
  const pct = settings.daily_limit > 0 ? Math.round(todayCount / settings.daily_limit * 100) : 0;
  settings.usage_percent = pct;
  settings.alert = pct >= (settings.alert_threshold || 80);
  settings.today_count = todayCount;
  res.json({ ok: true, ...settings });
}

async function saveAiSettings(req, res) {
  try {
    const current = readAiSettings();
    const { enabled, api_key, provider, base_url, model, daily_limit, alert_threshold } = req.body;
    if (typeof enabled === 'boolean') current.enabled = enabled;
    if (api_key !== undefined && api_key !== '') current.api_key = String(api_key);
    if (provider) current.provider = String(provider);
    if (base_url) current.base_url = String(base_url);
    if (model) current.model = String(model);
    if (daily_limit !== undefined) current.daily_limit = Math.max(0, parseInt(daily_limit, 10) || 0);
    if (alert_threshold !== undefined) current.alert_threshold = Math.min(100, Math.max(0, parseInt(alert_threshold, 10) || 80));
    current.updated_at = new Date().toISOString();
    saveAiSettingsFile(current);
    res.json({ ok: true, message: 'AI 设置已保存' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getAiUsage(req, res) {
  const settings = readAiSettings();
  const usage = settings.usage || {};
  const todayStr = new Date().toISOString().slice(0, 10);
  const todayCount = usage.today_date === todayStr ? usage.today_count : 0;
  const pct = settings.daily_limit > 0 ? Math.round(todayCount / settings.daily_limit * 100) : 0;
  res.json({
    ok: true,
    today_count: todayCount,
    daily_limit: settings.daily_limit,
    total_count: usage.total_count || 0,
    usage_percent: pct,
    alert: pct >= (settings.alert_threshold || 80),
    history: (usage.history || []).slice(-30), // 最近 30 天
  });
}

async function resetAiUsage(req, res) {
  try {
    const current = readAiSettings();
    current.usage = { today_count: 0, today_date: '', total_count: 0, history: [] };
    current.updated_at = new Date().toISOString();
    saveAiSettingsFile(current);
    res.json({ ok: true, message: '用量计数已重置' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab,
  importVocab, importVocabFile,
  listGrammar, createGrammar, updateGrammar, deleteGrammar, bulkDeleteGrammar,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser, updateUserMembership,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats, getFeatureUsage,
  getMembershipConfig, saveMembershipConfig,
  getFeatureToggles, saveFeatureToggles,
  uploadApp,
  listAppReleases,
  downloadApp,
  deleteAppRelease,
  getAiSettings, saveAiSettings, getAiUsage, resetAiUsage, readAiSettings, saveAiSettingsFile,
  listAdmins, updateAdminPermissions, getAdminInfo,
};
