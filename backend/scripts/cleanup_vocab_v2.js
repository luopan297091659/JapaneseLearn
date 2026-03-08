/**
 * 词汇库数据清理脚本 v2（批量优化版）
 */
const mysql = require('mysql2/promise');

const POS_LABELS = ['名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語'];
const POS_MAP = {
  '名': 'noun', '動Ⅰ': 'verb', '動Ⅱ': 'verb', '動Ⅲ': 'verb',
  '副': 'adverb', 'イ形': 'adjective', 'ナ形': 'adjective',
  '連語': 'other', '感': 'interjection', '助数': 'other',
  '接': 'conjunction', '助': 'particle', '接辞': 'other',
  '接尾': 'other', '連体': 'other', '造語': 'other'
};

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  console.log('========================================');
  console.log('  词汇库数据清理开始');
  console.log('========================================\n');

  const posIn = POS_LABELS.map(p => conn.escape(p)).join(',');

  // ====== Phase 1: 修复垃圾数据（word=词性标签） ======
  console.log('--- Phase 1: 修复垃圾数据 ---');

  // 1a. 有example_sentence的：把example_sentence当word
  const [fixCount1] = await conn.query(`
    UPDATE vocabulary 
    SET 
      part_of_speech = CASE word
        ${POS_LABELS.map(p => `WHEN ${conn.escape(p)} THEN ${conn.escape(POS_MAP[p])}`).join('\n        ')}
        ELSE 'other'
      END,
      reading = CASE 
        WHEN reading IN (${posIn}) AND example_sentence IS NOT NULL THEN example_sentence
        ELSE reading
      END,
      word = example_sentence
    WHERE word IN (${posIn})
    AND example_sentence IS NOT NULL
    AND example_sentence != ''
  `);
  console.log('  Phase1a 已修复(有example):', fixCount1.affectedRows, '条');

  // 1b. 没有example_sentence的垃圾记录 → 删除
  const [delCount1] = await conn.query(`
    DELETE FROM vocabulary 
    WHERE word IN (${posIn})
    AND (example_sentence IS NULL OR example_sentence = '')
  `);
  console.log('  Phase1b 已删除(无example):', delCount1.affectedRows, '条');

  // ====== Phase 2: 修复中日文颠倒 ======
  console.log('\n--- Phase 2: 修复中日文颠倒 ---');

  // 2a. word是纯中文(长度>1, 无假名) + reading有假名 → 交换word和meaning_zh
  const [fixCount2a] = await conn.query(`
    UPDATE vocabulary 
    SET 
      meaning_zh = word,
      word = reading
    WHERE word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND word REGEXP '[\u4e00-\u9fff]'
    AND CHAR_LENGTH(word) > 1
    AND reading REGEXP '[ぁ-んァ-ヶー]'
    AND word NOT IN (${posIn})
  `);
  console.log('  Phase2a 交换修复(word中文→reading日文):', fixCount2a.affectedRows, '条');

  // 2b. word和meaning_zh完全相同(都含中文) + reading有假名 → word用reading
  const [fixCount2b] = await conn.query(`
    UPDATE vocabulary 
    SET word = reading
    WHERE word = meaning_zh
    AND word REGEXP '[\u4e00-\u9fff]'
    AND reading REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('  Phase2b 修复(word=meaning_zh→reading):', fixCount2b.affectedRows, '条');

  // 2c. meaning_zh 以"日文读音[词性]"开头的 → 去除开头部分
  const [fixCount2c] = await conn.query(`
    UPDATE vocabulary
    SET meaning_zh = TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶーa-zA-Z\u4e00-\u9fff]*\\\\[[^\\\\]]*\\\\]', ''))
    WHERE meaning_zh REGEXP '^[ぁ-んァ-ヶー]+.*\\\\['
    AND word REGEXP '[ぁ-んァ-ヶー]'
    AND TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶーa-zA-Z\u4e00-\u9fff]*\\\\[[^\\\\]]*\\\\]', '')) != ''
  `);
  console.log('  Phase2c meaning_zh清理(去日文前缀):', fixCount2c.affectedRows, '条');

  // ====== Phase 3: 去重 ======
  console.log('\n--- Phase 3: 去重处理 ---');

  // 保留每组中数据最完整的一条(id最小的作为保底)
  // 先标记要保留的id
  const [keepIds] = await conn.query(`
    SELECT MIN(id) as keep_id, word, reading, jlpt_level
    FROM vocabulary
    GROUP BY word, reading, jlpt_level
    HAVING COUNT(*) > 1
  `);
  console.log('  重复组数:', keepIds.length);

  if (keepIds.length > 0) {
    // 使用临时表高效去重
    await conn.query(`CREATE TEMPORARY TABLE keep_ids (id CHAR(36) PRIMARY KEY)`);
    
    // 批量插入要保留的 id
    const batchSize = 500;
    for (let i = 0; i < keepIds.length; i += batchSize) {
      const batch = keepIds.slice(i, i + batchSize);
      const values = batch.map(r => `(${conn.escape(r.keep_id)})`).join(',');
      await conn.query(`INSERT INTO keep_ids VALUES ${values}`);
    }

    // 删除重复记录（保留每组的最早一条）
    const [delCount3] = await conn.query(`
      DELETE v FROM vocabulary v
      INNER JOIN (
        SELECT word, reading, jlpt_level
        FROM vocabulary
        GROUP BY word, reading, jlpt_level
        HAVING COUNT(*) > 1
      ) dups ON v.word = dups.word AND v.reading = dups.reading AND v.jlpt_level = dups.jlpt_level
      LEFT JOIN keep_ids k ON v.id = k.id
      WHERE k.id IS NULL
    `);
    console.log('  去重删除:', delCount3.affectedRows, '条');

    await conn.query('DROP TEMPORARY TABLE keep_ids');
  }

  // ====== Phase 4: 清理reading字段 ======
  console.log('\n--- Phase 4: 清理reading字段 ---');

  // reading是纯中文(无假名) + word有假名 → 把word复制到reading
  const [fixCount4] = await conn.query(`
    UPDATE vocabulary 
    SET reading = word
    WHERE reading REGEXP '[\u4e00-\u9fff]'
    AND reading NOT REGEXP '[ぁ-んァ-ヶー]'
    AND word REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('  reading修复(中文→复制word):', fixCount4.affectedRows, '条');

  // ====== 最终统计 ======
  const [finalCount] = await conn.query('SELECT COUNT(*) as cnt FROM vocabulary');
  const [finalLevels] = await conn.query('SELECT jlpt_level, COUNT(*) as cnt FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level');
  const [finalDups] = await conn.query(`
    SELECT COUNT(*) as cnt FROM (
      SELECT word, reading, jlpt_level FROM vocabulary GROUP BY word, reading, jlpt_level HAVING COUNT(*) > 1
    ) t
  `);
  const [meaningKana] = await conn.query(`
    SELECT COUNT(*) as cnt FROM vocabulary WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー]'
  `);

  console.log('\n========================================');
  console.log('  清理完成!');
  console.log('========================================');
  console.log('  最终词汇数:', finalCount[0].cnt);
  console.log('  按级别:');
  finalLevels.forEach(r => console.log('    ' + r.jlpt_level + ': ' + r.cnt));
  console.log('  剩余重复组:', finalDups[0].cnt);
  console.log('  meaning_zh仍含假名:', meaningKana[0].cnt);

  await conn.end();
  console.log('\n完成。');
})().catch(e => console.error('Error:', e));
