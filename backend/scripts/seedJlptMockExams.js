require('dotenv').config();

const { sequelize } = require('../src/config/database');
const { JlptExamPaper, JlptExamQuestion } = require('../src/models');

const samplePapers = [
  {
    level: 'N3',
    year: 2021,
    session: '12',
    title: 'N3 模拟测验 A 卷',
    slug: 'n3-mock-a',
    description: '覆盖词汇语法、阅读、听解三类题型的综合模拟卷。',
    duration_minutes: 95,
    is_published: true,
    sort_order: 10,
    tags: ['N3', 'mock', 'starter'],
    source_label: 'seed-v1',
    questions: [
      {
        section_type: 'vocabulary_grammar',
        section_title: '文字・語彙',
        question_group: '問題1',
        question_no: '1',
        sort_order: 1,
        prompt: '「連絡」の読み方として正しいものを選んでください。',
        options: [
          { key: '1', text: 'れんらく' },
          { key: '2', text: 'れいらく' },
          { key: '3', text: 'りんらく' },
          { key: '4', text: 'りいらく' }
        ],
        answer: '1',
        explanation: '「連絡（れんらく）」は N3 頻出語彙。',
        explanation_zh: '“连络/联系”读作 れんらく。',
        knowledge_points: ['词汇读音'],
        score: 1,
      },
      {
        section_type: 'reading',
        section_title: '読解',
        question_group: '問題4',
        question_no: '2',
        sort_order: 2,
        passage: '図書館の利用時間が変更されました。平日は午前9時から午後8時まで、土日は午前10時から午後6時までです。',
        prompt: '平日の利用時間として正しいものを選んでください。',
        options: [
          { key: '1', text: '午前8時から午後8時' },
          { key: '2', text: '午前9時から午後8時' },
          { key: '3', text: '午前10時から午後6時' },
          { key: '4', text: '午前9時から午後6時' }
        ],
        answer: '2',
        explanation: '本文中「平日は午前9時から午後8時まで」。',
        explanation_zh: '文中明确说明平日是 9:00-20:00。',
        knowledge_points: ['阅读定位'],
        score: 1,
      },
      {
        section_type: 'listening',
        section_title: '聴解',
        question_group: '問題2',
        question_no: '3',
        sort_order: 3,
        transcript: '男の人と女の人が話しています。女の人は明日の会議に何時に行きますか。女：明日は少し早めに行きます。九時半には着きたいです。',
        prompt: '女の人は明日の会議に何時に行きますか。',
        options: [
          { key: '1', text: '9時' },
          { key: '2', text: '9時半' },
          { key: '3', text: '10時' },
          { key: '4', text: '10時半' }
        ],
        answer: '2',
        explanation: '発話「九時半には着きたいです」。',
        explanation_zh: '女生说希望 9 点半到。',
        knowledge_points: ['听力关键信息'],
        score: 1,
      }
    ],
  },
  {
    level: 'N2',
    year: 2020,
    session: '07',
    title: 'N2 模拟测验 A 卷',
    slug: 'n2-mock-a',
    description: 'N2 难度基础卷，适合第一轮摸底。',
    duration_minutes: 110,
    is_published: true,
    sort_order: 20,
    tags: ['N2', 'mock', 'starter'],
    source_label: 'seed-v1',
    questions: [
      {
        section_type: 'vocabulary_grammar',
        section_title: '文法',
        question_group: '問題3',
        question_no: '1',
        sort_order: 1,
        prompt: '時間がないので、要点（　　　）説明します。',
        options: [
          { key: '1', text: 'に対して' },
          { key: '2', text: 'にかけて' },
          { key: '3', text: 'に限って' },
          { key: '4', text: 'だけ' }
        ],
        answer: '4',
        explanation: '「要点だけ」表示“只讲要点”。',
        explanation_zh: '句意是“只说明要点”，选 だけ。',
        knowledge_points: ['助词用法'],
        score: 1,
      },
      {
        section_type: 'reading',
        section_title: '読解',
        question_group: '問題6',
        question_no: '2',
        sort_order: 2,
        passage: '最近、オンライン会議が増えたことで、移動時間が減り、その分資料準備に時間を使えるようになった。',
        prompt: '本文の内容として正しいものはどれですか。',
        options: [
          { key: '1', text: '移動時間が増えた' },
          { key: '2', text: '資料準備の時間が減った' },
          { key: '3', text: '移動が減って準備時間が増えた' },
          { key: '4', text: '会議が減った' }
        ],
        answer: '3',
        explanation: '本文に「移動時間が減り、その分資料準備に時間を使える」。',
        explanation_zh: '线上会议增多后，移动减少，准备时间增加。',
        knowledge_points: ['阅读同义改写'],
        score: 1,
      },
      {
        section_type: 'listening',
        section_title: '聴解',
        question_group: '問題1',
        question_no: '3',
        sort_order: 3,
        transcript: '店員：本日のおすすめは焼き魚定食です。客：では、それをお願いします。',
        prompt: '客は何を注文しましたか。',
        options: [
          { key: '1', text: 'カレー' },
          { key: '2', text: '焼き魚定食' },
          { key: '3', text: 'ラーメン' },
          { key: '4', text: 'サンドイッチ' }
        ],
        answer: '2',
        explanation: '客は「それをお願いします」と応答。',
        explanation_zh: '顾客说“那就那个”，指店员推荐的烤鱼定食。',
        knowledge_points: ['听力指代词'],
        score: 1,
      }
    ],
  },
  {
    level: 'N1',
    year: 2019,
    session: '12',
    title: 'N1 模拟测验 A 卷',
    slug: 'n1-mock-a',
    description: 'N1 综合模拟，强调语义辨析与长文信息提取。',
    duration_minutes: 120,
    is_published: true,
    sort_order: 30,
    tags: ['N1', 'mock', 'starter'],
    source_label: 'seed-v1',
    questions: [
      {
        section_type: 'vocabulary_grammar',
        section_title: '語彙',
        question_group: '問題2',
        question_no: '1',
        sort_order: 1,
        prompt: '新しい制度の導入で、業務の流れが（　）された。',
        options: [
          { key: '1', text: '簡素化' },
          { key: '2', text: '簡素' },
          { key: '3', text: '簡略' },
          { key: '4', text: '単純' }
        ],
        answer: '1',
        explanation: '受け身「〜された」に自然に接続できる名詞は「簡素化」。',
        explanation_zh: '“被……化”结构应选名词“简素化”。',
        knowledge_points: ['词形辨析'],
        score: 1,
      },
      {
        section_type: 'reading',
        section_title: '読解',
        question_group: '問題8',
        question_no: '2',
        sort_order: 2,
        passage: '筆者は、効率のみを重視する社会では、短期的成果は得られても、長期的には創造性が損なわれる可能性があると述べている。',
        prompt: '筆者の主張として最も近いものはどれですか。',
        options: [
          { key: '1', text: '効率重視は常に創造性を高める' },
          { key: '2', text: '短期成果より長期の創造性に注意が必要' },
          { key: '3', text: '創造性は効率と無関係である' },
          { key: '4', text: '短期成果は得られない' }
        ],
        answer: '2',
        explanation: '文中で「短期的成果」と「長期的な創造性低下」を対比。',
        explanation_zh: '作者强调效率优先可能牺牲长期创造性。',
        knowledge_points: ['长文主旨'],
        score: 1,
      },
      {
        section_type: 'listening',
        section_title: '聴解',
        question_group: '問題3',
        question_no: '3',
        sort_order: 3,
        transcript: '教授：レポートは来週金曜までに提出してください。学生：木曜に提出してもよろしいでしょうか。教授：もちろん構いません。',
        prompt: '学生はいつレポートを提出したいですか。',
        options: [
          { key: '1', text: '来週金曜' },
          { key: '2', text: '来週木曜' },
          { key: '3', text: '明日' },
          { key: '4', text: '今日' }
        ],
        answer: '2',
        explanation: '学生の発話「木曜に提出しても」。',
        explanation_zh: '学生希望周四提交。',
        knowledge_points: ['听力时间表达'],
        score: 1,
      }
    ],
  },
];

async function upsertPaper(paperInput) {
  const { questions, ...paperData } = paperInput;
  const existing = await JlptExamPaper.findOne({ where: { slug: paperData.slug } });

  if (existing) {
    await existing.update(paperData);
    await JlptExamQuestion.destroy({ where: { paper_id: existing.id } });
    await JlptExamQuestion.bulkCreate(
      questions.map(question => ({ ...question, paper_id: existing.id }))
    );
    return { id: existing.id, action: 'updated' };
  }

  const created = await JlptExamPaper.create(paperData);
  await JlptExamQuestion.bulkCreate(
    questions.map(question => ({ ...question, paper_id: created.id }))
  );
  return { id: created.id, action: 'created' };
}

async function main() {
  await sequelize.authenticate();
  await sequelize.sync({ alter: { drop: false } });

  for (const paper of samplePapers) {
    const result = await upsertPaper(paper);
    console.log(`[seed:jlpt] ${paper.slug} -> ${result.action}`);
  }

  const count = await JlptExamPaper.count();
  console.log(`[seed:jlpt] done. total papers: ${count}`);
}

main()
  .then(async () => {
    await sequelize.close();
    process.exit(0);
  })
  .catch(async err => {
    console.error('[seed:jlpt] failed:', err.message);
    await sequelize.close();
    process.exit(1);
  });
