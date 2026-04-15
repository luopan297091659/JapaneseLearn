const { UserProgress, QuizSession, SrsCard, StudyPlanCardState, Vocabulary, GrammarLesson } = require('../models');
const { Op } = require('sequelize');
const { sequelize } = require('../config/database');

/**
 * 从请求头 X-Client-Date 获取客户端本地日期，校验合理性（±1天内），
 * 不合法或缺失时回退到服务器 UTC 日期。
 */
function getClientDate(req) {
  const clientDate = req.headers['x-client-date'];
  if (clientDate && /^\d{4}-\d{2}-\d{2}$/.test(clientDate)) {
    const cd = new Date(clientDate + 'T00:00:00Z');
    const now = Date.now();
    const diff = Math.abs(cd.getTime() - now);
    // 允许±26小时（覆盖所有时区差异 + 容错）
    if (diff < 26 * 60 * 60 * 1000) return clientDate;
  }
  return new Date().toISOString().split('T')[0];
}

function getClientYesterday(clientToday) {
  const d = new Date(clientToday + 'T00:00:00Z');
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().split('T')[0];
}

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
      studied_at: getClientDate(req),
    });
    // Update total study time & streak
    await updateStreak(req.user, req);
    res.status(201).json({ record, xp_earned: xp });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ── 今日统计 + 目标进度 ──────────────────────────────────────────────────────
async function getDailyGoals(req, res) {
  try {
    const userId = req.user.id;
    const today = getClientDate(req);

    // 合并查询：今日统计 + 今日 SRS 复习数 + 总 XP + 测验数并行执行
    const [todayStats, todayByType, totalXpRow, todayQuizCount, srsDueCount, todayQuizByType] = await Promise.all([
      UserProgress.findAll({
        where: { user_id: userId, studied_at: today },
        attributes: [
          [sequelize.fn('SUM', sequelize.col('duration_seconds')), 'total_seconds'],
          [sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp'],
          [sequelize.fn('COUNT', sequelize.col('id')), 'activity_count'],
        ],
      }),
      UserProgress.findAll({
        where: { user_id: userId, studied_at: today },
        attributes: [
          'activity_type',
          [sequelize.fn('COUNT', sequelize.col('id')), 'count'],
        ],
        group: ['activity_type'],
      }),
      UserProgress.findAll({
        where: { user_id: userId },
        attributes: [[sequelize.fn('SUM', sequelize.col('xp_earned')), 'total_xp']],
      }),
      QuizSession.count({
        where: {
          user_id: userId,
          completed_at: { [Op.gte]: new Date(today) },
        },
      }),
      SrsCard.count({
        where: { user_id: userId, due_date: { [Op.lte]: today } },
      }),
      QuizSession.findAll({
        where: {
          user_id: userId,
          completed_at: { [Op.gte]: new Date(today) },
        },
        attributes: [
          'quiz_type',
          [sequelize.fn('COUNT', sequelize.col('id')), 'count'],
        ],
        group: ['quiz_type'],
      }),
    ]);

    // 今日 SRS 复习数
    const todaySrsCount = todayByType.find(t => t.activity_type === 'srs_review');

    const totalXp = parseInt(totalXpRow[0]?.dataValues?.total_xp) || 0;
    const dailyGoalMinutes = req.user.daily_goal_minutes || 15;
    const todaySeconds = parseInt(todayStats[0]?.dataValues?.total_seconds) || 0;
    const todayXp = parseInt(todayStats[0]?.dataValues?.total_xp) || 0;
    const todayActivities = parseInt(todayStats[0]?.dataValues?.activity_count) || 0;

    // ── 实时计算连续打卡 ──
    const yesterday = getClientYesterday(today);
    const lastStudy = req.user.last_study_date;
    let realStreak = req.user.streak_days || 0;
    if (lastStudy && lastStudy !== today && lastStudy !== yesterday) {
      realStreak = 0;
    }

    // 测验分类统计
    const quizBreakdown = {};
    for (const row of todayQuizByType) {
      quizBreakdown[row.quiz_type] = parseInt(row.dataValues.count) || 0;
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
        quiz_breakdown: quizBreakdown,
        srs_review_count: parseInt(todaySrsCount?.dataValues?.count) || 0,
      },
      goals: {
        study_minutes: { target: dailyGoalMinutes, current: Math.floor(todaySeconds / 60) },
        lessons: { target: 1, current: Math.min(todayActivities, 1) },
        reviews: { target: Math.max(srsDueCount, 1), current: parseInt(todaySrsCount?.dataValues?.count) || 0 },
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

    // 测验分类统计（30天内按类型分组）
    const quizByType = await QuizSession.findAll({
      where: { user_id: userId, completed_at: { [Op.gte]: thirtyDaysAgo } },
      attributes: [
        'quiz_type',
        [sequelize.fn('COUNT', sequelize.col('id')), 'count'],
        [sequelize.fn('AVG', sequelize.col('score_percent')), 'avg_score'],
      ],
      group: ['quiz_type'],
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
    const today = getClientDate(req);
    const yesterday = getClientYesterday(today);
    const lastStudy = req.user.last_study_date;
    let realStreak = req.user.streak_days || 0;
    if (lastStudy && lastStudy !== today && lastStudy !== yesterday) {
      realStreak = 0; // 链条已断，实时归零
    }

    // 测验分类明细
    const quizBreakdown = {};
    for (const row of quizByType) {
      quizBreakdown[row.quiz_type] = {
        count: parseInt(row.dataValues.count) || 0,
        avg_score: Math.round(parseFloat(row.dataValues.avg_score) || 0),
      };
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
      quiz_breakdown: quizBreakdown,
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

async function updateStreak(user, req) {
  const today = getClientDate(req);
  if (user.last_study_date && user.last_study_date >= today) return;
  const yesterday = getClientYesterday(today);
  const streakDays = (user.last_study_date && user.last_study_date >= yesterday)
    ? user.streak_days + 1 : 1;
  await user.update({
    last_study_date: today,
    streak_days: streakDays,
    total_study_minutes: user.total_study_minutes + 1,
  });
}

// ── 学习计划进度统计 (用于学习计划详情页) ──────────────────────────────────
async function getStudyPlanProgress(req, res) {
  const { level, type } = req.query; // type: 'vocabulary'|'grammar'|'anki'
  try {
    if (!level || !type) {
      return res.status(400).json({ error: 'level and type are required' });
    }

    const userId = req.user.id;
    const cardType = type === 'anki' ? 'anki' : (type === 'grammar' ? 'grammar' : 'vocabulary');

    // Count total cards from source table
    let totalCards = 0;
    if (cardType === 'vocabulary') {
      totalCards = await Vocabulary.count({ where: { jlpt_level: level } });
    } else if (cardType === 'grammar') {
      totalCards = await GrammarLesson.count({ where: { jlpt_level: level } });
    }

    // Get learning flow states from StudyPlanCardState, filtered by JLPT level
    let learningCount = 0, reviewCount = 0, masteredCount = 0;
    if (cardType === 'vocabulary' || cardType === 'grammar') {
      const sourceTable = cardType === 'vocabulary' ? 'vocabulary' : 'grammar_lessons';
      const result = await sequelize.query(
        `SELECT s.state, COUNT(*) AS cnt
         FROM study_plan_card_states s
         JOIN ${sourceTable} t ON s.ref_id = t.id
         WHERE s.user_id = ? AND s.card_type = ? AND t.jlpt_level = ?
         GROUP BY s.state`,
        { replacements: [userId, cardType, level] }
      );
      const countRows = result[0] || [];
      for (const r of countRows) {
        switch (r.state) {
          case 'learning': learningCount = parseInt(r.cnt) || 0; break;
          case 'review': reviewCount = parseInt(r.cnt) || 0; break;
          case 'mastered': masteredCount = parseInt(r.cnt) || 0; break;
        }
      }
    }
    const trackedCount = learningCount + reviewCount + masteredCount;
    const newCount = Math.max(0, totalCards - trackedCount);

    res.json({
      level,
      type,
      total: totalCards,
      progress: {
        new: newCount,
        learning: learningCount,
        review: reviewCount,
        mastered: masteredCount,
      },
      overdue_count: 0,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

// ── 签到 ──────────────────────────────────────────────────────────────────

async function checkin(req, res) {
  try {
    const user = req.user;
    const today = getClientDate(req);

    if (user.last_study_date && user.last_study_date >= today) {
      // Already checked in today (or from a later timezone)
      return res.json({
        already: true,
        streak_days: user.streak_days,
        last_study_date: user.last_study_date,
      });
    }

    const yesterday = getClientYesterday(today);
    // 延续连续天数：last_study_date 是昨天或更近（跨时区可能为今天与昨天之间）
    const streakDays = (user.last_study_date && user.last_study_date >= yesterday)
      ? user.streak_days + 1 : 1;
    await user.update({
      last_study_date: today,
      streak_days: streakDays,
    });

    // Give 5 XP for check-in
    await UserProgress.create({
      user_id: user.id,
      activity_type: 'checkin',
      duration_seconds: 0,
      score: null,
      xp_earned: 5,
      studied_at: today,
    });

    res.json({
      already: false,
      streak_days: streakDays,
      last_study_date: today,
      xp_earned: 5,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
}

module.exports = { logActivity, getSummary, getDailyGoals, getStudyPlanProgress, checkin };
