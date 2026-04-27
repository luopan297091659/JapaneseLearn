const path = require('path');
const { sequelize } = require('../config/database');
const { JlptExamPaper, JlptExamQuestion, JlptExamAttempt } = require('../models');

function normalizePaperPayload(body = {}) {
  const level = String(body.level || 'N3').toUpperCase();
  const year = parseInt(body.year, 10);
  const session = ['07', '12', 'other'].includes(body.session) ? body.session : 'other';
  const title = String(body.title || '').trim();
  const slug = String(body.slug || '').trim();

  if (!['N5', 'N4', 'N3', 'N2', 'N1'].includes(level)) throw new Error('level 无效');
  if (!year || year < 2000 || year > 2100) throw new Error('year 无效');
  if (!title) throw new Error('title 不能为空');
  if (!slug) throw new Error('slug 不能为空');

  const meta = body.meta_json && typeof body.meta_json === 'object' ? { ...body.meta_json } : {};
  const incomingMaterials = body.section_materials && typeof body.section_materials === 'object'
    ? body.section_materials
    : (meta.section_materials && typeof meta.section_materials === 'object' ? meta.section_materials : null);

  if (incomingMaterials) {
    const normalizedMaterials = {};
    ['reading', 'listening'].forEach(key => {
      const item = incomingMaterials[key] && typeof incomingMaterials[key] === 'object' ? incomingMaterials[key] : null;
      if (!item) return;
      const text = String(item.text || '').trim();
      const imageUrl = String(item.image_url || '').trim();
      const audioUrl = String(item.audio_url || '').trim();
      if (text || imageUrl || audioUrl) normalizedMaterials[key] = { text, image_url: imageUrl, audio_url: audioUrl };
    });
    if (Object.keys(normalizedMaterials).length) {
      meta.section_materials = normalizedMaterials;
    }
  }

  return {
    level,
    year,
    session,
    title,
    slug,
    source_label: body.source_label ? String(body.source_label).trim() : null,
    description: body.description ? String(body.description).trim() : null,
    duration_minutes: body.duration_minutes ? parseInt(body.duration_minutes, 10) : null,
    is_published: !!body.is_published,
    sort_order: Number.isFinite(Number(body.sort_order)) ? Number(body.sort_order) : 0,
    tags: Array.isArray(body.tags) ? body.tags : null,
    meta_json: Object.keys(meta).length ? meta : null,
  };
}

function buildFallbackOption(key) {
  return { key: String(key), text: `选项${key}（待校对）` };
}

function normalizeOptions(rawOptions, answer) {
  const optionMap = new Map();

  (Array.isArray(rawOptions) ? rawOptions : []).forEach((opt, optIndex) => {
    if (typeof opt === 'string') {
      const text = opt.trim();
      const key = String(optIndex + 1);
      if (text && !optionMap.has(key)) optionMap.set(key, { key, text });
      return;
    }

    const key = String(opt?.key || optIndex + 1).trim();
    const text = String(opt?.text || '').trim();
    const imageUrl = String(opt?.image_url || '').trim();
    if (key && text && !optionMap.has(key)) {
      optionMap.set(key, imageUrl ? { key, text, image_url: imageUrl } : { key, text });
    }
  });

  if (answer && !optionMap.has(answer)) {
    optionMap.set(answer, buildFallbackOption(answer));
  }

  ['1', '2', '3', '4'].forEach(key => {
    if (optionMap.size < 2 && !optionMap.has(key)) {
      optionMap.set(key, buildFallbackOption(key));
    }
  });

  return Array.from(optionMap.values()).slice(0, 4);
}

function normalizeStoredQuestionOptions(rawOptions, answer) {
  let parsed = rawOptions;

  if (typeof parsed === 'string') {
    try {
      parsed = JSON.parse(parsed);
    } catch (_) {
      parsed = parsed
        .split(/\r?\n|[|｜]/)
        .map(item => item.trim())
        .filter(Boolean);
    }
  }

  if (parsed && !Array.isArray(parsed) && typeof parsed === 'object') {
    parsed = Object.entries(parsed).map(([key, text]) => ({ key, text }));
  }

  return normalizeOptions(parsed, answer);
}

function pickField(row = {}, keys = []) {
  for (const key of keys) {
    if (row[key] != null && String(row[key]).trim() !== '') return String(row[key]).trim();
  }
  return '';
}

function parseCsvLine(line = '') {
  const out = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    const next = line[i + 1];
    if (ch === '"') {
      if (inQuotes && next === '"') {
        current += '"';
        i += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }
    if (ch === ',' && !inQuotes) {
      out.push(current);
      current = '';
      continue;
    }
    current += ch;
  }
  out.push(current);
  return out;
}

function parseCsvToRows(text = '') {
  const lines = String(text)
    .replace(/^\uFEFF/, '')
    .split(/\r?\n/)
    .filter(line => line.trim());
  if (!lines.length) return [];

  const headers = parseCsvLine(lines[0]).map(h => String(h || '').trim());
  return lines.slice(1).map(line => {
    const values = parseCsvLine(line);
    return headers.reduce((acc, header, index) => {
      acc[header] = String(values[index] || '').trim();
      return acc;
    }, {});
  });
}

function parseTags(raw) {
  if (!raw) return [];
  return String(raw)
    .split(/[|,，;；]/)
    .map(item => item.trim())
    .filter(Boolean);
}

function isQuestionTypeDescription(value) {
  const s = String(value || '').replace(/[：:]/g, '').replace(/\s+/g, '').trim();
  if (!s) return false;
  return /^問題[0-9０-９]+$/i.test(s) || /^问[题題][0-9０-９]+$/i.test(s);
}

function parseSectionMaterialsFromRows(rows = [], forcedSectionType = '') {
  const first = rows[0] || {};
  const materials = {};

  const readingText = pickField(first, ['reading_text', 'reading_passage', 'reading_article', '読解文章', '读解文章', '読解素材']);
  const readingImage = pickField(first, ['reading_image_url', 'reading_passage_image_url', '読解图片', '读解图片']);
  const listeningText = pickField(first, ['listening_text', 'listening_passage', 'listening_article', '聴解文章', '听解文章', '聴解素材']);
  const listeningImage = pickField(first, ['listening_image_url', 'listening_passage_image_url', '聴解图片', '听解图片']);
  const listeningAudio = pickField(first, ['listening_audio_url', 'audio_url', '聴解音频', '听解音频']);

  if (readingText || readingImage) materials.reading = { text: readingText, image_url: readingImage };
  if (listeningText || listeningImage || listeningAudio) materials.listening = { text: listeningText, image_url: listeningImage, audio_url: listeningAudio };

  const genericText = pickField(first, ['section_text', 'section_material_text', '文章', '素材']);
  const genericImage = pickField(first, ['section_image_url', 'section_material_image_url', '文章图片', '素材图片']);
  const genericAudio = pickField(first, ['section_audio_url', 'section_material_audio_url', '音频', '音频URL']);
  if (genericText || genericImage) {
    if (forcedSectionType === 'reading') materials.reading = { text: genericText, image_url: genericImage };
    if (forcedSectionType === 'listening') materials.listening = { text: genericText, image_url: genericImage, audio_url: genericAudio };
  } else if (genericAudio && forcedSectionType === 'listening') {
    materials.listening = { text: '', image_url: '', audio_url: genericAudio };
  }

  return Object.keys(materials).length ? materials : null;
}

function normalizeAnswerValue(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  const map = {
    '①': '1', '❶': '1', 'Ａ': '1', 'A': '1',
    '②': '2', '❷': '2', 'Ｂ': '2', 'B': '2',
    '③': '3', '❸': '3', 'Ｃ': '3', 'C': '3',
    '④': '4', '❹': '4', 'Ｄ': '4', 'D': '4',
  };
  return map[raw] || raw;
}

function resolveAnswerFromRow(row, options) {
  const normalized = normalizeAnswerValue(row.answer || row.correct_answer);
  if (!normalized) return options[0]?.key || '1';

  if (options.some(opt => opt.key === normalized)) return normalized;

  const byText = options.find(opt => String(opt.text || '').trim() === normalized);
  if (byText) return byText.key;

  return options[0]?.key || '1';
}

function buildOptionsFromCsvRow(row) {
  const optionTextKeys = [
    ['option_1', 'option1', '选项1', 'A', 'a'],
    ['option_2', 'option2', '选项2', 'B', 'b'],
    ['option_3', 'option3', '选项3', 'C', 'c'],
    ['option_4', 'option4', '选项4', 'D', 'd'],
  ];
  const optionImageKeys = [
    ['option_1_image_url', 'option1_image_url', '选项1图片', 'A_image_url'],
    ['option_2_image_url', 'option2_image_url', '选项2图片', 'B_image_url'],
    ['option_3_image_url', 'option3_image_url', '选项3图片', 'C_image_url'],
    ['option_4_image_url', 'option4_image_url', '选项4图片', 'D_image_url'],
  ];

  const options = optionTextKeys
    .map((keys, index) => {
      const text = pickField(row, keys);
      const imageUrl = pickField(row, optionImageKeys[index]);
      if (!text) return null;
      return imageUrl ? { key: String(index + 1), text, image_url: imageUrl } : { key: String(index + 1), text };
    })
    .filter(Boolean);

  if (options.length >= 2) return options;

  const fallback = String(row.options || '').trim();
  if (fallback) {
    const split = fallback.split(/[|｜\n]/).map(s => s.trim()).filter(Boolean);
    return split.map((text, index) => ({ key: String(index + 1), text }));
  }

  return [];
}

function normalizeQuestionsFromCsvRows(rows = [], forcedSectionType = '') {
  const questions = [];
  let skipped = 0;

  rows.forEach((row, index) => {
    const options = buildOptionsFromCsvRow(row);
    const answer = resolveAnswerFromRow(row, options);
    const prompt = pickField(row, ['prompt', '题干', '题目']);
    const questionGroup = pickField(row, ['question_group', '题组']);
    const sectionTitle = pickField(row, ['section_title', '分区标题']);
    const sectionType = forcedSectionType || pickField(row, ['section_type', '题型']) || 'reading';

    // 忽略“問題 1 / 問題11”这类题型描述行
    if ((isQuestionTypeDescription(prompt) || isQuestionTypeDescription(questionGroup) || isQuestionTypeDescription(sectionTitle)) && options.length < 2) {
      skipped += 1;
      return;
    }

    if (!prompt) throw new Error(`第 ${index + 1} 行缺少题干（prompt/题干）`);
    if (options.length < 2) throw new Error(`第 ${index + 1} 行至少需要 2 个选项`);

    const meta = {};
    const promptImageUrl = pickField(row, ['prompt_image_url', 'question_image_url', '题干图片']);
    const passageImageUrl = pickField(row, ['passage_image_url', '材料图片']);
    if (promptImageUrl) meta.prompt_image_url = promptImageUrl;
    if (passageImageUrl) meta.passage_image_url = passageImageUrl;

    questions.push({
      section_type: sectionType,
      section_title: sectionTitle || null,
      question_group: questionGroup || null,
      question_no: pickField(row, ['question_no', '题号']) || String(questions.length + 1),
      sort_order: pickField(row, ['sort_order', '排序']) ? Number(pickField(row, ['sort_order', '排序'])) : questions.length + 1,
      prompt,
      passage: pickField(row, ['passage', '材料']) || null,
      transcript: pickField(row, ['transcript', '听力原文']) || null,
      options,
      answer,
      explanation: pickField(row, ['explanation', '日文解析']) || null,
      explanation_zh: pickField(row, ['explanation_zh', '中文解析']) || null,
      knowledge_points: parseTags(pickField(row, ['knowledge_points', '知识点'])),
      score: pickField(row, ['score', '分值']) ? Number(pickField(row, ['score', '分值'])) : 1,
      audio_url: pickField(row, ['audio_url', '音频地址']) || null,
      meta_json: Object.keys(meta).length ? meta : (pickField(row, ['source_question_no']) ? { source_question_no: String(pickField(row, ['source_question_no'])) } : null),
    });
  });

  if (!questions.length) {
    throw new Error('没有可导入的有效题目（可能全部是“問題+数字”描述行）');
  }

  return { questions, skipped };
}

function normalizePaperFromCsvRows(rows = []) {
  if (!rows.length) throw new Error('CSV 内容为空');
  const first = rows[0];

  const title = pickField(first, ['paper_title', 'title', '试卷标题', '标题']);
  const slug = pickField(first, ['paper_slug', 'slug', '试卷slug', '试卷标识']);
  const level = pickField(first, ['level', 'jlpt_level', '级别']);
  const yearRaw = pickField(first, ['year', '年份']);
  const session = pickField(first, ['session', '场次']) || 'other';

  const paper = {
    title,
    slug,
    level,
    year: Number(yearRaw),
    session,
    duration_minutes: pickField(first, ['duration_minutes', '时长']) ? Number(pickField(first, ['duration_minutes', '时长'])) : null,
    source_label: pickField(first, ['source_label', '来源标识']),
    sort_order: pickField(first, ['paper_sort_order', 'sort_order', '排序']) ? Number(pickField(first, ['paper_sort_order', 'sort_order', '排序'])) : 0,
    description: pickField(first, ['paper_description', 'description', '简介']),
    tags: parseTags(pickField(first, ['paper_tags', 'tags', '标签'])),
    is_published: ['1', 'true', 'yes', 'published', '已发布'].includes(String(pickField(first, ['is_published', '发布状态'])).toLowerCase()),
  };

  if (!paper.title || !paper.slug || !paper.level || !paper.year) {
    throw new Error('CSV 缺少必要字段：title/slug/level/year（支持中文列名：标题/试卷slug/级别/年份）');
  }

  const parsed = normalizeQuestionsFromCsvRows(rows);
  const materials = parseSectionMaterialsFromRows(rows);

  return {
    ...paper,
    questions: parsed.questions,
    meta_json: materials ? { section_materials: materials } : null,
  };
}

function normalizePaperFromJsonObject(parsed = {}) {
  if (!parsed || typeof parsed !== 'object') {
    throw new Error('JSON 内容格式无效');
  }

  if (Array.isArray(parsed)) {
    return normalizePaperFromCsvRows(parsed);
  }

  if (!Array.isArray(parsed.questions)) {
    throw new Error('JSON 需要包含 questions 数组，或使用 CSV 行数组格式');
  }

  return parsed;
}

async function upsertPaperWithQuestions(rawBody, transaction) {
  const paperData = normalizePaperPayload(rawBody);
  const questions = normalizeQuestions(rawBody.questions);

  const existing = await JlptExamPaper.findOne({ where: { slug: paperData.slug }, transaction });
  if (existing) {
    await existing.update(paperData, { transaction });
    await JlptExamQuestion.destroy({ where: { paper_id: existing.id }, transaction });
    await JlptExamQuestion.bulkCreate(
      questions.map(question => ({ ...question, paper_id: existing.id })),
      { transaction }
    );
    return { action: 'updated', id: existing.id };
  }

  const created = await JlptExamPaper.create(paperData, { transaction });
  await JlptExamQuestion.bulkCreate(
    questions.map(question => ({ ...question, paper_id: created.id })),
    { transaction }
  );
  return { action: 'created', id: created.id };
}

function normalizeQuestions(input) {
  if (!Array.isArray(input) || input.length === 0) {
    throw new Error('questions 不能为空');
  }

  return input.map((item, index) => {
    const sectionType = item.section_type;
    if (!['vocabulary_grammar', 'reading', 'listening'].includes(sectionType)) {
      throw new Error(`第 ${index + 1} 题 section_type 无效`);
    }

    const prompt = String(item.prompt || '').trim();
    const questionNo = String(item.question_no || '').trim();
    const answer = String(item.answer || '').trim();
    const options = normalizeOptions(item.options, answer);

    if (!questionNo) throw new Error(`第 ${index + 1} 题 question_no 不能为空`);
    if (sectionType === 'vocabulary_grammar' && !prompt) throw new Error(`第 ${index + 1} 题 prompt 不能为空`);
    if (options.length < 2) throw new Error(`第 ${index + 1} 题至少需要 2 个选项`);
    if (!answer) throw new Error(`第 ${index + 1} 题 answer 不能为空`);
    if (!options.some(opt => opt.key === answer)) throw new Error(`第 ${index + 1} 题 answer 不在 options 中`);

    const meta = item.meta_json && typeof item.meta_json === 'object' ? { ...item.meta_json } : {};
    if (item.prompt_image_url) meta.prompt_image_url = String(item.prompt_image_url).trim();
    if (item.passage_image_url) meta.passage_image_url = String(item.passage_image_url).trim();

    return {
      section_type: sectionType,
      section_title: item.section_title ? String(item.section_title).trim() : null,
      question_group: item.question_group ? String(item.question_group).trim() : null,
      question_no: questionNo,
      sort_order: Number.isFinite(Number(item.sort_order)) ? Number(item.sort_order) : index,
      prompt,
      passage: item.passage ? String(item.passage).trim() : null,
      transcript: item.transcript ? String(item.transcript).trim() : null,
      options,
      answer,
      explanation: item.explanation ? String(item.explanation).trim() : null,
      explanation_zh: item.explanation_zh ? String(item.explanation_zh).trim() : null,
      knowledge_points: Array.isArray(item.knowledge_points) ? item.knowledge_points : null,
      score: Number.isFinite(Number(item.score)) ? Number(item.score) : 1,
      audio_url: item.audio_url ? String(item.audio_url).trim() : null,
      meta_json: Object.keys(meta).length ? meta : null,
    };
  });
}

function toPublicQuestion(question) {
  const meta = question.meta_json && typeof question.meta_json === 'object' ? question.meta_json : {};
  return {
    id: question.id,
    section_type: question.section_type,
    section_title: question.section_title,
    question_group: question.question_group,
    question_no: question.question_no,
    sort_order: question.sort_order,
    prompt: question.prompt,
    passage: question.passage,
    transcript: question.transcript,
    options: normalizeStoredQuestionOptions(question.options, question.answer),
    prompt_image_url: meta.prompt_image_url || null,
    passage_image_url: meta.passage_image_url || null,
    score: question.score,
    audio_url: question.audio_url,
  };
}

function computeBreakdown(questions, answersMap) {
  const breakdown = {
    vocabulary_grammar: { total: 0, correct: 0, score: 0, earned: 0 },
    reading: { total: 0, correct: 0, score: 0, earned: 0 },
    listening: { total: 0, correct: 0, score: 0, earned: 0 },
  };

  const details = questions.map(question => {
    const meta = question.meta_json && typeof question.meta_json === 'object' ? question.meta_json : {};
    const userAnswer = answersMap.get(question.id) || '';
    const isCorrect = userAnswer === question.answer;
    const bucket = breakdown[question.section_type];

    bucket.total += 1;
    bucket.score += Number(question.score || 1);
    if (isCorrect) {
      bucket.correct += 1;
      bucket.earned += Number(question.score || 1);
    }

    return {
      id: question.id,
      section_type: question.section_type,
      question_no: question.question_no,
      prompt: question.prompt,
      passage: question.passage,
      transcript: question.transcript,
      options: normalizeStoredQuestionOptions(question.options, question.answer),
      prompt_image_url: meta.prompt_image_url || null,
      passage_image_url: meta.passage_image_url || null,
      correct_answer: question.answer,
      user_answer: userAnswer,
      is_correct: isCorrect,
      explanation: question.explanation,
      explanation_zh: question.explanation_zh,
      score: question.score,
    };
  });

  return { breakdown, details };
}

async function adminListJlptPapers(req, res) {
  const where = {};
  if (req.query.level) where.level = String(req.query.level).toUpperCase();
  if (req.query.status === 'published') where.is_published = true;
  if (req.query.status === 'draft') where.is_published = false;

  const papers = await JlptExamPaper.findAll({
    where,
    include: [{ model: JlptExamQuestion, as: 'questions', attributes: ['id', 'section_type'] }],
    order: [['level', 'ASC'], ['year', 'DESC'], ['session', 'DESC'], ['sort_order', 'ASC']],
  });

  res.json({
    data: papers.map(paper => ({
      id: paper.id,
      level: paper.level,
      year: paper.year,
      session: paper.session,
      title: paper.title,
      slug: paper.slug,
      source_label: paper.source_label,
      description: paper.description,
      duration_minutes: paper.duration_minutes,
      is_published: paper.is_published,
      sort_order: paper.sort_order,
      question_count: paper.questions.length,
      section_counts: paper.questions.reduce((acc, question) => {
        acc[question.section_type] = (acc[question.section_type] || 0) + 1;
        return acc;
      }, {}),
      updatedAt: paper.updatedAt,
    })),
  });
}

async function adminGetJlptPaper(req, res) {
  const paper = await JlptExamPaper.findByPk(req.params.id, {
    include: [{ model: JlptExamQuestion, as: 'questions' }],
    order: [[{ model: JlptExamQuestion, as: 'questions' }, 'sort_order', 'ASC']],
  });
  if (!paper) return res.status(404).json({ error: '试卷不存在' });

  const raw = paper.toJSON();
  const paperMeta = raw.meta_json && typeof raw.meta_json === 'object' ? raw.meta_json : {};
  raw.section_materials = paperMeta.section_materials || {};
  raw.questions = (raw.questions || []).map(question => {
    const meta = question.meta_json && typeof question.meta_json === 'object' ? question.meta_json : {};
    return {
      ...question,
      options: normalizeStoredQuestionOptions(question.options, question.answer),
      prompt_image_url: meta.prompt_image_url || '',
      passage_image_url: meta.passage_image_url || '',
    };
  });

  res.json(raw);
}

async function adminCreateJlptPaper(req, res) {
  const result = await sequelize.transaction(transaction => upsertPaperWithQuestions(req.body, transaction));
  res.status(201).json({ id: result.id, action: result.action });
}

async function adminUpdateJlptPaper(req, res) {
  const paper = await JlptExamPaper.findByPk(req.params.id);
  if (!paper) return res.status(404).json({ error: '试卷不存在' });

  const paperData = normalizePaperPayload(req.body);
  const questions = normalizeQuestions(req.body.questions);

  await sequelize.transaction(async transaction => {
    await paper.update(paperData, { transaction });
    await JlptExamQuestion.destroy({ where: { paper_id: paper.id }, transaction });
    await JlptExamQuestion.bulkCreate(
      questions.map(question => ({ ...question, paper_id: paper.id })),
      { transaction }
    );
  });

  res.json({ ok: true });
}

async function adminImportJlptPaperFile(req, res) {
  if (!req.file) return res.status(400).json({ error: '未找到上传文件' });

  const ext = path.extname(req.file.originalname || '').toLowerCase();
  const text = req.file.buffer.toString('utf8');
  let payload;

  if (ext === '.csv') {
    const rows = parseCsvToRows(text);
    payload = normalizePaperFromCsvRows(rows);
  } else if (ext === '.json') {
    const parsed = JSON.parse(text);
    payload = normalizePaperFromJsonObject(parsed);
  } else {
    return res.status(400).json({ error: '仅支持 .csv 或 .json 文件' });
  }

  if (req.body.publish === '1' || req.body.publish === 'true') {
    payload.is_published = true;
  }

  const result = await sequelize.transaction(transaction => upsertPaperWithQuestions(payload, transaction));
  res.json({ ok: true, action: result.action, id: result.id, slug: payload.slug });
}

async function adminParseJlptQuestionsFile(req, res) {
  if (!req.file) return res.status(400).json({ error: '未找到上传文件' });

  const sectionType = String(req.body.section_type || '').trim();
  if (!['vocabulary_grammar', 'reading', 'listening'].includes(sectionType)) {
    return res.status(400).json({ error: 'section_type 无效，应为 vocabulary_grammar/reading/listening' });
  }

  const ext = path.extname(req.file.originalname || '').toLowerCase();
  const text = req.file.buffer.toString('utf8');
  let questions = [];
  let skipped = 0;
  let sectionMaterials = null;

  if (ext === '.csv') {
    const rows = parseCsvToRows(text);
    const parsed = normalizeQuestionsFromCsvRows(rows, sectionType);
    questions = parsed.questions;
    skipped = parsed.skipped;
    sectionMaterials = parseSectionMaterialsFromRows(rows, sectionType);
  } else if (ext === '.json') {
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) {
      const parsedRows = normalizeQuestionsFromCsvRows(parsed, sectionType);
      questions = parsedRows.questions;
      skipped = parsedRows.skipped;
      sectionMaterials = parseSectionMaterialsFromRows(parsed, sectionType);
    } else if (Array.isArray(parsed.questions)) {
      questions = normalizeQuestions(parsed.questions.map(q => ({ ...q, section_type: sectionType })));
      if (parsed.section_materials && typeof parsed.section_materials === 'object') {
        const key = sectionType === 'reading' ? 'reading' : (sectionType === 'listening' ? 'listening' : sectionType);
        sectionMaterials = { [key]: parsed.section_materials[key] || parsed.section_materials };
      }
    } else {
      return res.status(400).json({ error: 'JSON 文件格式无效：应为数组或包含 questions 数组的对象' });
    }
  } else {
    return res.status(400).json({ error: '仅支持 .csv 或 .json 文件' });
  }

  res.json({ ok: true, section_type: sectionType, count: questions.length, skipped, questions, section_materials: sectionMaterials || {} });
}

async function adminBulkPublishJlptPapers(req, res) {
  const ids = Array.isArray(req.body.ids) ? req.body.ids.map(id => String(id).trim()).filter(Boolean) : [];
  const isPublished = req.body.is_published !== false;

  if (!ids.length) {
    return res.status(400).json({ error: 'ids 不能为空' });
  }

  const affected = await JlptExamPaper.update(
    { is_published: isPublished },
    { where: { id: ids } }
  );

  res.json({ ok: true, affected: Array.isArray(affected) ? affected[0] : affected });
}

async function adminBulkDeleteJlptPapers(req, res) {
  const ids = Array.isArray(req.body.ids) ? req.body.ids.map(id => String(id).trim()).filter(Boolean) : [];
  if (!ids.length) {
    return res.status(400).json({ error: 'ids 不能为空' });
  }

  const affected = await JlptExamPaper.destroy({ where: { id: ids } });
  res.json({ ok: true, affected });
}

async function adminDeleteJlptPaper(req, res) {
  const paper = await JlptExamPaper.findByPk(req.params.id);
  if (!paper) return res.status(404).json({ error: '试卷不存在' });
  await paper.destroy();
  res.json({ ok: true });
}

async function publicListJlptPapers(req, res) {
  const where = { is_published: true };
  if (req.query.level) where.level = String(req.query.level).toUpperCase();

  const papers = await JlptExamPaper.findAll({
    where,
    attributes: ['id', 'level', 'year', 'session', 'title', 'slug', 'description', 'duration_minutes'],
    order: [['level', 'ASC'], ['sort_order', 'ASC'], ['year', 'DESC'], ['session', 'DESC']],
  });

  res.json({ data: papers });
}

async function publicGetJlptPaper(req, res) {
  const paper = await JlptExamPaper.findOne({
    where: { slug: req.params.slug, is_published: true },
    include: [{ model: JlptExamQuestion, as: 'questions' }],
    order: [[{ model: JlptExamQuestion, as: 'questions' }, 'sort_order', 'ASC']],
  });

  if (!paper) return res.status(404).json({ error: '试卷不存在' });

  const paperMeta = paper.meta_json && typeof paper.meta_json === 'object' ? paper.meta_json : {};

  res.json({
    id: paper.id,
    level: paper.level,
    year: paper.year,
    session: paper.session,
    title: paper.title,
    slug: paper.slug,
    description: paper.description,
    duration_minutes: paper.duration_minutes,
    section_materials: paperMeta.section_materials || {},
    questions: paper.questions.map(toPublicQuestion),
  });
}

async function submitJlptPaper(req, res) {
  const paper = await JlptExamPaper.findOne({
    where: { slug: req.params.slug, is_published: true },
    include: [{ model: JlptExamQuestion, as: 'questions' }],
    order: [[{ model: JlptExamQuestion, as: 'questions' }, 'sort_order', 'ASC']],
  });

  if (!paper) return res.status(404).json({ error: '试卷不存在' });

  const answers = Array.isArray(req.body.answers) ? req.body.answers : [];
  const answersMap = new Map(
    answers
      .filter(item => item && item.question_id)
      .map(item => [String(item.question_id), String(item.answer || '').trim()])
  );

  const requestedSectionType = ['vocabulary_grammar', 'reading', 'listening'].includes(req.body.section_type)
    ? req.body.section_type
    : '';
  const scoredQuestions = requestedSectionType
    ? paper.questions.filter(question => question.section_type === requestedSectionType)
    : paper.questions;

  const { breakdown, details } = computeBreakdown(scoredQuestions, answersMap);
  const totalQuestions = scoredQuestions.length;
  const correctCount = details.filter(item => item.is_correct).length;
  const totalScore = details.reduce((sum, item) => sum + Number(item.score || 1), 0);
  const earnedScore = details.reduce((sum, item) => sum + (item.is_correct ? Number(item.score || 1) : 0), 0);
  const scorePercent = totalScore > 0 ? Number(((earnedScore / totalScore) * 100).toFixed(2)) : 0;

  const attempt = await JlptExamAttempt.create({
    user_id: req.user?.id || null,
    paper_id: paper.id,
    answers: answers,
    score_percent: scorePercent,
    total_questions: totalQuestions,
    correct_count: correctCount,
    breakdown,
    time_spent_seconds: Number(req.body.time_spent_seconds || 0),
  });

  const paperMeta = paper.meta_json && typeof paper.meta_json === 'object' ? paper.meta_json : {};

  res.json({
    attempt_id: attempt.id,
    paper: {
      id: paper.id,
      level: paper.level,
      year: paper.year,
      session: paper.session,
      title: paper.title,
      slug: paper.slug,
    },
    section_materials: paperMeta.section_materials || {},
    score_percent: scorePercent,
    total_questions: totalQuestions,
    correct_count: correctCount,
    breakdown,
    details,
  });
}

module.exports = {
  adminListJlptPapers,
  adminGetJlptPaper,
  adminCreateJlptPaper,
  adminUpdateJlptPaper,
  adminImportJlptPaperFile,
  adminParseJlptQuestionsFile,
  adminBulkPublishJlptPapers,
  adminBulkDeleteJlptPapers,
  adminDeleteJlptPaper,
  publicListJlptPapers,
  publicGetJlptPaper,
  submitJlptPaper,
};