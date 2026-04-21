/**
 * Admin Controller
 * 仪表板统计、词库管理、语法管理、听力管理、用户管理、内容版本同步
 */
const { Op, fn, col, literal } = require('sequelize');
const { sequelize } = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const path = require('path');
const fs = require('fs');
const axios = require('axios');
const User = require('../models/User');
const {
  Vocabulary, GrammarLesson, GrammarExample,
  ListeningTrack, UserProgress, ContentVersion, ApiLog,
  QuizSession, SrsCard,
  AppRelease, AppConfig, MembershipPlan,
  StudyPlanDailyTask, StudyPlanCardState,
} = require('../models');
const {
  getUserPreferences,
  mergeUserPreferences,
  summarizeUserPreferences,
} = require('../utils/userPreferences');
// utilities used across controllers
const { stripHtml } = require('../services/ankiService');

/** 创建带状态码的错误 */
function apiError(message, status = 400, code) {
  const err = new Error(message);
  err.status = status;
  if (code) err.code = code;
  return err;
}

// ─── 工具：读取 Kokoro TTS 配置 ──────────────────────────────────────────────
async function getKokoroConfig() {
  const defaults = { voice: 'a', emotion: 'neutral', engine: 'edge-tts', speed: 1.0 };
  try {
    const kv = await sequelize.models.AppConfig?.findOne({ where: { key: 'kokoro_tts_settings' } });
    if (kv && kv.value) {
      const c = JSON.parse(kv.value);
      return { voice: c.default_voice || 'a', emotion: c.default_emotion || 'neutral', engine: c.default_engine || 'edge-tts', speed: c.default_speed || 1.0 };
    }
  } catch (_) {}
  return defaults;
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
  const lim = Math.min(parseInt(limit) || 30, 200);
  const where = {};
  if (level) where.jlpt_level = level;
  if (category) where.category = category;
  if (q) {
    where[Op.or] = [
      { word: { [Op.like]: `%${q}%` } },
      { reading: { [Op.like]: `%${q}%` } },
      { meaning_zh: { [Op.like]: `%${q}%` } },
      { example_sentence: { [Op.like]: `%${q}%` } },
    ];
  }
  const offset = (parseInt(page) - 1) * lim;
  try {
    const { count, rows } = await Vocabulary.findAndCountAll({
      where, limit: lim, offset,
      order: [['jlpt_level', 'ASC'], ['word', 'ASC']],
    });
    res.json({ total: count, page: parseInt(page), limit: lim, data: rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function createVocab(req, res) {
  try {
    const { example_sentences, verb_forms, ...vocabData } = req.body;
    
    // 规范化例句格式
    const normalizedExamples = Array.isArray(example_sentences)
      ? example_sentences.map(ex => ({
          jp: ex.jp || ex.sentence || '',
          reading: ex.reading || '',
          zh: ex.zh || ex.meaning_zh || '',
          audio_url: ex.audio_url || null,
        })).filter(ex => ex.jp)
      : [];
    
    // 规范化动词变形格式
    const normalizedVerbForms = verb_forms && typeof verb_forms === 'object'
      ? verb_forms
      : null;

    const vocab = await Vocabulary.create({
      id: uuidv4(),
      ...vocabData,
      example_sentences: normalizedExamples.length > 0 ? normalizedExamples : null,
      verb_forms: normalizedVerbForms,
    });
    
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
    
    const { example_sentences, verb_forms, ...vocabData } = req.body;
    
    // 规范化例句格式
    const normalizedExamples = Array.isArray(example_sentences)
      ? example_sentences.map(ex => ({
          jp: ex.jp || ex.sentence || '',
          reading: ex.reading || '',
          zh: ex.zh || ex.meaning_zh || '',
          audio_url: ex.audio_url || null,
        })).filter(ex => ex.jp)
      : [];
    
    // 规范化动词变形格式
    const normalizedVerbForms = verb_forms && typeof verb_forms === 'object'
      ? verb_forms
      : null;

    await vocab.update({
      ...vocabData,
      example_sentences: normalizedExamples.length > 0 ? normalizedExamples : null,
      verb_forms: normalizedVerbForms,
    });
    
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

/** 批量生成词汇Kokoro音频 （单词本身和例句） */
async function generateVocabExamplesKokoroAudio(req, res) {
  try {
    const audioLocalizationService = require('../services/audioLocalizationService');
    const { selectedIds } = req.body || {};
    
    // 构建WHERE条件
    let vocabWhere = { audio_url: { [Op.or]: [null, ''] } };
    if (selectedIds && Array.isArray(selectedIds) && selectedIds.length > 0) {
      vocabWhere.id = { [Op.in]: selectedIds };
    }
    
    // 获取所有需要音频的词汇（无audio_url）
    const vocabs = await Vocabulary.findAll({
      where: vocabWhere,
      attributes: ['id', 'word', 'reading'],
      raw: false,
    });
    
    if (vocabs.length === 0) {
      return res.status(400).json({ error: '所有词汇都已有读音音频或未选择任何项目' });
    }
    
    // 获取所有需要音频的例句（来自VocabularyExample表）
    const VocabExample = sequelize.models.VocabularyExample;
    if (!VocabExample) {
      return res.status(400).json({ error: 'VocabularyExample model not initialized' });
    }
    
    const examples = await VocabExample.findAll({
      where: { audio_url: { [Op.or]: [null, ''] } },
      raw: false,
    });
    
    // 收集需要生成音频的文本
    const textsToGenerate = [];
    const textIndexMap = new Map();
    
    // 添加单词本身（已过滤为仅无音频的词汇）
    vocabs.forEach((v, idx) => {
      if (v.reading && v.reading.trim()) {
        textsToGenerate.push(v.reading);
        textIndexMap.set(idx, { type: 'word', id: v.id, text: v.reading });
      }
    });
    
    // 添加例句
    examples.forEach((ex, idx) => {
      if (ex.sentence && ex.sentence.trim()) {
        textsToGenerate.push(ex.sentence);
        textIndexMap.set(vocabs.length + idx, { type: 'example', id: ex.id, text: ex.sentence });
      }
    });
    
    if (textsToGenerate.length === 0) {
      return res.json({ success: true, message: '所有内容都已有音频或无有效文本', generated: 0, total: 0 });
    }
    
    // 调用批量生成API
    const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
    
    // 读取管理员配置的Kokoro参数
    const { voice: defaultVoice, emotion: defaultEmotion, engine: defaultEngine, speed: defaultSpeed } = await getKokoroConfig();
    console.log(`[Vocab Audio] 使用配置: voice=${defaultVoice}, emotion=${defaultEmotion}, engine=${defaultEngine}, speed=${defaultSpeed}`);
    
    try {
      // 计算合理的超时: 文本数量 * 5秒 + buffer
      const timeoutMs = Math.max(30000, textsToGenerate.length * 5000 + 20000);
      
      console.log(`[Vocab Audio] 调用Kokoro API生成 ${textsToGenerate.length} 条音频...`);
      const resp = await axios.post(
        `${KOKORO_SERVICE_URL}/api/v1/tts/batch-generate`,
        { texts: textsToGenerate, voice: defaultVoice, emotion: defaultEmotion, engine: defaultEngine, speed: defaultSpeed },
        { timeout: timeoutMs }
      );
      
      const results = resp.data.results || [];
      console.log(`[Vocab Audio] Kokoro返回 ${results.length} 条结果，正在下载并本地化...`);
      
      // 提取所有成功的音频URL用于下载，需要拼接完整URL
      const successfulAudioUrls = results
        .filter(r => r.success && r.audio_url)
        .map(r => {
          // r.audio_url 是相对路径，需要拼接完整URL
          const audioUrl = r.audio_url.startsWith('http') 
            ? r.audio_url 
            : `${KOKORO_SERVICE_URL}${r.audio_url}`;
          return audioUrl;
        });
      
      console.log(`[Vocab Audio] 待下载的完整URL示例: ${successfulAudioUrls[0] || 'N/A'}`);
      
      // 批量下载并本地化音频到 /uploads/audio/vocab/ 目录
      const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(successfulAudioUrls, 'vocabulary');
      const localizationMap = new Map(localizationResults.map(r => [r.originalUrl, r.localPath]));
      
      // 并发更新所有的数据库记录
      const Vocabulary = sequelize.models.Vocabulary;
      const updatePromises = [];
      const now = new Date();
      
      // 更新数据库中的音频URL（使用本地路径）
      for (let i = 0; i < results.length; i++) {
        const result = results[i];
        const info = textIndexMap.get(i);
        
        if (result && result.success && result.audio_url && info) {
          // 查询Map时也需要拼接为完整URL
          const fullUrl = result.audio_url.startsWith('http')
            ? result.audio_url
            : `${KOKORO_SERVICE_URL}${result.audio_url}`;
          const localPath = localizationMap.get(fullUrl);
          
          if (localPath) {
            if (info.type === 'word') {
              updatePromises.push(
                Vocabulary.update(
                  {
                    audio_url: localPath,
                    audio_url_type: 'kokoro',
                    audio_generated_at: now,
                    audio_expires_at: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000) // 30天后过期
                  },
                  { where: { id: info.id } }
                )
              );
            } else if (info.type === 'example') {
              updatePromises.push(
                VocabExample.update(
                  {
                    audio_url: localPath,
                    audio_url_type: 'kokoro',
                    audio_generated_at: now,
                    audio_expires_at: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
                  },
                  { where: { id: info.id } }
                )
              );
            }
          } else {
            console.warn(`[Vocab Audio] ⚠️ 找不到本地路径: result.audio_url=${result.audio_url}, fullUrl=${fullUrl}`);
          }
        }
      }
      
      // 等待所有更新完成
      const updateResults = await Promise.all(updatePromises);
      const updateCount = updateResults.length;
      
      // 更新版本号
      if (updateCount > 0) {
        await bumpVersion('vocab_version');
      }
      
      console.log(`[Vocab Audio] ✓ 完成: 生成 ${updateCount}/${textsToGenerate.length}`);
      
      res.json({
        success: true,
        message: `成功生成 ${updateCount}/${textsToGenerate.length} 个音频`,
        generated: updateCount,
        total: textsToGenerate.length,
        details: resp.data.summary
      });
    } catch (apiErr) {
      console.error('[Vocab Audio] Kokoro API调用失败:', apiErr.message);
      
      // 区分不同的错误
      if (apiErr.code === 'ECONNABORTED' || apiErr.message.includes('timeout')) {
        res.status(504).json({ error: '音频生成超时，请检查文本数量或网络连接' });
      } else if (apiErr.response?.status === 504) {
        res.status(504).json({ error: 'Kokoro TTS 服务超时' });
      } else {
        res.status(503).json({ error: 'Kokoro TTS 服务不可用: ' + apiErr.message });
      }
    }
  } catch (err) {
    console.error('[Vocab Audio] 批量生成失败:', err);
    res.status(500).json({ error: err.message });
  }
}

// ─── 词汇去重 ─────────────────────────────────────────────────────────────────
async function deduplicateVocab(req, res) {
  try {
    // 按 word + jlpt_level 分组，保留最早创建的那条
    const [dupes] = await sequelize.query(`
      SELECT v.id FROM vocabulary v
      INNER JOIN (
        SELECT word, jlpt_level, MIN(created_at) AS minCreated
        FROM vocabulary
        GROUP BY word, jlpt_level
        HAVING COUNT(*) > 1
      ) d ON v.word = d.word AND v.jlpt_level = d.jlpt_level AND v.created_at > d.minCreated
    `);

    // 跨级别去重：删除 N5 中与 N4 同 word + reading 的记录
    const [crossLevelDupes] = await sequelize.query(`
      SELECT n5.id
      FROM vocabulary n5
      WHERE n5.jlpt_level = 'N5'
        AND EXISTS (
          SELECT 1
          FROM vocabulary n4
          WHERE n4.jlpt_level = 'N4'
            AND n4.word = n5.word
            AND COALESCE(n4.reading, '') = COALESCE(n5.reading, '')
        )
    `);

    const idSet = new Set([
      ...dupes.map(r => r.id),
      ...crossLevelDupes.map(r => r.id),
    ]);
    if (idSet.size === 0) return res.json({ deleted: 0, message: '没有发现重复数据' });

    const ids = [...idSet];
    const count = await Vocabulary.destroy({ where: { id: { [Op.in]: ids } } });
    await bumpVersion('vocab_version');
    res.json({ deleted: count, message: `已删除 ${count} 条重复词汇（含 N5/N4 交叉去重）` });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// 修复 reading=word 的词汇：从 word 中提取 [假名] 拼成正确读音
async function fixVocabReadings(req, res) {
  try {
    const rows = await Vocabulary.findAll({
      where: sequelize.where(sequelize.col('reading'), sequelize.col('word')),
      attributes: ['id', 'word', 'reading'],
    });
    let fixed = 0;
    for (const row of rows) {
      const brackets = (row.word || '').match(/\[([^\]]*)\]/g);
      if (brackets && brackets.length > 0) {
        const newReading = brackets.map(b => b.slice(1, -1)).join('');
        if (newReading && newReading !== row.reading) {
          await row.update({ reading: newReading });
          fixed++;
        }
      }
    }
    if (fixed > 0) await bumpVersion('vocab_version');
    res.json({ total: rows.length, fixed, message: `已修复 ${fixed} 条词汇读音` });
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

  // 从 word 字段中提取假名读音，如 "吉[よし]野[の]山[やま]" → "よしのやま"
  function extractReading(word) {
    const w = stripHtml(String(word));
    const brackets = w.match(/\[([^\]]*)\]/g);
    if (brackets && brackets.length > 0) {
      return brackets.map(b => b.slice(1, -1)).join('');
    }
    return w; // 没有方括号标注，原样返回
  }

  const rows = cards.filter(c => c.word && String(c.word).trim()).map(c => ({
    id: uuidv4(),
    word: stripHtml(String(c.word)).substring(0, 100),
    reading: (c.reading ? stripHtml(String(c.reading)) : extractReading(c.word)).substring(0, 200),
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

// ─── 语法管理 ─────────────────────────────────────────────────────────────────
async function listGrammar(req, res) {
  const { level, q, page = 1, limit = 30 } = req.query;
  const lim = Math.min(parseInt(limit) || 30, 200);
  const where = {};
  if (level) where.jlpt_level = level;
  const offset = (parseInt(page) - 1) * lim;
  try {
    if (q) {
      // 搜索例句时先单独查出匹配的课程ID，避免 JOIN + LIMIT 导致分页按例句行数计算
      const exMatches = await GrammarExample.findAll({
        where: { [Op.or]: [
          { sentence: { [Op.like]: `%${q}%` } },
          { meaning_zh: { [Op.like]: `%${q}%` } },
        ]},
        attributes: ['grammar_lesson_id'],
        group: ['grammar_lesson_id'],
        raw: true,
      });
      const exIds = exMatches.map(r => r.grammar_lesson_id);
      where[Op.or] = [
        { title: { [Op.like]: `%${q}%` } },
        { pattern: { [Op.like]: `%${q}%` } },
        { explanation_zh: { [Op.like]: `%${q}%` } },
        ...(exIds.length > 0 ? [{ id: exIds }] : []),
      ];
    }
    const { count, rows } = await GrammarLesson.findAndCountAll({
      where, limit: lim, offset,
      include: [{ model: GrammarExample, as: 'examples', attributes: ['id', 'sentence', 'reading', 'meaning_zh', 'audio_url'] }],
      order: [['jlpt_level', 'ASC'], ['order_index', 'ASC']],
      distinct: true,
    });
    // 附加 example_count 并截取例句摘要
    const data = rows.map(r => {
      const j = r.toJSON();
      j.example_count = (j.examples || []).length;
      j.example_summary = (j.examples || []).slice(0, 2).map(e => e.sentence).join('；');
      return j;
    });
    res.json({ total: count, page: parseInt(page), limit: lim, data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getGrammar(req, res) {
  try {
    const lesson = await GrammarLesson.findByPk(req.params.id, {
      include: [{ model: GrammarExample, as: 'examples', attributes: ['id', 'sentence', 'reading', 'meaning_zh', 'audio_url'] }],
    });
    if (!lesson) return res.status(404).json({ error: 'Not found' });
    res.json(lesson);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function createGrammar(req, res) {
  const t = await sequelize.transaction();
  try {
    const { examples = [], ...lessonData } = req.body;
    const lesson = await GrammarLesson.create({ id: uuidv4(), ...lessonData }, { transaction: t });
    if (examples.length) {
      await GrammarExample.bulkCreate(examples.map(ex => ({ id: uuidv4(), grammar_lesson_id: lesson.id, ...ex })), { transaction: t });
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
      if (examples.length) {
        await GrammarExample.bulkCreate(examples.map(ex => ({ id: uuidv4(), grammar_lesson_id: lesson.id, ...ex })), { transaction: t });
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
  const t = await sequelize.transaction();
  try {
    const lesson = await GrammarLesson.findByPk(req.params.id, { transaction: t });
    if (!lesson) { await t.rollback(); return res.status(404).json({ error: 'Not found' }); }
    await GrammarExample.destroy({ where: { grammar_lesson_id: lesson.id }, transaction: t });
    await lesson.destroy({ transaction: t });
    await t.commit();
    await bumpVersion('grammar_version');
    res.json({ ok: true });
  } catch (err) {
    await t.rollback();
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

/** 批量生成语法例句Kokoro音频 */
async function generateGrammarExamplesKokoroAudio(req, res) {
  try {
    const audioLocalizationService = require('../services/audioLocalizationService');
    const { grammar_ids } = req.body;
    
    // 获取所有待处理的语法
    const grammars = await GrammarLesson.findAll({
      where: grammar_ids ? { id: { [Op.in]: grammar_ids } } : {},
      include: [{ model: GrammarExample, as: 'examples' }],
      raw: false,
    });
    
    if (grammars.length === 0) {
      return res.status(400).json({ error: '未找到语法数据' });
    }
    
    // 收集所有需要音频的例句
    const examplesNeedingAudio = [];
    grammars.forEach(g => {
      if (g.examples && Array.isArray(g.examples)) {
        g.examples.forEach(ex => {
          if (!ex.audio_url || ex.audio_url.trim() === '') {
            examplesNeedingAudio.push({
              id: ex.id,
              sentence: ex.sentence,
              grammar_id: g.id,
            });
          }
        });
      }
    });
    
    if (examplesNeedingAudio.length === 0) {
      return res.json({ success: true, message: '所有例句都已有音频', updated: 0, total: 0 });
    }
    
    // 调用批量生成API
    const axios = require('axios');
    const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
    
    const texts = examplesNeedingAudio.map(e => e.sentence);
    
    // 读取管理员配置的Kokoro参数
    const { voice: defaultVoice, emotion: defaultEmotion, engine: defaultEngine, speed: defaultSpeed } = await getKokoroConfig();
    console.log(`[Grammar Audio] 使用配置: voice=${defaultVoice}, emotion=${defaultEmotion}, engine=${defaultEngine}, speed=${defaultSpeed}`);
    
    try {
      // 计算合理的超时: 文本数量 * 5秒 + buffer
      const timeoutMs = Math.max(30000, examplesNeedingAudio.length * 5000 + 20000);
      
      console.log(`[Grammar Audio] 调用Kokoro API生成 ${examplesNeedingAudio.length} 条音频...`);
      const resp = await axios.post(
        `${KOKORO_SERVICE_URL}/api/v1/tts/batch-generate`,
        { texts, voice: defaultVoice, emotion: defaultEmotion, engine: defaultEngine, speed: defaultSpeed },
        { timeout: timeoutMs }
      );
      
      const results = resp.data.results || [];
      console.log(`[Grammar Audio] Kokoro返回 ${results.length} 条结果，正在下载并本地化...`);
      
      // 提取所有成功的音频URL用于下载，需要拼接完整URL
      const successfulAudioUrls = results
        .filter(r => r.success && r.audio_url)
        .map(r => {
          // r.audio_url 是相对路径，需要拼接完整URL
          const audioUrl = r.audio_url.startsWith('http') 
            ? r.audio_url 
            : `${KOKORO_SERVICE_URL}${r.audio_url}`;
          return audioUrl;
        });
      
      console.log(`[Grammar Audio] 待下载的完整URL示例: ${successfulAudioUrls[0] || 'N/A'}`);
      
      // 批量下载并本地化音频到 /uploads/grammar/audio/ 目录
      const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(successfulAudioUrls, 'grammar');
      const localizationMap = new Map(localizationResults.map(r => [r.originalUrl, r.localPath]));
      
      // 并发更新所有的数据库记录
      const updatePromises = [];
      const now = new Date();
      
      for (let i = 0; i < examplesNeedingAudio.length; i++) {
        const example = examplesNeedingAudio[i];
        const result = results[i];
        
        if (result && result.success && result.audio_url) {
          // 查询Map时也需要拼接为完整URL
          const fullUrl = result.audio_url.startsWith('http')
            ? result.audio_url
            : `${KOKORO_SERVICE_URL}${result.audio_url}`;
          const localPath = localizationMap.get(fullUrl);
          
          if (localPath) {
            // 并发执行所有数据库更新
            updatePromises.push(
              GrammarExample.update(
                {
                  audio_url: localPath,
                  audio_url_type: 'kokoro',
                  audio_generated_at: now,
                  audio_expires_at: new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000) // 30天后过期
                },
                { where: { id: example.id } }
              )
            );
          } else {
            console.warn(`[Grammar Audio] ⚠️ 找不到本地路径: result.audio_url=${result.audio_url}, fullUrl=${fullUrl}`);
          }
        }
      }
      
      // 等待所有更新完成
      const updateResults = await Promise.all(updatePromises);
      const updateCount = updateResults.length;
      
      // 更新版本号
      if (updateCount > 0) {
        await bumpVersion('grammar_version');
      }
      
      console.log(`[Grammar Audio] ✓ 完成: 生成 ${updateCount}/${examplesNeedingAudio.length}`);
      
      res.json({
        success: true,
        message: `成功生成 ${updateCount}/${examplesNeedingAudio.length} 个音频`,
        generated: updateCount,
        total: examplesNeedingAudio.length,
        details: resp.data.summary
      });
    } catch (apiErr) {
      console.error('[Grammar Audio] Kokoro API调用失败:', apiErr.message);
      
      // 区分不同的错误
      if (apiErr.code === 'ECONNABORTED' || apiErr.message.includes('timeout')) {
        res.status(504).json({ error: '音频生成超时，请检查文本数量或网络连接' });
      } else if (apiErr.response?.status === 504) {
        res.status(504).json({ error: 'Kokoro TTS 服务超时' });
      } else {
        res.status(503).json({ error: 'Kokoro TTS 服务不可用: ' + apiErr.message });
      }
    }
  } catch (err) {
    console.error('[Grammar Audio]批量生成失败:', err);
    res.status(500).json({ error: err.message });
  }
}

// ─── Anki Apkg 导入语法 ──────────────────────────────────────────────────────
const AdmZip = require('adm-zip');
const { getSqlJs, detectMapping } = require('../services/ankiService');

async function importGrammarApkg(req, res) {
  if (!req.file) return res.status(400).json({ error: '未上传文件' });

  const audioDir = path.join(__dirname, '../../uploads/audio/grammar');
  if (!fs.existsSync(audioDir)) fs.mkdirSync(audioDir, { recursive: true });

  try {
    // 1. 解压 apkg 文件
    const zip = new AdmZip(req.file.buffer);
    const collectionEntry = zip.getEntry('collection.anki2');
    if (!collectionEntry) {
      return res.status(400).json({ error: 'apkg 文件损坏：未找到 collection.anki2' });
    }

    // 2. 解析 Anki 数据库
    const SQL = await getSqlJs();
    const dbData = collectionEntry.getData();
    const db = new SQL.Database(new Uint8Array(dbData));

    // 获取 notes 表
    const notesResult = db.exec('SELECT * FROM notes');
    if (!notesResult || notesResult.length === 0) {
      return res.status(400).json({ error: 'apkg 文件中无有效 notes 数据' });
    }

    const columns = notesResult[0].columns;
    const values = notesResult[0].values;
    const mapping = detectMapping(columns);

    // 检查媒体索引
    const mediaEntry = zip.getEntry('media');
    let mediaIndex = {};
    if (mediaEntry) {
      try {
        const mediaStr = mediaEntry.getData().toString('utf-8');
        mediaIndex = JSON.parse(mediaStr);
      } catch (e) {
        console.warn('Failed to parse media index:', e);
      }
    }

    let lessonCreated = 0, exampleCreated = 0, audioCount = 0;
    const audioMap = {}; // 记录已保存的音频文件，避免重复

    // 3. 处理每个 note
    for (const noteValues of values) {
      try {
        const patternField = noteValues[mapping.pattern ?? 0] || '';
        const explanationField = noteValues[mapping.explanation ?? 1] || '';
        const explanationZhField = noteValues[mapping.explanation_zh ?? 2] || '';
        const exampleField = noteValues[mapping.example ?? 3] || '';

        // 清理 HTML 和音频标签
        const pattern = stripHtml(String(patternField)).trim();
        const explanation = stripHtml(String(explanationField)).trim();
        const explanation_zh = stripHtml(String(explanationZhField)).trim();
        const exampleRaw = String(exampleField);

        if (!pattern) continue;

        // 4. 创建或获取语法课程
        const [lesson] = await GrammarLesson.findOrCreate({
          where: { pattern },
          defaults: {
            id: uuidv4(),
            pattern,
            title: pattern,
            title_zh: pattern,
            explanation: explanation || null,
            explanation_zh: explanation_zh || null,
            jlpt_level: 'N3',
            order_index: 0,
          },
        });

        // 5. 处理例句（可能包含音频）
        if (exampleRaw && exampleRaw.trim()) {
          // 提取 [sound:xxx] 标签
          const soundMatches = exampleRaw.match(/\[sound:([^\]]+)\]/g) || [];
          const soundFiles = soundMatches.map(s => s.match(/\[sound:([^\]]+)\]/)[1]);

          const sentenceClean = stripHtml(exampleRaw.replace(/\[sound:[^\]]+\]/g, '')).trim();
          if (sentenceClean) {
            let audioUrl = null;

            // 6. 处理音频文件
            if (soundFiles.length > 0) {
              for (const soundFile of soundFiles) {
                const mediaEntry = zip.getEntry(soundFile);
                if (mediaEntry) {
                  const audioData = mediaEntry.getData();
                  let audioFilename = audioMap[soundFile];

                  if (!audioFilename) {
                    // 生成唯一的文件名
                    const ext = path.extname(soundFile) || '.mp3';
                    audioFilename = `grammar_${Date.now()}_${Math.random().toString(36).slice(2)}${ext}`;
                    const audioPath = path.join(audioDir, audioFilename);
                    fs.writeFileSync(audioPath, audioData);
                    audioMap[soundFile] = audioFilename;
                    audioCount++;
                  }

                  audioUrl = `/audio/grammar/${audioFilename}`;
                  break; // 只使用第一个音频
                }
              }
            }

            // 7. 创建例句
            await GrammarExample.findOrCreate({
              where: {
                grammar_lesson_id: lesson.id,
                sentence: sentenceClean,
              },
              defaults: {
                id: uuidv4(),
                grammar_lesson_id: lesson.id,
                sentence: sentenceClean,
                reading: null,
                meaning_zh: null,
                audio_url: audioUrl,
              },
            });

            exampleCreated++;
          }
        }

        lessonCreated++;
      } catch (e) {
        console.warn('Failed to import note:', e);
      }
    }

    // 8. 递增语法版本
    await bumpVersion('grammar_version');

    res.json({
      ok: true,
      message: `导入成功：${lessonCreated} 个课程，${exampleCreated} 个例句，${audioCount} 个音频文件`,
      stats: {
        lessons: lessonCreated,
        examples: exampleCreated,
        audios: audioCount,
      },
    });
  } catch (err) {
    console.error('Grammar import error:', err);
    res.status(500).json({ error: err.message });
  }
}

// ─── Kokoro 生成语法例句音频 ────────────────────────────────────────────────
async function generateGrammarExampleAudio(req, res) {
  const { lessonId, exId } = req.params;
  
  try {
    // 1. 检查例句是否存在
    const example = await GrammarExample.findOne({
      where: { id: exId, grammar_lesson_id: lessonId },
    });
    
    if (!example) {
      return res.status(404).json({ error: '例句不存在' });
    }
    
    // 2. 获取管理员配置的 Kokoro 参数
    const { voice: defaultVoice, emotion: defaultEmotion, engine: defaultEngine, speed: defaultSpeed } = await getKokoroConfig();
    
    // 3. 调用 Kokoro TTS 服务生成音频
    const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
    const grammarAudioDir = path.join(__dirname, '../../uploads/grammar/audio');
    if (!fs.existsSync(grammarAudioDir)) {
      fs.mkdirSync(grammarAudioDir, { recursive: true });
    }
    
    try {
      const ttsResponse = await axios.post(
        `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
        {
          text: example.sentence,
          voice: defaultVoice,
          emotion: defaultEmotion,
          engine: defaultEngine,
          speed: defaultSpeed,
        },
        { timeout: 30000 }
      );
      
      // 获得Kokoro返回的相对URL: /api/v1/tts/kokoro/audio/kokoro_abc123.wav
      const kokoroAudioUrl = ttsResponse.data.audio_url;
      
      let savedAudioUrl = null;
      
      if (kokoroAudioUrl) {
        try {
          // 从Kokoro服务下载音频文件
          const audioResponse = await axios.get(
            `${KOKORO_SERVICE_URL}${kokoroAudioUrl}`,
            { responseType: 'arraybuffer', timeout: 10000 }
          );
          
          // 提取文件名 (e.g., kokoro_abc123.wav)
          const filename = path.basename(kokoroAudioUrl);
          const audioFilePath = path.join(grammarAudioDir, filename);
          
          // 保存到本地磁盘
          fs.writeFileSync(audioFilePath, audioResponse.data);
          
          // 保存相对URL到数据库
          savedAudioUrl = `/uploads/grammar/audio/${filename}`;
          
          // 更新数据库
          await example.update({ audio_url: savedAudioUrl });
          
          res.json({
            ok: true,
            example: example.toJSON(),
            audio_url: savedAudioUrl,
            message: '音频生成成功',
          });
          
          console.log(`[Grammar Audio] 生成成功: lesson_id=${lessonId}, example_id=${exId}, audio_url=${savedAudioUrl}, file_size=${audioResponse.data.length} bytes`);
        } catch (fileError) {
          console.error('[Grammar Audio] 文件保存失败:', fileError.message);
          return res.status(500).json({ error: '音频文件保存失败: ' + fileError.message });
        }
      } else {
        return res.status(500).json({ error: 'Kokoro未返回有效的音频URL' });
      }
    } catch (kokoroError) {
      console.error('[Kokoro] 音频生成失败:', kokoroError.message);
      
      if (kokoroError.code === 'ECONNREFUSED') {
        return res.status(503).json({ error: 'Kokoro 服务不可用', code: 'KOKORO_UNAVAILABLE' });
      } else if (kokoroError.response?.status) {
        return res.status(kokoroError.response.status).json({
          error: '音频生成失败',
          details: kokoroError.response.data
        });
      } else {
        return res.status(500).json({ error: '音频生成失败: ' + kokoroError.message });
      }
    }
  } catch (err) {
    console.error('[Grammar Audio] 操作失败:', err);
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
  const { q, page = 1, limit = 30, role, sort, order, min_invite, membership } = req.query;
  const lim = Math.min(parseInt(limit) || 30, 200);
  const where = {};
  if (role) where.role = role;
  if (membership === 'none') {
    where.membership_plan = null;
  } else if (membership === 'trial') {
    where.membership_plan = 'trial';
  } else if (membership === 'active') {
    where.membership_plan = { [Op.ne]: null };
    where.membership_expire = { [Op.gt]: new Date() };
  } else if (membership === 'expired') {
    where.membership_plan = { [Op.ne]: null };
    where.membership_expire = { [Op.lt]: new Date() };
  }
  if (q) {
    where[Op.or] = [
      { username: { [Op.like]: `%${q}%` } },
      { email: { [Op.like]: `%${q}%` } },
    ];
  }
  // 非超级管理员不能看到其他管理员
  if (!req.isSuperAdmin) {
    where.admin_level = { [Op.or]: [null, { [Op.ne]: 'super_admin' }] };
  }
  const offset = (parseInt(page) - 1) * lim;
  try {
    const { count, rows } = await User.findAndCountAll({
      where, limit: lim, offset,
      order: [['createdAt', 'DESC']],
      attributes: { exclude: ['password_hash'] },
    });
    // 批量查询每个用户的邀请人数
    const userIds = rows.map(r => r.id);
    const inviteCounts = await User.findAll({
      where: { invited_by: { [Op.in]: userIds } },
      attributes: ['invited_by', [require('sequelize').fn('COUNT', require('sequelize').col('id')), 'cnt']],
      group: ['invited_by'],
      raw: true,
    });
    const inviteMap = {};
    inviteCounts.forEach(r => { inviteMap[r.invited_by] = parseInt(r.cnt); });
    const data = rows.map((row) => {
      const json = row.toJSON ? row.toJSON() : row;
      return {
        ...json,
        invite_count: inviteMap[row.id] || 0,
        preferences: json.preferences || getUserPreferences(json),
        preference_summary: json.preference_summary || summarizeUserPreferences(json.preferences || getUserPreferences(json)),
      };
    });
    // 支持按邀请数排序（内存排序，因为是计算字段）
    if (sort === 'invite_count') {
      data.sort((a, b) => order === 'asc' ? a.invite_count - b.invite_count : b.invite_count - a.invite_count);
    }
    // 支持按最小邀请数筛选
    const filteredData = min_invite ? data.filter(u => u.invite_count >= parseInt(min_invite)) : data;
    res.json({ total: min_invite ? filteredData.length : count, page: parseInt(page), limit: lim, data: filteredData });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function updateUser(req, res) {
  try {
    const user = await User.findByPk(req.params.id);
    if (!user) return res.status(404).json({ error: 'Not found' });
    // 非超级管理员不能修改管理员用户
    if (!req.isSuperAdmin && (user.role === 'admin' || user.admin_level === 'super_admin')) {
      return res.status(403).json({ error: '权限不足，不能修改管理员用户' });
    }
    const { is_active, role, level, daily_goal_minutes, notification_enabled, preferences } = req.body;
    const updates = {};
    if (is_active !== undefined) updates.is_active = is_active;
    // 非超级管理员不能设置角色为 admin
    if (role !== undefined) {
      if (role === 'admin' && !req.isSuperAdmin) return res.status(403).json({ error: '权限不足，不能授予管理员角色' });
      updates.role = role;
    }
    if (level !== undefined) updates.level = level;
    if (daily_goal_minutes !== undefined) updates.daily_goal_minutes = daily_goal_minutes;
    if (notification_enabled !== undefined) updates.notification_enabled = notification_enabled;
    await user.update(updates);

    if (daily_goal_minutes !== undefined || notification_enabled !== undefined || (preferences && typeof preferences === 'object')) {
      const mergedPreferences = mergeUserPreferences(user, {
        ...(daily_goal_minutes !== undefined ? { daily_goal_minutes } : {}),
        ...(notification_enabled !== undefined ? { notification_enabled } : {}),
        ...(preferences && typeof preferences === 'object' ? preferences : {}),
      });
      await user.update({
        daily_goal_minutes: mergedPreferences.daily_goal_minutes,
        notification_enabled: mergedPreferences.notification_enabled,
        preferences_json: JSON.stringify(mergedPreferences),
      });
    }

    await user.reload();
    const json = user.toJSON ? user.toJSON() : user;
    res.json(json);
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

// ─── 高级管理员重置用户密码 ─────────────────────────────────────────────────
async function resetUserPassword(req, res) {
  try {
    const user = await User.findByPk(req.params.id);
    if (!user) return res.status(404).json({ error: '用户不存在' });
    const { new_password } = req.body;
    if (!new_password || new_password.length < 6) {
      return res.status(400).json({ error: '密码长度至少6位' });
    }
    // password_hash 的 beforeUpdate hook 会自动 bcrypt hash
    await user.update({ password_hash: new_password });
    res.json({ ok: true, message: '密码已重置' });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
}

// ─── 管理员权限管理 ──────────────────────────────────────────────────────────
const ADMIN_PERMISSIONS = [
  { key: 'vocabulary', name: '词汇管理', icon: '📚' },
  { key: 'grammar', name: '语法管理', icon: '📖' },
  { key: 'tracks', name: '听力管理', icon: '🎧' },
  { key: 'users', name: '用户管理', icon: '👥' },
  { key: 'reports', name: '问题反馈', icon: '🐛' },
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

function incrementCounter(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function mapToCountArray(map, keyName = 'label') {
  return Array.from(map.entries())
    .map(([label, count]) => ({ [keyName]: label, count }))
    .sort((a, b) => b.count - a.count);
}

function dailyGoalBucket(minutes) {
  if (minutes <= 15) return '15分钟内';
  if (minutes <= 30) return '16-30分钟';
  if (minutes <= 60) return '31-60分钟';
  return '60分钟以上';
}

function slowSpeedBucket(speed) {
  if (speed <= 0.4) return '0.20-0.40x';
  if (speed <= 0.55) return '0.41-0.55x';
  if (speed <= 0.7) return '0.56-0.70x';
  return '0.71-0.80x';
}

function localeLabel(locale) {
  return { zh: '中文', en: 'English', ja: '日本語' }[locale] || locale || '未知';
}

function appearanceLabel(mode) {
  return mode === 'anime' ? '蓝调' : '经典';
}

function buildPreferenceStats(rows) {
  const localeDist = new Map();
  const appearanceDist = new Map();
  const slowSpeedDist = new Map();
  const dailyGoalDist = new Map();
  const notificationDist = new Map();
  let syncedUsers = 0;

  for (const row of rows) {
    const pref = getUserPreferences(row);
    if (row.preferences_json) syncedUsers += 1;
    incrementCounter(localeDist, localeLabel(pref.locale));
    incrementCounter(appearanceDist, appearanceLabel(pref.appearance_mode));
    incrementCounter(slowSpeedDist, slowSpeedBucket(pref.slow_speed));
    incrementCounter(dailyGoalDist, dailyGoalBucket(pref.daily_goal_minutes));
    incrementCounter(notificationDist, pref.notification_enabled ? '已开启' : '已关闭');
  }

  return {
    syncedUsers,
    localeDist: mapToCountArray(localeDist, 'locale'),
    appearanceDist: mapToCountArray(appearanceDist, 'mode'),
    slowSpeedDist: mapToCountArray(slowSpeedDist, 'bucket'),
    dailyGoalDist: mapToCountArray(dailyGoalDist, 'bucket'),
    notificationDist: mapToCountArray(notificationDist, 'label'),
  };
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

    // 偏好习惯统计
    const preferenceRows = await User.findAll({
      attributes: ['preferences_json', 'daily_goal_minutes', 'notification_enabled'],
      raw: true,
    });
    const preferenceStats = buildPreferenceStats(preferenceRows);

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

    res.json({
      grain,
      start,
      end,
      regTrend,
      activeTrend,
      levelDist,
      streakDist,
      newUsers,
      activeUsers,
      preferenceStats: {
        ...preferenceStats,
        totalUsers: preferenceRows.length,
        syncRate: preferenceRows.length
          ? Math.round((preferenceStats.syncedUsers / preferenceRows.length) * 100)
          : 0,
      },
    });
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
// ─── 功能分级配置（存储于 backend/config/feature_tiers.json）────────────────
const TIERS_FILE = path.join(__dirname, '../../config/feature_tiers.json');
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
    { id: 'quiz',          name: '单词测验', icon: '✏️', web: true,  mobile: true  },
    { id: 'todofuken',     name: '都道府県', icon: '🗾', web: true,  mobile: true  },
    { id: 'dictionary',    name: '辞书检索', icon: '🔍', web: true,  mobile: true  },
    { id: 'news',          name: 'NHK新闻',  icon: '📰', web: true,  mobile: true  },
    { id: 'anki',          name: 'Anki导入', icon: '📥', web: false, mobile: true  },
    { id: 'translate',     name: '翻译解析', icon: '🌐', web: true,  mobile: true  },
    { id: 'localvocab',    name: 'Anki词库', icon: '📂', web: false, mobile: true  },
    { id: 'wrong-answers', name: '错题集',   icon: '📋', web: false, mobile: true  },
    { id: 'grammar-quiz',  name: '语法测验', icon: '📖', web: true,  mobile: true  },
    { id: 'immersion',     name: '磨耳朵',   icon: '📺', web: false, mobile: true  },
    { id: 'kana-writing-test', name: '假名书写', icon: '✍️', web: false, mobile: true  },
    { id: 'study-plan',    name: '学习计划', icon: '📅', web: true,  mobile: true  },
  ],
  updated_at: null,
};

function readFeatureToggles() {
  let data;
  try {
    if (fs.existsSync(TOGGLES_FILE)) {
      data = JSON.parse(fs.readFileSync(TOGGLES_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  if (!data) return JSON.parse(JSON.stringify(DEFAULT_FEATURE_TOGGLES));
  // 自动合并新增的默认功能开关
  const saved = data.features || [];
  const savedIds = new Set(saved.map(f => f.id));
  for (const def of DEFAULT_FEATURE_TOGGLES.features) {
    if (!savedIds.has(def.id)) saved.push({ ...def });
  }
  data.features = saved;
  return data;
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

// ─── 功能分级配置 ──────────────────────────────────────────────────────────
const DEFAULT_FEATURE_TIERS = {
  tiers: [
    { id: 'grammar_lessons', name: '语法课程', icon: '📝', type: 'limit', free_limit: 5, free_label: '前5课免费', member_label: '全部' },
    { id: 'srs_daily', name: 'SRS复习', icon: '🗂️', type: 'daily_limit', free_limit: 30, free_label: '每日限30张', member_label: '无限制' },
    { id: 'listening_daily', name: '听力训练', icon: '🎧', type: 'daily_limit', free_limit: 3, free_label: '每日3个', member_label: '无限制' },
    { id: 'listening_exercise_daily', name: '听力测验', icon: '📝', type: 'daily_limit', free_limit: 10, free_label: '每日10题', member_label: '无限制' },
    { id: 'immersion_daily', name: '磨耳朵', icon: '👂', type: 'daily_limit', free_limit: 3, free_label: '每日3个', member_label: '无限制' },
    { id: 'ai_features', name: 'AI功能(翻译/解析)', icon: '🤖', type: 'blocked', free_label: '不可用', member_label: '可用' },
    { id: 'pronunciation', name: '发音训练', icon: '🎤', type: 'blocked', free_label: '不可用', member_label: '可用' },
    { id: 'anki_import', name: 'Anki导入', icon: '📥', type: 'blocked', free_label: '不可用', member_label: '可用' },
    { id: 'game_levels', name: '游戏模式', icon: '🎮', type: 'limit', free_limit: 5, free_label: '前5关', member_label: '全部' },
    { id: 'quiz_meaning_daily', name: '词汇测验(意思题)', icon: '✏️', type: 'daily_limit', free_limit: 10, free_label: '每日10题', member_label: '无限制' },
    { id: 'quiz_reading_daily', name: '词汇测验(读音题)', icon: '📖', type: 'daily_limit', free_limit: 10, free_label: '每日10题', member_label: '无限制' },
    { id: 'quiz_jlpt_levels', name: 'JLPT等级筛选', icon: '🏅', type: 'enum', free_values: ['N5','N4'], member_values: ['N5','N4','N3','N2','N1'], free_label: 'N5 / N4', member_label: 'N5~N1 全部' },
    { id: 'quiz_count_options', name: '题目数量选择', icon: '🔢', type: 'enum', free_values: [10], member_values: [10,20,30], free_label: '仅10题', member_label: '无限制' },
    { id: 'kana_writing_modes', name: '假名手写测试', icon: '✍️', type: 'enum', free_values: ['basic'], member_values: ['basic','dakuon','mixed'], free_label: '基础清音', member_label: '全部(浊音/混合)' },
    { id: 'flashcard_levels', name: '闪卡复习', icon: '🃏', type: 'enum', free_values: ['N5'], member_values: ['N5','N4','N3','N2','N1'], free_label: 'N5', member_label: '全等级' },
    { id: 'anki_quiz', name: 'Anki本地卡组测验', icon: '📋', type: 'blocked', free_label: '不可用', member_label: '可用' },
    { id: 'wrong_answers', name: '错题集', icon: '📝', type: 'blocked', free_label: '不可用', member_label: '可用' },
    { id: 'grammar_quiz_daily', name: '语法测验', icon: '📖', type: 'daily_limit', free_limit: 10, free_label: '每日10题', member_label: '无限制' },
    { id: 'dictionary_daily', name: '词典查询', icon: '🔍', type: 'daily_limit', free_limit: 20, free_label: '每日限20次', member_label: '无限制' },
    { id: 'news_limit', name: 'NHK新闻', icon: '📰', type: 'limit', free_limit: 5, free_label: '最新5篇', member_label: '全部' },
    { id: 'study_plan_daily', name: '学习计划', icon: '📅', type: 'daily_limit', free_limit: 10, free_label: '每日10张', member_label: '无限制' },
  ],
  updated_at: null,
};

function readFeatureTiers() {
  try {
    if (fs.existsSync(TIERS_FILE)) {
      return JSON.parse(fs.readFileSync(TIERS_FILE, 'utf8'));
    }
  } catch { /* ignore */ }
  return JSON.parse(JSON.stringify(DEFAULT_FEATURE_TIERS));
}

async function getFeatureTiers(req, res) {
  res.json({ ok: true, ...readFeatureTiers() });
}

async function saveFeatureTiers(req, res) {
  try {
    const { tiers } = req.body;
    if (!Array.isArray(tiers)) return res.status(400).json({ error: '参数 tiers 必须为数组' });
    const data = {
      tiers: tiers.map(t => ({
        id: String(t.id || ''),
        name: String(t.name || ''),
        icon: String(t.icon || ''),
        type: String(t.type || 'blocked'),
        ...(t.type === 'daily_limit' || t.type === 'limit' ? { free_limit: parseInt(t.free_limit) || 0 } : {}),
        ...(t.type === 'enum' ? { free_values: t.free_values || [], member_values: t.member_values || [] } : {}),
        free_label: String(t.free_label || ''),
        member_label: String(t.member_label || ''),
      })),
      updated_at: new Date().toISOString(),
    };
    const dir = path.dirname(TIERS_FILE);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(TIERS_FILE, JSON.stringify(data, null, 2), 'utf8');
    res.json({ ok: true, ...data });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

const DEFAULT_MEMBERSHIP = {
  plans: [
    { id: 'free',     name: '免费版',   price: 0,   period: 'forever', description: '基础学习功能，适合入门用户',   features: ['词汇学习', '语法学习', '听力训练', 'NHK新闻'], enabled: true  },
    { id: 'monthly',  name: '月度会员', price: 18,  period: 'month',   description: '完整功能解锁，按月计费，随时取消', features: ['发音训练', '错题集', '学习计划', 'AI翻译'], enabled: true  },
    { id: 'yearly',   name: '年度会员', price: 128, period: 'year',    description: '全功能 + 年度优惠，比月付省22%',  features: ['无限练习题', 'SRS 间隔复习', '听力课程', '离线下载'], enabled: true  },
    { id: 'lifetime', name: '终身会员', price: 398, period: 'forever', description: '一次购买永久使用，含未来所有新功能', features: ['全功能永久解锁', '未来新功能免费', '专属徽章'], enabled: false },
  ],
  trial: {
    enabled: true,
    days: 3,
    description: '免费体验全部会员功能',
  },
  payment: {
    alipay_enabled: false,
    alipay_appid: '',
    alipay_notify_url: '',
    wechat_enabled: false,
    wechat_appid: '',
    wechat_mchid: '',
    wechat_notify_url: '',
    stripe_enabled: false,
    stripe_secret_key: '',
    stripe_webhook_secret: '',
    stripe_currency: 'cny',
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
          let bf = dbMap[p.id].bound_features || [];
          if (typeof bf === 'string') { try { bf = JSON.parse(bf); } catch { bf = []; } }
          p.bound_features = Array.isArray(bf) ? bf : [];
        }
      });
    }
  } catch { /* table may not exist yet */ }
  res.json(config);
}

async function saveMembershipConfig(req, res) {
  try {
    const current = readMembershipConfig();
    const { plans, payment, notice, trial } = req.body;
    if (Array.isArray(plans)) current.plans = plans;
    if (payment && typeof payment === 'object') current.payment = { ...current.payment, ...payment };
    if (notice !== undefined) current.notice = String(notice);
    if (trial && typeof trial === 'object') {
      current.trial = {
        enabled: !!trial.enabled,
        days: Math.max(1, Math.min(30, parseInt(trial.days) || 3)),
        description: String(trial.description || '').slice(0, 200),
      };
    }
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
          apple_product_id: p.apple_product_id || null,
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
    is_published: false,
    published_at: null,
  });
  res.json({ ok: true, app });
}

// ─── 获取所有 App 版本 ─────────────────────────────────────────────────────
async function listAppReleases(req, res) {
  const { platform } = req.query;
  const where = platform ? { platform } : {};
  const list = await AppRelease.findAll({ where, order: [['is_published', 'DESC'], ['published_at', 'DESC'], ['upload_time', 'DESC']] });
  res.json({ data: list });
}

async function publishAppRelease(req, res) {
  const app = await AppRelease.findByPk(req.params.id);
  if (!app) return res.status(404).json({ error: '未找到该版本' });

  await AppRelease.update(
    { is_published: false, published_at: null },
    { where: { platform: app.platform, is_published: true } },
  );

  await app.update({
    is_published: true,
    published_at: new Date(),
  });

  res.json({ ok: true, app });
}

async function getLatestAppRelease(req, res) {
  const platform = String(req.query.platform || 'android').trim().toLowerCase();
  const app = await AppRelease.findOne({
    where: { platform, is_published: true },
    order: [['published_at', 'DESC'], ['upload_time', 'DESC']],
  });

  if (!app) return res.status(404).json({ error: '当前平台暂无已发布版本' });

  res.json({
    ok: true,
    data: {
      id: app.id,
      version: app.version,
      platform: app.platform,
      changelog: app.changelog,
      file_url: app.file_url,
      published_at: app.published_at,
      download_url: `/api/v1/admin/downloadApp/${app.id}`,
    },
  });
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

// ── 用户报错管理 ────────────────────────────────────
const { UserReport } = require('../routes/reports');

async function listReports(req, res) {
  const { status, ref_type, page = 1, limit = 20, q } = req.query;
  const where = {};
  if (status) where.status = status;
  if (ref_type) where.ref_type = ref_type;
  if (q) {
    where[Op.or] = [
      { ref_title: { [Op.like]: `%${q}%` } },
      { username: { [Op.like]: `%${q}%` } },
      { description: { [Op.like]: `%${q}%` } },
    ];
  }
  const offset = (parseInt(page) - 1) * parseInt(limit);
  const { count, rows } = await UserReport.findAndCountAll({
    where,
    order: [['createdAt', 'DESC']],
    limit: parseInt(limit),
    offset,
  });
  res.json({ total: count, data: rows });
}

async function getReport(req, res) {
  const { id } = req.params;
  const report = await UserReport.findByPk(id);
  if (!report) return res.status(404).json({ error: '未找到该报告' });
  res.json({ data: report });
}

async function updateReport(req, res) {
  const { id } = req.params;
  const { status, admin_reply } = req.body;
  const report = await UserReport.findByPk(id);
  if (!report) return res.status(404).json({ error: '未找到该报告' });
  const prevStatus = report.status;
  if (status) report.status = status;
  if (admin_reply !== undefined) report.admin_reply = admin_reply;
  await report.save();

  // 通知用户：状态变化或仅仅回复了
  try {
    const refLabel = report.ref_type === 'grammar' ? '语法' : '单词';
    const titleSuffix = report.ref_title ? `《${report.ref_title}》` : '';
    if (status && status !== prevStatus) {
      if (status === 'resolved') {
        // 奖励 xp
        const xpAward = 20;
        try {
          const { User } = require('../models/index');
          const u = await User.findByPk(report.user_id);
          if (u) {
            await u.update({ xp_earned: (u.xp_earned || 0) + xpAward });
          }
        } catch (_) {}
        createNotification({
          userId: report.user_id,
          type: 'report_resolved',
          title: `${refLabel}反馈已采纳`,
          content: (admin_reply ? `管理员回复：${admin_reply}\n\n` : '感谢您的反馈！\n')
            + `已为您奖励 ${xpAward} XP。`,
          refType: 'report',
          refId: report.id,
          extra: { ref_type: report.ref_type, ref_title: report.ref_title, admin_reply: admin_reply || null, xp_awarded: xpAward },
        });
      } else if (status === 'rejected') {
        createNotification({
          userId: report.user_id,
          type: 'report_rejected',
          title: `${refLabel}反馈未采纳${titleSuffix}`,
          content: admin_reply ? `管理员回复：${admin_reply}` : '您的反馈经核实后未予采纳，感谢支持。',
          refType: 'report',
          refId: report.id,
          extra: { ref_type: report.ref_type, ref_title: report.ref_title, admin_reply: admin_reply || null },
        });
      }
    } else if (admin_reply !== undefined && admin_reply) {
      // 仅添加了回复
      createNotification({
        userId: report.user_id,
        type: 'report_replied',
        title: `${refLabel}反馈有新回复${titleSuffix}`,
        content: `管理员回复：${admin_reply}`,
        refType: 'report',
        refId: report.id,
        extra: { ref_type: report.ref_type, ref_title: report.ref_title, admin_reply },
      });
    }
  } catch (_) {}

  res.json({ success: true, data: report });
}

async function deleteReport(req, res) {
  const { id } = req.params;
  const deleted = await UserReport.destroy({ where: { id } });
  res.json({ success: true, deleted });
}

/* ─────── 学习计划管理 ─────── */
async function getStudyPlanStats(req, res) {
  // 总览统计
  const [totalUsers] = await sequelize.query(
    `SELECT COUNT(DISTINCT user_id) AS cnt FROM study_plan_daily_tasks`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );
  const [taskStats] = await sequelize.query(
    `SELECT status, COUNT(*) AS cnt FROM study_plan_daily_tasks GROUP BY status`,
    { type: sequelize.constructor.QueryTypes.SELECT, raw: true }
  );
  const taskStatusRaw = await sequelize.query(
    `SELECT status, COUNT(*) AS cnt FROM study_plan_daily_tasks GROUP BY status`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );
  const cardStateRaw = await sequelize.query(
    `SELECT state, COUNT(*) AS cnt FROM study_plan_card_states GROUP BY state`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );
  const avgCompletion = await sequelize.query(
    `SELECT ROUND(AVG(completion_rate)*100,1) AS avg_rate FROM study_plan_daily_tasks WHERE status='finished'`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );

  // 近30天趋势
  const trend = await sequelize.query(
    `SELECT task_date AS period, COUNT(*) AS tasks, SUM(status='finished') AS finished,
       ROUND(AVG(completion_rate)*100,1) AS avg_rate
     FROM study_plan_daily_tasks
     WHERE task_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
     GROUP BY task_date ORDER BY task_date`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );

  // 用户排行（按完成天数、平均完成率）
  const userRank = await sequelize.query(
    `SELECT t.user_id, u.username,
       COUNT(*) AS total_days,
       SUM(t.status='finished') AS finished_days,
       ROUND(AVG(t.completion_rate)*100,1) AS avg_rate,
       MAX(t.task_date) AS last_active
     FROM study_plan_daily_tasks t
     LEFT JOIN users u ON u.id = t.user_id
     GROUP BY t.user_id
     ORDER BY finished_days DESC, avg_rate DESC
     LIMIT 50`,
    { type: sequelize.constructor.QueryTypes.SELECT }
  );

  res.json({
    totalUsers: totalUsers?.cnt || 0,
    taskStatus: taskStatusRaw,
    cardState: cardStateRaw,
    avgCompletionRate: avgCompletion[0]?.avg_rate || 0,
    trend,
    userRank,
  });
}

// ─── Kokoro TTS 设置 ───────────────────────────────────────────────────────────

/** 获取 Kokoro TTS 配置 */
async function getKokoroSettings(req, res) {
  try {
    // 默认配置
    let kokoroConfig = {
      enabled: true,
      default_voice: 'a',
      default_emotion: 'neutral',
      default_engine: 'edge-tts',
      default_speed: 1.0,
      speed_range: { min: 0.5, max: 2.0 },
      engines: ['edge-tts', 'gtts', 'google-tts', 'white-noise'],
      voices: {
        'a': { name: '女声优美', lang: 'ja_JP', emotions: ['neutral', 'happy', 'sad'] },
        'b': { name: '女声清晰', lang: 'ja_JP', emotions: ['neutral', 'happy', 'sad'] },
        'c': { name: '男声深沉', lang: 'ja_JP', emotions: ['neutral', 'happy', 'sad'] },
      },
      emotions: ['neutral', 'happy', 'sad'],
      port: 8010,
      host: '0.0.0.0',
    };
    
    // 尝试从数据库读取用户设置
    try {
      const AppConfigModel = sequelize.models.AppConfig;
      if (AppConfigModel) {
        const kv = await AppConfigModel.findOne({
          where: { key: 'kokoro_tts_settings' }
        });
        if (kv && kv.value) {
          const userSettings = JSON.parse(kv.value);
          console.log('[Kokoro] 从数据库加载配置:', userSettings);
          kokoroConfig = { ...kokoroConfig, ...userSettings };
        } else {
          console.log('[Kokoro] 数据库中无已保存的配置，使用默认值');
        }
      }
    } catch (dbErr) {
      console.error('[Kokoro] 从数据库读取配置失败:', dbErr.message);
      // 继续使用默认配置
    }
    
    res.json({
      kokoro_tts: kokoroConfig,
      service_url: process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010',
    });
  } catch (err) {
    console.error('获取Kokoro配置失败:', err);
    res.status(500).json({ error: err.message });
  }
}

/** 保存 Kokoro TTS 配置 */
async function saveKokoroSettings(req, res) {
  try {
    const { enabled, default_voice, default_emotion, default_engine, default_speed, service_url } = req.body;
    
    // 验证voice参数
    if (default_voice && !['a', 'b', 'c'].includes(default_voice)) {
      return res.status(400).json({ error: 'Invalid voice: must be a, b, or c' });
    }
    
    // 验证emotion参数
    if (default_emotion && !['neutral', 'happy', 'sad'].includes(default_emotion)) {
      return res.status(400).json({ error: 'Invalid emotion: must be neutral, happy, or sad' });
    }
    
    // 验证engine参数
    const validEngines = ['edge-tts', 'gtts', 'google-tts', 'white-noise'];
    if (default_engine && !validEngines.includes(default_engine)) {
      return res.status(400).json({ error: `Invalid engine: must be one of ${validEngines.join(', ')}` });
    }
    
    // 验证speed参数（0.5-2.0x）
    let speed = parseFloat(default_speed) || 1.0;
    speed = Math.max(0.5, Math.min(2.0, speed));
    
    const settings = {
      enabled: enabled !== false,
      default_voice: default_voice || 'a',
      default_emotion: default_emotion || 'neutral',
      default_engine: default_engine || 'edge-tts',  // 新增
      default_speed: speed,
      speed_range: { min: 0.5, max: 2.0 },
      service_url: service_url || process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010',
    };
    
    console.log('[Kokoro] 准备保存配置:', settings);
    
    // 保存到数据库
    const AppConfigModel = sequelize.models.AppConfig;
    if (!AppConfigModel) {
      console.error('[Kokoro] AppConfig 模型未初始化！');
      return res.status(500).json({ error: 'AppConfig model not initialized' });
    }
    
    try {
      // 使用 upsert 执行保存
      const [config, created] = await AppConfigModel.upsert({
        key: 'kokoro_tts_settings',
        value: JSON.stringify(settings),
      });
      console.log(`[Kokoro] 配置${created ? '创建' : '更新'}成功`);
      
      // 验证数据确实被保存到数据库
      const verify = await AppConfigModel.findOne({
        where: { key: 'kokoro_tts_settings' }
      });
      
      if (!verify) {
        console.error('[Kokoro] 保存验证失败：数据库中找不到保存的配置');
        return res.status(500).json({ error: 'Failed to verify saved configuration' });
      }
      
      const verifiedSettings = JSON.parse(verify.value);
      console.log('[Kokoro] 保存验证成功，数据库中的值:', verifiedSettings);
      
    } catch (dbErr) {
      console.error('[Kokoro] 数据库操作失败:', dbErr.message);
      console.error('[Kokoro] 完整错误:', dbErr.stack);
      throw dbErr;
    }
    
    // 同时更新环境变量
    if (service_url) {
      process.env.KOKORO_SERVICE_URL = service_url;
    }
    
    console.log('[Kokoro] 配置已更新:', {
      voice: settings.default_voice,
      emotion: settings.default_emotion,
      engine: settings.default_engine,
      speed: settings.default_speed,
      enabled: settings.enabled,
    });
    
    res.json({
      success: true,
      settings,
    });
  } catch (err) {
    console.error('保存Kokoro配置失败:', err);
    res.status(500).json({ error: err.message });
  }
}

// ─── 五十音管理 ────────────────────────────────────────
/** 列出所有五十音 */
async function listKana(req, res) {
  try {
    const { type, category } = req.query;  // 可选: hiragana或katakana; 五十音/濁音/半濁音/拗音
    let where = {};
    if (type) where.type = type;
    if (category) where.category = category;
    
    const kanas = await sequelize.models.Kana.findAll({
      where,
      attributes: ['id', 'type', 'character', 'romanization', 'category', 'audio_url', 'order_index'],
      order: [['order_index', 'ASC'], ['type', 'ASC']],
      raw: true,
    });
    
    res.json({ data: kanas });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 批量生成五十音音频 */
async function batchGenerateKanaAudio(req, res) {
  try {
    const audioLocalizationService = require('../services/audioLocalizationService');
    const { selectedIds } = req.body || {};
    
    // 构建WHERE条件
    let where = { audio_url: { [Op.or]: [null, ''] } };
    if (selectedIds && Array.isArray(selectedIds) && selectedIds.length > 0) {
      where.id = { [Op.in]: selectedIds };
    }
    
    const Kana = sequelize.models.Kana;
    const kanas = await Kana.findAll({
      where,
      attributes: ['id', 'character', 'romanization'],
      order: [['order_index', 'ASC']],
      raw: false,
    });
    
    if (kanas.length === 0) {
      return res.json({ success: true, message: '所有五十音都已有音频或未选择任何项目', generated: 0, total: 0 });
    }
    
    // 收集所有需要生成音频的文本（使用字符本身）
    const textsToGenerate = kanas.map(k => k.character);
    
    try {
      const axios = require('axios');
      const timeoutMs = Math.max(30000, textsToGenerate.length * 5000 + 20000);
      
      // 读取管理员配置
      let kanaEngine = 'edge-tts', kanaVoice = 'a', kanaEmotion = 'neutral', kanaSpeed = 1.0;
      try {
        const kv = await sequelize.models.AppConfig?.findOne({ where: { key: 'kokoro_tts_settings' } });
        if (kv && kv.value) {
          const cfg = JSON.parse(kv.value);
          kanaEngine = cfg.default_engine || 'edge-tts';
          kanaVoice = cfg.default_voice || 'a';
          kanaEmotion = cfg.default_emotion || 'neutral';
          kanaSpeed = cfg.default_speed || 1.0;
        }
      } catch (_) {}
      
      const resp = await axios.post(
        'http://127.0.0.1:8010/api/v1/tts/batch-generate',
        { texts: textsToGenerate, voice: kanaVoice, emotion: kanaEmotion, engine: kanaEngine, speed: kanaSpeed },
        { timeout: timeoutMs }
      );
      
      const results = resp.data.results || [];
      
      // 提取成功的Kokoro音频URL，批量下载到 /uploads/audio/kana/
      const successfulUrls = results
        .filter(r => r && r.success && r.audio_url)
        .map(r => r.audio_url);
      
      const localizationResults = await audioLocalizationService.batchDownloadAndLocalize(successfulUrls, 'kana');
      const localizationMap = new Map(localizationResults.map(r => [r.originalUrl, r.localPath]));
      
      const updatePromises = [];
      
      for (let i = 0; i < results.length; i++) {
        const result = results[i];
        if (result && result.success && result.audio_url && kanas[i]) {
          const localPath = localizationMap.get(result.audio_url);
          if (localPath) {
            updatePromises.push(
              Kana.update(
                { audio_url: localPath },
                { where: { id: kanas[i].id } }
              )
            );
          }
        }
      }
      
      const updateResults = await Promise.all(updatePromises);
      const updateCount = updateResults.length;
      
      res.json({
        success: true,
        generated: updateCount,
        total: textsToGenerate.length,
        message: `成功生成${updateCount}/${textsToGenerate.length}个五十音音频`,
      });
    } catch (apiErr) {
      console.error('[Kana Audio] Kokoro API调用失败:', apiErr.message);
      
      if (apiErr.code === 'ECONNABORTED' || apiErr.message.includes('timeout')) {
        res.status(504).json({ error: '音频生成超时，请检查网络连接' });
      } else if (apiErr.code === 'ECONNREFUSED') {
        res.status(503).json({ error: 'Kokoro TTS服务不可用' });
      } else {
        res.status(500).json({ error: 'Kokoro API调用失败: ' + apiErr.message });
      }
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 获取五十音（分页） */
async function getKanaList(req, res) {
  try {
    const { page = 1, limit = 20, q = '', type = '', category = '' } = req.query;
    const offset = (page - 1) * limit;
    const Kana = sequelize.models.Kana;
    
    let where = {};
    if (q) where.character = { [Op.like]: `%${q}%` };
    if (type) where.type = type;
    if (category) where.category = category;
    
    const { count, rows } = await Kana.findAndCountAll({
      where,
      offset,
      limit: parseInt(limit),
      order: [['order_index', 'ASC']],
      attributes: ['id', 'character', 'romanization', 'type', 'category', 'audio_url', 'order_index'],
    });
    
    res.json({ data: rows, total: count });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 获取单个五十音 */
async function getKanaById(req, res) {
  try {
    const Kana = sequelize.models.Kana;
    const kana = await Kana.findByPk(req.params.id);
    if (!kana) return res.status(404).json({ error: '五十音不存在' });
    res.json(kana);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 创建五十音 */
async function createKanaItem(req, res) {
  try {
    const { character, romanization, type, category, audio_url } = req.body;
    if (!character) return res.status(400).json({ error: '字符不能为空' });
    if (!romanization) return res.status(400).json({ error: '罗马音不能为空' });
    
    const Kana = sequelize.models.Kana;
    const maxOrder = await Kana.max('order_index');
    const kana = await Kana.create({
      character,
      romanization,
      type: type || 'hiragana',
      category: category || '五十音',
      audio_url: audio_url || null,
      order_index: (maxOrder || 0) + 1,
    });
    
    res.json({ message: '已创建', data: kana });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 更新五十音 */
async function updateKanaItem(req, res) {
  try {
    const { character, romanization, type, category, audio_url } = req.body;
    const Kana = sequelize.models.Kana;
    
    const kana = await Kana.findByPk(req.params.id);
    if (!kana) return res.status(404).json({ error: '五十音不存在' });
    
    await kana.update({
      character: character || kana.character,
      romanization: romanization || kana.romanization,
      type: type || kana.type,
      category: category || kana.category,
      audio_url: audio_url !== undefined ? audio_url : kana.audio_url,
    });
    
    res.json({ message: '已更新', data: kana });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 删除五十音 */
async function deleteKanaItem(req, res) {
  try {
    const Kana = sequelize.models.Kana;
    const result = await Kana.destroy({ where: { id: req.params.id } });
    if (!result) return res.status(404).json({ error: '五十音不存在' });
    res.json({ message: '已删除' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 批量删除五十音 */
async function bulkDeleteKanaItems(req, res) {
  try {
    const { ids } = req.body;
    if (!Array.isArray(ids) || ids.length === 0) {
      return res.status(400).json({ error: 'IDs不能为空' });
    }
    
    const Kana = sequelize.models.Kana;
    const result = await Kana.destroy({ where: { id: { [Op.in]: ids } } });
    res.json({ message: `已删除 ${result} 项`, deleted: result });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/** 单条TTS生成并持久化到本地 */
async function generateSingleAudio(req, res) {
  const { text, subdir = 'vocab' } = req.body;
  if (!text || !text.trim()) return res.status(400).json({ error: '文本不能为空' });

  const allowedDirs = ['vocab', 'kana', 'grammar/audio'];
  if (!allowedDirs.includes(subdir)) return res.status(400).json({ error: '无效的subdir' });

  // 读取管理员TTS配置
  let voice = 'a', emotion = 'neutral', engine = 'edge-tts', speed = 1.0;
  try {
    const kv = await sequelize.models.AppConfig?.findOne({ where: { key: 'kokoro_tts_settings' } });
    if (kv && kv.value) {
      const cfg = JSON.parse(kv.value);
      voice = cfg.default_voice || 'a';
      emotion = cfg.default_emotion || 'neutral';
      engine = cfg.default_engine || 'edge-tts';
      speed = cfg.default_speed || 1.0;
    }
  } catch (_) {}

  const KOKORO_SERVICE_URL = process.env.KOKORO_SERVICE_URL || 'http://127.0.0.1:8010';
  try {
    const ttsResp = await axios.post(
      `${KOKORO_SERVICE_URL}/api/v1/tts/kokoro`,
      { text: text.trim(), voice, emotion, engine, speed },
      { timeout: 30000 }
    );
    const kokoroUrl = ttsResp.data.audio_url;
    if (!kokoroUrl) return res.status(500).json({ error: 'TTS未返回音频URL' });

    // 下载并保存到本地
    const audioDir = path.join(__dirname, `../../uploads/audio/${subdir}`);
    if (!fs.existsSync(audioDir)) fs.mkdirSync(audioDir, { recursive: true });

    const audioResp = await axios.get(`${KOKORO_SERVICE_URL}${kokoroUrl}`, { responseType: 'arraybuffer', timeout: 10000 });
    const filename = path.basename(kokoroUrl);
    fs.writeFileSync(path.join(audioDir, filename), audioResp.data);

    const persistentUrl = `/uploads/audio/${subdir}/${filename}`;
    res.json({ ok: true, audio_url: persistentUrl });
  } catch (e) {
    console.error('[SingleAudio] 生成失败:', e.message);
    res.status(500).json({ error: 'TTS生成失败: ' + e.message });
  }
}

// ─── 订单管理 ───────────────────────────────────────────────────────────────
const { MembershipOrder } = require('../models/index');
const { isActiveMember } = require('../middlewares/membership');
const { createNotification } = require('../routes/notifications');

async function listOrders(req, res) {
  const { status, channel, page = 1, limit = 20 } = req.query;
  const where = {};
  if (status) where.status = status;
  if (channel) where.channel = channel;
  const offset = (Math.max(1, parseInt(page)) - 1) * parseInt(limit);
  const { rows, count } = await MembershipOrder.findAndCountAll({
    where,
    order: [['createdAt', 'DESC']],
    limit: parseInt(limit),
    offset,
  });
  // 附加用户信息
  const userIds = [...new Set(rows.map(r => r.user_id))];
  const users = await User.findAll({ where: { id: userIds }, attributes: ['id', 'username', 'email'] });
  const userMap = {};
  users.forEach(u => { userMap[u.id] = { username: u.username, email: u.email }; });
  res.json({
    orders: rows.map(r => ({
      ...r.toJSON(),
      user: userMap[r.user_id] || null,
    })),
    total: count,
    page: parseInt(page),
    limit: parseInt(limit),
  });
}

async function reviewOrder(req, res) {
  const { id } = req.params;
  const { action, admin_note } = req.body; // action: 'approve' | 'reject'
  if (!['approve', 'reject'].includes(action)) {
    return res.status(400).json({ error: '操作必须为 approve 或 reject' });
  }

  const order = await MembershipOrder.findByPk(id);
  if (!order) return res.status(404).json({ error: '订单不存在' });
  if (order.status !== 'pending') {
    return res.status(400).json({ error: `订单状态为 ${order.status}，无法审核` });
  }

  if (action === 'reject') {
    await order.update({
      status: 'rejected',
      admin_note: admin_note || null,
      reviewed_by: req.user.id,
      reviewed_at: new Date(),
    });
    createNotification({
      userId: order.user_id,
      type: 'order_rejected',
      title: '订单审核未通过',
      content: admin_note ? `审核备注：${admin_note}` : '您的支付凭证未通过审核，如有疑问请联系客服。',
      refType: 'order',
      refId: order.id,
      extra: { plan_id: order.plan_id, channel: order.channel, admin_note: admin_note || null },
    });
    return res.json({ ok: true, message: '已拒绝', order: order.toJSON() });
  }

  // approve — 激活会员
  const config = readMembershipConfig();
  const plan = (config.plans || []).find(p => p.id === order.plan_id);
  const period = plan?.period || 'month';

  const user = await User.findByPk(order.user_id);
  if (!user) return res.status(404).json({ error: '用户不存在' });

  // 计算到期时间（支持叠加）
  const now = new Date();
  let expire;
  switch (period) {
    case 'month':   expire = new Date(now.setMonth(now.getMonth() + 1)); break;
    case 'year':    expire = new Date(now.setFullYear(now.getFullYear() + 1)); break;
    case 'forever': expire = new Date('2099-12-31'); break;
    default:        expire = new Date(now.setMonth(now.getMonth() + 1));
  }
  if (user.membership_expire && new Date(user.membership_expire) > new Date()) {
    const currentExpire = new Date(user.membership_expire);
    const extension = expire.getTime() - Date.now();
    expire.setTime(currentExpire.getTime() + extension);
  }

  await user.update({ membership_plan: order.plan_id, membership_expire: expire });
  await order.update({
    status: 'paid',
    paid_at: new Date(),
    expire_at: expire,
    admin_note: admin_note || null,
    reviewed_by: req.user.id,
    reviewed_at: new Date(),
  });

  createNotification({
    userId: order.user_id,
    type: 'order_approved',
    title: '订单审核已通过',
    content: admin_note
      ? `您的会员已成功开通，到期时间：${expire.toISOString().slice(0,10)}。审核备注：${admin_note}`
      : `您的会员已成功开通，到期时间：${expire.toISOString().slice(0,10)}。`,
    refType: 'order',
    refId: order.id,
    extra: { plan_id: order.plan_id, channel: order.channel, expire_at: expire, admin_note: admin_note || null },
  });

  res.json({ ok: true, message: '已通过，会员已激活', order: order.toJSON() });
}

// ── 收款二维码上传 ──────────────────────────────────────────────────────────
async function uploadQrCode(req, res) {
  if (!req.file) return res.status(400).json({ error: '请上传二维码图片' });
  const { type } = req.body; // 'alipay' | 'wechat'
  if (!['alipay', 'wechat'].includes(type)) {
    return res.status(400).json({ error: 'type 必须为 alipay 或 wechat' });
  }
  const ext = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' }[req.file.mimetype] || '.jpg';
  const filename = `qr_${type}_${Date.now()}${ext}`;
  const qrDir = path.join(__dirname, '../../uploads/qrcodes');
  if (!fs.existsSync(qrDir)) fs.mkdirSync(qrDir, { recursive: true });
  fs.writeFileSync(path.join(qrDir, filename), req.file.buffer);
  const qrUrl = `/uploads/qrcodes/${filename}`;

  // 更新到 membership.json
  const config = readMembershipConfig();
  if (!config.payment) config.payment = {};
  if (type === 'alipay') {
    config.payment.alipay_qr_url = qrUrl;
    config.payment.alipay_enabled = true;
  } else {
    config.payment.wechat_qr_url = qrUrl;
    config.payment.wechat_enabled = true;
  }
  const dir = path.dirname(PLANS_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(PLANS_FILE, JSON.stringify(config, null, 2), 'utf8');

  res.json({ ok: true, qr_url: qrUrl, type });
}

// ─── 邮件（SMTP）配置 ──────────────────────────────────────────────────────
const DEFAULT_EMAIL_SETTINGS = {
  smtp_host: 'smtp.aliyun.com',
  smtp_port: 465,
  smtp_user: '',
  smtp_pass: '',
  daily_limit: 200,
};

async function getEmailSettings(req, res) {
  try {
    const AppConfigModel = sequelize.models.AppConfig;
    const kv = await AppConfigModel?.findOne({ where: { key: 'email_settings' } });
    const settings = kv ? JSON.parse(kv.value) : { ...DEFAULT_EMAIL_SETTINGS };
    // 不返回密码明文，前端只显示掩码
    const masked = { ...settings, smtp_pass: settings.smtp_pass ? '••••••••' : '' };
    // 查询今日已发送数量
    const PasswordResetCode = require('../models/PasswordResetCode');
    const { Op } = require('sequelize');
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);
    const sentToday = await PasswordResetCode.count({ where: { createdAt: { [Op.gte]: todayStart } } });
    res.json({ email_settings: masked, sent_today: sentToday });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

async function saveEmailSettings(req, res) {
  try {
    const { smtp_host, smtp_port, smtp_user, smtp_pass, daily_limit } = req.body;
    const AppConfigModel = sequelize.models.AppConfig;
    // 读取现有配置
    const existing = await AppConfigModel?.findOne({ where: { key: 'email_settings' } });
    const current = existing ? JSON.parse(existing.value) : { ...DEFAULT_EMAIL_SETTINGS };
    const settings = {
      smtp_host: smtp_host || current.smtp_host,
      smtp_port: parseInt(smtp_port, 10) || current.smtp_port,
      smtp_user: smtp_user || current.smtp_user,
      // 如果前端传来掩码或空值，保留原密码
      smtp_pass: (smtp_pass && smtp_pass !== '••••••••') ? smtp_pass : current.smtp_pass,
      daily_limit: parseInt(daily_limit, 10) || current.daily_limit,
    };
    await AppConfigModel.upsert({ key: 'email_settings', value: JSON.stringify(settings) });
    res.json({ ok: true, message: '邮件配置已保存' });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
}

async function testEmailSettings(req, res) {
  try {
    const { to } = req.body;
    if (!to) return res.status(400).json({ error: '请输入测试邮箱地址' });
    const nodemailer = require('nodemailer');
    const AppConfigModel = sequelize.models.AppConfig;
    const kv = await AppConfigModel?.findOne({ where: { key: 'email_settings' } });
    const cfg = kv ? JSON.parse(kv.value) : { ...DEFAULT_EMAIL_SETTINGS };
    if (!cfg.smtp_user || !cfg.smtp_pass) return res.status(400).json({ error: '请先配置 SMTP 账号和密码' });
    const transporter = nodemailer.createTransport({
      host: cfg.smtp_host, port: cfg.smtp_port, secure: true,
      auth: { user: cfg.smtp_user, pass: cfg.smtp_pass },
    });
    await transporter.sendMail({
      from: `"言旅 Kotabi" <${cfg.smtp_user}>`, to,
      subject: '【言旅 Kotabi】邮件配置测试',
      html: '<div style="font-family:sans-serif;color:#333;"><h2 style="color:#8B4513;">邮件配置测试成功 ✅</h2><p>如果您收到此邮件，说明 SMTP 配置正确。</p></div>',
    });
    res.json({ ok: true, message: '测试邮件已发送' });
  } catch (e) {
    res.status(500).json({ error: '发送失败: ' + e.message });
  }
}

// ─── 支持渠道管理 ──────────────────────────────────────────────────────
const SUPPORT_KEY = 'support_channels';

async function _readSupportChannels() {
  try {
    const kv = await sequelize.models.AppConfig?.findOne({ where: { key: SUPPORT_KEY } });
    return kv ? JSON.parse(kv.value) : [];
  } catch { return []; }
}

async function _writeSupportChannels(channels) {
  await sequelize.models.AppConfig.upsert({
    key: SUPPORT_KEY,
    value: JSON.stringify(channels),
    description: '软件支持渠道配置',
  });
}

async function getSupportChannels(req, res) {
  const channels = await _readSupportChannels();
  res.json({ channels });
}

async function saveSupportChannel(req, res) {
  const { id, platform, name, link, qr_code_url, enabled, sort_order } = req.body;
  if (!platform || !name) return res.status(400).json({ error: 'platform 和 name 必填' });
  const allowed = ['wechat', 'dingtalk', 'slack', 'telegram', 'discord', 'qq', 'line', 'feishu', 'other'];
  if (!allowed.includes(platform)) return res.status(400).json({ error: `platform 必须为: ${allowed.join(', ')}` });

  const channels = await _readSupportChannels();
  if (id) {
    // 更新
    const idx = channels.findIndex(c => c.id === id);
    if (idx === -1) return res.status(404).json({ error: '渠道不存在' });
    channels[idx] = { ...channels[idx], platform, name, link: link || '', qr_code_url: qr_code_url || channels[idx].qr_code_url || '', enabled: enabled !== false, sort_order: sort_order ?? channels[idx].sort_order ?? 0, updated_at: new Date().toISOString() };
  } else {
    // 新增
    channels.push({
      id: uuidv4(),
      platform, name,
      link: link || '',
      qr_code_url: qr_code_url || '',
      enabled: enabled !== false,
      sort_order: sort_order ?? channels.length,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });
  }
  await _writeSupportChannels(channels);
  res.json({ ok: true, channels });
}

async function deleteSupportChannel(req, res) {
  const { id } = req.params;
  const channels = await _readSupportChannels();
  const target = channels.find(c => c.id === id);
  if (!target) return res.status(404).json({ error: '渠道不存在' });
  // 删除关联的二维码文件
  if (target.qr_code_url && target.qr_code_url.startsWith('/uploads/')) {
    const filePath = path.join(__dirname, '../..', target.qr_code_url);
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  }
  await _writeSupportChannels(channels.filter(c => c.id !== id));
  res.json({ ok: true });
}

async function uploadSupportQrCode(req, res) {
  if (!req.file) return res.status(400).json({ error: '请上传二维码图片' });
  const ext = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' }[req.file.mimetype] || '.jpg';
  const filename = `support_${Date.now()}${ext}`;
  const dir = path.join(__dirname, '../../uploads/support');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, filename), req.file.buffer);
  const url = `/uploads/support/${filename}`;
  res.json({ ok: true, url });
}

async function getPublicSupportChannels(req, res) {
  const channels = await _readSupportChannels();
  const visible = channels.filter(c => c.enabled !== false).sort((a, b) => (a.sort_order || 0) - (b.sort_order || 0));
  res.json({ channels: visible });
}

module.exports = {
  getDashboard,
  listVocab, createVocab, updateVocab, deleteVocab, bulkDeleteVocab, generateVocabExamplesKokoroAudio, deduplicateVocab, fixVocabReadings,
  importVocab, importVocabFile,
  listGrammar, getGrammar, createGrammar, updateGrammar, deleteGrammar, bulkDeleteGrammar, generateGrammarExamplesKokoroAudio, importGrammarApkg, generateGrammarExampleAudio,
  listTracks, createTrack, updateTrack, deleteTrack,
  listUsers, updateUser, updateUserMembership, resetUserPassword,
  getContentVersion, publishContent,
  getTrafficStats, getUserStats, getBehaviorStats, getFeatureUsage,
  getMembershipConfig, saveMembershipConfig,
  listKana, batchGenerateKanaAudio, getKanaList, getKanaById, createKanaItem, updateKanaItem, deleteKanaItem, bulkDeleteKanaItems,  // ✅ 五十音CRUD
  getFeatureToggles, saveFeatureToggles,
  getFeatureTiers, saveFeatureTiers,
  uploadApp,
  listAppReleases,
  publishAppRelease,
  getLatestAppRelease,
  downloadApp,
  deleteAppRelease,
  getAiSettings, saveAiSettings, getAiUsage, resetAiUsage, readAiSettings, saveAiSettingsFile,
  getKokoroSettings, saveKokoroSettings,
  listAdmins, updateAdminPermissions, getAdminInfo,
  listReports, getReport, updateReport, deleteReport,
  getStudyPlanStats,
  generateSingleAudio,
  listOrders, reviewOrder, uploadQrCode,
  getEmailSettings, saveEmailSettings, testEmailSettings,
  getSupportChannels, saveSupportChannel, deleteSupportChannel, uploadSupportQrCode, getPublicSupportChannels,
};
