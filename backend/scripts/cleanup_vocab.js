/**
 * 词汇库数据清理脚本
 * 
 * 问题分析：
 * 1. 垃圾数据(3975条): word=词性标签(名/動Ⅰ等)，但含有可恢复的meaning_zh和example_sentence
 * 2. 中日文颠倒: word字段存中文，reading存日文
 * 3. 真实重复: 同一word+reading+level存在多条
 * 4. reading字段含纯中文(3844条)
 */

const mysql = require('mysql2/promise');

const POS_LABELS = ['名','動Ⅰ','動Ⅱ','動Ⅲ','副','イ形','ナ形','連語','感','助数','接','助','接辞','接尾','連体','造語'];

// 词性标签 → part_of_speech 枚举映射
const POS_MAP = {
  '名': 'noun', '動Ⅰ': 'verb', '動Ⅱ': 'verb', '動Ⅲ': 'verb',
  '副': 'adverb', 'イ形': 'adjective', 'ナ形': 'adjective',
  '連語': 'other', '感': 'interjection', '助数': 'other',
  '接': 'conjunction', '助': 'particle', '接辞': 'other',
  '接尾': 'other', '連体': 'other', '造語': 'other'
};

// 判断字符串是否含日文假名
function hasKana(s) {
  if (!s) return false;
  return /[ぁ-んァ-ヶー]/.test(s);
}

// 判断字符串是否含汉字
function hasCJK(s) {
  if (!s) return false;
  return /[\u4e00-\u9fff]/.test(s);
}

// 判断字符串看起来像中文(有汉字且无假名)
function looksChinese(s) {
  if (!s) return false;
  return hasCJK(s) && !hasKana(s);
}

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4'
  });

  let fixedCount = 0;
  let deletedCount = 0;
  let dedupCount = 0;

  console.log('========================================');
  console.log('  词汇库数据清理开始');
  console.log('========================================\n');

  // ====== Phase 1: 修复垃圾数据（word=词性标签） ======
  console.log('--- Phase 1: 修复垃圾数据 (word=词性标签) ---');

  const posIn = POS_LABELS.map(p => conn.escape(p)).join(',');

  // 1a. 有example_sentence的可以恢复：把example_sentence当word, 修正part_of_speech
  const [recoverableWithEx] = await conn.query(`
    SELECT id, word, reading, meaning_zh, example_sentence, part_of_speech
    FROM vocabulary 
    WHERE word IN (${posIn})
    AND example_sentence IS NOT NULL
    AND example_sentence != ''
  `);
  console.log('  可恢复(有example_sentence):', recoverableWithEx.length, '条');

  for (const r of recoverableWithEx) {
    const newWord = r.example_sentence;
    const newPos = POS_MAP[r.word] || 'other';
    // 如果 reading 也是词性标签，用 example_sentence 的假名部分尝试提取
    let newReading = r.reading;
    if (POS_LABELS.includes(r.reading)) {
      // 尝试从 example_sentence 提取括号内的读音，如 面[おも]白[しろ]い → おもしろい
      const kanaMatch = newWord.match(/\[([^\]]+)\]/g);
      if (kanaMatch) {
        newReading = newWord.replace(/[^\[]*\[([^\]]+)\][^\[ぁ-んァ-ヶー]*/g, '$1')
          .replace(/\[|\]/g, '');
      } else {
        newReading = newWord; // fallback
      }
    }
    
    await conn.query(
      'UPDATE vocabulary SET word = ?, reading = ?, part_of_speech = ? WHERE id = ?',
      [newWord, newReading, newPos, r.id]
    );
    fixedCount++;
  }
  console.log('  已修复:', fixedCount, '条');

  // 1b. 没有example_sentence的垃圾记录 - 只有meaning_zh有用
  // 这种数据不可恢复(缺少日文单词)，但如果meaning_zh是中文且有内容，保留但标记
  // 否则直接删除
  const [unrecoverable] = await conn.query(`
    SELECT id, word, reading, meaning_zh
    FROM vocabulary 
    WHERE word IN (${posIn})
    AND (example_sentence IS NULL OR example_sentence = '')
  `);
  console.log('  不可恢复(无example_sentence):', unrecoverable.length, '条');

  // 删除这些垃圾记录
  if (unrecoverable.length > 0) {
    const ids = unrecoverable.map(r => conn.escape(r.id)).join(',');
    await conn.query(`DELETE FROM vocabulary WHERE id IN (${ids})`);
    deletedCount += unrecoverable.length;
    console.log('  已删除:', unrecoverable.length, '条垃圾数据');
  }

  // ====== Phase 2: 修复中日文颠倒 ======
  console.log('\n--- Phase 2: 修复中日文颠倒 ---');

  // 2a. word是纯中文 + reading有假名 → 交换
  const [swapped] = await conn.query(`
    SELECT id, word, reading, meaning_zh
    FROM vocabulary 
    WHERE word NOT REGEXP '[ぁ-んァ-ヶー]'
    AND word REGEXP '[\u4e00-\u9fff]'
    AND CHAR_LENGTH(word) > 1
    AND reading REGEXP '[ぁ-んァ-ヶー]'
    AND word NOT IN (${posIn})
  `);
  console.log('  word中文+reading日文:', swapped.length, '条');

  let swapFixed = 0;
  for (const r of swapped) {
    // word是中文含义 → 移到meaning_zh
    // reading是日文读音 → 移到word
    // meaning_zh如果等于word(也是中文)就保留
    const newWord = r.reading;
    const newMeaningZh = r.word;
    // reading置空或保持
    await conn.query(
      'UPDATE vocabulary SET word = ?, meaning_zh = ? WHERE id = ?',
      [newWord, newMeaningZh, r.id]
    );
    swapFixed++;
  }
  console.log('  已交换修复:', swapFixed, '条');

  // 2b. word和meaning_zh完全相同且都含中文 → reading有假名就用reading当word
  const [wordEqMeaning] = await conn.query(`
    SELECT id, word, reading, meaning_zh
    FROM vocabulary 
    WHERE word = meaning_zh
    AND word REGEXP '[\u4e00-\u9fff]'
    AND reading REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('  word=meaning_zh(均中文) + reading有假名:', wordEqMeaning.length, '条');

  let eqFixed = 0;
  for (const r of wordEqMeaning) {
    await conn.query(
      'UPDATE vocabulary SET word = ? WHERE id = ?',
      [r.reading, r.id]
    );
    eqFixed++;
  }
  console.log('  已修复:', eqFixed, '条');

  // 2c. meaning_zh含假名但word正常 → 清理meaning_zh中的假名部分
  // 这类数据 meaning_zh 类似 "つぼ[名]瓶，坛，罐" → 提取中文部分
  const [meaningHasKana] = await conn.query(`
    SELECT id, word, reading, meaning_zh
    FROM vocabulary
    WHERE meaning_zh REGEXP '[ぁ-んァ-ヶー]'
    AND word REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('  meaning_zh含假名(word正常):', meaningHasKana.length, '条');

  let meaningFixed = 0;
  for (const r of meaningHasKana) {
    let cleaned = r.meaning_zh;
    // 去除 "つぼ[名]" 这种开头的日文+词性标注
    cleaned = cleaned.replace(/^[ぁ-んァ-ヶーa-zA-Z\u4e00-\u9fff]*\[[^\]]*\]/, '').trim();
    // 去除 "（「もらいます」的谦逊语）" 中的假名不需要去，这是解释性的
    // 只去除开头的日文读音部分
    if (cleaned !== r.meaning_zh && cleaned.length > 0) {
      await conn.query('UPDATE vocabulary SET meaning_zh = ? WHERE id = ?', [cleaned, r.id]);
      meaningFixed++;
    }
  }
  console.log('  meaning_zh已清理:', meaningFixed, '条');

  // ====== Phase 3: 去重 ======
  console.log('\n--- Phase 3: 去重处理 ---');

  // 找所有 word+reading+jlpt_level 重复的组
  const [dupGroups] = await conn.query(`
    SELECT word, reading, jlpt_level, COUNT(*) as cnt, 
           GROUP_CONCAT(id ORDER BY 
             (CASE WHEN example_sentence IS NOT NULL AND example_sentence != '' THEN 1 ELSE 0 END) +
             (CASE WHEN meaning_en IS NOT NULL AND meaning_en != '' THEN 1 ELSE 0 END) +
             (CASE WHEN category IS NOT NULL AND category != '' AND category != 'blank' THEN 1 ELSE 0 END)
           DESC) as ids
    FROM vocabulary
    GROUP BY word, reading, jlpt_level
    HAVING cnt > 1
  `);
  console.log('  重复组数:', dupGroups.length);

  for (const g of dupGroups) {
    const ids = g.ids.split(',');
    const keepId = ids[0]; // 保留数据最完整的第一条
    const deleteIds = ids.slice(1).map(id => conn.escape(id)).join(',');
    if (deleteIds.length > 0) {
      await conn.query(`DELETE FROM vocabulary WHERE id IN (${deleteIds})`);
      dedupCount += ids.length - 1;
    }
  }
  console.log('  已去重删除:', dedupCount, '条');

  // ====== Phase 4: 清理reading字段 ======
  console.log('\n--- Phase 4: 清理reading字段 ---');

  // reading是纯中文(无假名) → 如果word有假名，把word复制到reading
  const [readingChinese] = await conn.query(`
    SELECT id, word, reading
    FROM vocabulary
    WHERE reading REGEXP '[\u4e00-\u9fff]'
    AND reading NOT REGEXP '[ぁ-んァ-ヶー]'
    AND word REGEXP '[ぁ-んァ-ヶー]'
  `);
  console.log('  reading纯中文(word有假名):', readingChinese.length, '条');

  let readingFixed = 0;
  for (const r of readingChinese) {
    await conn.query('UPDATE vocabulary SET reading = ? WHERE id = ?', [r.word, r.id]);
    readingFixed++;
  }
  console.log('  reading已修复:', readingFixed, '条');

  // ====== 最终统计 ======
  const [finalCount] = await conn.query('SELECT COUNT(*) as cnt FROM vocabulary');
  const [finalLevels] = await conn.query('SELECT jlpt_level, COUNT(*) as cnt FROM vocabulary GROUP BY jlpt_level ORDER BY jlpt_level');
  const [finalDups] = await conn.query(`
    SELECT COUNT(*) as cnt FROM (
      SELECT word, reading, jlpt_level FROM vocabulary GROUP BY word, reading, jlpt_level HAVING COUNT(*) > 1
    ) t
  `);

  console.log('\n========================================');
  console.log('  清理完成!');
  console.log('========================================');
  console.log('  Phase1 修复 (垃圾→正常):', fixedCount, '条');
  console.log('  Phase1 删除 (不可恢复):', deletedCount, '条');
  console.log('  Phase2 颠倒修复:', swapFixed + eqFixed, '条');
  console.log('  Phase2 meaning清理:', meaningFixed, '条');
  console.log('  Phase3 去重删除:', dedupCount, '条');
  console.log('  Phase4 reading修复:', readingFixed, '条');
  console.log('');
  console.log('  最终词汇数:', finalCount[0].cnt);
  console.log('  按级别:');
  finalLevels.forEach(r => console.log('    ' + r.jlpt_level + ': ' + r.cnt));
  console.log('  剩余重复组:', finalDups[0].cnt);

  await conn.end();
})().catch(e => console.error('Error:', e));
