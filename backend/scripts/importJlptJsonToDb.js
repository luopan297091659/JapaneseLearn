#!/usr/bin/env node
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const { sequelize } = require('../src/config/database');
const { JlptExamPaper, JlptExamQuestion } = require('../src/models');

function parseArgs(argv) {
  const args = {
    input: path.resolve(__dirname, '../../temp_jlpt_json_all'),
    publish: false,
    sync: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--input' || token === '-i') args.input = path.resolve(argv[i + 1]);
    if (token === '--publish') args.publish = true;
    if (token === '--sync') args.sync = true;
  }
  return args;
}

function loadJsonFiles(inputDir) {
  if (!fs.existsSync(inputDir)) throw new Error(`input dir not found: ${inputDir}`);
  return fs
    .readdirSync(inputDir)
    .filter(name => name.endsWith('.json') && name !== '_index.json')
    .map(name => path.join(inputDir, name));
}

function normalizePaper(raw, forcePublish) {
  if (!raw.slug || !raw.title || !raw.level) {
    throw new Error('missing required fields: slug/title/level');
  }
  if (!Array.isArray(raw.questions) || !raw.questions.length) {
    throw new Error(`paper ${raw.slug} has no questions`);
  }

  return {
    paper: {
      level: raw.level,
      year: Number(raw.year || new Date().getFullYear()),
      session: raw.session || 'other',
      title: raw.title,
      slug: raw.slug,
      source_label: raw.source_label || null,
      description: raw.description || null,
      duration_minutes: raw.duration_minutes || null,
      is_published: forcePublish ? true : !!raw.is_published,
      sort_order: Number(raw.sort_order || 0),
      tags: raw.tags || null,
      meta_json: raw.parse_meta || raw.meta_json || null,
    },
    questions: raw.questions.map((q, idx) => ({
      section_type: q.section_type || 'reading',
      section_title: q.section_title || null,
      question_group: q.question_group || null,
      question_no: String(q.question_no || idx + 1),
      sort_order: Number(q.sort_order || idx + 1),
      prompt: q.prompt || '',
      passage: q.passage || null,
      transcript: q.transcript || null,
      options: Array.isArray(q.options) ? q.options : [
        { key: '1', text: '选项1' },
        { key: '2', text: '选项2' },
        { key: '3', text: '选项3' },
        { key: '4', text: '选项4' },
      ],
      answer: String(q.answer || '1'),
      explanation: q.explanation || null,
      explanation_zh: q.explanation_zh || null,
      knowledge_points: q.knowledge_points || null,
      score: Number(q.score || 1),
      audio_url: q.audio_url || null,
      meta_json: q.meta_json || null,
    })),
  };
}

async function upsertPaper(paperData, questions) {
  const existing = await JlptExamPaper.findOne({ where: { slug: paperData.slug } });
  if (existing) {
    await existing.update(paperData);
    await JlptExamQuestion.destroy({ where: { paper_id: existing.id } });
    await JlptExamQuestion.bulkCreate(questions.map(q => ({ ...q, paper_id: existing.id })));
    return 'updated';
  }

  const created = await JlptExamPaper.create(paperData);
  await JlptExamQuestion.bulkCreate(questions.map(q => ({ ...q, paper_id: created.id })));
  return 'created';
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const files = loadJsonFiles(args.input);

  await sequelize.authenticate();
  if (args.sync) {
    await sequelize.sync({ alter: { drop: false } });
  }

  let created = 0;
  let updated = 0;
  let failed = 0;

  for (const file of files) {
    try {
      const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
      const { paper, questions } = normalizePaper(raw, args.publish);
      const action = await upsertPaper(paper, questions);
      if (action === 'created') created += 1;
      if (action === 'updated') updated += 1;
      console.log(`[import:jlpt-json] ${action} -> ${paper.slug}`);
    } catch (err) {
      failed += 1;
      const name = path.basename(file);
      if (err && Array.isArray(err.errors) && err.errors.length) {
        const details = err.errors
          .map(e => `${e.path || 'unknown'}: ${e.message}`)
          .join(' | ');
        console.error(`[import:jlpt-json] failed -> ${name} :: ${details}`);
      } else {
        console.error(`[import:jlpt-json] failed -> ${name} :: ${err.message}`);
      }
    }
  }

  console.log(`[import:jlpt-json] done. created=${created}, updated=${updated}, failed=${failed}, total=${files.length}`);
}

main()
  .then(async () => {
    await sequelize.close();
    process.exit(0);
  })
  .catch(async err => {
    console.error('[import:jlpt-json] failed:', err.message);
    await sequelize.close();
    process.exit(1);
  });
