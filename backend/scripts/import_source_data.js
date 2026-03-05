/**
 * import_source_data.js
 * 
 * 将 C:\Users\28296\Downloads\source 目录下的N1-N5词汇、语法数据导入数据库
 * 
 * 用法:
 *   DB_PASSWORD=yourpassword node scripts/import_source_data.js
 *   # 或指定连接信息:
 *   DB_HOST=139.196.44.6 DB_USER=root DB_PASSWORD=xxx node scripts/import_source_data.js
 */

require('dotenv').config();
const path = require('path');
const fs   = require('fs');
const mysql = require('mysql2/promise');
const XLSX  = require('xlsx');
const { v4: uuidv4 } = require('uuid');

// ─── 数据源目录 ───────────────────────────────────────────────────────────────
const SOURCE_DIR = 'C:/Users/28296/Downloads/source';

// ─── 数据库连接配置 ────────────────────────────────────────────────────────────
const DB_CONFIG = {
  host:     process.env.DB_HOST     || '139.196.44.6',
  port:     parseInt(process.env.DB_PORT || '3306'),
  user:     process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '6586156',
  database: process.env.DB_NAME     || 'japanese_learn',
  charset:  'utf8mb4',
  connectTimeout: 30000,
};

// ─── 工具函数 ─────────────────────────────────────────────────────────────────

/** 将词性字符串映射为 ENUM 值 */
function parsePOS(posStr) {
  if (!posStr) return 'other';
  const s = posStr.replace(/[・~～·]/g, '');
  if (/動|どう|verb/i.test(s))           return 'verb';
  if (/形容詞|い形|形1/i.test(s))         return 'adjective';
  if (/形容動詞|な形|形2/i.test(s))        return 'adjective';
  if (/形/i.test(s))                       return 'adjective';
  if (/副|adv/i.test(s))                  return 'adverb';
  if (/助詞|助|particle/i.test(s))         return 'particle';
  if (/接続|conjunction/i.test(s))        return 'conjunction';
  if (/感動詞|interjection/i.test(s))     return 'interjection';
  if (/名|noun/i.test(s))                 return 'noun';
  return 'other';
}

/**
 * 解析 wordDesc 字段，例如:
 *   "（いがい）⓪【名·ナ形】意外；意想不到的"
 *   "（たべる）③【他動】食べる を食べます"
 * 返回 { reading, pos, meaning }
 */
function parseWordDesc(desc) {
  if (!desc) return { reading: '', pos: 'other', meaning: '' };

  // 提取括号内读音（支持半角/全角括号）
  const readingMatch = desc.match(/[（(]([^）)]+)[）)]/);
  const reading = readingMatch ? readingMatch[1].trim() : '';

  // 提取 【词性】
  const posMatch = desc.match(/【([^】]+)】/);
  const pos = posMatch ? parsePOS(posMatch[1]) : 'other';

  // 提取含义（】 之后的内容）
  const meaningMatch = desc.match(/】(.+)$/s);
  const meaning = meaningMatch ? meaningMatch[1].trim() : '';

  return { reading, pos, meaning };
}

/** 按 lesson 编号推断语法的 JLPT 级别 */
function guessGrammarLevel(lesson) {
  const s = String(lesson).trim();
  // 数字类型: Minnano 教材课次
  const n = parseInt(s);
  if (!isNaN(n)) {
    if (n <= 12)  return 'N5';
    if (n <= 25)  return 'N4';
    if (n <= 50)  return 'N3';
    if (n <= 75)  return 'N2';
    return 'N1';
  }
  // m## 格式: 中级/高级语法
  const mMatch = s.match(/m(\d+)/);
  if (mMatch) {
    const m = parseInt(mMatch[1]);
    if (m <= 8)   return 'N3';
    if (m <= 18)  return 'N2';
    return 'N1';
  }
  return 'N3';
}

/** 数组分批 */
function chunkArray(arr, size) {
  const result = [];
  for (let i = 0; i < arr.length; i += size)
    result.push(arr.slice(i, i + size));
  return result;
}

// ─── 导入器 ───────────────────────────────────────────────────────────────────

/**
 * 导入 JSON 词汇文件（n1/ n2/ n3/ n5n4/）
 */
async function importJSONVocab(conn, dirName, jlptLevel) {
  const dir = path.join(SOURCE_DIR, dirName);
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.json')).sort();
  const rows = [];

  for (const file of files) {
    const raw  = fs.readFileSync(path.join(dir, file), 'utf8');
    const json = JSON.parse(raw);
    for (const item of (json.data || [])) {
      const word = item.wordName?.trim();
      if (!word) continue;

      const { reading, pos, meaning } = parseWordDesc(item.wordDesc);
      const finalMeaning = (item.correctDesc?.trim()) || meaning || '';
      const finalReading = reading || word;

      rows.push([
        uuidv4(), word, finalReading, finalMeaning,
        null,          // meaning_en
        pos,           // part_of_speech
        jlptLevel,     // jlpt_level
        null, null, null, null, null, null, null,
      ]);
    }
  }

  let inserted = 0;
  for (const chunk of chunkArray(rows, 200)) {
    const [res] = await conn.query(
      `INSERT IGNORE INTO vocabulary
         (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level,
          example_sentence, example_reading, example_meaning_zh,
          audio_url, image_url, category, tags)
       VALUES ?`,
      [chunk]
    );
    inserted += res.affectedRows;
  }
  return { total: rows.length, inserted };
}

/**
 * 导入 word-list.js（N5 基础词汇）
 */
async function importWordListJS(conn) {
  const rawContent = fs.readFileSync(path.join(SOURCE_DIR, 'word-list.js'), 'utf8');
  // 提取 JSON 数组
  const match = rawContent.match(/var word_list\s*=\s*(\[[\s\S]+?\]);?\s*$/m)
    || rawContent.match(/\[[\s\S]+\]/);
  if (!match) { console.warn('  ⚠ word-list.js 解析失败'); return { total: 0, inserted: 0 }; }

  let items;
  try {
    items = JSON.parse(match[1] || match[0]);
  } catch {
    console.warn('  ⚠ word-list.js JSON 解析失败');
    return { total: 0, inserted: 0 };
  }

  const rows = [];
  for (const item of items) {
    const word = item.content?.trim();
    if (!word) continue;
    const reading = item.pron?.trim() || word;
    const meaning = item.definition?.trim() || '';
    rows.push([
      uuidv4(), word, reading, meaning,
      null, 'other', 'N5',
      null, null, null, null, null, null, null,
    ]);
  }

  let inserted = 0;
  for (const chunk of chunkArray(rows, 200)) {
    const [res] = await conn.query(
      `INSERT IGNORE INTO vocabulary
         (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level,
          example_sentence, example_reading, example_meaning_zh,
          audio_url, image_url, category, tags)
       VALUES ?`,
      [chunk]
    );
    inserted += res.affectedRows;
  }
  return { total: rows.length, inserted };
}

/**
 * 导入 jp_zhongji.xlsx（中高级词汇，含词性与读音）
 */
async function importZhongji(conn) {
  const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'jp_zhongji.xlsx'));
  const ws   = wb.Sheets[wb.SheetNames[0]];
  const data = XLSX.utils.sheet_to_json(ws, { header: 1 });

  // 字段: 日文, 假名, 中文, 发音, 类型
  // 第一行为 header，但每个章节段落有一行标题行（只有第一列有值）
  const rows = [];
  for (let i = 1; i < data.length; i++) {
    const r = data[i];
    const word    = String(r[0] || '').trim();
    const kana    = String(r[1] || '').trim();
    const meaning = String(r[2] || '').trim();
    const posRaw  = String(r[4] || '').trim();
    if (!word || !kana || !meaning) continue; // 跳过章节标题行
    const pos = parsePOS(posRaw);
    rows.push([
      uuidv4(), word, kana, meaning,
      null, pos, 'N3',   // 中级词汇默认 N3
      null, null, null, null, null, null, null,
    ]);
  }

  let inserted = 0;
  for (const chunk of chunkArray(rows, 200)) {
    const [res] = await conn.query(
      `INSERT IGNORE INTO vocabulary
         (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level,
          example_sentence, example_reading, example_meaning_zh,
          audio_url, image_url, category, tags)
       VALUES ?`,
      [chunk]
    );
    inserted += res.affectedRows;
  }
  return { total: rows.length, inserted };
}

/**
 * 导入 ABAB.xlsx（副词擬態語）
 */
async function importABAB(conn) {
  const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'ABAB.xlsx'));
  const ws   = wb.Sheets[wb.SheetNames[0]];
  const data = XLSX.utils.sheet_to_json(ws);

  // 字段: 副词, 意思, 例句, 例句意思
  const rows = [];
  for (const r of data) {
    const word    = String(r['副词'] || '').trim();
    const meaning = String(r['意思'] || '').trim();
    const example = String(r['例句'] || '').trim();
    const exMean  = String(r['例句意思'] || '').trim();
    if (!word || !meaning) continue;
    rows.push([
      uuidv4(), word, word, meaning,
      null, 'adverb', 'N3',
      example || null, null, exMean || null,
      null, null, null, null,
    ]);
  }

  let inserted = 0;
  for (const chunk of chunkArray(rows, 100)) {
    const [res] = await conn.query(
      `INSERT IGNORE INTO vocabulary
         (id, word, reading, meaning_zh, meaning_en, part_of_speech, jlpt_level,
          example_sentence, example_reading, example_meaning_zh,
          audio_url, image_url, category, tags)
       VALUES ?`,
      [chunk]
    );
    inserted += res.affectedRows;
  }
  return { total: rows.length, inserted };
}

/**
 * 导入 grammar.xlsx（语法句型）
 */
async function importGrammar(conn) {
  const wb   = XLSX.readFile(path.join(SOURCE_DIR, 'grammar.xlsx'));
  const ws   = wb.Sheets[wb.SheetNames[0]];
  const data = XLSX.utils.sheet_to_json(ws);

  const rows = [];
  let orderIdx = 1;
  for (const r of data) {
    const pattern = String(r['expression'] || '').trim();
    if (!pattern) continue;

    const explanation = String(r['explanation'] || r['shortexplain'] || '').trim();
    const level = guessGrammarLevel(r['lesson']);

    rows.push([
      uuidv4(),
      pattern,       // title
      pattern,       // title_zh
      level,         // jlpt_level
      pattern,       // pattern
      explanation,   // explanation
      explanation,   // explanation_zh
      null,          // usage_notes
      orderIdx++,    // order_index
    ]);
  }

  let inserted = 0;
  for (const chunk of chunkArray(rows, 100)) {
    const [res] = await conn.query(
      `INSERT IGNORE INTO grammar_lessons
         (id, title, title_zh, jlpt_level, pattern,
          explanation, explanation_zh, usage_notes, order_index)
       VALUES ?`,
      [chunk]
    );
    inserted += res.affectedRows;
  }
  return { total: rows.length, inserted };
}

// ─── 主程序 ───────────────────────────────────────────────────────────────────
async function main() {
  if (!process.env.DB_PASSWORD && DB_CONFIG.password === '') {
    console.error('❌ 请通过环境变量提供数据库密码，例如:');
    console.error('   DB_PASSWORD=yourpassword node scripts/import_source_data.js');
    process.exit(1);
  }

  console.log(`\n🔌 连接数据库 ${DB_CONFIG.host}:${DB_CONFIG.port}/${DB_CONFIG.database} ...`);
  const conn = await mysql.createConnection(DB_CONFIG);
  console.log('✅ 连接成功\n');

  const results = {};

  try {
    console.log('📚 [1/7] 导入 N5/N4 词汇 (n5n4/)...');
    results.n5n4 = await importJSONVocab(conn, 'n5n4', 'N5');
    console.log(`       总计 ${results.n5n4.total} 条，新增 ${results.n5n4.inserted} 条`);

    console.log('📚 [2/7] 导入 N3 词汇 (n3/)...');
    results.n3 = await importJSONVocab(conn, 'n3', 'N3');
    console.log(`       总计 ${results.n3.total} 条，新增 ${results.n3.inserted} 条`);

    console.log('📚 [3/7] 导入 N2 词汇 (n2/)...');
    results.n2 = await importJSONVocab(conn, 'n2', 'N2');
    console.log(`       总计 ${results.n2.total} 条，新增 ${results.n2.inserted} 条`);

    console.log('📚 [4/7] 导入 N1 词汇 (n1/)...');
    results.n1 = await importJSONVocab(conn, 'n1', 'N1');
    console.log(`       总计 ${results.n1.total} 条，新增 ${results.n1.inserted} 条`);

    console.log('📚 [5/7] 导入 word-list.js (N5 基础词)...');
    results.wordList = await importWordListJS(conn);
    console.log(`       总计 ${results.wordList.total} 条，新增 ${results.wordList.inserted} 条`);

    console.log('📚 [6/7] 导入 jp_zhongji.xlsx (中高级词汇)...');
    results.zhongji = await importZhongji(conn);
    console.log(`       总计 ${results.zhongji.total} 条，新增 ${results.zhongji.inserted} 条`);

    console.log('📚 [7/7] 导入 ABAB.xlsx (副词/擬態語)...');
    results.abab = await importABAB(conn);
    console.log(`       总计 ${results.abab.total} 条，新增 ${results.abab.inserted} 条`);

    console.log('\n📖 导入语法句型 grammar.xlsx...');
    results.grammar = await importGrammar(conn);
    console.log(`       总计 ${results.grammar.total} 条，新增 ${results.grammar.inserted} 条`);

    const totalVocab = Object.values(results)
      .filter((_, k) => k < 7)
      .reduce((s, r) => s + r.inserted, 0);

    console.log('\n' + '='.repeat(50));
    console.log('✅ 导入完成!');
    console.log(`   词汇总新增: ${
      results.n5n4.inserted + results.n3.inserted + results.n2.inserted +
      results.n1.inserted + results.wordList.inserted + results.zhongji.inserted +
      results.abab.inserted
    } 条`);
    console.log(`   语法总新增: ${results.grammar.inserted} 条`);
    console.log('='.repeat(50) + '\n');

  } catch (err) {
    console.error('\n❌ 导入出错:', err.message);
    if (err.code) console.error('   MySQL 错误码:', err.code);
    process.exit(1);
  } finally {
    await conn.end();
  }
}

main();
