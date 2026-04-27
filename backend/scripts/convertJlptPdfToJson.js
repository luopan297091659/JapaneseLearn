#!/usr/bin/env node
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const pdfParseModule = require('pdf-parse');

function parseArgs(argv) {
  const args = { input: '', out: path.resolve(__dirname, '../../temp_jlpt_json') };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--input' || token === '-i') args.input = argv[i + 1];
    if (token === '--out' || token === '-o') args.out = argv[i + 1];
  }
  return args;
}

function sanitizeSlugPart(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function inferLevel(filePath) {
  const m = filePath.match(/\\(N[1-5])\\/i);
  return m ? m[1].toUpperCase() : 'N3';
}

function inferYearSession(fileName) {
  const yearMatch = fileName.match(/(20\d{2}|19\d{2})/);
  const year = yearMatch ? Number(yearMatch[1]) : new Date().getFullYear();

  // Prefer explicit month markers to avoid matching "2012" as "12".
  let session = 'other';
  if (/([\s_\-]|年)?0?7月/.test(fileName) || /(?:-|_|\b)07(?:\b|[^0-9])/.test(fileName)) {
    session = '07';
  } else if (/([\s_\-]|年)?12月/.test(fileName) || /(?:-|_|\b)12(?:\b|[^0-9])/.test(fileName)) {
    session = '12';
  }
  return { year, session };
}

function normalizeText(text) {
  return String(text || '')
    .replace(/\u0000/g, '')
    .replace(/\r/g, '')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function splitLines(text) {
  return text
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean);
}

function detectSection(line) {
  if (/語彙|文字|文法|ことば|語法/.test(line)) return 'vocabulary_grammar';
  if (/読解|文章|長文|短文/.test(line)) return 'reading';
  if (/聴解|听解|会話|話を聞いて/.test(line)) return 'listening';
  return null;
}

function extractQuestionBlocks(lines) {
  const blocks = [];
  let currentSection = 'vocabulary_grammar';
  let current = null;

  const startRegex = /^(?:問題|問|Q)\s*([0-9０-９]+)/;

  for (const line of lines) {
    const sec = detectSection(line);
    if (sec) {
      currentSection = sec;
    }

    const start = line.match(startRegex);
    if (start) {
      if (current) blocks.push(current);
      current = {
        section_type: currentSection,
        question_no: String(start[1]).replace(/[０-９]/g, d => String('０１２３４５６７８９'.indexOf(d))),
        lines: [line],
      };
      continue;
    }

    if (current) {
      current.lines.push(line);
    }
  }

  if (current) blocks.push(current);
  return blocks;
}

function guessOptions(blockText) {
  const options = [];
  const optionRegex = /(?:^|\n)\s*([1-4①-④Ａ-ＤA-D])[\.\)）\s]+([^\n]+)/g;
  let m;
  while ((m = optionRegex.exec(blockText)) !== null) {
    const rawKey = m[1];
    const keyMap = { '①': '1', '②': '2', '③': '3', '④': '4', A: '1', B: '2', C: '3', D: '4', 'Ａ': '1', 'Ｂ': '2', 'Ｃ': '3', 'Ｄ': '4' };
    const key = keyMap[rawKey] || rawKey;
    options.push({ key: String(key), text: m[2].trim() });
  }

  if (options.length >= 2) return options;
  return [
    { key: '1', text: '选项1（待人工整理）' },
    { key: '2', text: '选项2（待人工整理）' },
    { key: '3', text: '选项3（待人工整理）' },
    { key: '4', text: '选项4（待人工整理）' },
  ];
}

function toQuestions(blocks, fullText) {
  if (!blocks.length) {
    return [
      {
        section_type: 'reading',
        section_title: '要人工整理',
        question_group: '导入草稿',
        question_no: '1',
        sort_order: 1,
        prompt: fullText.slice(0, 500) || '未能自动识别题目结构，请人工粘贴并整理。',
        passage: fullText.slice(0, 1600) || '',
        transcript: '',
        options: [
          { key: '1', text: '选项1（待人工整理）' },
          { key: '2', text: '选项2（待人工整理）' },
          { key: '3', text: '选项3（待人工整理）' },
          { key: '4', text: '选项4（待人工整理）' },
        ],
        answer: '1',
        explanation: '自动导入草稿，待人工补全。',
        explanation_zh: '自动导入草稿，待人工补全。',
        knowledge_points: ['draft'],
        score: 1,
      },
    ];
  }

  return blocks.map((block, idx) => {
    const content = block.lines.join('\n');
    return {
      section_type: block.section_type,
      section_title:
        block.section_type === 'vocabulary_grammar'
          ? '文字・語彙・文法'
          : block.section_type === 'reading'
            ? '読解'
            : '聴解',
      question_group: '自动解析',
      question_no: String(block.question_no || idx + 1),
      sort_order: idx + 1,
      prompt: content.slice(0, 900),
      passage: block.section_type === 'reading' ? content.slice(0, 1800) : '',
      transcript: block.section_type === 'listening' ? content.slice(0, 1800) : '',
      options: guessOptions(content),
      answer: '1',
      explanation: '自动转换草稿，请人工确认正确答案与解析。',
      explanation_zh: '自动转换草稿，请人工确认正确答案与解析。',
      knowledge_points: ['auto-import'],
      score: 1,
    };
  });
}

async function extractPdfText(pdfPath) {
  const buffer = fs.readFileSync(pdfPath);
  // Support both old and new pdf-parse APIs.
  if (typeof pdfParseModule === 'function') {
    const data = await pdfParseModule(buffer);
    return {
      numPages: data.numpages || 0,
      text: normalizeText(data.text || ''),
    };
  }

  if (pdfParseModule && typeof pdfParseModule.PDFParse === 'function') {
    const parser = new pdfParseModule.PDFParse({ data: buffer });
    try {
      const data = await parser.getText();
      return {
        numPages: data.total || 0,
        text: normalizeText(data.text || ''),
      };
    } finally {
      await parser.destroy();
    }
  }

  throw new Error('Unsupported pdf-parse module format');
}

function scanPdfFiles(inputPath) {
  const stat = fs.statSync(inputPath);
  if (stat.isFile()) return [inputPath];

  const files = [];
  const stack = [inputPath];
  while (stack.length) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) stack.push(full);
      if (entry.isFile() && entry.name.toLowerCase().endsWith('.pdf') && !entry.name.startsWith('._')) files.push(full);
    }
  }
  return files.sort();
}

function buildPaperJson(pdfPath, extracted) {
  const fileName = path.basename(pdfPath);
  const level = inferLevel(pdfPath);
  const { year, session } = inferYearSession(fileName);
  const slug = sanitizeSlugPart(`${level}-${year}-${session}-${path.parse(fileName).name}`) || `${level.toLowerCase()}-${year}-${session}`;

  const lines = splitLines(extracted.text);
  const blocks = extractQuestionBlocks(lines);
  const questions = toQuestions(blocks, extracted.text);

  const japaneseChars = (extracted.text.match(/[\u3040-\u30ff\u4e00-\u9fff]/g) || []).length;
  const requiresOcr = extracted.text.length < 500 || japaneseChars < 80;

  return {
    level,
    year,
    session,
    title: `${level} 模拟测验 ${year}-${session}`,
    slug,
    source_label: fileName,
    description: '由 PDF 自动转换生成的草稿，请在后台人工校对后发布。',
    duration_minutes: null,
    is_published: false,
    sort_order: 0,
    tags: ['auto-converted', level],
    parse_meta: {
      source_pdf: pdfPath,
      pages: extracted.numPages,
      text_length: extracted.text.length,
      detected_blocks: blocks.length,
      requires_ocr: requiresOcr,
    },
    questions,
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.input) {
    console.error('Usage: node scripts/convertJlptPdfToJson.js --input <pdf-or-folder> [--out <output-folder>]');
    process.exit(1);
  }

  const inputPath = path.resolve(args.input);
  const outDir = path.resolve(args.out);

  if (!fs.existsSync(inputPath)) {
    console.error('[convert:jlpt-pdf] input not found:', inputPath);
    process.exit(1);
  }

  fs.mkdirSync(outDir, { recursive: true });
  const files = scanPdfFiles(inputPath);
  if (!files.length) {
    console.error('[convert:jlpt-pdf] no pdf files found');
    process.exit(1);
  }

  const index = [];
  for (const file of files) {
    try {
      const extracted = await extractPdfText(file);
      const paper = buildPaperJson(file, extracted);
      const outPath = path.join(outDir, `${paper.slug}.json`);
      fs.writeFileSync(outPath, JSON.stringify(paper, null, 2), 'utf8');
      index.push({
        slug: paper.slug,
        level: paper.level,
        year: paper.year,
        session: paper.session,
        source_pdf: file,
        output_json: outPath,
        questions: paper.questions.length,
        requires_ocr: !!paper.parse_meta.requires_ocr,
      });
      console.log('[convert:jlpt-pdf] done ->', path.basename(outPath));
    } catch (err) {
      console.error('[convert:jlpt-pdf] failed ->', file, err.message);
    }
  }

  const indexPath = path.join(outDir, '_index.json');
  fs.writeFileSync(indexPath, JSON.stringify(index, null, 2), 'utf8');
  console.log('[convert:jlpt-pdf] index ->', indexPath);
}

main().catch(err => {
  console.error('[convert:jlpt-pdf] unexpected error:', err.message);
  process.exit(1);
});
