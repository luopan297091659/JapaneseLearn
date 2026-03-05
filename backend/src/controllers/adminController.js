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
  AppRelease,
} = require('../models');
// utilities used across controllers
const { stripHtml } = require('../services/ankiService');

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
    const [vocabCount, grammarCount, trackCount, userCount, recentUsers] = await Promise.all([
      Vocabulary.count(),
      GrammarLesson.count(),
      ListeningTrack.count(),
      User.count(),
      User.findAll({ order: [['createdAt', 'DESC']], limit: 5, attributes: ['id', 'username', 'email', 'level', 'role', 'createdAt'] }),
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
      vocabCount, grammarCount, trackCount, userCount, activeUsers,
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

// ─── 会员套餐配置（存储于 backend/config/membership.json）────────────────────
const PLANS_FILE = path.join(__dirname, '../../config/membership.json');

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
  res.json(readMembershipConfig());
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
  // 保存文件到 uploads/app/
  const uploadDir = path.join(__dirname, '../../uploads/app');
  if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
  const ext = path.extname(req.file.originalname);
  const filename = `${platform}_${version}_${Date.now()}${ext}`;
  const filepath = path.join(uploadDir, filename);
  fs.writeFileSync(filepath, req.file.buffer);
  const fileUrl = `/uploads/app/${filename}`;
  const app = await AppRelease.create({
    version,
    platform,
    file_url: fileUrl,
    changelog,
  });
  res.json({ ok: true, app });
}

// ─── 获取所有 App 版本 ─────────────────────────────────────────────────────
async function listAppReleases(req, res) {
  const { platform } = req.query;
  const where = platform ? { platform } : {};
  const list = await AppRelease.findAll({ where, order: [['upload_time', 'DESC']] });
  res.json(list);
}

// ─── 下载计数 + 返回直链 ─────────────────────────────────────────────────────
async function downloadApp(req, res) {
  const { id } = req.params;
  const app = await AppRelease.findByPk(id);
  if (!app) return res.status(404).json({ error: '未找到该版本' });
  app.download_count += 1;
  await app.save();
  // 返回可复制的直链
  res.json({ url: app.file_url, download_count: app.download_count });
}

module.exports = {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab,
  importVocab, importVocabFile,
  listGrammar, createGrammar, updateGrammar, deleteGrammar,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats,
  getMembershipConfig, saveMembershipConfig,
  uploadApp,
  listAppReleases,
  downloadApp,
};
