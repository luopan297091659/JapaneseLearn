/**
 * 词汇库去重 v4：按 word + jlpt_level 去重
 * 解决 reading 不同但 word 相同的重复（如 reading="せいき" vs reading="一 世[せい]紀[き]"）
 * 保留纯假名 reading 的那条（更规范），若都不是纯假名则保留数据最丰富的
 */
const mysql = require('mysql2/promise');
const fs = require('fs');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  const log = [];
  const p = (...a) => { const s = a.join(' '); console.log(s); log.push(s); };

  p('=== 按 word + jlpt_level 去重分析 ===\n');

  // 找出 word+level 重复但 reading 不同的组
  const [dups] = await conn.query(`
    SELECT word, jlpt_level, COUNT(*) as cnt, GROUP_CONCAT(reading SEPARATOR ' | ') as readings
    FROM vocabulary
    GROUP BY word, jlpt_level
    HAVING COUNT(*) > 1
    ORDER BY jlpt_level, word
  `);

  p(`发现 ${dups.length} 组 word+level 重复\n`);

  // 抽样展示前20组
  const sample = dups.slice(0, 20);
  for (const d of sample) {
    p(`[${d.jlpt_level}] word="${d.word}" x${d.cnt}  readings: ${d.readings}`);
  }
  if (dups.length > 20) p(`... 还有 ${dups.length - 20} 组\n`);

  // 逐组处理：保留最佳的一条
  let totalDel = 0;
  for (const d of dups) {
    const [rows] = await conn.query(
      `SELECT id, word, reading, meaning_zh, part_of_speech, example_sentence,
              CHAR_LENGTH(COALESCE(meaning_zh,'')) + CHAR_LENGTH(COALESCE(example_sentence,'')) as richness
       FROM vocabulary WHERE word = ? AND jlpt_level = ? ORDER BY id`,
      [d.word, d.jlpt_level]
    );

    // 优先保留：reading 是纯假名（不含汉字/方括号）的那条
    // 其次保留：数据最丰富的（meaning_zh + example_sentence 最长）
    let keepIdx = 0;
    let bestScore = -1;
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      const reading = r.reading || '';
      const isPureKana = /^[ぁ-んァ-ヶー・～〜a-zA-Z0-9\s]+$/.test(reading) && !/[\[\]（）]/.test(reading);
      // Score: pure kana reading gets big bonus, then richness
      const score = (isPureKana ? 100000 : 0) + (r.richness || 0);
      if (score > bestScore) {
        bestScore = score;
        keepIdx = i;
      }
    }

    const keepId = rows[keepIdx].id;
    const delIds = rows.filter((_, i) => i !== keepIdx).map(r => r.id);
    
    if (delIds.length > 0) {
      const ph = delIds.map(() => '?').join(',');
      const [result] = await conn.query(`DELETE FROM vocabulary WHERE id IN (${ph})`, delIds);
      totalDel += result.affectedRows;
    }
  }

  p(`\n去重删除: ${totalDel} 条`);

  // 最终统计
  const [cnt] = await conn.query('SELECT COUNT(*) as c FROM vocabulary');
  const [levels] = await conn.query('SELECT jlpt_level, COUNT(*) as c FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level');
  const [remDups] = await conn.query(`
    SELECT COUNT(*) as c FROM (
      SELECT word, jlpt_level FROM vocabulary GROUP BY word, jlpt_level HAVING COUNT(*) > 1
    ) t
  `);

  p('\n========================================');
  p('  最终结果');
  p('========================================');
  p('  词汇总数:', cnt[0].c);
  levels.forEach(r => p(`    ${r.jlpt_level}: ${r.c}`));
  p('  剩余重复组:', remDups[0].c);

  await conn.end();
  fs.writeFileSync('scripts/cleanup_v4_result.txt', log.join('\n'), 'utf8');
  p('\n完成。');
})().catch(e => console.error('Error:', e));
