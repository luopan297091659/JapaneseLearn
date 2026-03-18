/**
 * 修复语法例句读音数据
 * 
 * 原因：之前 extractReading 的正则表达式有 bug，
 *       会把汉字前面的假名前缀也一起吞掉。
 *       例如：そろそろ食事[しょくじ]にしましょう → しょくじにしましょう（丢失了「そろそろ」）
 * 
 * 修复：重新从 APKG 源数据提取正确的 reading，更新数据库。
 * 
 * 用法：node backend/scripts/fix_grammar_readings.js [--dry-run]
 */
const Database = require('better-sqlite3');
const mysql = require('mysql2/promise');
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
    .trim();
}

// ── 去除振假名标注，保留汉字：食事[しょくじ] → 食事 ──
function cleanFurigana(text) {
  if (!text) return '';
  return text.replace(/\[([^\]]*)\]/g, '').replace(/\s+/g, '').trim();
}

// ── 修复后的 extractReading：只匹配汉字+[读音]，保留假名前缀 ──
function extractReading(text) {
  if (!text) return '';
  // 只替换 汉字[读音] → 读音，保留其余文字不变
  let result = text.replace(/[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]+\[([^\]]+)\]/g, '$1');
  // 去掉残留的空括号
  result = result.replace(/\[[^\]]*\]/g, '');
  result = result.replace(/\s+/g, '').trim();
  return result;
}

// ── 旧的有 bug 的 extractReading（用于对比） ──
function extractReadingOld(text) {
  if (!text) return '';
  let result = text.replace(/([^\[\]\s]*)\[([^\]]+)\]/g, '$2');
  result = result.replace(/\s+/g, '').trim();
  return result;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');
  
  console.log('╔══════════════════════════════════════╗');
  console.log('║   修复语法例句读音数据               ║');
  console.log('╚══════════════════════════════════════╝');
  if (dryRun) console.log('⚠️  DRY-RUN 模式，不会实际更新数据库\n');

  // 1. 读取 APKG 源数据
  console.log('【1/3】读取 APKG 源数据...');
  const db = new Database(APKG_DB, { readonly: true });
  const notes = db.prepare('SELECT id, flds, tags FROM notes').all();
  console.log(`  共 ${notes.length} 条记录\n`);

  // 2. 构建 sentence → correct reading 的映射
  const readingMap = new Map(); // sentence → newReading
  let diffCount = 0;

  for (const note of notes) {
    const fields = note.flds.split('\x1f');
    for (let j = 0; j < 25; j++) {
      const rawSentence = stripHtml(fields[29 + j] || '').trim();
      if (!rawSentence) continue;
      const sentence = cleanFurigana(rawSentence);
      const oldReading = extractReadingOld(rawSentence);
      const newReading = extractReading(rawSentence);
      if (sentence && newReading) {
        readingMap.set(sentence, newReading);
        if (oldReading !== newReading) {
          diffCount++;
          if (diffCount <= 20) {
            console.log(`  差异 #${diffCount}: ${sentence}`);
            console.log(`    旧: ${oldReading}`);
            console.log(`    新: ${newReading}\n`);
          }
        }
      }
    }
  }
  db.close();
  console.log(`  映射总数: ${readingMap.size}, 有差异: ${diffCount}\n`);

  if (diffCount === 0) {
    console.log('✅ 没有需要修复的数据');
    return;
  }

  // 3. 更新数据库
  console.log('【2/3】连接数据库...');
  const conn = await mysql.createConnection(DB_CONFIG);

  const [rows] = await conn.query('SELECT id, sentence, reading FROM grammar_examples');
  console.log(`  数据库中共 ${rows.length} 条例句\n`);

  console.log('【3/3】更新错误的 reading...');
  let updated = 0;
  let skipped = 0;

  for (const row of rows) {
    const correctReading = readingMap.get(row.sentence);
    if (correctReading && correctReading !== row.reading) {
      if (!dryRun) {
        await conn.query('UPDATE grammar_examples SET reading = ? WHERE id = ?', [correctReading, row.id]);
      }
      updated++;
      if (updated <= 10) {
        console.log(`  更新: ${row.sentence}`);
        console.log(`    旧: ${row.reading}`);
        console.log(`    新: ${correctReading}`);
      }
    } else {
      skipped++;
    }
  }

  await conn.end();

  console.log(`\n${'═'.repeat(40)}`);
  console.log(`✅ 完成！更新: ${updated}, 跳过: ${skipped}`);
  if (dryRun) console.log('⚠️  DRY-RUN 模式，以上更新未实际执行');
}

main().catch(err => {
  console.error('❌ 错误:', err);
  process.exit(1);
});
