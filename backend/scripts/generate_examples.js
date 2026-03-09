/**
 * 批量生成词汇例句 + 语法例句
 * 根据词性和词汇自动组合日语例句 + 中文翻译
 */
const mysql = require('mysql2/promise');

// ============ 词汇例句模板 ============
// 每个词性有多个模板，按 {word} 和 {reading} 插入
const VOCAB_TEMPLATES = {
  noun: [
    { ja: '{word}はどこですか。', zh: '{meaning}在哪里？' },
    { ja: '{word}をください。', zh: '请给我{meaning}。' },
    { ja: 'これは{word}です。', zh: '这是{meaning}。' },
    { ja: '{word}が好きです。', zh: '喜欢{meaning}。' },
    { ja: '{word}を買いました。', zh: '买了{meaning}。' },
  ],
  verb: [
    { ja: '毎日{word}。', zh: '每天{meaning}。' },
    { ja: '{word}ことができます。', zh: '能够{meaning}。' },
    { ja: '{word}のが好きです。', zh: '喜欢{meaning}。' },
    { ja: 'よく{word}。', zh: '经常{meaning}。' },
    { ja: '{word}つもりです。', zh: '打算{meaning}。' },
  ],
  adjective: [
    { ja: 'この部屋は{word}です。', zh: '这个房间很{meaning}。' },
    { ja: '{word}ものが好きです。', zh: '喜欢{meaning}的东西。' },
    { ja: 'とても{word}です。', zh: '非常{meaning}。' },
    { ja: '{word}と思います。', zh: '觉得{meaning}。' },
  ],
  adverb: [
    { ja: '{word}勉強します。', zh: '{meaning}学习。' },
    { ja: '{word}食べてください。', zh: '请{meaning}吃。' },
    { ja: '{word}歩きます。', zh: '{meaning}走。' },
  ],
  particle: [
    { ja: '「{word}」は文法で大切です。', zh: '「{word}」在语法中很重要。' },
  ],
  conjunction: [
    { ja: '雨です。{word}、出かけません。', zh: '下雨了。{meaning}，不出门。' },
  ],
  interjection: [
    { ja: '「{word}」と言いました。', zh: '说了「{word}」。' },
  ],
  other: [
    { ja: '{word}について勉強しました。', zh: '学习了关于{meaning}的内容。' },
    { ja: '{word}は大切です。', zh: '{meaning}很重要。' },
    { ja: '{word}を使います。', zh: '使用{meaning}。' },
  ],
};

// ============ 语法例句模板 ============
// 按 pattern 中的文型特征匹配
const GRAMMAR_TEMPLATES = {
  'てもいい': [
    { ja: 'ここで写真を撮ってもいいですか。', zh: '可以在这里拍照吗？' },
    { ja: '窓を開けてもいいですか。', zh: '可以开窗户吗？' },
  ],
  'てはいけない': [
    { ja: 'ここでタバコを吸ってはいけません。', zh: '不可以在这里吸烟。' },
    { ja: '遅刻してはいけません。', zh: '不可以迟到。' },
  ],
  'ている': [
    { ja: '今、本を読んでいます。', zh: '现在正在读书。' },
    { ja: '東京に住んでいます。', zh: '住在东京。' },
  ],
  'たい': [
    { ja: '日本に行きたいです。', zh: '想去日本。' },
    { ja: '寿司が食べたいです。', zh: '想吃寿司。' },
  ],
  'なければならない': [
    { ja: '薬を飲まなければなりません。', zh: '必须吃药。' },
    { ja: '宿題をしなければなりません。', zh: '必须做作业。' },
  ],
  'ことができる': [
    { ja: '日本語を話すことができます。', zh: '会说日语。' },
    { ja: '漢字を読むことができます。', zh: '能读汉字。' },
  ],
  'たことがある': [
    { ja: '富士山に登ったことがあります。', zh: '爬过富士山。' },
    { ja: '日本に行ったことがあります。', zh: '去过日本。' },
  ],
  'ようにする': [
    { ja: '毎日運動するようにしています。', zh: '尽量每天运动。' },
  ],
  'ようになる': [
    { ja: '日本語が話せるようになりました。', zh: '变得会说日语了。' },
  ],
  'そうだ': [
    { ja: '雨が降りそうです。', zh: '好像要下雨了。' },
    { ja: 'このケーキはおいしそうです。', zh: '这个蛋糕看起来很好吃。' },
  ],
  'らしい': [
    { ja: '明日は雨らしいです。', zh: '明天好像要下雨。' },
  ],
  'ば': [
    { ja: '安ければ買います。', zh: '如果便宜就买。' },
    { ja: '時間があれば行きます。', zh: '如果有时间就去。' },
  ],
  'たら': [
    { ja: '雨が降ったら、家にいます。', zh: '如果下雨就待在家里。' },
  ],
  'ても': [
    { ja: '雨が降っても、行きます。', zh: '即使下雨也去。' },
  ],
  'のに': [
    { ja: '勉強したのに、テストに落ちました。', zh: '明明学习了，却考试没过。' },
  ],
  'ながら': [
    { ja: '音楽を聞きながら勉強します。', zh: '一边听音乐一边学习。' },
  ],
  'てしまう': [
    { ja: '財布を忘れてしまいました。', zh: '（不小心）忘了钱包。' },
  ],
  'てあげる': [
    { ja: '友達に日本語を教えてあげました。', zh: '教了朋友日语。' },
  ],
  'てもらう': [
    { ja: '友達に手伝ってもらいました。', zh: '请朋友帮忙了。' },
  ],
  'てくれる': [
    { ja: '母が料理を作ってくれました。', zh: '妈妈给我做了饭。' },
  ],
  'させる': [
    { ja: '子供に野菜を食べさせます。', zh: '让孩子吃蔬菜。' },
  ],
  'れる': [
    { ja: '先生に褒められました。', zh: '被老师表扬了。' },
  ],
  'と': [
    { ja: '春になると、桜が咲きます。', zh: '一到春天，樱花就开了。' },
  ],
};

function cleanWordForSentence(word) {
  // 去掉方括号注音，获取纯文字用于造句
  return word.replace(/\[[^\]]*\]/g, '').replace(/\s+/g, '').replace(/[（()）]/g, '');
}

function pickTemplate(templates, wordId) {
  // 用 wordId hash 来确定选哪个模板，保证同一个词每次生成的例句一样
  let hash = 0;
  for (let i = 0; i < wordId.length; i++) {
    hash = ((hash << 5) - hash + wordId.charCodeAt(i)) | 0;
  }
  return templates[Math.abs(hash) % templates.length];
}

(async () => {
  const conn = await mysql.createConnection({
    host: '139.196.44.6', port: 3306, user: 'root',
    password: '6586156', database: 'japanese_learn', charset: 'utf8mb4',
    connectTimeout: 60000
  });

  console.log('=== 开始生成例句 ===\n');

  // ====== Part 1: 词汇例句 ======
  console.log('--- Part 1: 词汇例句 ---');
  
  // 获取所有需要例句的词汇（无例句、或例句不含造句结构如です/ます/ください等）
  const [words] = await conn.query(`
    SELECT id, word, reading, meaning_zh, part_of_speech
    FROM vocabulary 
    WHERE example_sentence IS NULL 
       OR example_sentence = '' 
       OR example_sentence = word
       OR example_sentence = reading
       OR (example_sentence NOT LIKE '%です%' 
           AND example_sentence NOT LIKE '%ます%' 
           AND example_sentence NOT LIKE '%ください%'
           AND example_sentence NOT LIKE '%について%'
           AND CHAR_LENGTH(example_sentence) < 10)
  `);
  console.log(`需要生成例句: ${words.length} 条`);

  // 为每个生成例句
  let updated = 0;
  for (const w of words) {
    try {
      const pos = w.part_of_speech || 'other';
      const templates = VOCAB_TEMPLATES[pos] || VOCAB_TEMPLATES['other'];
      const tmpl = pickTemplate(templates, w.id);
      
      const cleanWord = cleanWordForSentence(w.word);
      const meaning = (w.meaning_zh || '').split(/[,，;；、]/)[0].trim() || cleanWord;
      
      const exJa = tmpl.ja.replace(/{word}/g, cleanWord).replace(/{reading}/g, w.reading || cleanWord).replace(/{meaning}/g, meaning);
      const exZh = tmpl.zh.replace(/{word}/g, cleanWord).replace(/{meaning}/g, meaning);
      
      await conn.query(
        'UPDATE vocabulary SET example_sentence = ?, example_meaning_zh = ? WHERE id = ?',
        [exJa, exZh, w.id]
      );
      updated++;
      if (updated % 2000 === 0) {
        console.log(`  进度: ${updated}/${words.length}`);
      }
    } catch (e) {
      console.log(`  跳过 ${w.id} (${w.word}): ${e.message}`);
    }
  }
  console.log(`词汇例句生成完成: ${updated} 条\n`);

  // ====== Part 2: 语法例句 ======
  console.log('--- Part 2: 语法例句 ---');
  
  // 检查grammar_examples表当前数据
  const [gramCount] = await conn.query('SELECT COUNT(*) as c FROM grammar_examples');
  console.log(`现有语法例句: ${gramCount[0].c} 条`);

  // 获取所有语法课
  const [lessons] = await conn.query('SELECT id, pattern, title, jlpt_level FROM grammar_lessons ORDER BY jlpt_level, order_index');
  console.log(`语法课总数: ${lessons.length} 条`);

  // 检查哪些语法课已有例句
  const [existingExamples] = await conn.query('SELECT DISTINCT grammar_lesson_id FROM grammar_examples');
  const hasExamples = new Set(existingExamples.map(e => e.grammar_lesson_id));
  const needExamples = lessons.filter(l => !hasExamples.has(l.id));
  console.log(`需要生成例句的语法课: ${needExamples.length} 条`);

  let gramGenerated = 0;
  for (const lesson of needExamples) {
    const pattern = lesson.pattern || '';
    
    // 找匹配的模板
    let matched = null;
    for (const [key, templates] of Object.entries(GRAMMAR_TEMPLATES)) {
      if (pattern.includes(key)) {
        matched = templates;
        break;
      }
    }

    if (!matched) {
      // 通用模板：用 pattern 本身造句
      const cleanPattern = cleanWordForSentence(pattern);
      matched = [
        { ja: `「${cleanPattern}」を使って文を作ります。`, zh: `用「${cleanPattern}」造句。` },
        { ja: `${cleanPattern}の使い方を練習します。`, zh: `练习「${cleanPattern}」的用法。` },
      ];
    }

    // 插入例句（每个语法课插入对应模板的所有例句）
    for (const tmpl of matched) {
      await conn.query(
        'INSERT INTO grammar_examples (id, grammar_lesson_id, sentence, meaning_zh, created_at, updated_at) VALUES (UUID(), ?, ?, ?, NOW(), NOW())',
        [lesson.id, tmpl.ja, tmpl.zh]
      );
      gramGenerated++;
    }
  }
  console.log(`语法例句生成完成: ${gramGenerated} 条\n`);

  // ====== 最终统计 ======
  const [finalVocab] = await conn.query("SELECT COUNT(*) as c FROM vocabulary WHERE example_sentence IS NOT NULL AND example_sentence != ''");
  const [finalVocabTotal] = await conn.query("SELECT COUNT(*) as c FROM vocabulary");
  const [finalGram] = await conn.query('SELECT COUNT(*) as c FROM grammar_examples');

  console.log('========================================');
  console.log('  生成完成!');
  console.log('========================================');
  console.log(`  词汇例句: ${finalVocab[0].c}/${finalVocabTotal[0].c} (${(finalVocab[0].c/finalVocabTotal[0].c*100).toFixed(1)}%)`);
  console.log(`  语法例句: ${finalGram[0].c} 条`);

  await conn.end();
  console.log('\n完成。');
})().catch(e => console.error('Error:', e));
