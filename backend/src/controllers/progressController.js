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

// ── 今日统计 + 目标进度 ──────────────────────────────────────────────────────
async function getDailyGoals(req, res) {
  try {
    const userId = req.user.id;
    const today = new Date().toISOString().split('T')[0];

    // 今日学习统计
    const todayStats = await UserProgress.findAll({
      where: { user_id: userId, studied_at: today },
      attributes: [
        [sequelize.fn('SUM', sequelize.col('duration_seconds')), 'total_seconds'],
        [sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp'],
        [sequelize.fn('COUNT', sequelize.col('id')), 'activity_count'],
      ],
    });

    // 今日各类型活动计数
    const todayByType = await UserProgress.findAll({
      where: { user_id: userId, studied_at: today },
      attributes: [
        'activity_type',
        [sequelize.fn('COUNT', sequelize.col('id')), 'count'],
      ],
      group: ['activity_type'],
    });

    // 今日测验数
    const todayQuizCount = await QuizSession.count({
      where: {
        user_id: userId,
        completed_at: { [Op.gte]: new Date(today) },
      },
    });

    // 今日 SRS 复习数
    const todaySrsCount = todayByType.find(t => t.activity_type === 'srs_review');

    // 总 XP
    const totalXpRow = await UserProgress.findAll({
      where: { user_id: userId },
      attributes: [[sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp']],
    });

    const totalXp = parseInt(totalXpRow[0]?.dataValues?.total_xp) || 0;
    const dailyGoalMinutes = req.user.daily_goal_minutes || 15;
    const todaySeconds = parseInt(todayStats[0]?.dataValues?.total_seconds) || 0;
    const todayXp = parseInt(todayStats[0]?.dataValues?.total_xp) || 0;
    const todayActivities = parseInt(todayStats[0]?.dataValues?.activity_count) || 0;

    // ── 实时计算连续打卡 ──
    const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];
    const lastStudy = req.user.last_study_date;
    let realStreak = req.user.streak_days || 0;
    if (lastStudy && lastStudy !== today && lastStudy !== yesterday) {
      realStreak = 0;
    }

    res.json({
      streak_days: realStreak,
      total_xp: totalXp,
      level: req.user.level || 'N5',
      today: {
        study_seconds: todaySeconds,
        xp_earned: todayXp,
        activity_count: todayActivities,
        quiz_count: todayQuizCount,
        srs_review_count: parseInt(todaySrsCount?.dataValues?.count) || 0,
      },
      goals: {
        study_minutes: { target: dailyGoalMinutes, current: Math.floor(todaySeconds / 60) },
        lessons: { target: 1, current: Math.min(todayActivities, 1) },
        reviews: { target: 20, current: parseInt(todaySrsCount?.dataValues?.count) || 0 },
      },
    });
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

    // ── 本周统计 ──
    const weekStart = new Date();
    weekStart.setDate(weekStart.getDate() - weekStart.getDay());
    weekStart.setHours(0,0,0,0);
    const weeklyAgg = await UserProgress.findAll({
      where: { user_id: userId, studied_at: { [Op.gte]: weekStart.toISOString().split('T')[0] } },
      attributes: [
        [sequelize.fn('SUM', sequelize.col('xp_earned')), 'week_xp'],
        [sequelize.fn('SUM', sequelize.col('duration_seconds')), 'week_seconds'],
        [sequelize.fn('COUNT', sequelize.col('id')), 'week_activities'],
        [sequelize.fn('COUNT', sequelize.fn('DISTINCT', sequelize.col('studied_at'))), 'week_days'],
      ],
    });
    const weekQuiz = await QuizSession.findAll({
      where: { user_id: userId, completed_at: { [Op.gte]: weekStart } },
      attributes: [
        [sequelize.fn('AVG', sequelize.col('score_percent')), 'avg_score'],
        [sequelize.fn('COUNT', sequelize.col('id')), 'total_quizzes'],
      ],
    });
    // 总 XP
    const totalXpRow = await UserProgress.findAll({
      where: { user_id: userId },
      attributes: [[sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp']],
    });

    // ── 实时计算连续打卡 ──
    const today = new Date().toISOString().split('T')[0];
    const yesterday = new Date(Date.now() - 86400000).toISOString().split('T')[0];
    const lastStudy = req.user.last_study_date;
    let realStreak = req.user.streak_days || 0;
    if (lastStudy && lastStudy !== today && lastStudy !== yesterday) {
      realStreak = 0; // 链条已断，实时归零
    }

    res.json({
      user: {
        streak_days: realStreak,
        total_study_minutes: req.user.total_study_minutes,
        level: req.user.level,
        total_xp: parseInt(totalXpRow[0]?.dataValues?.total_xp) || 0,
      },
      daily_stats: dailyStats,
      quiz_stats: quizStats[0],
      srs_stats: srsStats[0],
      weekly_stats: {
        xp: parseInt(weeklyAgg[0]?.dataValues?.week_xp) || 0,
        study_seconds: parseInt(weeklyAgg[0]?.dataValues?.week_seconds) || 0,
        activities: parseInt(weeklyAgg[0]?.dataValues?.week_activities) || 0,
        study_days: parseInt(weeklyAgg[0]?.dataValues?.week_days) || 0,
        quiz_count: parseInt(weekQuiz[0]?.dataValues?.total_quizzes) || 0,
        quiz_avg_score: Math.round(parseFloat(weekQuiz[0]?.dataValues?.avg_score) || 0),
      },
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

module.exports = { logActivity, getSummary, getDailyGoals };
