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
  return keyMap[key] || (/^[1-4]$/.test(key) ? key : null);
}

function extractAnswer(text) {
  const t = String(text || '');
  const patterns = [
    /正解\s*[:：]\s*([1-4①-④Ａ-ＤA-D])/u,
    /答[え案]\s*[:：]\s*([1-4①-④Ａ-ＤA-D])/u,
    /解答\s*[:：]\s*([1-4①-④Ａ-ＤA-D])/u,
  ];

  for (const re of patterns) {
    const m = t.match(re);
    if (m && m[1]) {
      const key = normalizeKey(m[1]);
      if (key) return key;
    }
  }
  return null;
}

function applyAnswers(filePath) {
  const json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  let updated = 0;

  json.questions = (json.questions || []).map((q) => {
    const source = [q.prompt || '', q.passage || '', q.transcript || ''].join('\n');
    const extracted = extractAnswer(source);
    if (!extracted) return q;

    updated += 1;
    return {
      ...q,
      answer: extracted,
      meta_json: {
        ...(q.meta_json || {}),
        answer_source: 'ocr-inline-pattern',
      },
    };
  });

  json.parse_meta = {
    ...(json.parse_meta || {}),
    answer_extract_at: new Date().toISOString(),
    answer_extract_updated: updated,
    answer_extract_method: 'inline-pattern',
  };

  fs.writeFileSync(filePath, JSON.stringify(json, null, 2), 'utf8');
  return { total: (json.questions || []).length, updated };
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!fs.existsSync(args.input)) {
    console.error('[answer:ocr] input not found:', args.input);
    process.exit(1);
  }

  const files = fs.readdirSync(args.input)
    .filter(name => name.endsWith('.json') && !name.startsWith('_'))
    .map(name => path.join(args.input, name));

  let allTotal = 0;
  let allUpdated = 0;

  for (const file of files) {
    const res = applyAnswers(file);
    allTotal += res.total;
    allUpdated += res.updated;
    console.log(`[answer:ocr] ${path.basename(file)} updated=${res.updated}/${res.total}`);
  }

  console.log(`[answer:ocr] done updated=${allUpdated}/${allTotal}`);
}

main();
