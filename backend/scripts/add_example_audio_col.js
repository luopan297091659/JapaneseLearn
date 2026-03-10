require('dotenv').config();
const mysql = require('mysql2/promise');
async function main() {
  const conn = await mysql.createConnection({host:'139.196.44.6',port:3306,user:'root',password:'6586156',database:'japanese_learn',charset:'utf8mb4'});
  
  // 添加 example_audio_url 列
  await conn.query("ALTER TABLE vocabulary ADD COLUMN example_audio_url VARCHAR(500) NULL AFTER example_meaning_zh");
  console.log('已添加 example_audio_url 列');
  
  await conn.end();
}
main().catch(e => { console.error(e); process.exit(1); });
