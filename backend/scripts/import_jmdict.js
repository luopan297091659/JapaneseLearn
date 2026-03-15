#!/usr/bin/env node
/**
 * JMdict 词典导入脚本 (流式 line-by-line 解析，避免 SAX DOCTYPE 问题)
 *
 * 用法:
 *   node scripts/import_jmdict.js <JMdict 或 JMdict.gz>
 *
 * 该脚本会:
 *   1. 自动建表 dict_entries
 *   2. 解析 DOCTYPE 内的 ENTITY 定义（POS 标记）
 *   3. 流式逐行解析 XML
 *   4. 批量插入 MySQL（每 2000 条一批）
 */

const fs = require('fs');
const path = require('path');
const { createGunzip } = require('zlib');
const readline = require('readline');

// ── DB setup ──
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const { sequelize } = require('../src/config/database');
const { DictEntry } = require('../src/models');

// JMdict 常用标记 → 优先级
const PRIORITY_MAP = {
  'ichi1': 5, 'news1': 5, 'spec1': 4,
  'ichi2': 3, 'news2': 3, 'spec2': 2,
  'gai1': 2, 'gai2': 1,
};

async function main() {
  const xmlFile = process.argv[2];
  if (!xmlFile) {
    console.error('用法: node scripts/import_jmdict.js <JMdict 或 JMdict.gz>');
    process.exit(1);
  }
  if (!fs.existsSync(xmlFile)) {
    console.error(`文件不存在: ${xmlFile}`);
    process.exit(1);
  }

  console.log('=== JMdict 词典导入 ===');
  console.log(`文件: ${xmlFile}`);

  // 同步建表
  await DictEntry.sync({ force: true });
  console.log('✓ dict_entries 表已创建');

  // 统计
  let entryCount = 0, rowCount = 0, zhCount = 0;
  const batch = [];
  const BATCH_SIZE = 2000;

  async function flushBatch() {
    if (batch.length === 0) return;
    try {
      await DictEntry.bulkCreate(batch, { ignoreDuplicates: true });
    } catch (err) {
      console.error('批量插入失败:', err.message);
    }
    batch.length = 0;
  }

  // ── 解析 ENTITY 定义（用于解析 &xxx; 实体引用） ──
  const entities = {};

  // ── 解析状态 ──
  let inEntry = false;
  let inKEle = false, inREle = false, inSense = false;
  let entSeq = '';
  let kanjiList = [];
  let readingList = [];
  let senseList = [];
  let currentSense = null;
  let priorities = [];
  let accum = ''; // 多行 buffer

  function resolveEntities(text) {
    return text.replace(/&([a-zA-Z0-9_.-]+);/g, (match, name) => {
      if (entities[name]) return entities[name];
      if (name === 'amp') return '&';
      if (name === 'lt') return '<';
      if (name === 'gt') return '>';
      if (name === 'quot') return '"';
      if (name === 'apos') return "'";
      return match; // 未知实体保持原样
    });
  }

  function extractTag(line, tagName) {
    const re = new RegExp(`<${tagName}[^>]*>([^<]*)</${tagName}>`);
    const m = line.match(re);
    return m ? resolveEntities(m[1].trim()) : null;
  }

  function extractAttr(line, attrName) {
    const re = new RegExp(`${attrName}="([^"]*)"`);
    const m = line.match(re);
    return m ? m[1] : null;
  }

  function processEntry() {
    entryCount++;
    // 计算优先级
    let priority = 0;
    for (const p of priorities) {
      priority = Math.max(priority, PRIORITY_MAP[p] || 0);
    }

    // 合并所有 sense 的释义
    const allPos = [...new Set(senseList.flatMap(s => s.pos))];
    const allEn = senseList.map(s => s.en.join('; ')).filter(Boolean);
    const allZh = senseList.map(s => s.zh.join('; ')).filter(Boolean);

    const posStr = allPos.join('; ').substring(0, 200);
    const enStr = allEn.join('；');
    const zhStr = allZh.join('；');
    if (zhStr) zhCount++;

    // 为每个 kanji 形式生成行
    const kanji = kanjiList.length > 0 ? kanjiList : [null];
    const reading = readingList.length > 0 ? readingList[0] : '';
    const seq = parseInt(entSeq) || 0;

    for (const k of kanji) {
      batch.push({
        ent_seq: seq,
        kanji: k,
        reading: reading,
        pos: posStr || null,
        meaning_en: enStr || null,
        meaning_zh: zhStr || null,
        priority,
      });
      rowCount++;
    }
  }

  // ── 创建读取流 ──
  let input = fs.createReadStream(xmlFile);
  if (xmlFile.endsWith('.gz')) {
    input = input.pipe(createGunzip());
  }

  const rl = readline.createInterface({ input, crlfDelay: Infinity });

  for await (const rawLine of rl) {
    const line = rawLine.trim();
    if (!line) continue;

    // 解析 ENTITY 定义
    const entityMatch = line.match(/<!ENTITY\s+(\S+)\s+"([^"]*)"\s*>/);
    if (entityMatch) {
      entities[entityMatch[1]] = entityMatch[2];
      continue;
    }

    // 跳过 DOCTYPE 等
    if (line.startsWith('<?') || line.startsWith('<!') || line.startsWith(']>')) continue;

    // <entry>
    if (line === '<entry>') {
      inEntry = true;
      entSeq = '';
      kanjiList = [];
      readingList = [];
      senseList = [];
      priorities = [];
      inKEle = false; inREle = false; inSense = false;
      continue;
    }

    // </entry>
    if (line === '</entry>') {
      processEntry();

      if (batch.length >= BATCH_SIZE) {
        await flushBatch();
      }
      if (entryCount % 20000 === 0) {
        console.log(`  已处理 ${entryCount.toLocaleString()} 条目, ${rowCount.toLocaleString()} 行 (${zhCount} 有中文)`);
      }
      inEntry = false;
      continue;
    }

    if (!inEntry) continue;

    // ent_seq
    const seq = extractTag(line, 'ent_seq');
    if (seq) { entSeq = seq; continue; }

    // k_ele / r_ele / sense 块
    if (line === '<k_ele>') { inKEle = true; continue; }
    if (line === '</k_ele>') { inKEle = false; continue; }
    if (line === '<r_ele>') { inREle = true; continue; }
    if (line === '</r_ele>') { inREle = false; continue; }
    if (line === '<sense>') {
      inSense = true;
      currentSense = { pos: [], en: [], zh: [] };
      continue;
    }
    if (line === '</sense>') {
      if (currentSense) senseList.push(currentSense);
      currentSense = null;
      inSense = false;
      continue;
    }

    // 在 k_ele 内
    if (inKEle) {
      const keb = extractTag(line, 'keb');
      if (keb) kanjiList.push(keb);
      const kePri = extractTag(line, 'ke_pri');
      if (kePri) priorities.push(kePri);
    }

    // 在 r_ele 内
    if (inREle) {
      const reb = extractTag(line, 'reb');
      if (reb) readingList.push(reb);
      const rePri = extractTag(line, 're_pri');
      if (rePri) priorities.push(rePri);
    }

    // 在 sense 内
    if (inSense && currentSense) {
      const pos = extractTag(line, 'pos');
      if (pos) { currentSense.pos.push(pos); continue; }

      // <gloss xml:lang="xxx">text</gloss> or <gloss>text</gloss>
      if (line.includes('<gloss')) {
        const glossMatch = line.match(/<gloss[^>]*>([^<]*)<\/gloss>/);
        if (glossMatch) {
          const text = resolveEntities(glossMatch[1].trim());
          const lang = extractAttr(line, 'xml:lang');
          if (!lang || lang === 'eng') {
            currentSense.en.push(text);
          } else if (lang === 'chi' || lang === 'zho') {
            currentSense.zh.push(text);
          }
        }
      }
    }
  }

  // flush 剩余
  await flushBatch();

  console.log(`\n✓ 导入完成!`);
  console.log(`  总条目: ${entryCount.toLocaleString()}`);
  console.log(`  总行数: ${rowCount.toLocaleString()}`);
  console.log(`  含中文: ${zhCount.toLocaleString()} (${(zhCount > 0 ? (zhCount/entryCount*100).toFixed(1) : 0)}%)`);
  console.log(`  ENTITY 定义: ${Object.keys(entities).length}`);

  // 创建全文索引加速中文搜索
  console.log('创建索引...');
  try {
    await sequelize.query('ALTER TABLE dict_entries ADD FULLTEXT INDEX ft_meaning_zh (meaning_zh) WITH PARSER ngram', { raw: true });
    console.log('✓ 全文索引已创建');
  } catch (e) {
    if (e.message && e.message.includes('Duplicate')) {
      console.log('  全文索引已存在, 跳过');
    } else {
      console.warn('  全文索引创建失败 (非关键):', e.message);
    }
  }

  await sequelize.close();
  console.log('=== 完成 ===');
}

main().catch(err => {
  console.error('致命错误:', err);
  process.exit(1);
});
