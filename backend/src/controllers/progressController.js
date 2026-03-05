const { UserProgress, QuizSession, SrsCard } = require('../models');
const { Op } = require('sequelize');
const { sequelize } = require('../config/database');

async function logActivity(req, res) {
  const { activity_type, ref_id, duration_seconds, score } = req.body;
  const xp = calculateXP(activity_type, score, duration_seconds);
  try {
    const record = await UserProgress.create({
      user_id: req.user.id,
      activity_type,
      ref_id,
      duration_seconds,
      score,
      xp_earned: xp,
      studied_at: new Date().toISOString().split('T')[0],
    });
    // Update total study time & streak
    await updateStreak(req.user);
    res.status(201).json({ record, xp_earned: xp });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

async function getSummary(req, res) {
  try {
    const userId = req.user.id;
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const dailyStats = await UserProgress.findAll({
      where: { user_id: userId, studied_at: { [Op.gte]: thirtyDaysAgo } },
      attributes: [
        'studied_at',
        [sequelize.fn('SUM', sequelize.col('duration_seconds')), 'total_seconds'],
        [sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp'],
        [sequelize.fn('COUNT', sequelize.col('id')), 'activity_count'],
      ],
      group: ['studied_at'],
      order: [['studied_at', 'ASC']],
    });

    const quizStats = await QuizSession.findAll({
      where: { user_id: userId, completed_at: { [Op.gte]: thirtyDaysAgo } },
      attributes: [
        [sequelize.fn('AVG', sequelize.col('score_percent')), 'avg_score'],
        [sequelize.fn('COUNT', sequelize.col('id')), 'total_quizzes'],
      ],
    });

    const srsStats = await SrsCard.findAll({
      where: { user_id: userId },
      attributes: [
        [sequelize.fn('COUNT', sequelize.col('id')), 'total'],
        [sequelize.fn('SUM', sequelize.literal('CASE WHEN is_graduated THEN 1 ELSE 0 END')), 'graduated'],
      ],
    });

    res.json({
      user: {
        streak_days: req.user.streak_days,
        total_study_minutes: req.user.total_study_minutes,
        level: req.user.level,
      },
      daily_stats: dailyStats,
      quiz_stats: quizStats[0],
      srs_stats: srsStats[0],
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

function calculateXP(type, score, duration) {
  const base = { vocabulary: 5, grammar: 8, listening: 10, quiz: 15, news: 12, srs_review: 3 };
  let xp = base[type] || 5;
  if (score) xp = Math.round(xp * (score / 100) * 2);
  if (duration > 300) xp += 5; // bonus for 5+ min sessions
  return xp;
}

async function updateStreak(user) {
  const today = new Date().toISOString().split('T')[0];
  const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];
  if (user.last_study_date === today) return;
  const streakDays = user.last_study_date === yesterday ? user.streak_days + 1 : 1;
  await user.update({
    last_study_date: today,
    streak_days: streakDays,
    total_study_minutes: user.total_study_minutes + 1,
  });
}

module.exports = { logActivity, getSummary };
