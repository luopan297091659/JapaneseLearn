require('dotenv').config();
const mysql = require('mysql2/promise');
async function main() {
  const conn = await mysql.createConnection({host:'139.196.44.6',port:3306,user:'root',password:'6586156',database:'japanese_learn',charset:'utf8mb4'});
  const [r] = await conn.query("SELECT word, example_sentence, example_reading, example_meaning_zh FROM vocabulary WHERE word LIKE '%向け%' LIMIT 5");
  for (const x of r) {
    console.log('word:', x.word);
    console.log('ex_sentence:', x.example_sentence);
    console.log('ex_reading:', x.example_reading);
    console.log('ex_meaning:', x.example_meaning_zh);
    console.log('---');
  }
  // 统计
  const [[{total}]] = await conn.query('SELECT COUNT(*) as total FROM vocabulary');
  const [[{has_reading}]] = await conn.query("SELECT COUNT(*) as has_reading FROM vocabulary WHERE example_reading IS NOT NULL AND example_reading != ''");
  const [[{empty_reading}]] = await conn.query("SELECT COUNT(*) as empty_reading FROM vocabulary WHERE example_reading IS NULL OR example_reading = ''");
  console.log(`总词汇: ${total}, 有例句读音: ${has_reading}, 无例句读音: ${empty_reading}`);
  await conn.end();
}
main();
