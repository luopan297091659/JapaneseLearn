const { Op } = require('sequelize');
const { sequelize } = require('../config/database');
const { GrammarExample, GrammarLesson, Vocabulary } = require('../models');

/**
 * 听力练习 API
 * 从 grammar_examples 和 vocabulary 的例句中抽取题目，
 * 优先使用有 audio_url 的数据，否则前端用 TTS 降级。
 */

// ── 获取听力练习题目 ─────────────────────────────────────────────────────────

/**
 * 清洗 meaning_zh：去除日语部分，只保留中文
 * 处理情况：
 *  - "はじめまして。→ 初次见面。" → "初次见面。"
 *  - "いただきます。→ 我开始吃饭了；我收下了。" → "我开始吃饭了；我收下了。"
 *  - 纯中文保持不变
 */
function cleanMeaningZh(text) {
  if (!text) return '';
  let s = text.trim();
  // 1. 如果含 →/->，取最后一段（中文部分）
  if (s.includes('→')) {
    s = s.split('→').pop().trim();
  } else if (s.includes('->')) {
    s = s.split('->').pop().trim();
  }
  // 2. 去除残留的平假名、片假名段落（保留汉字和中文标点）
  //    匹配连续的假名+日式标点序列
  s = s.replace(/[\u3040-\u309F\u30A0-\u30FF\u31F0-\u31FF\uFF65-\uFF9F]+[。、！？\s]*/g, '').trim();
  // 3. 去除开头的 "A：" "B：" 等对话标记
  s = s.replace(/^[A-Za-z]\s*[：:]\s*/g, '').trim();
  // 4. 如果清洗后为空，返回原文
  return s || text.trim();
}

async function getExercises(req, res) {
  const { level = 'N5', count = 10, source = 'all' } = req.query;
  const questionCount = Math.min(Math.max(parseInt(count) || 10, 5), 30);

  try {
    let questions = [];

    // 1. 从 grammar_examples 获取题目
    if (source === 'all' || source === 'grammar') {
      const grammarQuestions = await buildGrammarQuestions(level, questionCount);
      questions.push(...grammarQuestions);
    }

    // 2. 从 vocabulary example_sentence 获取题目
    if (source === 'all' || source === 'vocabulary') {
      const vocabQuestions = await buildVocabQuestions(level, questionCount);
      questions.push(...vocabQuestions);
    }

    // 3. 打乱并截取指定数量
    shuffle(questions);
    questions = questions.slice(0, questionCount);

    res.json({
      total: questions.length,
      level,
      data: questions,
    });
  } catch (err) {
    console.error('ListeningExercise error:', err);
    res.status(500).json({ error: err.message });
  }
}

// ── 从语法例句构建题目 ───────────────────────────────────────────────────────
async function buildGrammarQuestions(level, maxCount) {
  // 获取该级别的所有语法例句（有 meaning_zh 的）
  const examples = await GrammarExample.findAll({
    attributes: ['id', 'sentence', 'reading', 'meaning_zh', 'audio_url'],
    include: [{
      model: GrammarLesson,
      attributes: ['id', 'jlpt_level', 'title'],
      where: { jlpt_level: level },
    }],
    where: {
      sentence: { [Op.ne]: '' },
      meaning_zh: { [Op.ne]: '' },
    },
    order: sequelize.random(),
    limit: maxCount * 3, // 多取一些用来生成干扰项
  });

  if (examples.length < 4) return [];

  // 构建 MCQ 题目
  const questions = [];
  const selectedExamples = examples.slice(0, Math.min(maxCount, examples.length));

  for (const ex of selectedExamples) {
    const cleanAnswer = cleanMeaningZh(ex.meaning_zh);
    // 从同级别其他例句中选 3 个干扰项
    const distractors = examples
      .filter(e => e.id !== ex.id && cleanMeaningZh(e.meaning_zh) !== cleanAnswer)
      .slice(0, 3)
      .map(e => cleanMeaningZh(e.meaning_zh));

    if (distractors.length < 3) continue;

    const options = shuffle([cleanAnswer, ...distractors]);

    questions.push({
      id: ex.id,
      type: 'grammar',
      sentence: ex.sentence,
      reading: ex.reading,
      audio_url: ex.audio_url,
      correct_answer: cleanAnswer,
      options,
      grammar_title: ex.GrammarLesson?.title || null,
      jlpt_level: level,
    });
  }

  return questions;
}

// ── 从词汇例句构建题目 ───────────────────────────────────────────────────────
async function buildVocabQuestions(level, maxCount) {
  const vocabs = await Vocabulary.findAll({
    attributes: ['id', 'word', 'example_sentence', 'example_reading', 'example_meaning_zh', 'example_audio_url'],
    where: {
      jlpt_level: level,
      example_sentence: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
      example_meaning_zh: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
    },
    order: sequelize.random(),
    limit: maxCount * 3,
  });

  if (vocabs.length < 4) return [];

  const questions = [];
  const selectedVocabs = vocabs.slice(0, Math.min(maxCount, vocabs.length));

  for (const v of selectedVocabs) {
    const cleanAnswer = cleanMeaningZh(v.example_meaning_zh);
    const distractors = vocabs
      .filter(e => e.id !== v.id && cleanMeaningZh(e.example_meaning_zh) !== cleanAnswer)
      .slice(0, 3)
      .map(e => cleanMeaningZh(e.example_meaning_zh));

    if (distractors.length < 3) continue;

    const options = shuffle([cleanAnswer, ...distractors]);

    questions.push({
      id: v.id,
      type: 'vocabulary',
      sentence: v.example_sentence,
      reading: v.example_reading,
      audio_url: v.example_audio_url,
      correct_answer: cleanAnswer,
      options,
      word: v.word,
      jlpt_level: level,
    });
  }

  return questions;
}

// ── 获取听力练习统计信息 ─────────────────────────────────────────────────────
async function getStats(req, res) {
  try {
    const stats = {};
    for (const level of ['N5', 'N4', 'N3', 'N2', 'N1']) {
      // 语法例句数
      const grammarCount = await GrammarExample.count({
        include: [{
          model: GrammarLesson,
          where: { jlpt_level: level },
        }],
        where: {
          sentence: { [Op.ne]: '' },
          meaning_zh: { [Op.ne]: '' },
        },
      });

      // 有音频的语法例句数
      const grammarWithAudio = await GrammarExample.count({
        include: [{
          model: GrammarLesson,
          where: { jlpt_level: level },
        }],
        where: {
          sentence: { [Op.ne]: '' },
          meaning_zh: { [Op.ne]: '' },
          audio_url: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
        },
      });

      // 词汇例句数
      const vocabCount = await Vocabulary.count({
        where: {
          jlpt_level: level,
          example_sentence: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
          example_meaning_zh: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
        },
      });

      // 有音频的词汇例句数
      const vocabWithAudio = await Vocabulary.count({
        where: {
          jlpt_level: level,
          example_sentence: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
          example_audio_url: { [Op.and]: [{ [Op.ne]: null }, { [Op.ne]: '' }] },
        },
      });

      stats[level] = {
        grammar_examples: grammarCount,
        grammar_with_audio: grammarWithAudio,
        vocab_examples: vocabCount,
        vocab_with_audio: vocabWithAudio,
        total: grammarCount + vocabCount,
        total_with_audio: grammarWithAudio + vocabWithAudio,
      };
    }
    res.json(stats);
  } catch (err) {
    console.error('ListeningExercise stats error:', err);
    res.status(500).json({ error: err.message });
  }
}

// ── Fisher-Yates 洗牌算法 ────────────────────────────────────────────────────
function shuffle(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

module.exports = { getExercises, getStats };
