const mysql = require('mysql2/promise');

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  // 1. 总数 & 级别统计
  const [total] = await conn.query('SELECT COUNT(*) as cnt FROM vocabulary');
  console.log('=== 总词汇数:', total[0].cnt, '===\n');

  const [levels] = await conn.query('SELECT jlpt_level, COUNT(*) as cnt FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level');
  console.log('按级别:');
  levels.forEach(r => console.log('  ' + r.jlpt_level + ': ' + r.cnt));

  // 2. 重复统计
  const [dupTotal] = await conn.query(`
    SELECT COUNT(*) as groups_cnt FROM (
      SELECT word, reading, jlpt_level FROM vocabulary GROUP BY word, reading, jlpt_level HAVING COUNT(*) > 1
    ) t
  `);
  const [dupRows] = await conn.query(`
    SELECT COALESCE(SUM(cnt-1),0) as removable FROM (
      SELECT COUNT(*) as cnt FROM vocabulary GROUP BY word, reading, jlpt_level HAVING cnt > 1
    ) t
  `);
  console.log('\n=== 重复分析 ===');
  console.log('重复组数:', dupTotal[0].groups_cnt);
  console.log('可删除行数:', dupRows[0].removable);

  const [dups] = await conn.query(`
    SELECT word, reading, jlpt_level, COUNT(*) as cnt 
    FROM vocabulary GROUP BY word, reading, jlpt_level HAVING cnt > 1 ORDER BY cnt DESC LIMIT 15
  `);
  console.log('\n重复样例 (前15):');
  dups.forEach(r => console.log('  [' + r.cnt + 'x] ' + r.word + ' | ' + r.reading + ' | ' + r.jlpt_level));

  // 3. 中日文颠倒检测
  // meaning_zh 含假名（平假名或片假名）
  const [swapCnt] = await conn.query(`
    SELECT COUNT(*) as cnt FROM vocabulary 
    WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('\n=== 中日文颠倒检测 ===');
  console.log('meaning_zh含假名记录数:', swapCnt[0].cnt);

  const [swapSamples] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary 
    WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー]'
    LIMIT 30
  `);
  console.log('\n样例 (前30):');
  swapSamples.forEach(r => console.log('  word=' + r.word + ' | reading=' + r.reading + ' | meaning_zh=' + r.meaning_zh + ' | ' + r.jlpt_level));

  // 4. word字段包含中文词汇特征（无假名但meaning_zh有假名 = 很可能颠倒了）
  const [swapStrong] = await conn.query(`
    SELECT COUNT(*) as cnt FROM vocabulary 
    WHERE word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND meaning_zh REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('\n强疑似颠倒(word无假名+meaning_zh有假名):', swapStrong[0].cnt);

  const [swapStrongSamples] = await conn.query(`
    SELECT id, word, reading, meaning_zh, jlpt_level
    FROM vocabulary 
    WHERE word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND meaning_zh REGEXP '[ぁ-んァ-ヶー]'
    LIMIT 20
  `);
  if (swapStrongSamples.length > 0) {
    console.log('样例:');
    swapStrongSamples.forEach(r => console.log('  word=' + r.word + ' | meaning_zh=' + r.meaning_zh));
  }

  // 5. reading字段含中文字符
  const [readingZh] = await conn.query(`
    SELECT COUNT(*) as cnt FROM vocabulary
    WHERE reading REGEXP '[\u4e00-\u9fff]'
    AND reading NOT REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('\nreading含纯中文(无假名):', readingZh[0].cnt);

  // Write results to file to avoid encoding issues in terminal
  const fs = require('fs');
  const lines = [];
  lines.push('=== 总词汇数: ' + total[0].cnt + ' ===');
  lines.push('');
  lines.push('按级别:');
  levels.forEach(r => lines.push('  ' + r.jlpt_level + ': ' + r.cnt));
  lines.push('');
  lines.push('=== 重复分析 ===');
  lines.push('重复组数: ' + dupTotal[0].groups_cnt);
  lines.push('可删除行数: ' + dupRows[0].removable);
  lines.push('');
  lines.push('重复样例 (前15):');
  dups.forEach(r => lines.push('  [' + r.cnt + 'x] word=' + r.word + ' | reading=' + r.reading + ' | ' + r.jlpt_level));
  lines.push('');
  lines.push('=== 中日文颠倒检测 ===');
  lines.push('meaning_zh含假名记录数: ' + swapCnt[0].cnt);
  lines.push('');
  lines.push('样例 (前30):');
  swapSamples.forEach(r => lines.push('  word=' + r.word + ' | reading=' + r.reading + ' | meaning_zh=' + r.meaning_zh));
  lines.push('');
  lines.push('强疑似颠倒(word无假名+meaning_zh有假名): ' + swapStrong[0].cnt);
  if (swapStrongSamples.length > 0) {
    lines.push('样例:');
    swapStrongSamples.forEach(r => lines.push('  word=' + r.word + ' | meaning_zh=' + r.meaning_zh));
  }
  lines.push('');
  lines.push('reading含纯中文(无假名): ' + readingZh[0].cnt);

  // Also check: word field = part_of_speech label (garbage data)
  const [garbageWords] = await conn.query(`
    SELECT word, COUNT(*) as cnt FROM vocabulary 
    WHERE word IN ('名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語')
    GROUP BY word ORDER BY cnt DESC
  `);
  lines.push('');
  lines.push('=== 垃圾数据(word=词性标签) ===');
  let garbageTotal = 0;
  garbageWords.forEach(r => { lines.push('  ' + r.word + ': ' + r.cnt); garbageTotal += r.cnt; });
  lines.push('合计: ' + garbageTotal);

  // Sample some real duplicate entries (not garbage)
  const [realDups] = await conn.query(`
    SELECT word, reading, jlpt_level, COUNT(*) as cnt 
    FROM vocabulary 
    WHERE word NOT IN ('名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語')
    AND LENGTH(word) > 1
    GROUP BY word, reading, jlpt_level 
    HAVING cnt > 1 
    ORDER BY cnt DESC LIMIT 20
  `);
  lines.push('');
  lines.push('=== 真实重复(排除词性标签, 前20) ===');
  realDups.forEach(r => lines.push('  [' + r.cnt + 'x] ' + r.word + ' | ' + r.reading + ' | ' + r.jlpt_level));

  fs.writeFileSync('scripts/vocab_analysis.txt', lines.join('\n'), 'utf8');
  console.log('Analysis written to scripts/vocab_analysis.txt');

  await conn.end();
})().catch(e => console.error(e));
