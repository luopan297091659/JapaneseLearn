/**
 * import_anki_vocab.js
 * 
 * 方案A: 从 Anki JLPT10k 词库全量导入词汇到数据库
 * - 清空现有 vocabulary 表及相关 srs_cards / quiz_questions
 * - 解析 notes.csv (TSV, 40列)
 * - 批量插入
 * 
 * 用法: cd backend && node scripts/import_anki_vocab.js
 */

require('dotenv').config();
const fs = require('fs');
const mysql = require('mysql2/promise');
const { v4: uuidv4 } = require('uuid');

// ─── 数据源 ──────────────────────────────────────────────────────────────────
const NOTES_CSV = 'C:/Users/28296/Downloads/anki-jlpt-decks/anki-jlpt-decks-26.02.16_3/eggrolls-JLPT10k-v3/notes.csv';

// ─── 数据库连接 ──────────────────────────────────────────────────────────────
const DB_CONFIG = {
  host:     process.env.DB_HOST     || '139.196.44.6',
  port:     parseInt(process.env.DB_PORT || '3306'),
  user:     process.env.DB_USER     || 'root',
  password: process.env.DB_PASSWORD || '6586156',
  database: process.env.DB_NAME     || 'japanese_learn',
  charset:  'utf8mb4',
  connectTimeout: 30000,
};

// ─── 列索引 (0-based, 共40列) ────────────────────────────────────────────────
const COL = {
  DECK:               2,   // eggrolls-JLPT10k-v3::1-N4+N5
  WORD:               4,   // 高校
  PITCH:              5,   // ⓪
  POS:                6,   // 名
  READING:            7,   // こうこう
  MEANING_ZH:         8,   // 高中
  MEANING_ZH_TW:      9,   // 高中 (繁体)
  NOTES:             10,   // 「高等学校」の略
  WORD_AUDIO:        11,   // [sound:xxx.mp3]
  EX_SENTENCE:       13,   // 妹は高校に通っています
  EX_FURIGANA:       14,   // 妹[いもうと]は<b>高校[こうこう]</b>に...
  EX_MEANING_ZH:     15,   // 妹妹在上高中
  EX_AUDIO:          17,   // [sound:voicepeak-xxx.mp3]
  FREQ_RANK:         36,   // 1.0171
  TAGS:              39,   // eggrolls-JLPT10k-v3::1-N4+N5 ...
};

// ─── 工具函数 ────────────────────────────────────────────────────────────────

/** 从 deck 名推断 JLPT 级别 */
function extractJlptLevel(deck) {
  if (/1-N4\+N5/i.test(deck)) return 'N5';
  if (/2-N3/i.test(deck))     return 'N3';
  if (/3-N2/i.test(deck))     return 'N2';
  if (/4-N1/i.test(deck))     return 'N1';
  return 'N5';
}

/** 日文词性映射 → 英文 ENUM */
function parsePOS(pos) {
  if (!pos) return 'other';
  const s = pos.trim();
  // 动词 (他動, 自動, 自他動, 補動, 動1/2/3)
  if (/他動|自動|自他動|補動|^動\d?$/.test(s)) return 'verb';
  // 形容词 (ナ形, イ形, 形動, 連体, トタル)
  if (/ナ形|な形|形動|形容動|イ形|い形|形容|トタル/.test(s)) return 'adjective';
  if (/連体/.test(s))                 return 'adjective';
  // 副词
  if (/副/.test(s))                   return 'adverb';
  // 助词 (副助, 格助, 接助, 終助)
  if (/副助|格助|接助|終助/.test(s))   return 'particle';
  // 感叹词
  if (/感/.test(s))                   return 'interjection';
  // 接续词 (接続 或单独的 接)
  if (/接続/.test(s))                 return 'conjunction';
  if (/^接$/.test(s))                 return 'conjunction';
  // 名词类 (名, 代名词, 接尾, 接頭)
  if (/名|代|接尾|接頭/.test(s))       return 'noun';
  // 连语、成句、造语 → noun (作为固定表达/词组)
  if (/連語|成句|造/.test(s))          return 'noun';
  return 'other';
}

/** 从 [sound:filename.mp3] 提取文件名 */
function extractAudioFile(field) {
  if (!field) return null;
  const m = field.match(/\[sound:([^\]]+)\]/);
  return m ? m[1] : null;
}

/** 去除 HTML 标签 */
function stripHtml(s) {
  return s ? s.replace(/<[^>]+>/g, '').trim() : '';
}

/** 清理例句读音: 去 HTML 但保留振假名方括号 */
function cleanReading(s) {
  if (!s) return '';
  return s.replace(/<\/?b>/g, '').replace(/\s+/g, ' ').trim();
}

// ─── 主流程 ──────────────────────────────────────────────────────────────────

async function main() {
  // 1. 读取并解析 notes.csv
  console.log('=== 读取 notes.csv ===');
  const content = fs.readFileSync(NOTES_CSV, 'utf-8');
  const lines = content.split('\n');
  const dataLines = lines.filter(l => !l.startsWith('#') && l.trim());
  console.log(`数据行数: ${dataLines.length}`);

  const records = [];
  const levelCounts = {};
  const posCounts = {};
  let skipped = 0;

  for (const line of dataLines) {
    const c = line.split('\t');
    if (c.length < 15) { skipped++; continue; }

    const word = stripHtml(c[COL.WORD] || '');
    if (!word) { skipped++; continue; }

    const deck  = c[COL.DECK] || '';
    const level = extractJlptLevel(deck);
    levelCounts[level] = (levelCounts[level] || 0) + 1;

    const posRaw = (c[COL.POS] || '').trim();
    const pos = parsePOS(posRaw);
    posCounts[pos] = (posCounts[pos] || 0) + 1;

    const reading    = (c[COL.READING] || '').trim();
    const meaningZh  = (c[COL.MEANING_ZH] || '').trim();
    const notes      = stripHtml(c[COL.NOTES] || '');
    const audioFile  = extractAudioFile(c[COL.WORD_AUDIO]);

    const exSentence  = stripHtml(c[COL.EX_SENTENCE] || '');
    const exReading   = cleanReading(c[COL.EX_FURIGANA] || '');
    const exMeaningZh = (c[COL.EX_MEANING_ZH] || '').trim();
    const exAudioFile = extractAudioFile(c[COL.EX_AUDIO]);

    const freqStr = (c[COL.FREQ_RANK] || '').trim();
    const freqRank = freqStr ? parseFloat(freqStr) : null;

    records.push({
      id:                uuidv4(),
      word,
      reading,
      meaning_zh:        meaningZh + (notes ? '\n' + notes : ''),
      meaning_en:        null,
      part_of_speech:    pos,
      part_of_speech_raw: posRaw || null,
      jlpt_level:        level,
      example_sentence:  exSentence || null,
      example_reading:   exReading || null,
      example_meaning_zh: exMeaningZh || null,
      example_audio_url: exAudioFile ? `/uploads/audio/vocab/${exAudioFile}` : null,
      audio_url:         audioFile ? `/uploads/audio/vocab/${audioFile}` : null,
      image_url:         null,
      category:          null,
      tags:              (freqRank && !isNaN(freqRank))
                           ? JSON.stringify({ frequency_rank: freqRank })
                           : null,
    });
  }

  console.log(`解析成功: ${records.length}  跳过: ${skipped}`);
  console.log('JLPT 分布:', levelCounts);
  console.log('词性分布:', posCounts);
  console.log(`有例句: ${records.filter(r => r.example_sentence).length}`);
  console.log(`有音频: ${records.filter(r => r.audio_url).length}`);
  console.log(`有例句音频: ${records.filter(r => r.example_audio_url).length}`);

  // 2. 连接数据库
  console.log('\n=== 连接数据库 ===');
  const conn = await mysql.createConnection(DB_CONFIG);
  console.log('已连接:', DB_CONFIG.host);

  // 3. 查看现有数据
  const [[{ cnt: oldCount }]] = await conn.query('SELECT COUNT(*) as cnt FROM vocabulary');
  console.log(`现有词汇数: ${oldCount}`);

  // 4. 清理关联表
  console.log('\n=== 清理关联数据 ===');
  const [srs] = await conn.query("DELETE FROM srs_cards WHERE card_type = 'vocabulary'");
  console.log(`删除 srs_cards: ${srs.affectedRows}`);

  const [quiz] = await conn.query("DELETE FROM quiz_questions WHERE ref_vocabulary_id IS NOT NULL");
  console.log(`删除 quiz_questions: ${quiz.affectedRows}`);

  // 5. 清空词汇表
  await conn.query('SET FOREIGN_KEY_CHECKS = 0');
  await conn.query('TRUNCATE TABLE vocabulary');
  await conn.query('SET FOREIGN_KEY_CHECKS = 1');
  console.log('已清空 vocabulary 表');

  // 6. 批量插入
  console.log('\n=== 批量插入 ===');
  const BATCH = 500;
  let inserted = 0;
  const now = new Date().toISOString().slice(0, 19).replace('T', ' ');

  for (let i = 0; i < records.length; i += BATCH) {
    const batch = records.slice(i, i + BATCH);
    const values = batch.map(r => [
      r.id, r.word, r.reading, r.meaning_zh, r.meaning_en,
      r.part_of_speech, r.part_of_speech_raw, r.jlpt_level, r.example_sentence,
      r.example_reading, r.example_meaning_zh, r.example_audio_url,
      r.audio_url, r.image_url, r.category, r.tags, now, now,
    ]);

    await conn.query(
      `INSERT INTO vocabulary
        (id, word, reading, meaning_zh, meaning_en,
         part_of_speech, part_of_speech_raw, jlpt_level, example_sentence,
         example_reading, example_meaning_zh, example_audio_url,
         audio_url, image_url, category, tags, created_at, updated_at)
       VALUES ?`,
      [values]
    );

    inserted += batch.length;
    process.stdout.write(`\r已插入: ${inserted} / ${records.length}`);
  }
  console.log('');

  // 7. 验证
  console.log('\n=== 验证结果 ===');
  const [[{ cnt: newCount }]] = await conn.query('SELECT COUNT(*) as cnt FROM vocabulary');
  console.log(`最终词汇数: ${newCount}`);

  const [levels] = await conn.query(
    'SELECT jlpt_level, COUNT(*) as cnt FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level'
  );
  console.log('级别分布:', levels.map(r => `${r.jlpt_level}:${r.cnt}`).join(', '));

  const [[{ cnt: exCnt }]] = await conn.query(
    'SELECT COUNT(*) as cnt FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ""'
  );
  console.log(`有例句: ${exCnt}`);

  const [[{ cnt: auCnt }]] = await conn.query(
    'SELECT COUNT(*) as cnt FROM vocabulary WHERE audio_url IS NOT NULL'
  );
  console.log(`有音频: ${auCnt}`);

  // 抽样
  const [samples] = await conn.query(
    'SELECT word, reading, jlpt_level, LEFT(meaning_zh, 30) as mz, LEFT(example_sentence, 40) as ex, audio_url FROM vocabulary ORDER BY RAND() LIMIT 5'
  );
  console.log('\n--- 随机抽样 ---');
  for (const s of samples) {
    console.log(`  ${s.jlpt_level} | ${s.word} (${s.reading}) → ${s.mz}`);
    console.log(`       例句: ${s.ex || '无'}`);
    console.log(`       音频: ${s.audio_url || '无'}`);
  }

  await conn.end();
  console.log('\n=== 导入完成! ===');
}

main().catch(err => {
  console.error('导入失败:', err);
  process.exit(1);
});
