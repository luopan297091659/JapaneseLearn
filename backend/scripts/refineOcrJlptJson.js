#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const args = {
    input: path.resolve(__dirname, '../../temp_jlpt_json_ocr3'),
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--input' || token === '-i') args.input = path.resolve(argv[i + 1]);
  }
  return args;
}

function normalizeKey(raw) {
  const keyMap = {
    '①': '1', '②': '2', '③': '3', '④': '4',
    A: '1', B: '2', C: '3', D: '4',
    'Ａ': '1', 'Ｂ': '2', 'Ｃ': '3', 'Ｄ': '4',
  };
  const key = String(raw || '').trim();
  if (keyMap[key]) return keyMap[key];
  if (/^[1-4]$/.test(key)) return key;
  const m = key.match(/[1-4]/);
  return m ? m[0] : null;
}

function compactText(text) {
  return String(text || '')
    .replace(/\r/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function inferSectionByNo(no) {
  const n = Number(no);
  if (!Number.isFinite(n)) return 'reading';
  if (n <= 20) return 'vocabulary_grammar';
  if (n <= 29) return 'reading';
  return 'listening';
}

function sectionTitle(sectionType) {
  if (sectionType === 'vocabulary_grammar') return '文字・語彙・文法';
  if (sectionType === 'reading') return '読解';
  return '聴解';
}

function normalizeOptions(options) {
  const byKey = { '1': null, '2': null, '3': null, '4': null };

  for (const opt of Array.isArray(options) ? options : []) {
    const key = normalizeKey(opt && opt.key);
    const text = compactText(opt && opt.text);
    if (!key || !text) continue;
    if (!byKey[key]) byKey[key] = text;
  }

  for (const key of ['1', '2', '3', '4']) {
    if (!byKey[key]) byKey[key] = `选项${key}（OCR待校对）`;
  }

  return ['1', '2', '3', '4'].map(key => ({ key, text: byKey[key] }));
}

function refineQuestion(q, idx) {
  const questionNo = String(idx + 1);
  const sectionType = inferSectionByNo(questionNo);
  const options = normalizeOptions(q.options);
  const answer = ['1', '2', '3', '4'].includes(String(q.answer)) ? String(q.answer) : '1';

  const base = {
    ...q,
    question_no: questionNo,
    sort_order: idx + 1,
    section_type: sectionType,
    section_title: sectionTitle(sectionType),
    question_group: sectionType === 'vocabulary_grammar' ? '問題1-20' : sectionType === 'reading' ? '問題21-29' : '問題30-35',
    prompt: compactText(q.prompt).slice(0, 1500),
    passage: sectionType === 'reading' ? compactText(q.passage || q.prompt).slice(0, 3000) : '',
    transcript: sectionType === 'listening' ? compactText(q.transcript || q.prompt).slice(0, 3000) : '',
    options,
    answer,
    explanation: compactText(q.explanation || 'OCR草稿，请人工核对答案与解析。').slice(0, 3000),
    explanation_zh: compactText(q.explanation_zh || 'OCR草稿，请人工核对答案与解析。').slice(0, 3000),
    score: Number(q.score || 1) > 0 ? Number(q.score) : 1,
  };

  return base;
}

function refinePaper(paper) {
  const questions = Array.isArray(paper.questions) ? paper.questions : [];
  const refinedQuestions = questions.map(refineQuestion);
  return {
    ...paper,
    description: 'OCR转换后自动结构化草稿，已进行题号分段与选项清洗，仍需后台人工校对。',
    tags: Array.from(new Set([...(Array.isArray(paper.tags) ? paper.tags : []), 'ocr-refined'])),
    parse_meta: {
      ...(paper.parse_meta || {}),
      refined_at: new Date().toISOString(),
      refinement_version: 'v1',
      refined_question_count: refinedQuestions.length,
      requires_ocr: false,
    },
    questions: refinedQuestions,
  };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!fs.existsSync(args.input)) {
    console.error('[refine:jlpt-ocr] input not found:', args.input);
    process.exit(1);
  }

  const files = fs.readdirSync(args.input)
    .filter(name => name.endsWith('.json') && !name.startsWith('_'))
    .map(name => path.join(args.input, name));

  for (const file of files) {
    const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
    const refined = refinePaper(raw);
    fs.writeFileSync(file, JSON.stringify(refined, null, 2), 'utf8');
    console.log('[refine:jlpt-ocr] done ->', path.basename(file));
  }

  console.log('[refine:jlpt-ocr] total ->', files.length);
}

main();
