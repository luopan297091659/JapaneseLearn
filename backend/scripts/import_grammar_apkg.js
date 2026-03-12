/**
 * 语法数据导入工具 - 从蓝宝书APKG导入语法到数据库
 * 
 * 功能：
 * 1. 解析 APKG (SQLite) 中的语法数据
 * 2. 清空现有语法数据（grammar_examples → grammar_lessons → srs_cards[grammar]）
 * 3. 导入新数据
 */
const Database = require('better-sqlite3');
const mysql = require('mysql2/promise');
const crypto = require('crypto');
const path = require('path');

const APKG_DB = path.join(__dirname, '../../temp_grammar_extract/collection.anki21');

const DB_CONFIG = {
  host: '139.196.44.6',
  port: 3306,
  user: 'root',
  password: '6586156',
  database: 'japanese_learn',
};

// ── HTML清理 ──
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

// ── 清理振假名标记，保留汉字：山[やま]田[だ] → 山田 ──
function cleanFurigana(text) {
  if (!text) return '';
  return text
    .replace(/\[([^\]]*)\]/g, '')  // 移除 [reading] 部分
    .replace(/\s+/g, '')           // 清除空格（Anki用空格分隔振假名组）
    .trim();
}

// ── 提取读音：山[やま]田[だ]さん → やまださん ──
function extractReading(text) {
  if (!text) return '';
  // 把 汉字[读音] 替换为 读音，保留非注音文字
  let result = text.replace(/([^\[\]\s]*)\[([^\]]+)\]/g, '$2');
  // 清除多余空格
  result = result.replace(/\s+/g, '').trim();
  return result;
}

// ── 解析JLPT级别 ──
function parseLevel(levelField, tags) {
  // 优先从Level字段解析
  if (levelField) {
    const m = levelField.match(/N([1-5])/);
    if (m) return 'N' + m[1];
  }
  // 从tags解析
  if (tags) {
    const m = tags.match(/N([1-5])/);
    if (m) return 'N' + m[1];
  }
  // 敬語归入N1
  if ((tags && tags.includes('敬語')) || (levelField && levelField.includes('敬語'))) {
    return 'N1';
  }
  return null;
}

function generateUUID() {
  return crypto.randomUUID();
}

async function main() {
  console.log('╔══════════════════════════════════════╗');
  console.log('║   蓝宝书语法数据导入工具             ║');
  console.log('╚══════════════════════════════════════╝\n');

  // ─── 1. 读取APKG SQLite数据 ───
  console.log('【1/4】读取APKG数据...');
  const db = new Database(APKG_DB, { readonly: true });
  const notes = db.prepare('SELECT id, mid, flds, tags FROM notes').all();
  console.log(`  共读取 ${notes.length} 条记录`);

  // ─── 解析语法条目 ───
  const grammarItems = [];
  let skipped = 0;
  const skipReasons = {};

  for (const note of notes) {
    const fields = note.flds.split('\x1f');
    const tags = note.tags.trim();

    // 解析级别
    const level = parseLevel(fields[2] || '', tags);
    if (!level) {
      skipped++;
      skipReasons['无级别'] = (skipReasons['无级别'] || 0) + 1;
      continue;
    }

    // 标题
    const title = stripHtml(fields[3] || '').trim();
    if (!title) {
      skipped++;
      skipReasons['无标题'] = (skipReasons['无标题'] || 0) + 1;
      continue;
    }

    // 接续方式 (ConnectiveType1-10) → pattern + explanation
    const patterns = [];
    for (let i = 4; i <= 13; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) patterns.push(val);
    }

    // 中文解释 (Explain1-15)
    const explanations = [];
    for (let i = 14; i <= 28; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) explanations.push(val);
    }

    // 例句 (Example1-25 + Chinese1-25)
    const examples = [];
    for (let j = 0; j < 25; j++) {
      const rawSentence = stripHtml(fields[29 + j] || '').trim();
      const rawChinese = stripHtml(fields[54 + j] || '').trim();
      if (rawSentence) {
        examples.push({
          sentence: cleanFurigana(rawSentence),
          reading: extractReading(rawSentence),
          meaning_zh: rawChinese || '',
        });
      }
    }

    // 使用注记 (Note1-15)
    const usageNotes = [];
    for (let i = 104; i <= 118; i++) {
      const val = stripHtml(fields[i] || '').trim();
      if (val) usageNotes.push(val);
    }

    // 排序
    const subOrder = parseInt(fields[119]) || 0;
    const totalOrder = parseInt(fields[120]) || 0;

    // 是否敬語
    const isKeigo = tags.includes('敬語');

    grammarItems.push({
      title: title.substring(0, 200),
      level,
      pattern: (patterns[0] || title).substring(0, 300),
      explanation: patterns.join('\n') || title,        // 日文解释用接续方式
      explanation_zh: explanations.join('\n') || null,   // 中文解释
      usage_notes: usageNotes.join('\n') || null,
      order_index: totalOrder || subOrder,
      examples,
      isKeigo,
    });
  }

  db.close();

  // 统计
  let totalExamples = 0;
  grammarItems.forEach(g => totalExamples += g.examples.length);
  const levelDist = {};
  grammarItems.forEach(g => { levelDist[g.level] = (levelDist[g.level] || 0) + 1; });

  console.log(`  ✓ 解析成功: ${grammarItems.length} 条语法`);
  console.log(`  ✓ 例句总数: ${totalExamples} 条`);
  console.log(`  ✓ 级别分布:`, JSON.stringify(levelDist));
  if (skipped > 0) console.log(`  ⚠ 跳过: ${skipped} 条`, JSON.stringify(skipReasons));

  // ─── 2. 连接数据库 ───
  console.log('\n【2/4】连接数据库...');
  const conn = await mysql.createConnection(DB_CONFIG);
  console.log('  ✓ 已连接');

  // ─── 3. 清空现有数据 ───
  console.log('\n【3/4】清空现有语法数据...');
  
  // 先删除引用语法的SRS卡片
  const [srsResult] = await conn.execute(
    "DELETE FROM srs_cards WHERE card_type = 'grammar'"
  );
  console.log(`  ✓ 删除语法SRS卡片: ${srsResult.affectedRows} 条`);

  // 删除语法例句
  const [exResult] = await conn.execute('DELETE FROM grammar_examples');
  console.log(`  ✓ 删除语法例句: ${exResult.affectedRows} 条`);

  // 删除语法课程
  const [lessonResult] = await conn.execute('DELETE FROM grammar_lessons');
  console.log(`  ✓ 删除语法课程: ${lessonResult.affectedRows} 条`);

  // ─── 4. 批量导入 ───
  console.log('\n【4/4】导入新数据...');
  
  let insertedLessons = 0;
  let insertedExamples = 0;

  // 使用事务确保数据一致性
  await conn.beginTransaction();

  try {
    for (const item of grammarItems) {
      const lessonId = generateUUID();

      await conn.execute(
        `INSERT INTO grammar_lessons 
         (id, title, title_zh, jlpt_level, pattern, explanation, explanation_zh, usage_notes, order_index, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())`,
        [
          lessonId,
          item.title,
          null,
          item.level,
          item.pattern,
          item.explanation,
          item.explanation_zh,
          item.usage_notes,
          item.order_index,
        ]
      );
      insertedLessons++;

      // 批量插入例句
      for (const ex of item.examples) {
        const exId = generateUUID();
        await conn.execute(
          `INSERT INTO grammar_examples 
           (id, grammar_lesson_id, sentence, reading, meaning_zh, audio_url, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, NULL, NOW(), NOW())`,
          [exId, lessonId, ex.sentence, ex.reading || null, ex.meaning_zh]
        );
        insertedExamples++;
      }

      if (insertedLessons % 100 === 0) {
        console.log(`  进度: ${insertedLessons}/${grammarItems.length} 条语法...`);
      }
    }

    await conn.commit();
    console.log('  ✓ 事务已提交');
  } catch (err) {
    await conn.rollback();
    console.error('  ✗ 导入失败，已回滚:', err.message);
    await conn.end();
    process.exit(1);
  }

  // ─── 统计 ───
  const [finalLessons] = await conn.execute('SELECT jlpt_level, COUNT(*) as cnt FROM grammar_lessons GROUP BY jlpt_level ORDER BY jlpt_level');
  const [finalExamples] = await conn.execute('SELECT COUNT(*) as cnt FROM grammar_examples');
  const [noAudio] = await conn.execute('SELECT COUNT(*) as cnt FROM grammar_examples WHERE audio_url IS NULL');

  console.log('\n╔══════════════════════════════════════╗');
  console.log('║   导入结果                            ║');
  console.log('╠══════════════════════════════════════╣');
  console.log(`║  语法条目: ${insertedLessons}`);
  console.log(`║  例句总数: ${insertedExamples}`);
  console.log('║  级别分布:');
  for (const row of finalLessons) {
    console.log(`║    ${row.jlpt_level}: ${row.cnt} 条`);
  }
  console.log(`║  需要TTS: ${noAudio[0].cnt} 条例句`);
  console.log('╚══════════════════════════════════════╝');

  await conn.end();
  console.log('\n完成！');
}

main().catch(err => {
  console.error('致命错误:', err);
  process.exit(1);
});
