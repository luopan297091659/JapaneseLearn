const mysql = require('mysql2/promise');
(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });
  const [cols] = await conn.query("SHOW COLUMNS FROM vocabulary");
  cols.forEach(c => console.log(c.Field + ': ' + c.Type));
  await conn.end();
})().catch(e => console.error(e));
