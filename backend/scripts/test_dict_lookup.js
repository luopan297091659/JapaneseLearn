const { sequelize } = require('../src/config/database');

(async () => {
  try {
    // Test 1: Check if 学校 exists
    const [rows1] = await sequelize.query(
      `SELECT id, word, reading, meaning_zh, meaning_en, part_of_speech 
       FROM vocabularies 
       WHERE word = '学校' OR reading = 'がっこう' 
       LIMIT 10`
    );
    console.log('=== DB lookup for 学校 / がっこう ===');
    console.log(JSON.stringify(rows1, null, 2));

    // Test 2: Check total rows with meaning_zh
    const [cnt] = await sequelize.query(
      `SELECT COUNT(*) as total, 
              SUM(CASE WHEN meaning_zh IS NOT NULL AND meaning_zh != '' THEN 1 ELSE 0 END) as has_zh
       FROM vocabularies`
    );
    console.log('\n=== Stats ===');
    console.log(JSON.stringify(cnt[0]));

    // Test 3: Sample some words that DO have meaning_zh
    const [samples] = await sequelize.query(
      `SELECT word, reading, LEFT(meaning_zh, 40) as meaning_zh 
       FROM vocabularies 
       WHERE meaning_zh IS NOT NULL AND meaning_zh != '' 
       LIMIT 5`
    );
    console.log('\n=== Samples with meaning_zh ===');
    samples.forEach(r => console.log(`  ${r.word} (${r.reading}): ${r.meaning_zh}`));

    process.exit(0);
  } catch (e) {
    console.error('Error:', e.message);
    process.exit(1);
  }
})();
