const { QuizQuestion, QuizSession, GrammarLesson, GrammarExample } = require('../models');
const { Op } = require('sequelize');

async function generateQuiz(req, res) {
  const { level = 'N5', quiz_type = 'vocabulary', count = 10 } = req.query;
  const safeCount = Math.min(parseInt(count) || 10, 50);
  try {
    // 语法测验走独立逻辑
    if (quiz_type === 'grammar') {
      const questions = await buildGrammarQuiz(level, safeCount);
      return res.json({ quiz_type, level, questions });
    }

    const { sequelize: db } = require('../config/database');
    const questions = await QuizQuestion.findAll({
      where: {
        jlpt_level: level,
        question_type: { [Op.in]: quizTypeToTypes(quiz_type) },
        options: { [Op.not]: null },
      },
      order: db.literal('RAND()'),
      limit: safeCount,
    });
    if (questions && questions.length > 0) {
      return res.json({ quiz_type, level, questions });
    }
    // 预置题目不足时，从词汇表动态生成
    const dynamic = await buildDynamicQuiz(level, quiz_type, safeCount);
    res.json({ quiz_type, level, questions: dynamic });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

/**
 * 从 vocabulary 表动态生成测验题目
 */
async function buildDynamicQuiz(level, quizType, count) {
  const { Vocabulary } = require('../models');
  const { sequelize: db } = require('../config/database');
  // 取足够多的词汇用于生成题目和干扰项
  const pool = await Vocabulary.findAll({
    where: { jlpt_level: level },
    order: db.literal('RAND()'),
    limit: Math.max(count * 4, 80),
  });
  if (pool.length < 4) return [];

  const types = quizTypeToTypes(quizType);
  const questions = [];

  for (let i = 0; i < pool.length && questions.length < count; i++) {
    const word = pool[i];
    const others = pool.filter((w, idx) => idx !== i);

    if (types.includes('meaning')) {
      const correct = (word.meaning_zh || '').trim();
      if (!correct) continue;
      const wrongSet = new Set();
      for (const w of others) {
        const m = (w.meaning_zh || '').trim();
        if (m && m !== correct) wrongSet.add(m);
        if (wrongSet.size >= 3) break;
      }
      if (wrongSet.size < 3) continue;
      const opts = [correct, ...wrongSet].sort(() => Math.random() - 0.5);
      questions.push({
        id: word.id,
        question_type: 'meaning',
        question: word.reading ? `「${word.word}」(${word.reading}) の意味は？` : `「${word.word}」の意味は？`,
        correct_answer: correct,
        options: JSON.stringify(opts),
        explanation: `${word.word} → ${correct}`,
        jlpt_level: level,
      });
    } else if (types.includes('reading')) {
      const correct = (word.reading || '').trim();
      if (!correct) continue;
      const wrongSet = new Set();
      for (const w of others) {
        const r = (w.reading || '').trim();
        if (r && r !== correct) wrongSet.add(r);
        if (wrongSet.size >= 3) break;
      }
      if (wrongSet.size < 3) continue;
      const opts = [correct, ...wrongSet].sort(() => Math.random() - 0.5);
      questions.push({
        id: word.id,
        question_type: 'reading',
        question: `「${word.word}」の読み方は？`,
        correct_answer: correct,
        options: JSON.stringify(opts),
        explanation: `${word.word} の読みは ${correct}`,
        jlpt_level: level,
      });
    }
  }
  return questions;
}

/**
 * 从 grammar_examples 动态生成语法选词填空题
 * 题目：给出日语例句，将语法关键词替换为 ______，让用户选出正确的语法词
 * 正确答案：从句子中挖出的语法关键词
 * 干扰项：同级别其他语法课的关键词
 */
async function buildGrammarQuiz(level, count) {
  const { sequelize: db } = require('../config/database');

  // 1. 获取该级别所有语法课（用于生成干扰项）
  const allLessons = await GrammarLesson.findAll({
    attributes: ['id', 'title'],
    where: { jlpt_level: level, title: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] } },
  });
  if (allLessons.length < 4) return [];

  // 2. 取足够多的例句
  const pool = await GrammarExample.findAll({
    attributes: ['id', 'sentence', 'reading', 'meaning_zh', 'grammar_lesson_id'],
    include: [{
      model: GrammarLesson,
      attributes: ['id', 'title', 'jlpt_level', 'pattern', 'explanation_zh'],
      where: { jlpt_level: level },
    }],
    where: {
      sentence: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
      meaning_zh: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
    },
    order: db.literal('RAND()'),
    limit: Math.max(count * 5, 100),
  });

  if (pool.length < 4) return [];

  const questions = [];
  const usedLessonIds = new Set();

  for (let i = 0; i < pool.length && questions.length < count; i++) {
    const ex = pool[i];
    const lesson = ex.GrammarLesson;
    if (!lesson || !lesson.title) continue;
    if (usedLessonIds.has(lesson.id)) continue;

    // 尝试从句子中挖出语法关键词
    const blankResult = makeBlankFromSentence(ex.sentence, lesson.title);
    if (!blankResult) continue;

    usedLessonIds.add(lesson.id);

    const correctAnswer = blankResult.keyword;
    const blankSentence = blankResult.blanked;
    const meaningZh = cleanGrammarMeaning(ex.meaning_zh);

    // 从同级别其他语法课中提取关键词作为干扰项
    const wrongSet = new Set();
    const otherLessons = shuffle(allLessons.filter(l => l.id !== lesson.id));
    for (const l of otherLessons) {
      const kw = extractGrammarKeyword(l.title);
      if (kw && kw !== correctAnswer && kw.length >= 1) {
        wrongSet.add(kw);
      }
      if (wrongSet.size >= 3) break;
    }
    if (wrongSet.size < 3) continue;

    const options = shuffle([correctAnswer, ...wrongSet]);
    const grammarPattern = lesson.pattern || '';
    const grammarExplain = lesson.explanation_zh || '';
    const briefExplain = grammarExplain.length > 80
      ? grammarExplain.substring(0, 80) + '…'
      : grammarExplain;

    const explanationParts = [];
    explanationParts.push(`【${lesson.title}】`);
    if (grammarPattern && grammarPattern !== lesson.title) explanationParts.push(`文型: ${grammarPattern}`);
    explanationParts.push(`原句: ${ex.sentence}`);
    if (meaningZh) explanationParts.push(`译文: ${meaningZh}`);
    if (briefExplain) explanationParts.push(briefExplain);

    questions.push({
      id: ex.id,
      question_type: 'grammar',
      question: blankSentence,
      correct_answer: correctAnswer,
      options: JSON.stringify(options),
      explanation: explanationParts.join('\n'),
      jlpt_level: level,
      grammar_title: lesson.title,
      meaning_zh: meaningZh,
    });
  }

  return questions;
}

/**
 * 从语法 title 中提取核心关键词（用于生成干扰项选项文本）
 * 过滤掉含中文的关键词，只保留以假名为主的日语表达
 */
function extractGrammarKeyword(title) {
  if (!title) return '';
  let s = title;
  // 去除各种括号内容（含中日文括号）
  s = s.replace(/\s*[\[（(【「｛〈《].*?[》〉｝」】)\]）]\s*/g, '');
  if (s.includes('/')) s = s.split('/')[0];
  s = s.replace(/[～〜~，,。、？！\s\-]/g, '');
  if (!s) return '';
  // 必须包含假名
  if (!/[\u3040-\u309F\u30A0-\u30FF]/.test(s)) return '';
  // 假名占比必须 >= 40%，否则视为中文描述性标题
  const kanaCount = (s.match(/[\u3040-\u309F\u30A0-\u30FF]/g) || []).length;
  if (kanaCount / s.length < 0.4) return '';
  if (s.length < 2 || s.length > 8) return '';
  return s;
}

/**
 * 尝试在句子中找到语法关键词并替换为 ______
 * 返回 { blanked, keyword } 或 null
 */
function makeBlankFromSentence(sentence, title) {
  if (!sentence || !title) return null;
  const candidates = getKeywordCandidates(title);
  for (const kw of candidates) {
    if (kw.length < 2) continue;
    const idx = sentence.indexOf(kw);
    if (idx >= 0) {
      const blanked = sentence.substring(0, idx) + '______' + sentence.substring(idx + kw.length);
      return { blanked, keyword: kw };
    }
  }
  return null;
}

/** 检测关键词是否为日语表达（假名占比 >= 40%） */
function isJapaneseKeyword(s) {
  if (!s || !/[\u3040-\u309F\u30A0-\u30FF]/.test(s)) return false;
  const kanaCount = (s.match(/[\u3040-\u309F\u30A0-\u30FF]/g) || []).length;
  return kanaCount / s.length >= 0.4;
}

/**
 * 从 title 生成多个候选关键词，按长度降序排列
 * 只保留包含日语假名的候选词
 */
function getKeywordCandidates(title) {
  const candidates = new Set();
  let s = title;
  s = s.replace(/\s*[\[（(【「｛〈《].*?[》〉｝」】)\]）]\s*/g, '');
  // 处理 / 分隔的变体
  const variants = s.split('/').map(v => v.replace(/[～〜~，,。、？！\s]/g, '').trim()).filter(Boolean);
  variants.forEach(v => { if (v.length >= 2 && v.length <= 10 && isJapaneseKeyword(v)) candidates.add(v); });
  // 按 ～ 分割取有意义的部分
  const parts = s.split(/[～〜~]/).map(p => p.replace(/[，,。、？！\s]/g, '').trim()).filter(p => p.length >= 2);
  parts.forEach(p => { if (p.length <= 10 && isJapaneseKeyword(p)) candidates.add(p); });
  // 组合相邻部分
  if (parts.length >= 2) {
    for (let i = 0; i < parts.length - 1; i++) {
      const combined = parts[i] + parts[i + 1];
      if (combined.length <= 10 && isJapaneseKeyword(combined)) candidates.add(combined);
    }
  }
  return [...candidates].sort((a, b) => b.length - a.length);
}

/**
 * 清洗语法例句翻译：去除箭头前的日文部分
 * 如果清洗后为空或与原文相同（纯日文），返回原始文本
 */
function cleanGrammarMeaning(text) {
  if (!text) return '';
  let s = text.trim();
  if (s.includes('→')) s = s.split('→').pop().trim();
  else if (s.includes('->')) s = s.split('->').pop().trim();
  // 只去除开头的连续假名片段（保留中文/汉字内容）
  s = s.replace(/^[\u3040-\u309F\u30A0-\u30FF\u31F0-\u31FF\uFF65-\uFF9F]+[。、！？\s]*/g, '').trim();
  return s || text.trim();
}

function quizTypeToTypes(type) {
  const map = {
    vocabulary: ['meaning', 'reading'],
    reading:    ['reading'],           // 前端发 'reading' 时只取读音题
    meaning:    ['meaning'],
    grammar:    ['fill_blank'],
    listening:  ['listening'],
    mixed:      ['meaning', 'reading', 'fill_blank', 'listening'],
  };
  return map[type] || ['meaning', 'reading'];
}

async function submitQuiz(req, res) {
  const { level, quiz_type, answers, time_spent_seconds } = req.body;
  if (!answers || !Array.isArray(answers) || answers.length === 0) {
    return res.status(400).json({ error: 'answers array is required' });
  }
  const correct = answers.filter(a => a.user_answer === a.correct_answer).length;
  const score = Math.round((correct / answers.length) * 100);

  // QuizSession.quiz_type ENUM 只允许 vocabulary/grammar/mixed/listening
  // 'reading' 题型归入 vocabulary 分类存储
  const sessionType = ['vocabulary','grammar','mixed','listening'].includes(quiz_type)
    ? quiz_type : 'vocabulary';
  // 安全的 jlpt_level（拦截 'ALL' 等非法值）
  const validLevels = ['N1','N2','N3','N4','N5'];
  const sessionLevel = validLevels.includes(level) ? level : 'N5';

  try {
    const session = await QuizSession.create({
      user_id: req.user.id,
      quiz_type: sessionType,
      jlpt_level: sessionLevel,
      total_questions: answers.length,
      correct_count: correct,
      score_percent: score,
      time_spent_seconds: time_spent_seconds || 0,
      completed_at: new Date(),
    });
    res.json({ session, correct, total: answers.length, score });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getHistory(req, res) {
  try {
    const sessions = await QuizSession.findAll({
      where: { user_id: req.user.id },
      order: [['completed_at', 'DESC']],
      limit: 20,
    });
    res.json(sessions);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

module.exports = { generateQuiz, submitQuiz, getHistory };
