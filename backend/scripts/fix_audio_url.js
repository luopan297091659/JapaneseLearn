require('dotenv').config();
const mysql = require('mysql2/promise');
async function main() {
  const conn = await mysql.createConnection({host:'139.196.44.6',port:3306,user:'root',password:'6586156',database:'japanese_learn',charset:'utf8mb4'});
  const [r] = await conn.query("UPDATE vocabulary SET audio_url = CONCAT('/uploads', audio_url) WHERE audio_url LIKE '/audio/%'");
  console.log('Updated rows:', r.affectedRows);
  const [s] = await conn.query('SELECT audio_url FROM vocabulary LIMIT 5');
  for(const x of s) console.log(x.audio_url);
  await conn.end();
}
main();
