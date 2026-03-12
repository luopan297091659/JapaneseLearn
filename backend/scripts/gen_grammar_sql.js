/**
 * 语法数据导入 - 生成SQL文件版
 * 解析APKG后输出SQL文件，通过SSH上传到服务器执行
 */
const Database = require('better-sqlite3');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const APKG_DB = path.join(__dirname, '../../temp_grammar_extract/collection.anki21');
const OUTPUT_SQL = path.join(__dirname, '../../temp_grammar_import.sql');

function stripHtml(str) {
  if (!str) return '';
  return str
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#x27;/g, "'")
    .trim();
}

function cleanFurigana(text) {
  if (!text) return '';
  return text.replace(/\[([^\]]*)\]/g, '').replace(/\s+/g, '').trim();
}

function extractReading(text) {
  if (!text) return '';
  let result = text.replace(/([^\[\]\s]*)\[([^\]]+)\]/g, '$2');
  result = result.replace(/\s+/g, '').trim();
  return result;
}

function escSql(str) {
  if (str === null || str === undefined) return 'NULL';
  // Escape single quotes and backslashes for SQL
  const escaped = str
    .replace(/\\/g, '\\\\')
    .replace(/'/g, "\\'")
    .replace(/\n/g, '\\n')
    .replace(/\r/g, '\\r')
    .replace(/\t/g, '\\t');
  return `'${escaped}'`;
}

function main() {
  console.log('=== 语法SQL生成工具 ===\n');

  // 1. 读取APKG
  console.log('1. 读取APKG数据...');
  const db = new Database(APKG_DB, { readonly: true });
  const notes = db.prepare('SELECT id, mid, flds, tags FROM notes').all();
  console.log(`   共 ${notes.length} 条记录`);

  const sqlLines = [];
  sqlLines.push('SET NAMES utf8mb4;');
  sqlLines.push('SET FOREIGN_KEY_CHECKS = 0;');
  sqlLines.push('');
  sqlLines.push("-- 清空现有数据");
  sqlLines.push("DELETE FROM srs_cards WHERE card_type = 'grammar';");
  sqlLines.push('DELETE FROM grammar_examples;');
  sqlLines.push('DELETE FROM grammar_lessons;');
  sqlLines.push('');
  sqlLines.push("-- 导入语法课程");

  let lessonCount = 0;
  let exampleCount = 0;
  const levelDist = {};

  for (const note of notes) {
    const fields = note.flds.split('\x1f');
    const tags = note.tags.trim();

    // 解析级别
    let level = null;
    const levelField = fields[2] || '';
    const lm = levelField.match(/N([1-5])/);
    if (lm) level = 'N' + lm[1];
    else {
      const tm = tags.match(/N([1-5])/);
      if (tm) level = 'N' + tm[1];
      else if (tags.includes('敬語') || levelField.includes('敬語')) level = 'N1';
    }
    if (!level) continue;

    const title = stripHtml(fields[3] || '').trim();
    if (!title) continue;

    levelDist[level] = (levelDist[level] || 0) + 1;

    // 接续方式
    const patterns = [];
    for (let i = 4; i <= 13; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) patterns.push(val);
    }

    // 中文解释
    const explanations = [];
    for (let i = 14; i <= 28; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) explanations.push(val);
    }

    // 使用注记
    const usageNotes = [];
    for (let i = 104; i <= 118; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) usageNotes.push(val);
    }

    const subOrder = parseInt(fields[119]) || 0;
    const totalOrder = parseInt(fields[120]) || 0;

    const lessonId = crypto.randomUUID();
    const patternStr = (patterns[0] || title).substring(0, 300);
    const explanation = patterns.join('\n') || title;
    const explanationZh = explanations.join('\n') || null;
    const usageNote = usageNotes.join('\n') || null;
    const orderIndex = totalOrder || subOrder;

    sqlLines.push(
      `INSERT INTO grammar_lessons (id, title, title_zh, jlpt_level, pattern, explanation, explanation_zh, usage_notes, order_index, created_at, updated_at) VALUES (${escSql(lessonId)}, ${escSql(title.substring(0, 200))}, NULL, ${escSql(level)}, ${escSql(patternStr)}, ${escSql(explanation)}, ${escSql(explanationZh)}, ${escSql(usageNote)}, ${orderIndex}, NOW(), NOW());`
    );
    lessonCount++;

    // 例句
    for (let j = 0; j < 25; j++) {
      const rawSentence = stripHtml(fields[29 + j] || '').trim();
      const rawChinese = stripHtml(fields[54 + j] || '').trim();
      if (!rawSentence) continue;

      const exId = crypto.randomUUID();
      const sentence = cleanFurigana(rawSentence);
      const reading = extractReading(rawSentence);
      const meaningZh = rawChinese || '';

      sqlLines.push(
        `INSERT INTO grammar_examples (id, grammar_lesson_id, sentence, reading, meaning_zh, audio_url, created_at, updated_at) VALUES (${escSql(exId)}, ${escSql(lessonId)}, ${escSql(sentence)}, ${escSql(reading)}, ${escSql(meaningZh)}, NULL, NOW(), NOW());`
      );
      exampleCount++;
    }
  }

  db.close();

  sqlLines.push('');
  sqlLines.push('SET FOREIGN_KEY_CHECKS = 1;');

  // 写入SQL文件
  fs.writeFileSync(OUTPUT_SQL, sqlLines.join('\n'), 'utf8');

  console.log(`\n=== 生成完成 ===`);
  console.log(`语法条目: ${lessonCount}`);
  console.log(`例句: ${exampleCount}`);
  console.log(`级别分布:`, JSON.stringify(levelDist));
  console.log(`SQL文件: ${OUTPUT_SQL}`);
  console.log(`文件大小: ${(fs.statSync(OUTPUT_SQL).size / 1024).toFixed(1)} KB`);
}

main();
