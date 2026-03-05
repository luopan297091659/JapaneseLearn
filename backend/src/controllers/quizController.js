const { QuizQuestion, QuizSession } = require('../models');
const { Op } = require('sequelize');

async function generateQuiz(req, res) {
  const { level = 'N5', quiz_type = 'vocabulary', count = 10 } = req.query;
  try {
    const { sequelize: db } = require('../config/database');
    const questions = await QuizQuestion.findAll({
      where: {
        jlpt_level: level,
        question_type: { [Op.in]: quizTypeToTypes(quiz_type) },
        options: { [Op.not]: null },  // 只取有选项的题目
      },
      order: db.literal('RAND()'),   // MySQL 随机排序，每次不同
      limit: Math.min(parseInt(count) || 10, 50),
    });
    if (!questions || questions.length === 0) {
      return res.json({ quiz_type, level, questions: [] });
    }
    res.json({ quiz_type, level, questions });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
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
