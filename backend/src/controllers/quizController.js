const { QuizQuestion, QuizSession } = require('../models');
const { Op } = require('sequelize');

async function generateQuiz(req, res) {
  const { level = 'N5', quiz_type = 'vocabulary', count = 10 } = req.query;
  const safeCount = Math.min(parseInt(count) || 10, 50);
  try {
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

module.exports = { generateQuiz, submitQuiz, getHistory };
