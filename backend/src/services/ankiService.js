const path = require('path');
const fs = require('fs');
const os = require('os');
const { v4: uuidv4 } = require('uuid');
const AdmZip = require('adm-zip');
const { Vocabulary, GrammarLesson, GrammarExample, ContentVersion } = require('../models');

// audio upload dir
const UPLOAD_AUDIO_DIR = path.resolve(__dirname, '../../uploads/audio');
if (!fs.existsSync(UPLOAD_AUDIO_DIR)) fs.mkdirSync(UPLOAD_AUDIO_DIR, { recursive: true });

let _sqlJsPromise = null;
async function getSqlJs() {
  if (!_sqlJsPromise) _sqlJsPromise = require('sql.js')();
  return _sqlJsPromise;
}

function stripHtml(str) {
  if (!str) return '';
  return str
    .replace(/<br\s*\/?\>/gi, ' ')
    .replace(/<[^>]*>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&nbsp;/g, ' ')
    .replace(/&quot;/g, '"')
    .replace(/\[sound:[^\]]*\]/g, '')
    .trim();
}

function extractSoundRef(raw) {
  const m = (raw || '').match(/\[sound:([^\]]+)\]/);
  return m ? m[1] : null;
}

function detectMapping(fields) {
  const mapping = {};
  const match = (name, patterns) => patterns.some(p => p.test(name));

  const wordPat = [/^(expression|front|word|kanji|vocabulary|vocab|japanese|jp|単語|単字|日本語|词|詞|表达式)/i, /^front$/i];
  const readPat = [/^(reading|kana|hiragana|furigana|pronunciation|読み|よみ|かな|ひらがな)/i];
  const zhPat = [/^(meaning|意味|中文|chinese|translation|翻訳|意義|定義|back|中国語|中日|释义)/i];
  const enPat = [/^(english|en|meaning_en|definition|gloss)/i];
  const exPat = [/^(example|sentence|例文|例句|れいぶん|sample|usage|context)/i];
  const tagsPat = [/^tags?$/i];
  // grammar
  const patternPat = [/^(pattern|文型|grammar|文法|structure|構造)/i];
  const explPat = [/^(explanation|explain|説明|解説|meaning|意味)/i];
  const explZhPat = [/^(explanation_zh|中文解释|chinese_exp|翻訳|translation)/i];

  fields.forEach((name, idx) => {
    if (mapping.word === undefined && match(name, wordPat)) mapping.word = idx;
    else if (mapping.reading === undefined && match(name, readPat)) mapping.reading = idx;

    if (mapping.meaning_zh === undefined && match(name, zhPat)) mapping.meaning_zh = idx;
    if (mapping.meaning_en === undefined && match(name, enPat)) mapping.meaning_en = idx;
    if (mapping.example === undefined && match(name, exPat)) mapping.example = idx;
    if (mapping.tags === undefined && match(name, tagsPat)) mapping.tags = idx;
    if (mapping.pattern === undefined && match(name, patternPat)) mapping.pattern = idx;
    if (mapping.explanation === undefined && match(name, explPat)) mapping.explanation = idx;
    if (mapping.explanation_zh === undefined && match(name, explZhPat)) mapping.explanation_zh = idx;
  });

  if (mapping.word === undefined && fields.length >= 1) mapping.word = 0;
  if (mapping.pattern === undefined && fields.length >= 1) mapping.pattern = 0;
  if (
    mapping.meaning_zh === undefined &&
    mapping.meaning_en === undefined &&
    fields.length >= 2
  )
    mapping.meaning_zh = 1;
  if (
    mapping.explanation === undefined &&
    mapping.explanation_zh === undefined &&
    fields.length >= 2
  )
    mapping.explanation = 1;

  return mapping;
}

async function bumpVersion(type) {
  const [cv] = await ContentVersion.findOrCreate({
    where: { id: 1 },
    defaults: { version: 1, vocab_version: 1, grammar_version: 1, updated_at_ts: Date.now() },
  });
  const updates = { version: cv.version + 1, updated_at_ts: Date.now() };
  if (type === 'vocabulary' || type === 'all') updates.vocab_version = cv.vocab_version + 1;
  if (type === 'grammar' || type === 'all') updates.grammar_version = cv.grammar_version + 1;
  await cv.update(updates);
  return cv;
}

module.exports = {
  UPLOAD_AUDIO_DIR,
  getSqlJs,
  stripHtml,
  extractSoundRef,
  detectMapping,
  bumpVersion,
};
