/**
 * 扩展 user_progress.activity_type ENUM，增加所有功能类型
 */
const mysql = require('mysql2/promise');

async function main() {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306,
    user: 'root', password: '6586156',
    database: 'japanese_learn'
  });

  console.log('扩展 activity_type ENUM...');
  await conn.query(`
    ALTER TABLE user_progress
    MODIFY COLUMN activity_type ENUM(
      'vocabulary','grammar','listening','quiz','news','srs_review',
      'flashcard','game','game_verbs','pronunciation','gojuon',
      'dictionary','translate','todofuken'
    ) NOT NULL
  `);
  console.log('✅ activity_type ENUM 已扩展');

  // 验证
  const [cols] = await conn.query(`SHOW COLUMNS FROM user_progress LIKE 'activity_type'`);
  console.log('当前ENUM值:', cols[0].Type);

  await conn.end();
}

main().catch(e => { console.error('❌', e.message); process.exit(1); });
