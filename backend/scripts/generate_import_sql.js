/**
 * generate_import_sql.js
 * 
 * 将所有数据源生成一个 SQL 文件，可在 DBeaver/MySQL Workbench 中执行
 * 
 * 用法: node scripts/generate_import_sql.js
 * 输出: database/seeds/import_n1n5_data.sql
 */

const path = require('path');
const fs   = require('fs');
const XLSX = require('xlsx');

const SOURCE_DIR = 'C:/Users/28296/Downloads/source';
const OUTPUT_SQL = path.join(__dirname, '../database/seeds/import_n1n5_data.sql');

// ─── 工具函数 ─────────────────────────────────────────────────────────────────

function parsePOS(posStr) {
  if (!posStr) return 'other';
  const s = posStr.replace(/[・~～·]/g, '');
  if (/動|どう/i.test(s))               return 'verb';
  if (/形容詞|い形|形1/i.test(s))         return 'adjective';
  if (/形容動詞|な形|形2/i.test(s))        return 'adjective';
  if (/形/i.test(s))                       return 'adjective';
  if (/副/i.test(s))                       return 'adverb';
  if (/助詞|助/i.test(s))                  return 'particle';
  if (/接続/i.test(s))                     return 'conjunction';
  if (/感動詞/i.test(s))                   return 'interjection';
  if (/名/i.test(s))                       return 'noun';
  return 'other';
}

function parseWordDesc(desc) {
  if (!desc) return { reading: '', pos: 'other', meaning: '' };
  const readingMatch = desc.match(/[（(]([^）)]+)[）)]/);
  const reading = readingMatch ? readingMatch[1].trim() : '';
  const posMatch = desc.match(/【([^】]+)】/);
  const pos = posMatch ? parsePOS(posMatch[1]) : 'other';
  const meaningMatch = desc.match(/】(.+)$/s);
  const meaning = meaningMatch ? meaningMatch[1].trim() : '';
  return { reading, pos, meaning };
}

function guessGrammarLevel(lesson) {
  const s = String(lesson).trim();
  const n = parseInt(s);
  if (!isNaN(n)) {
    if (n <= 12) return 'N5';
    if (n <= 25) return 'N4';
    if (n <= 50) return 'N3';
    if (n <= 75) return 'N2';
    return 'N1';
  }
  const mMatch = s.match(/m(\d+)/);
  if (mMatch) {
    const m = parseInt(mMatch[1]);
    if (m <= 8)  return 'N3';
    if (m <= 18) return 'N2';
    return 'N1';
  }
  return 'N3';
}

/** 转义 SQL 字符串 */
function esc(val) {
  if (val === null || val === undefined) return 'NULL';
  const s = String(val)
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r');
  return `'${s}'`;
}

function chunkArray(arr, size) {
  const result = [];
  for (let i = 0; i < arr.length; i += size) result.push(arr.slice(i, i + size));
  return result;
}

/** 生成词汇 INSERT 语句 */
function vocabRow(uuid, word, reading, meaning_zh, pos, jlpt_level,
                  example = null, example_reading = null, example_zh = null) {
  return `(${esc(uuid)},${esc(word)},${esc(reading)},${esc(meaning_zh)},` +
         `NULL,${esc(pos)},${esc(jlpt_level)},` +
         `${esc(example)},${esc(example_reading)},${esc(example_zh)},` +
         `NULL,NULL,NULL,NULL)`;
}

/** 生成语法 INSERT 语句 */
function grammarRow(uuid, title, jlpt_level, pattern, explanation, order_idx) {
  return `(${esc(uuid)},${esc(title)},${esc(title)},${esc(jlpt_level)},` +
         `${esc(pattern)},${esc(explanation)},${esc(explanation)},NULL,${order_idx})`;
}

// ─── 主逻辑 ───────────────────────────────────────────────────────────────────
function main() {
  const lines = [];
  const now   = new Date().toISOString().replace('T', ' ').slice(0, 19);

  lines.push(`-- ==========================================================`);
  lines.push(`-- Japanese Learn - N1~N5 全量词汇 & 语法导入`);
  lines.push(`-- 生成时间: ${now}`);
  lines.push(`-- 数据来源: C:/Users/28296/Downloads/source`);
  lines.push(`-- 用法: 在 DBeaver / MySQL Workbench 中执行此文件`);
  lines.push(`--      数据库: japanese_learn`);
  lines.push(`-- ==========================================================`);
  lines.push('');
  lines.push('USE japanese_learn;');
  lines.push('SET NAMES utf8mb4;');
  lines.push('SET foreign_key_checks = 0;');
  lines.push('');

  // ── 词汇 INSERT 前缀 ──
  const vocabPrefix = 'INSERT IGNORE INTO vocabulary\n' +
    '  (id,word,reading,meaning_zh,meaning_en,part_of_speech,jlpt_level,\n' +
    '   example_sentence,example_reading,example_meaning_zh,\n' +
    '   audio_url,image_url,category,tags)\nVALUES\n';

  let vocabRowsBuf = [];
  let vocabCount   = 0;

  function flushVocab() {
    if (vocabRowsBuf.length === 0) return;
    for (const chunk of chunkArray(vocabRowsBuf, 200)) {
      lines.push(vocabPrefix + chunk.join(',\n') + ';');
      lines.push('');
    }
    vocabRowsBuf = [];
  }

  // ── 1. n5n4 JSON ──
  lines.push('-- ── N5/N4 词汇 (2000条) ──────────────────────────────────');
  const dirs = [['n5n4','N5'], ['n3','N3'], ['n2','N2'], ['n1','N1']];
  for (const [dirName, jlpt] of dirs) {
    const dir  = path.join(SOURCE_DIR, dirName);
    const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();
    for (const file of files) {
      const json  = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
      for (const item of (json.data || [])) {
        const word = item.wordName?.trim();
        if (!word) continue;
        const { reading, pos, meaning } = parseWordDesc(item.wordDesc);
        const finalMeaning = item.correctDesc?.trim() || meaning || '';
        const finalReading = reading || word;
        vocabRowsBuf.push(vocabRow(
          crypto.randomUUID(), word, finalReading, finalMeaning, pos, jlpt
        ));
        vocabCount++;
      }
    }
    flushVocab();
    lines.push(`-- ── ${jlpt} 词汇导入完毕 ──`);
    lines.push('');
  }

  // ── 2. word-list.js ──
  lines.push('-- ── word-list.js N5基础词 ──────────────────────────────────');
  try {
    const rawJS = fs.readFileSync(path.join(SOURCE_DIR, 'word-list.js'), 'utf8');
    const match = rawJS.match(/var word_list\s*=\s*(\[[\s\S]+?\]);?\s*$/m)
               || rawJS.match(/(\[[\s\S]+\])/);
    if (match) {
      const items = JSON.parse(match[1]);
      for (const item of items) {
        const word = item.content?.trim();
        if (!word) continue;
        vocabRowsBuf.push(vocabRow(
          crypto.randomUUID(),
          word,
          item.pron?.trim() || word,
          item.definition?.trim() || '',
          'other', 'N5'
        ));
        vocabCount++;
      }
      flushVocab();
    }
  } catch (e) {
    lines.push(`-- ⚠ word-list.js 处理失败: ${e.message}`);
  }
  lines.push('');

  // ── 3. jp_zhongji.xlsx ──
  lines.push('-- ── jp_zhongji.xlsx 中高级词汇 ─────────────────────────────');
  try {
    const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'jp_zhongji.xlsx'));
    const ws   = wb.Sheets[wb.SheetNames[0]];
    const data = XLSX.utils.sheet_to_json(ws, { header: 1 });
    for (let i = 1; i < data.length; i++) {
      const r       = data[i];
      const word    = String(r[0] || '').trim();
      const kana    = String(r[1] || '').trim();
      const meaning = String(r[2] || '').trim();
      const posRaw  = String(r[4] || '').trim();
      if (!word || !kana || !meaning) continue;
      vocabRowsBuf.push(vocabRow(
        crypto.randomUUID(), word, kana, meaning, parsePOS(posRaw), 'N3'
      ));
      vocabCount++;
    }
    flushVocab();
  } catch (e) {
    lines.push(`-- ⚠ jp_zhongji.xlsx 处理失败: ${e.message}`);
  }
  lines.push('');

  // ── 4. ABAB.xlsx ──
  lines.push('-- ── ABAB.xlsx 副词/擬態語 ──────────────────────────────────');
  try {
    const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'ABAB.xlsx'));
    const ws   = wb.Sheets[wb.SheetNames[0]];
    const data = XLSX.utils.sheet_to_json(ws);
    for (const r of data) {
      const word = String(r['副词'] || '').trim();
      const meaning = String(r['意思'] || '').trim();
      if (!word || !meaning) continue;
      vocabRowsBuf.push(vocabRow(
        crypto.randomUUID(), word, word, meaning, 'adverb', 'N3',
        String(r['例句'] || '').trim() || null,
        null,
        String(r['例句意思'] || '').trim() || null,
      ));
      vocabCount++;
    }
    flushVocab();
  } catch (e) {
    lines.push(`-- ⚠ ABAB.xlsx 处理失败: ${e.message}`);
  }
  lines.push('');

  // ── 5. grammar.xlsx ──
  lines.push('-- ── grammar.xlsx 语法句型 (599条) ─────────────────────────');
  const grammarPrefix = 'INSERT IGNORE INTO grammar_lessons\n' +
    '  (id,title,title_zh,jlpt_level,pattern,explanation,explanation_zh,usage_notes,order_index)\nVALUES\n';
  try {
    const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'grammar.xlsx'));
    const ws   = wb.Sheets[wb.SheetNames[0]];
    const data = XLSX.utils.sheet_to_json(ws);
    const grammarRows = [];
    let orderIdx = 1;
    for (const r of data) {
      const pattern = String(r['expression'] || '').trim();
      if (!pattern) continue;
      const explanation = String(r['explanation'] || r['shortexplain'] || '').trim();
      const level = guessGrammarLevel(r['lesson']);
      grammarRows.push(grammarRow(
        crypto.randomUUID(), pattern, level, pattern, explanation, orderIdx++
      ));
    }
    for (const chunk of chunkArray(grammarRows, 100)) {
      lines.push(grammarPrefix + chunk.join(',\n') + ';');
      lines.push('');
    }
  } catch (e) {
    lines.push(`-- ⚠ grammar.xlsx 处理失败: ${e.message}`);
  }

  lines.push('SET foreign_key_checks = 1;');
  lines.push('');
  lines.push(`-- 导入完成。词汇约 ${vocabCount} 条，语法约 599 条。`);

  // 写出文件
  const output = lines.join('\n');
  fs.writeFileSync(OUTPUT_SQL, output, 'utf8');
  console.log(`\n✅ SQL 文件已生成: ${OUTPUT_SQL}`);
  console.log(`   词汇: ~${vocabCount} 条`);
  console.log(`   语法: ~599 条`);
  console.log(`   文件大小: ${(output.length / 1024 / 1024).toFixed(1)} MB`);
  console.log(`\n📋 请在 DBeaver 或 MySQL Workbench 中执行此文件:\n   数据库: japanese_learn @ 139.196.44.6:3306`);
}

// Node.js 18+ 内置 crypto.randomUUID()
const crypto = require('crypto');
main();
