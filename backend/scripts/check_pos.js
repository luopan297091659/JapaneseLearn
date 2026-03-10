require('dotenv').config();
const mysql = require('mysql2/promise');
async function main() {
  const conn = await mysql.createConnection({host:'139.196.44.6',port:3306,user:'root',password:'6586156',database:'japanese_learn',charset:'utf8mb4'});
  
  const [rows] = await conn.query('SELECT part_of_speech, COUNT(*) as cnt FROM vocabulary GROUP BY part_of_speech ORDER BY cnt DESC');
  console.log('词性分布:');
  for(const r of rows) console.log('  ' + r.part_of_speech + ': ' + r.cnt);
  
  const [samples] = await conn.query("SELECT word, reading, LEFT(meaning_zh,40) as mz FROM vocabulary WHERE part_of_speech = 'other' LIMIT 30");
  console.log('\n--- other 类词汇抽样 ---');
  for(const s of samples) console.log(`  ${s.word} (${s.reading}) → ${s.mz}`);
  
  await conn.end();
}
main();
