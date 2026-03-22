const mysql = require('mysql2/promise');
async function main() {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn'
  });
  const [lessons] = await conn.query(`
    SELECT gl.title, gl.pattern, gl.jlpt_level, 
           ge.sentence, ge.meaning_zh
    FROM grammar_lessons gl
    JOIN grammar_examples ge ON ge.grammar_lesson_id = gl.id
    WHERE gl.jlpt_level IN ('N5','N4','N3')
    ORDER BY gl.jlpt_level, gl.order_index
    LIMIT 25
  `);
  lessons.forEach(r => {
    console.log('---');
    console.log('Lv:', r.jlpt_level, '| Title:', r.title, '| Pattern:', r.pattern);
    console.log('Sentence:', r.sentence);
    console.log('Meaning:', r.meaning_zh);
  });
  const [stats] = await conn.query(`
    SELECT gl.jlpt_level, COUNT(DISTINCT gl.id) as lessons, COUNT(ge.id) as examples
    FROM grammar_lessons gl LEFT JOIN grammar_examples ge ON ge.grammar_lesson_id = gl.id
    GROUP BY gl.jlpt_level ORDER BY gl.jlpt_level
  `);
  console.log('\n=== Stats ===');
  stats.forEach(s => console.log(s.jlpt_level, '- Lessons:', s.lessons, '- Examples:', s.examples));
  await conn.end();
}
main().catch(e => console.error(e));
