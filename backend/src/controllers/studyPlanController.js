const { Op } = require('sequelize');
const {
  StudyPlanDailyTask,
  StudyPlanCardState,
  SrsCard,
  Vocabulary,
  GrammarLesson,
} = require('../models');
const { sm2 } = require('../utils/srs');

const JLPT_LEVELS = ['N5', 'N4', 'N3', 'N2', 'N1'];

function todayStr() {
  return new Date().toISOString().split('T')[0];
}

function addDays(dateText, days) {
  const d = new Date(`${dateText}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().split('T')[0];
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function calcCompletionRate(task) {
  const target = (task.target_vocab || 0) + (task.target_grammar || 0) + (task.target_review || 0);
  const done = (task.done_vocab || 0) + (task.done_grammar || 0) + (task.done_review || 0);
  if (target <= 0) return 0;
  return Math.round((done / target) * 10000) / 100;
}

async function buildDynamicTargets(userId) {
  const base = { vocab: 10, grammar: 2, review: 5 };

  const recent = await StudyPlanDailyTask.findAll({
    where: { user_id: userId },
    order: [['task_date', 'DESC']],
    limit: 3,
  });

  const lastTask = await StudyPlanDailyTask.findOne({
    where: { user_id: userId },
    order: [['task_date', 'DESC']],
  });

  let skippedDays = 0;
  if (lastTask?.task_date) {
    const now = new Date(todayStr());
    const last = new Date(lastTask.task_date);
    const diff = Math.floor((now - last) / (1000 * 60 * 60 * 24));
    skippedDays = diff > 1 ? (diff - 1) : 0;
  }

  if (recent.length < 2) {
    const downBySkip = skippedDays >= 1 ? 2 : 0;
    return {
      vocab: clamp(base.vocab - downBySkip, 6, 20),
      grammar: clamp(base.grammar - (skippedDays >= 2 ? 1 : 0), 1, 6),
      review: base.review,
      reason: skippedDays >= 1
        ? `检测到连续跳过 ${skippedDays} 天，先降低任务量重建节奏`
        : '默认任务包（新用户或数据不足）',
      rule_snapshot: { mode: skippedDays >= 1 ? 'down_skip' : 'default', recent_days: recent.length, skipped_days: skippedDays },
    };
  }

  const rates = recent.map((t) => Number(t.completion_rate || 0));
  const avgRate = rates.reduce((a, b) => a + b, 0) / rates.length;
  const lowDays = rates.filter((r) => r < 50).length;
  const highDays = rates.filter((r) => r >= 90).length;

  let vocab = base.vocab;
  let grammar = base.grammar;
  let review = base.review;
  let reason = '保持默认任务强度';
  let mode = 'stable';

  if (skippedDays >= 2) {
    vocab = clamp(base.vocab - 3, 6, 20);
    grammar = clamp(base.grammar - 1, 1, 6);
    review = clamp(base.review, 3, 12);
    reason = `连续跳过 ${skippedDays} 天，优先恢复学习习惯`; 
    mode = 'down_skip';
  } else if (highDays >= 2 && avgRate >= 90) {
    vocab = clamp(base.vocab + 2, 6, 20);
    grammar = clamp(base.grammar + 1, 1, 6);
    review = clamp(base.review + 1, 3, 12);
    reason = '连续高完成率，适度提升任务量';
    mode = 'up';
  } else if (lowDays >= 2 || avgRate < 50) {
    vocab = clamp(base.vocab - 2, 6, 20);
    grammar = clamp(base.grammar - 1, 1, 6);
    review = clamp(base.review, 3, 12);
    reason = '近期完成率偏低，自动减负以保证持续性';
    mode = 'down';
  }

  return {
    vocab,
    grammar,
    review,
    reason,
    rule_snapshot: {
      mode,
      avg_rate: Math.round(avgRate * 100) / 100,
      recent_rates: rates,
      skipped_days: skippedDays,
      base,
    },
  };
}

function buildFocusTopic(level, ruleMode) {
  const fallback = 'て形';
  const map = {
    N5: 'ます形 / て形',
    N4: '可能形 / 受身形',
    N3: '使役 / 条件',
    N2: '书面表达连接',
    N1: '高级语气与篇章衔接',
  };
  const levelTopic = map[level] || fallback;
  if (ruleMode === 'down') return `${levelTopic}（轻量复习）`;
  if (ruleMode === 'up') return `${levelTopic}（进阶挑战）`;
  return levelTopic;
}

async function getOrCreateTodayTask(user) {
  const userId = user.id;
  const today = todayStr();

  let task = await StudyPlanDailyTask.findOne({
    where: { user_id: userId, task_date: today },
  });

  if (task) return task;

  const dynamic = await buildDynamicTargets(userId);
  const recommendedFocus = buildFocusTopic(user.level || 'N5', dynamic.rule_snapshot.mode);

  task = await StudyPlanDailyTask.create({
    user_id: userId,
    task_date: today,
    status: 'not_started',
    target_vocab: dynamic.vocab,
    target_grammar: dynamic.grammar,
    target_review: dynamic.review,
    done_vocab: 0,
    done_grammar: 0,
    done_review: 0,
    completion_rate: 0,
    recommended_focus: recommendedFocus,
    recommend_reason: dynamic.reason,
    rule_snapshot: dynamic.rule_snapshot,
  });

  return task;
}

async function getTodayTask(req, res) {
  try {
    const task = await getOrCreateTodayTask(req.user);
    const today = todayStr();

    const dueToday = await SrsCard.count({
      where: { user_id: req.user.id, due_date: { [Op.lte]: today } },
    });

    const difficultDue = await StudyPlanCardState.count({
      where: {
        user_id: req.user.id,
        is_difficult: true,
        [Op.or]: [{ next_due_at: null }, { next_due_at: { [Op.lte]: today } }],
      },
    });

    const mastered = await StudyPlanCardState.count({
      where: { user_id: req.user.id, state: 'mastered' },
    });

    return res.json({
      date: task.task_date,
      status: task.status,
      targets: {
        vocabulary: task.target_vocab,
        grammar: task.target_grammar,
        review: task.target_review,
      },
      done: {
        vocabulary: task.done_vocab,
        grammar: task.done_grammar,
        review: task.done_review,
      },
      completion_rate: task.completion_rate,
      recommended_focus: task.recommended_focus,
      reason: task.recommend_reason,
      review_entries: {
        due_today: dueToday,
        difficult: difficultDue,
        mastered,
      },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

async function startTodayTask(req, res) {
  try {
    const task = await getOrCreateTodayTask(req.user);
    if (task.status === 'not_started') {
      task.status = 'in_progress';
      await task.save();
    }
    return res.json({ success: true, date: task.task_date, status: task.status });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

async function getStudyQueue(req, res) {
  try {
    const task = await getOrCreateTodayTask(req.user);
    const today = todayStr();
    const level = JLPT_LEVELS.includes(req.query.level) ? req.query.level : (req.user.level || 'N5');

    const [dueCards, difficultStates] = await Promise.all([
      SrsCard.findAll({
        where: {
          user_id: req.user.id,
          due_date: { [Op.lte]: today },
        },
        order: [['due_date', 'ASC']],
        limit: Math.max(task.target_review * 2, 20),
      }),
      StudyPlanCardState.findAll({
        where: {
          user_id: req.user.id,
          is_difficult: true,
          [Op.or]: [{ next_due_at: null }, { next_due_at: { [Op.lte]: today } }],
        },
        order: [['updated_at', 'DESC']],
        limit: 30,
      }),
    ]);

    const difficultSet = new Set(difficultStates.map((x) => `${x.card_type}:${x.ref_id}`));

    const reviewedRefKeys = new Set(dueCards.map((c) => `${c.card_type}:${c.ref_id}`));

    const [knownVocabStates, knownGrammarStates] = await Promise.all([
      StudyPlanCardState.findAll({ where: { user_id: req.user.id, card_type: 'vocabulary' }, attributes: ['ref_id'] }),
      StudyPlanCardState.findAll({ where: { user_id: req.user.id, card_type: 'grammar' }, attributes: ['ref_id'] }),
    ]);

    const knownVocabIds = knownVocabStates.map((x) => x.ref_id);
    const knownGrammarIds = knownGrammarStates.map((x) => x.ref_id);

    const [newVocab, newGrammar] = await Promise.all([
      Vocabulary.findAll({
        where: {
          jlpt_level: level,
          ...(knownVocabIds.length ? { id: { [Op.notIn]: knownVocabIds } } : {}),
        },
        limit: Math.max(task.target_vocab * 3, 30),
      }),
      GrammarLesson.findAll({
        where: {
          jlpt_level: level,
          ...(knownGrammarIds.length ? { id: { [Op.notIn]: knownGrammarIds } } : {}),
        },
        limit: Math.max(task.target_grammar * 3, 15),
      }),
    ]);

    const difficultReviewQueue = [];
    const normalReviewQueue = [];

    for (const c of dueCards) {
      const item = {
        source: difficultSet.has(`${c.card_type}:${c.ref_id}`) ? 'difficult' : 'review',
        card_type: c.card_type,
        ref_id: c.ref_id,
        due_date: c.due_date,
      };
      if (item.source === 'difficult') {
        difficultReviewQueue.push(item);
      } else {
        normalReviewQueue.push(item);
      }
    }

    const minDifficultQuota = Math.ceil((task.target_review || 0) * 0.4);
    const reviewQueue = [];
    reviewQueue.push(...difficultReviewQueue.slice(0, minDifficultQuota));

    const remainForReview = Math.max((task.target_review || 0) - reviewQueue.length, 0);
    if (remainForReview > 0) {
      reviewQueue.push(...normalReviewQueue.slice(0, remainForReview));
      const stillRemain = Math.max((task.target_review || 0) - reviewQueue.length, 0);
      if (stillRemain > 0) {
        reviewQueue.push(...difficultReviewQueue.slice(minDifficultQuota, minDifficultQuota + stillRemain));
      }
    }

    const queue = [...reviewQueue];

    for (const item of newVocab) {
      const key = `vocabulary:${item.id}`;
      if (reviewedRefKeys.has(key)) continue;
      queue.push({ source: 'new', card_type: 'vocabulary', ref_id: item.id, level: item.jlpt_level });
    }

    for (const item of newGrammar) {
      const key = `grammar:${item.id}`;
      if (reviewedRefKeys.has(key)) continue;
      queue.push({ source: 'new', card_type: 'grammar', ref_id: item.id, level: item.jlpt_level });
    }

    return res.json({
      date: task.task_date,
      status: task.status,
      level,
      targets: {
        vocabulary: task.target_vocab,
        grammar: task.target_grammar,
        review: task.target_review,
      },
      queue,
      summary: {
        review_due: dueCards.length,
        difficult_due: difficultStates.length,
        difficult_quota: minDifficultQuota,
        new_vocab: newVocab.length,
        new_grammar: newGrammar.length,
      },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

function mapAnswerToQuality(answer) {
  if (answer === 'unknown') return 1;
  if (answer === 'fuzzy') return 3;
  if (answer === 'mastered') return 5;
  return 4;
}

function deriveStateByAnswer(prevState, prevLevel, answer) {
  let level = prevLevel || 0;
  let state = prevState || 'new';
  let wrongStreakDelta = 0;

  if (answer === 'unknown') {
    level = Math.max(0, level - 1);
    state = level <= 1 ? 'learning' : 'review';
    wrongStreakDelta = 1;
  } else if (answer === 'fuzzy') {
    level = Math.max(0, level);
    state = 'learning';
  } else if (answer === 'mastered') {
    level = 5;
    state = 'mastered';
  } else {
    level = Math.min(5, level + 1);
    state = level >= 5 ? 'mastered' : (level >= 3 ? 'review' : 'learning');
  }

  return { state, level, wrongStreakDelta };
}

function nextDueByAnswer(answer, today) {
  if (answer === 'unknown') return addDays(today, 0);
  if (answer === 'fuzzy') return addDays(today, 0);
  if (answer === 'mastered') return addDays(today, 3);
  return addDays(today, 1);
}

async function submitStudyAnswer(req, res) {
  const { card_type, ref_id, answer } = req.body;
  if (!['vocabulary', 'grammar'].includes(card_type)) {
    return res.status(400).json({ error: 'card_type must be vocabulary|grammar' });
  }
  if (!ref_id) {
    return res.status(400).json({ error: 'ref_id is required' });
  }
  if (!['known', 'unknown', 'fuzzy', 'mastered'].includes(answer)) {
    return res.status(400).json({ error: 'answer must be known|unknown|fuzzy|mastered' });
  }

  try {
    const userId = req.user.id;
    const today = todayStr();
    const task = await getOrCreateTodayTask(req.user);

    const [planState, srsCard] = await Promise.all([
      StudyPlanCardState.findOne({ where: { user_id: userId, card_type, ref_id } }),
      SrsCard.findOne({ where: { user_id: userId, card_type, ref_id } }),
    ]);

    const prevState = planState?.state || 'new';
    const prevLevel = planState?.level || 0;

    const { state, level, wrongStreakDelta } = deriveStateByAnswer(prevState, prevLevel, answer);

    const wasDifficult = planState?.is_difficult === true;
    const wrongStreak = answer === 'unknown'
      ? ((planState?.wrong_streak || 0) + wrongStreakDelta)
      : 0;

    let isDifficult = false;
    if (answer === 'unknown') {
      isDifficult = wrongStreak >= 2 || wasDifficult;
    } else if (answer === 'mastered') {
      isDifficult = false;
    } else if (answer === 'known') {
      isDifficult = wasDifficult && level < 3;
    } else {
      isDifficult = wasDifficult;
    }

    if (planState) {
      await planState.update({
        state,
        level,
        wrong_streak: wrongStreak,
        is_difficult: isDifficult,
        last_answer: answer,
        next_due_at: nextDueByAnswer(answer, today),
        last_seen_at: new Date(),
      });
    } else {
      await StudyPlanCardState.create({
        user_id: userId,
        card_type,
        ref_id,
        state,
        level,
        wrong_streak: wrongStreak,
        is_difficult: isDifficult,
        last_answer: answer,
        next_due_at: nextDueByAnswer(answer, today),
        last_seen_at: new Date(),
      });
    }

    const quality = mapAnswerToQuality(answer);
    if (srsCard) {
      const updates = sm2(srsCard, quality);
      await srsCard.update(updates);
    } else {
      await SrsCard.create({
        user_id: userId,
        card_type,
        ref_id,
        due_date: today,
        repetitions: 0,
        ease_factor: 2.5,
        interval_days: 0,
      });
    }

    if (card_type === 'vocabulary') {
      task.done_vocab = (task.done_vocab || 0) + 1;
    } else {
      task.done_grammar = (task.done_grammar || 0) + 1;
    }

    if (srsCard && srsCard.due_date <= today) {
      task.done_review = (task.done_review || 0) + 1;
    }

    task.completion_rate = calcCompletionRate(task);
    if (task.status === 'not_started') task.status = 'in_progress';
    await task.save();

    return res.json({
      success: true,
      state: { state, level, is_difficult: isDifficult },
      task: {
        done_vocab: task.done_vocab,
        done_grammar: task.done_grammar,
        done_review: task.done_review,
        completion_rate: task.completion_rate,
      },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

async function getReviewEntries(req, res) {
  try {
    const today = todayStr();
    const userId = req.user.id;

    const [dueToday, difficult, mastered] = await Promise.all([
      SrsCard.count({ where: { user_id: userId, due_date: { [Op.lte]: today } } }),
      StudyPlanCardState.count({
        where: {
          user_id: userId,
          is_difficult: true,
          [Op.or]: [{ next_due_at: null }, { next_due_at: { [Op.lte]: today } }],
        },
      }),
      StudyPlanCardState.count({ where: { user_id: userId, state: 'mastered' } }),
    ]);

    return res.json({
      due_today: dueToday,
      difficult,
      mastered,
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

async function finishTodayTask(req, res) {
  try {
    const task = await getOrCreateTodayTask(req.user);
    task.completion_rate = calcCompletionRate(task);
    task.status = 'finished';
    await task.save();

    return res.json({
      success: true,
      date: task.task_date,
      completion_rate: task.completion_rate,
      done: {
        vocabulary: task.done_vocab,
        grammar: task.done_grammar,
        review: task.done_review,
      },
      targets: {
        vocabulary: task.target_vocab,
        grammar: task.target_grammar,
        review: task.target_review,
      },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

module.exports = {
  getTodayTask,
  startTodayTask,
  getStudyQueue,
  submitStudyAnswer,
  getReviewEntries,
  finishTodayTask,
};
