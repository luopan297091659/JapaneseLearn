/**
 * 词汇库去重 v4b：按 word + jlpt_level 去重（批量高效版）
 * 保留纯假名 reading 的那条（更规范）
 */
const mysql = require('mysql2/promise');
const fs = require('fs');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4',
    connectTimeout: 30000
  });

  const log = [];
  const p = (...a) => { const s = a.join(' '); console.log(s); log.push(s); };

  // 统计重复
  const [dups] = await conn.query(`
    SELECT COUNT(*) as c FROM (
      SELECT word, jlpt_level FROM vocabulary GROUP BY word, jlpt_level HAVING COUNT(*) > 1
    ) t
  `);
  p(`发现 ${dups[0].c} 组 word+level 重复`);

  // 策略：用一条SQL找到每组要保留的id
  // 优先级：reading不含方括号且不含英文 > reading不含方括号 > 数据最丰富
  // 用临时表实现

  p('\n开始去重...');

  // 第一步：建立要保留的id临时表
  await conn.query(`DROP TEMPORARY TABLE IF EXISTS keep_vocab`);
  await conn.query(`
    CREATE TEMPORARY TABLE keep_vocab AS
    SELECT MIN(best_id) as keep_id
    FROM (
      SELECT 
        v.id as best_id,
        v.word,
        v.jlpt_level,
        ROW_NUMBER() OVER (
          PARTITION BY v.word, v.jlpt_level 
          ORDER BY 
            CASE 
              WHEN v.reading NOT LIKE '%[%' AND v.reading NOT REGEXP '[a-zA-Z]' THEN 0
              WHEN v.reading NOT LIKE '%[%' THEN 1
              ELSE 2
            END,
            CHAR_LENGTH(COALESCE(v.meaning_zh,'')) + CHAR_LENGTH(COALESCE(v.example_sentence,'')) DESC,
            v.id
        ) as rn
      FROM vocabulary v
      INNER JOIN (
        SELECT word, jlpt_level
        FROM vocabulary
        GROUP BY word, jlpt_level
        HAVING COUNT(*) > 1
      ) d ON v.word = d.word AND v.jlpt_level = d.jlpt_level
    ) ranked
    WHERE rn = 1
    GROUP BY word, jlpt_level
  `);

  // 验证
  const [keepCount] = await conn.query('SELECT COUNT(*) as c FROM keep_vocab');
  p(`保留 ${keepCount[0].c} 条（每组最佳）`);

  // 第二步：删除重复中不保留的
  const [delResult] = await conn.query(`
    DELETE v FROM vocabulary v
    INNER JOIN (
      SELECT word, jlpt_level
      FROM vocabulary
      GROUP BY word, jlpt_level
      HAVING COUNT(*) > 1
    ) d ON v.word = d.word AND v.jlpt_level = d.jlpt_level
    LEFT JOIN keep_vocab k ON v.id = k.keep_id
    WHERE k.keep_id IS NULL
  `);
  p(`去重删除: ${delResult.affectedRows} 条`);

  await conn.query('DROP TEMPORARY TABLE keep_vocab');

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
})().catch(e => { console.error('Error:', e.message); process.exit(1); });
