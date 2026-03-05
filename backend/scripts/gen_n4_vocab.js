/**
 * 从 words.xlsx 补充生成 N4 词汇 SQL
 * words.xlsx 字段：kana/kanji/pos/desc/word/lesson/idx
 * lesson 1-12 → N5, 13-25 → N4, 26-50 → N3, 51-75 → N2, >75 → N1
 *
 * 用法: node scripts/gen_n4_vocab.js
 */

const crypto = require('crypto');
const XLSX   = require('xlsx');
const fs     = require('fs');
const path   = require('path');

const SOURCE_DIR = 'C:/Users/28296/Downloads/source';
const OUT_FILE   = path.join(__dirname, '../database/seeds/import_n4_vocab.sql');

function lessonToLevel(lesson) {
  const n = parseInt(lesson) || 0;
  if (n <= 12) return 'N5';
  if (n <= 25) return 'N4';
  if (n <= 50) return 'N3';
  if (n <= 75) return 'N2';
  return 'N1';
}

function esc(v) {
  if (v == null) return 'NULL';
  return "'" + String(v).replace(/\\/g,'\\\\').replace(/'/g,"\\'") + "'";
}

const POS_MAP = {
  'n':'noun','v':'verb','adj':'adjective','adv':'adverb','conj':'conjunction',
  'particle':'particle','int':'interjection',
  '名词':'noun','动词':'verb','形容词':'adjective','副词':'adverb','助词':'particle',
};
function parsePOS(raw) {
  const s = (raw||'').toLowerCase().trim();
  return POS_MAP[s] || 'other';
}

function main() {
  const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'words.xlsx'));
  const ws   = wb.Sheets[wb.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(ws, { header: 1 });

  // 检测表头
  const header = rows[0] || [];
  console.log('表头:', header);

  // 字段索引（根据表头自适应）
  const colIdx = {};
  header.forEach((h, i) => {
    const key = String(h).toLowerCase().trim();
    colIdx[key] = i;
  });
  console.log('字段映射:', colIdx);

  const lines = [
    '-- words.xlsx 补充 N4 词汇',
    `-- 生成时间: ${new Date().toISOString()}`,
    'USE japanese_learn;',
    'SET NAMES utf8mb4;',
    '',
    'INSERT IGNORE INTO vocabulary',
    '  (id,word,reading,meaning_zh,meaning_en,part_of_speech,jlpt_level,',
    '   example_sentence,example_reading,example_meaning_zh,',
    '   audio_url,image_url,category,tags)',
    'VALUES',
  ];

  const levelCounts = { N1:0, N2:0, N3:0, N4:0, N5:0 };
  const valueLines = [];

  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    if (!r || r.length === 0) continue;

    // 尝试各种列名
    const word    = String(r[colIdx['word'] ?? colIdx['kanji'] ?? 0] || '').trim();
    const reading = String(r[colIdx['kana'] ?? colIdx['reading'] ?? 1] || '').trim();
    const meaning = String(r[colIdx['desc'] ?? colIdx['definition'] ?? colIdx['meaning'] ?? 3] || '').trim();
    const pos     = String(r[colIdx['pos'] ?? 2] || '').trim();
    const lesson  = r[colIdx['lesson'] ?? 5];

    if (!word) continue;
    const level = lessonToLevel(lesson);
    levelCounts[level]++;

    valueLines.push(
      `(${esc(crypto.randomUUID())},${esc(word)},${esc(reading||word)},${esc(meaning||word)},` +
      `NULL,${esc(parsePOS(pos))},${esc(level)},` +
      `NULL,NULL,NULL,NULL,NULL,NULL,NULL)`
    );
  }

  lines.push(valueLines.join(',\n') + ';');
  lines.push('');

  // 按级别统计
  console.log('\n按级别词数:');
  for (const [level, cnt] of Object.entries(levelCounts)) {
    console.log(`  ${level}: ${cnt} 条`);
  }

  fs.writeFileSync(OUT_FILE, lines.join('\n'), 'utf8');
  const sizeMB = (fs.statSync(OUT_FILE).size / 1024 / 1024).toFixed(2);
  console.log(`\n✅ 已生成: ${OUT_FILE} (${sizeMB} MB, 共 ${Object.values(levelCounts).reduce((a,b)=>a+b,0)} 条)`);
}

main();
