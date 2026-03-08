/**
 * 词汇库残余问题清理 v3
 * 处理：19组剩余重复 + 66条meaning_zh含假名
 */
const mysql = require('mysql2/promise');
const fs = require('fs');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  const log = [];
  const p = (...args) => { const s = args.join(' '); console.log(s); log.push(s); };

  p('=== Phase A: 分析剩余19组重复 ===\n');

  const [dups] = await conn.query(`
    SELECT word, reading, jlpt_level, COUNT(*) as cnt
    FROM vocabulary
    GROUP BY word, reading, jlpt_level
    HAVING COUNT(*) > 1
    ORDER BY cnt DESC
    LIMIT 30
  `);
  
  for (const d of dups) {
    const [rows] = await conn.query(
      `SELECT id, word, reading, meaning_zh, part_of_speech, example_sentence 
       FROM vocabulary WHERE word=? AND reading=? AND jlpt_level=? ORDER BY id`,
      [d.word, d.reading, d.jlpt_level]
    );
    p(`\n[DUP x${d.cnt}] word="${d.word}" reading="${d.reading}" level=${d.jlpt_level}`);
    rows.forEach((r, i) => {
      p(`  ${i}: id=${r.id} meaning="${r.meaning_zh}" pos=${r.part_of_speech} ex=${(r.example_sentence||'').substring(0,30)}`);
    });
  }

  p('\n\n=== Phase B: 分析66条meaning_zh含假名 ===\n');

  const [kanaRows] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary 
    WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー]'
    ORDER BY jlpt_level, id
    LIMIT 80
  `);
  
  for (const r of kanaRows) {
    p(`[KANA] id=${r.id} word="${r.word}" reading="${r.reading}" meaning="${r.meaning_zh}" level=${r.jlpt_level}`);
  }

  p('\n\n=== Phase C: 修复剩余重复（保留meaning_zh最长的） ===\n');

  // 对每组重复，保留 meaning_zh 最长（数据最丰富）的一条
  let delCount = 0;
  for (const d of dups) {
    const [rows] = await conn.query(
      `SELECT id, CHAR_LENGTH(COALESCE(meaning_zh,'')) + CHAR_LENGTH(COALESCE(example_sentence,'')) as richness
       FROM vocabulary WHERE word=? AND reading=? AND jlpt_level=?
       ORDER BY richness DESC, id ASC`,
      [d.word, d.reading, d.jlpt_level]
    );
    // 保留第一条（最丰富），删除其余
    const keepId = rows[0].id;
    const delIds = rows.slice(1).map(r => r.id);
    if (delIds.length > 0) {
      const placeholders = delIds.map(() => '?').join(',');
      const [result] = await conn.query(`DELETE FROM vocabulary WHERE id IN (${placeholders})`, delIds);
      delCount += result.affectedRows;
    }
  }
  p(`去重删除: ${delCount} 条`);

  p('\n=== Phase D: 修复meaning_zh含假名 ===\n');

  // 分析模式并修复
  // 情况1: meaning_zh 是纯假名/日文 → word和meaning_zh可能颠倒
  const [fix1] = await conn.query(`
    UPDATE vocabulary
    SET meaning_zh = word, word = meaning_zh
    WHERE meaning_zh REGEXP '^[ぁ-んァ-ヶー・a-zA-Z0-9]+$'
    AND word REGEXP '[\u4e00-\u9fff]'
    AND word NOT REGEXP '[ぁ-んァ-ヶー]'
  `);
  p(`修复(meaning纯假名,word中文→交换): ${fix1.affectedRows} 条`);

  // 情况2: meaning_zh 开头是假名+中文混合 → 去掉假名前缀
  // 例如 "きれいな 漂亮的" → "漂亮的"
  const [fix2] = await conn.query(`
    UPDATE vocabulary
    SET meaning_zh = TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶー・]+[\\\\s　]*', ''))
    WHERE meaning_zh REGEXP '^[ぁ-んァ-ヶー]'
    AND meaning_zh REGEXP '[\u4e00-\u9fff]'
    AND TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶー・]+[\\\\s　]*', '')) != ''
  `);
  p(`修复(去假名前缀): ${fix2.affectedRows} 条`);

  // 情况3: meaning_zh 中间含假名注释（如 "打招呼（あいさつする）"）→ 保留
  // 这种其实是正常的，不需要修复

  // 情况4: meaning_zh 是 "假名[词性]中文" 格式 → 提取中文部分
  const [fix4] = await conn.query(`
    UPDATE vocabulary
    SET meaning_zh = TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶーa-zA-Z]*\\\\[[^\\\\]]*\\\\][\\\\s　]*', ''))
    WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー].*\\\\['
    AND TRIM(REGEXP_REPLACE(meaning_zh, '^[ぁ-んァ-ヶーa-zA-Z]*\\\\[[^\\\\]]*\\\\][\\\\s　]*', '')) != ''
  `);
  p(`修复(去假名[词性]前缀): ${fix4.affectedRows} 条`);

  // 最终统计
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

  p('\n========================================');
  p('  最终结果');
  p('========================================');
  p('  词汇总数:', finalCount[0].cnt);
  p('  按级别:');
  finalLevels.forEach(r => p('    ' + r.jlpt_level + ': ' + r.cnt));
  p('  剩余重复组:', finalDups[0].cnt);
  p('  meaning_zh仍含假名:', meaningKana[0].cnt);

  await conn.end();

  // 写入结果文件
  fs.writeFileSync('scripts/cleanup_v3_result.txt', log.join('\n'), 'utf8');
  p('\n结果已写入 scripts/cleanup_v3_result.txt');
})().catch(e => console.error('Error:', e));
