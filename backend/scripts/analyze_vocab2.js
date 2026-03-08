const mysql = require('mysql2/promise');
const fs = require('fs');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  const lines = [];

  // 1. Look at garbage N3 records - what's in their meaning_zh?
  // These records have word=part_of_speech label, meaning_zh may contain the actual data
  const [garbageN3] = await conn.query(`
    SELECT id, word, reading, meaning_zh, part_of_speech, example_sentence, example_reading, example_meaning_zh, category
    FROM vocabulary 
    WHERE word IN ('名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語')
    AND jlpt_level = 'N3'
    LIMIT 30
  `);
  lines.push('=== N3 垃圾数据样例 (完整字段) ===');
  garbageN3.forEach(r => {
    lines.push(JSON.stringify({
      word: r.word, reading: r.reading, meaning_zh: r.meaning_zh,
      pos: r.part_of_speech, ex: r.example_sentence, 
      ex_reading: r.example_reading, ex_zh: r.example_meaning_zh, cat: r.category
    }));
  });

  // 2. Records where word contains Chinese text (no kana, pure Chinese/mixed)
  const [wordChinese] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary
    WHERE word REGEXP '[\u4e00-\u9fff]'
    AND word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND meaning_zh REGEXP '[ぁ-んァ-ヶー]'
    LIMIT 20
  `);
  lines.push('');
  lines.push('=== word是中文 + meaning_zh无假名 样例 ===');
  wordChinese.forEach(r => {
    lines.push('  word=' + r.word + ' | reading=' + r.reading + ' | meaning_zh=' + r.meaning_zh + ' | ' + r.jlpt_level);
  });

  // 3. Records where word is pure Chinese sentence
  const [wordChinese2] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary
    WHERE word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND CHAR_LENGTH(word) > 5
    AND word REGEXP '[\u4e00-\u9fff]'
    LIMIT 20
  `);
  lines.push('');
  lines.push('=== word是长中文文本(>5字符, 无假名) ===');
  wordChinese2.forEach(r => {
    lines.push('  word=' + r.word + ' | reading=' + r.reading + ' | meaning_zh=' + r.meaning_zh);
  });

  // 4. Check reading field patterns
  const [readingPatterns] = await conn.query(`
    SELECT 
      COUNT(*) as total,
      SUM(CASE WHEN reading REGEXP '[ぁ-ん]' THEN 1 ELSE 0 END) as has_hiragana,
      SUM(CASE WHEN reading REGEXP '[ァ-ヶ]' THEN 1 ELSE 0 END) as has_katakana,
      SUM(CASE WHEN reading REGEXP '[\u4e00-\u9fff]' AND reading NOT REGEXP '[ぁ-んァ-ヶー]' THEN 1 ELSE 0 END) as pure_chinese,
      SUM(CASE WHEN reading = word THEN 1 ELSE 0 END) as same_as_word,
      SUM(CASE WHEN reading IS NULL OR reading = '' THEN 1 ELSE 0 END) as empty_reading
    FROM vocabulary
  `);
  lines.push('');
  lines.push('=== reading字段模式 ===');
  lines.push(JSON.stringify(readingPatterns[0]));

  // 5. Sample of reading=Chinese only
  const [readingChinese] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary
    WHERE reading REGEXP '[\u4e00-\u9fff]'
    AND reading NOT REGEXP '[ぁ-んァ-ヶー]'
    LIMIT 20
  `);
  lines.push('');
  lines.push('=== reading是纯中文 样例 ===');
  readingChinese.forEach(r => {
    lines.push('  word=' + r.word + ' | reading=' + r.reading + ' | meaning_zh=' + r.meaning_zh + ' | ' + r.jlpt_level);
  });

  // 6. Check related tables for references
  try {
    const [srsRefs] = await conn.query(`SELECT COUNT(*) as cnt FROM srs_cards`);
    lines.push('');
    lines.push('=== 关联引用 ===');
    lines.push('srs_cards总数: ' + srsRefs[0].cnt);
  } catch(e) { lines.push('srs_cards: ' + e.message); }
  try {
    const [quizRefs] = await conn.query(`SELECT COUNT(*) as cnt FROM quiz_questions`);
    lines.push('quiz_questions总数: ' + quizRefs[0].cnt);
  } catch(e) { lines.push('quiz_questions: ' + e.message); }

  // 7. How many distinct word+meaning_zh combinations exist in garbage data
  const [garbageDistinct] = await conn.query(`
    SELECT COUNT(DISTINCT meaning_zh) as unique_meanings
    FROM vocabulary 
    WHERE word IN ('名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語')
    AND jlpt_level = 'N3'
  `);
  lines.push('');
  lines.push('垃圾数据中不同meaning_zh数: ' + garbageDistinct[0].unique_meanings);

  fs.writeFileSync('scripts/vocab_analysis2.txt', lines.join('\n'), 'utf8');
  console.log('Written to scripts/vocab_analysis2.txt');
  await conn.end();
})().catch(e => console.error(e));
