const mysql = require('mysql2/promise');

(async () => {
  const c = await mysql.createConnection({
    host: '139.196.44.6',
    user: 'root',
    password: '6586156',
    database: 'japanese_learn'
  });

  const [r1] = await c.query('SELECT COUNT(*) as cnt FROM vocabulary');
  console.log('Total vocab:', r1[0].cnt);

  const [r2] = await c.query('SELECT jlpt_level, COUNT(*) as cnt FROM vocabulary GROUP BY jlpt_level');
  console.log('By level:', JSON.stringify(r2));

  const [r3] = await c.query("SELECT COUNT(*) as cnt FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ''");
  console.log('With examples:', r3[0].cnt);

  const [r4] = await c.query("SELECT COUNT(*) as cnt FROM vocabulary WHERE audio_url IS NOT NULL AND audio_url != ''");
  console.log('With audio:', r4[0].cnt);

  const [r5] = await c.query('SELECT word, reading, meaning_zh, example_sentence, audio_url FROM vocabulary LIMIT 5');
  console.log('Sample:', JSON.stringify(r5, null, 2));

  // Check columns
  const [cols] = await c.query('DESCRIBE vocabulary');
  console.log('Columns:', cols.map(c => c.Field + ' ' + c.Type).join(', '));

  await c.end();
})();
