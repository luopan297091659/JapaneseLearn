/**
 * 分析词汇和语法的例句覆盖情况
 */
const mysql = require('mysql2/promise');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  console.log('=== 词汇例句覆盖分析 ===\n');

  // 词汇总数和有例句的数量
  const [vocabTotal] = await conn.query('SELECT COUNT(*) as c FROM vocabulary');
  const [vocabWithEx] = await conn.query("SELECT COUNT(*) as c FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ''");
  const [vocabByLevel] = await conn.query(`
    SELECT jlpt_level, 
           COUNT(*) as total,
           SUM(CASE WHEN example_sentence IS NOT NULL AND example_sentence != '' THEN 1 ELSE 0 END) as with_ex
    FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level
  `);

  console.log(`词汇总数: ${vocabTotal[0].c}`);
  console.log(`有例句: ${vocabWithEx[0].c} (${(vocabWithEx[0].c/vocabTotal[0].c*100).toFixed(1)}%)`);
  console.log(`无例句: ${vocabTotal[0].c - vocabWithEx[0].c}`);
  console.log('\n按级别:');
  vocabByLevel.forEach(r => {
    console.log(`  ${r.jlpt_level}: ${r.with_ex}/${r.total} (${(r.with_ex/r.total*100).toFixed(1)}%)`);
  });

  // 看几个有例句的样本
  const [samples] = await conn.query("SELECT word, reading, meaning_zh, example_sentence FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != '' LIMIT 5");
  console.log('\n例句样本:');
  samples.forEach(s => console.log(`  ${s.word} → ${s.example_sentence}`));

  // 语法分析
  console.log('\n\n=== 语法例句覆盖分析 ===\n');
  const [gramTotal] = await conn.query('SELECT COUNT(*) as c FROM grammar_points');
  const [gramWithEx] = await conn.query("SELECT COUNT(*) as c FROM grammar_points WHERE example_sentence IS NOT NULL AND example_sentence != ''");
  const [gramCols] = await conn.query("SHOW COLUMNS FROM grammar_points");
  
  console.log('grammar_points 表结构:');
  gramCols.forEach(c => console.log(`  ${c.Field}: ${c.Type} ${c.Null === 'YES' ? 'NULL' : 'NOT NULL'}`));
  
  console.log(`\n语法总数: ${gramTotal[0].c}`);
  console.log(`有例句: ${gramWithEx[0].c}`);

  const [gramByLevel] = await conn.query(`
    SELECT jlpt_level,
           COUNT(*) as total,
           SUM(CASE WHEN example_sentence IS NOT NULL AND example_sentence != '' THEN 1 ELSE 0 END) as with_ex
    FROM grammar_points GROUP BY jlpt_level ORDER BY jlpt_level
  `);
  console.log('\n按级别:');
  gramByLevel.forEach(r => {
    console.log(`  ${r.jlpt_level}: ${r.with_ex}/${r.total} (${(r.with_ex/r.total*100).toFixed(1)}%)`);
  });

  // 语法样本
  const [gramSamples] = await conn.query("SELECT pattern, meaning_zh, example_sentence FROM grammar_points LIMIT 5");
  console.log('\n语法样本:');
  gramSamples.forEach(s => console.log(`  ${s.pattern} → ex: ${s.example_sentence || '(无)'}`));

  // 检查AI配置
  console.log('\n\n=== AI 配置 ===');
  try {
    const fs = require('fs');
    const aiConfig = JSON.parse(fs.readFileSync('config/ai_settings.json', 'utf8'));
    console.log(JSON.stringify(aiConfig, null, 2));
  } catch(e) {
    console.log('无法读取AI配置:', e.message);
  }

  await conn.end();
})().catch(e => console.error('Error:', e));
