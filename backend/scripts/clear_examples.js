const mysql = require('mysql2/promise');

async function main() {
  const conn = await mysql.createConnection({
    host: '139.196.44.6',
    port: 3306,
    user: 'root',
    password: '6586156',
    database: 'japanese_learn'
  });

  // 先看看当前有多少条有例句的
  const [before] = await conn.query(
    `SELECT COUNT(*) as total FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ''`
  );
  console.log(`当前有例句的记录: ${before[0].total}`);

  // 清除所有例句（包括之前质量差的和模板生成的）
  const [result] = await conn.query(
    `UPDATE vocabulary SET example_sentence = NULL, example_reading = NULL, example_meaning_zh = NULL WHERE example_sentence IS NOT NULL AND example_sentence != ''`
  );
  console.log(`已清除 ${result.affectedRows} 条例句`);

  // 同时清除 grammar_examples 表中可能插入的数据
  const [geBefore] = await conn.query(`SELECT COUNT(*) as total FROM grammar_examples`);
  console.log(`grammar_examples 表记录数: ${geBefore[0].total}`);

  if (geBefore[0].total > 0) {
    const [geResult] = await conn.query(`DELETE FROM grammar_examples`);
    console.log(`已删除 ${geResult.affectedRows} 条文法例句`);
  }

  // 验证
  const [after] = await conn.query(
    `SELECT COUNT(*) as total FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ''`
  );
  console.log(`清除后有例句的记录: ${after[0].total}`);

  await conn.end();
  console.log('完成!');
}

main().catch(e => { console.error(e); process.exit(1); });
