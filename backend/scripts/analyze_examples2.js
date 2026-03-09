const mysql = require('mysql2/promise');
(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });
  // 列出所有表
  const [tables] = await conn.query("SHOW TABLES");
  console.log('=== 所有表 ===');
  tables.forEach(t => console.log('  ' + Object.values(t)[0]));

  // 找语法相关的表
  const grammarTables = tables.filter(t => Object.values(t)[0].toLowerCase().includes('grammar'));
  console.log('\n语法相关表:', grammarTables.map(t => Object.values(t)[0]));

  // 看所有表的行数
  for (const t of tables) {
    const name = Object.values(t)[0];
    const [cnt] = await conn.query(`SELECT COUNT(*) as c FROM \`${name}\``);
    if (cnt[0].c > 0) console.log(`  ${name}: ${cnt[0].c} rows`);
  }

  // 查看vocab example_sentence 真实内容
  console.log('\n=== N3 有 example_sentence 的样本(前10) ===');
  const [n3ex] = await conn.query("SELECT word, reading, meaning_zh, example_sentence FROM vocabulary WHERE jlpt_level='N3' AND example_sentence IS NOT NULL AND example_sentence != '' LIMIT 10");
  n3ex.forEach(r => console.log(`  word="${r.word}" reading="${r.reading}" meaning="${r.meaning_zh}" ex="${r.example_sentence}"`));

  // 查看N5样本
  console.log('\n=== N5 词汇样本(前10) ===');
  const [n5] = await conn.query("SELECT word, reading, meaning_zh, part_of_speech, example_sentence FROM vocabulary WHERE jlpt_level='N5' LIMIT 10");
  n5.forEach(r => console.log(`  word="${r.word}" reading="${r.reading}" meaning="${r.meaning_zh}" pos=${r.part_of_speech} ex="${r.example_sentence || ''}"`));

  await conn.end();
})().catch(e => console.error('Error:', e));
