const { DataTypes } = require('sequelize');
const { sequelize } = require('../config/database');

// ────────── Vocabulary ──────────
const Vocabulary = sequelize.define('Vocabulary', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  word: { type: DataTypes.STRING(100), allowNull: false },
  reading: { type: DataTypes.STRING(200), allowNull: false, comment: '読み方 (hiragana/katakana)' },
  meaning_zh: { type: DataTypes.TEXT, allowNull: false },
  meaning_en: { type: DataTypes.TEXT, allowNull: true },
  part_of_speech: {
    type: DataTypes.ENUM('noun','verb','adjective','adverb','particle','conjunction','interjection','other'),
    defaultValue: 'noun',
  },
  part_of_speech_raw: { type: DataTypes.STRING(100), allowNull: true, comment: '原始日文词性 e.g. 名・自他動3' },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
  audio_url: { type: DataTypes.STRING(500), allowNull: true, comment: '单词音频' },
  image_url: { type: DataTypes.STRING(500), allowNull: true },
  category: { type: DataTypes.STRING(50), allowNull: true, comment: 'e.g. food, travel, body' },
  example_sentences: { type: DataTypes.JSON, allowNull: true, comment: '例句数组: [{jp, reading, zh, audio_url}]' },
  verb_forms: { type: DataTypes.JSON, allowNull: true, comment: '动词变形: {base, te, ta, nai, ...}' },
  tags: { type: DataTypes.JSON, allowNull: true },
  // 已弃用字段（保留兼容性）
  example_sentence: { type: DataTypes.TEXT, allowNull: true, deprecated: true },
  example_reading: { type: DataTypes.TEXT, allowNull: true, deprecated: true },
  example_meaning_zh: { type: DataTypes.TEXT, allowNull: true, deprecated: true },
  example_audio_url: { type: DataTypes.STRING(500), allowNull: true, deprecated: true },
}, { tableName: 'vocabulary' });

// ────────── User Vocabulary (Anki 导入 — 与系统词库分离) ──────────
const UserVocabulary = sequelize.define('UserVocabulary', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false, comment: '导入用户' },
  word: { type: DataTypes.STRING(100), allowNull: false },
  reading: { type: DataTypes.STRING(200), allowNull: false },
  meaning_zh: { type: DataTypes.TEXT, allowNull: false },
  meaning_en: { type: DataTypes.TEXT, allowNull: true },
  part_of_speech: {
    type: DataTypes.ENUM('noun','verb','adjective','adverb','particle','conjunction','interjection','other'),
    defaultValue: 'other',
  },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: true, defaultValue: null },
  example_sentence: { type: DataTypes.TEXT, allowNull: true },
  example_audio_url: { type: DataTypes.STRING(500), allowNull: true },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  deck_name: { type: DataTypes.STRING(100), allowNull: true, comment: 'Anki 牌组名' },
  source: { type: DataTypes.STRING(50), defaultValue: 'anki', comment: 'anki / manual' },
  tags: { type: DataTypes.JSON, allowNull: true },
}, { tableName: 'user_vocabulary' });

// ────────── Shared Vocabulary Decks（用户共享词库）──────────
const SharedVocabDeck = sequelize.define('SharedVocabDeck', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  owner_user_id: { type: DataTypes.UUID, allowNull: false, comment: '发布者用户ID' },
  title: { type: DataTypes.STRING(120), allowNull: false },
  description: { type: DataTypes.TEXT, allowNull: true },
  cover_url: { type: DataTypes.STRING(500), allowNull: true },
  source_type: {
    type: DataTypes.ENUM('manual', 'apkg', 'csv', 'txt', 'tsv', 'paste', 'legacy'),
    allowNull: false,
    defaultValue: 'manual',
  },
  jlpt_level: { type: DataTypes.STRING(10), allowNull: true, comment: '主等级，如 N2；混合词库可为空' },
  tags: { type: DataTypes.JSON, allowNull: true },
  card_count: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  visibility: {
    type: DataTypes.ENUM('private', 'public', 'unlisted'),
    allowNull: false,
    defaultValue: 'public',
  },
  status: {
    type: DataTypes.ENUM('draft', 'published', 'archived'),
    allowNull: false,
    defaultValue: 'published',
  },
  import_count: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  like_count: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  meta_json: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'shared_vocab_decks',
  indexes: [
    { fields: ['owner_user_id'] },
    { fields: ['visibility', 'status'] },
    { fields: ['jlpt_level'] },
    { fields: ['source_type'] },
    { fields: ['created_at'] },
  ],
});

const SharedVocabCard = sequelize.define('SharedVocabCard', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  deck_id: { type: DataTypes.UUID, allowNull: false },
  deck_name: { type: DataTypes.STRING(300), allowNull: true },
  word: { type: DataTypes.STRING(100), allowNull: false },
  reading: { type: DataTypes.STRING(200), allowNull: true },
  meaning_zh: { type: DataTypes.TEXT, allowNull: false },
  meaning_en: { type: DataTypes.TEXT, allowNull: true },
  example_sentence: { type: DataTypes.TEXT, allowNull: true },
  example_reading: { type: DataTypes.TEXT, allowNull: true },
  example_meaning_zh: { type: DataTypes.TEXT, allowNull: true },
  example_audio_url: { type: DataTypes.STRING(500), allowNull: true },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  part_of_speech: { type: DataTypes.STRING(50), allowNull: false, defaultValue: 'other' },
  jlpt_level: { type: DataTypes.STRING(10), allowNull: true },
  sort_order: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  meta_json: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'shared_vocab_cards',
  indexes: [
    { fields: ['deck_id', 'sort_order'] },
    { fields: ['deck_name'] },
    { fields: ['word'] },
    { fields: ['jlpt_level'] },
  ],
});

// ────────── Grammar ──────────
const GrammarLesson = sequelize.define('GrammarLesson', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING(200), allowNull: false },
  title_zh: { type: DataTypes.STRING(200), allowNull: true },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
  pattern: { type: DataTypes.STRING(300), allowNull: false, comment: '文型 e.g. ～てもいい' },
  explanation: { type: DataTypes.TEXT, allowNull: false },
  explanation_zh: { type: DataTypes.TEXT, allowNull: true },
  usage_notes: { type: DataTypes.TEXT, allowNull: true },
  order_index: { type: DataTypes.INTEGER, defaultValue: 0 },
}, { tableName: 'grammar_lessons' });

const GrammarExample = sequelize.define('GrammarExample', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  grammar_lesson_id: { type: DataTypes.UUID, allowNull: false },
  sentence: { type: DataTypes.TEXT, allowNull: false },
  reading: { type: DataTypes.TEXT, allowNull: true },
  meaning_zh: { type: DataTypes.TEXT, allowNull: false },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
}, { tableName: 'grammar_examples' });

// ────────── Listening ──────────
const ListeningTrack = sequelize.define('ListeningTrack', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  title: { type: DataTypes.STRING(200), allowNull: false },
  title_zh: { type: DataTypes.STRING(200), allowNull: true },
  description: { type: DataTypes.TEXT, allowNull: true },
  audio_url: { type: DataTypes.STRING(500), allowNull: false },
  transcript: { type: DataTypes.TEXT, allowNull: true },
  transcript_zh: { type: DataTypes.TEXT, allowNull: true },
  duration_seconds: { type: DataTypes.INTEGER, allowNull: true },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
  category: { type: DataTypes.STRING(50), allowNull: true },
  play_count: { type: DataTypes.INTEGER, defaultValue: 0 },
}, { tableName: 'listening_tracks' });

// ────────── SRS Card ──────────
const SrsCard = sequelize.define('SrsCard', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  card_type: { type: DataTypes.ENUM('vocabulary','grammar'), defaultValue: 'vocabulary' },
  ref_id: { type: DataTypes.UUID, allowNull: false, comment: 'vocabulary.id or grammar.id' },
  // SM-2 algorithm fields
  repetitions: { type: DataTypes.INTEGER, defaultValue: 0 },
  ease_factor: { type: DataTypes.FLOAT, defaultValue: 2.5 },
  interval_days: { type: DataTypes.INTEGER, defaultValue: 0 },
  due_date: { type: DataTypes.DATEONLY, allowNull: false, defaultValue: DataTypes.NOW },
  last_reviewed_at: { type: DataTypes.DATE, allowNull: true },
  is_graduated: { type: DataTypes.BOOLEAN, defaultValue: false },
}, { tableName: 'srs_cards' });

// ────────── Quiz ──────────
const QuizQuestion = sequelize.define('QuizQuestion', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  question_type: { type: DataTypes.ENUM('meaning','reading','listening','fill_blank'), allowNull: false },
  question: { type: DataTypes.TEXT, allowNull: false },
  correct_answer: { type: DataTypes.TEXT, allowNull: false },
  options: { type: DataTypes.JSON, allowNull: true, comment: 'Array of choices for MCQ' },
  explanation: { type: DataTypes.TEXT, allowNull: true },
  ref_vocabulary_id: { type: DataTypes.UUID, allowNull: true },
  ref_grammar_id: { type: DataTypes.UUID, allowNull: true },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
}, { tableName: 'quiz_questions' });

const QuizSession = sequelize.define('QuizSession', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  quiz_type: { type: DataTypes.ENUM('vocabulary','grammar','mixed','listening'), defaultValue: 'vocabulary' },
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
  total_questions: { type: DataTypes.INTEGER, defaultValue: 0 },
  correct_count: { type: DataTypes.INTEGER, defaultValue: 0 },
  score_percent: { type: DataTypes.FLOAT, defaultValue: 0 },
  time_spent_seconds: { type: DataTypes.INTEGER, defaultValue: 0 },
  completed_at: { type: DataTypes.DATE, allowNull: true },
}, { tableName: 'quiz_sessions' });

// ────────── JLPT Mock Exam ──────────
const JlptExamPaper = sequelize.define('JlptExamPaper', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  level: { type: DataTypes.ENUM('N5', 'N4', 'N3', 'N2', 'N1'), allowNull: false },
  year: { type: DataTypes.INTEGER, allowNull: false },
  session: { type: DataTypes.ENUM('07', '12', 'other'), allowNull: false, defaultValue: 'other' },
  title: { type: DataTypes.STRING(200), allowNull: false },
  slug: { type: DataTypes.STRING(120), allowNull: false, unique: true },
  source_label: { type: DataTypes.STRING(200), allowNull: true, comment: '后台内部来源标识，不对前台展示' },
  description: { type: DataTypes.TEXT, allowNull: true },
  duration_minutes: { type: DataTypes.INTEGER, allowNull: true },
  is_published: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
  sort_order: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  tags: { type: DataTypes.JSON, allowNull: true },
  meta_json: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'jlpt_exam_papers',
  indexes: [
    { fields: ['level', 'is_published'] },
    { fields: ['level', 'year', 'session'] },
  ],
});

const JlptExamQuestion = sequelize.define('JlptExamQuestion', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  paper_id: { type: DataTypes.UUID, allowNull: false },
  section_type: { type: DataTypes.ENUM('vocabulary_grammar', 'reading', 'listening'), allowNull: false },
  section_title: { type: DataTypes.STRING(100), allowNull: true },
  question_group: { type: DataTypes.STRING(100), allowNull: true, comment: '如 問題1 / 問題2 / 内容理解' },
  question_no: { type: DataTypes.STRING(30), allowNull: false },
  sort_order: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  prompt: { type: DataTypes.TEXT('long'), allowNull: false },
  passage: { type: DataTypes.TEXT('long'), allowNull: true, comment: '阅读材料或题干上下文，已整理为横排语义文本' },
  transcript: { type: DataTypes.TEXT('long'), allowNull: true, comment: '听力原文，首期无音频时用于解析展示' },
  options: { type: DataTypes.JSON, allowNull: false, comment: '选项数组 [{ key, text }]' },
  answer: { type: DataTypes.STRING(20), allowNull: false, comment: '正确选项 key，如 1/A' },
  explanation: { type: DataTypes.TEXT('long'), allowNull: true },
  explanation_zh: { type: DataTypes.TEXT('long'), allowNull: true },
  knowledge_points: { type: DataTypes.JSON, allowNull: true },
  score: { type: DataTypes.FLOAT, allowNull: false, defaultValue: 1 },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  meta_json: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'jlpt_exam_questions',
  indexes: [
    { fields: ['paper_id', 'sort_order'] },
    { fields: ['paper_id', 'section_type'] },
  ],
});

const JlptExamAttempt = sequelize.define('JlptExamAttempt', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: true },
  paper_id: { type: DataTypes.UUID, allowNull: false },
  answers: { type: DataTypes.JSON, allowNull: false, defaultValue: [] },
  score_percent: { type: DataTypes.FLOAT, allowNull: false, defaultValue: 0 },
  total_questions: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  correct_count: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  breakdown: { type: DataTypes.JSON, allowNull: true, comment: '按三类题型拆分得分' },
  time_spent_seconds: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  submitted_at: { type: DataTypes.DATE, allowNull: false, defaultValue: DataTypes.NOW },
}, {
  tableName: 'jlpt_exam_attempts',
  updatedAt: false,
  indexes: [
    { fields: ['paper_id'] },
    { fields: ['user_id'] },
    { fields: ['submitted_at'] },
  ],
});

// ────────── News ──────────
const JlptResourceDirectory = sequelize.define('JlptResourceDirectory', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  level: { type: DataTypes.ENUM('N5', 'N4', 'N3', 'N2', 'N1'), allowNull: false },
  year: { type: DataTypes.INTEGER, allowNull: false },
  session: { type: DataTypes.ENUM('07', '12'), allowNull: false },
  membership_required: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
}, {
  tableName: 'jlpt_resource_directories',
  indexes: [
    { unique: true, fields: ['level', 'year', 'session'] },
    { fields: ['membership_required'] },
  ],
});

const JlptResourceFile = sequelize.define('JlptResourceFile', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  directory_id: { type: DataTypes.UUID, allowNull: false },
  original_name: { type: DataTypes.STRING(255), allowNull: false },
  stored_name: { type: DataTypes.STRING(255), allowNull: false },
  file_url: { type: DataTypes.STRING(600), allowNull: false },
  mime_type: { type: DataTypes.STRING(120), allowNull: true },
  file_size: { type: DataTypes.BIGINT, allowNull: false, defaultValue: 0 },
  sort_order: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
}, {
  tableName: 'jlpt_resource_files',
  indexes: [
    { fields: ['directory_id'] },
    { fields: ['created_at'] },
  ],
});

const NewsArticle = sequelize.define('NewsArticle', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  external_id: { type: DataTypes.STRING(100), allowNull: true, unique: true },
  title: { type: DataTypes.TEXT, allowNull: false },
  body: { type: DataTypes.TEXT('long'), allowNull: false },
  body_with_ruby: { type: DataTypes.TEXT('long'), allowNull: true, comment: 'HTML with ruby tags' },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  image_url: { type: DataTypes.STRING(500), allowNull: true },
  published_at: { type: DataTypes.DATE, allowNull: true },
  source: { type: DataTypes.STRING(100), defaultValue: 'NHK Easy' },
  difficulty: { type: DataTypes.ENUM('easy','medium','hard'), defaultValue: 'easy' },
  related_vocabulary: { type: DataTypes.JSON, allowNull: true },
}, { tableName: 'news_articles' });

// ────────── User Progress ──────────
const UserProgress = sequelize.define('UserProgress', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  activity_type: {
    type: DataTypes.ENUM('vocabulary','grammar','listening','quiz','news','srs_review','flashcard','game','game_verbs','pronunciation','gojuon','dictionary','translate','todofuken','checkin'),
    allowNull: false,
  },
  ref_id: { type: DataTypes.UUID, allowNull: true },
  duration_seconds: { type: DataTypes.INTEGER, defaultValue: 0 },
  score: { type: DataTypes.FLOAT, allowNull: true },
  xp_earned: { type: DataTypes.INTEGER, defaultValue: 0 },
  studied_at: { type: DataTypes.DATEONLY, allowNull: false, defaultValue: DataTypes.NOW },
}, { tableName: 'user_progress' });

// ────────── Study Plan Daily Task (方案C) ──────────
const StudyPlanDailyTask = sequelize.define('StudyPlanDailyTask', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  task_date: { type: DataTypes.DATEONLY, allowNull: false },
  status: {
    type: DataTypes.ENUM('not_started', 'in_progress', 'finished'),
    allowNull: false,
    defaultValue: 'not_started',
  },
  target_vocab: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 10 },
  target_grammar: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 2 },
  target_review: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 5 },
  done_vocab: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  done_grammar: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  done_review: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  completion_rate: { type: DataTypes.FLOAT, allowNull: false, defaultValue: 0 },
  recommended_focus: { type: DataTypes.STRING(100), allowNull: true },
  recommend_reason: { type: DataTypes.TEXT, allowNull: true },
  rule_snapshot: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'study_plan_daily_tasks',
  indexes: [
    { unique: true, fields: ['user_id', 'task_date'] },
    { fields: ['user_id', 'status'] },
  ],
});

// ────────── Study Plan Card State (方案C) ──────────
const StudyPlanCardState = sequelize.define('StudyPlanCardState', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  card_type: { type: DataTypes.ENUM('vocabulary', 'grammar'), allowNull: false },
  ref_id: { type: DataTypes.UUID, allowNull: false },
  state: {
    type: DataTypes.ENUM('new', 'learning', 'review', 'mastered'),
    allowNull: false,
    defaultValue: 'new',
  },
  level: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  wrong_streak: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 0 },
  is_difficult: { type: DataTypes.BOOLEAN, allowNull: false, defaultValue: false },
  last_answer: { type: DataTypes.ENUM('known', 'unknown', 'fuzzy', 'mastered'), allowNull: true },
  next_due_at: { type: DataTypes.DATEONLY, allowNull: true },
  last_seen_at: { type: DataTypes.DATE, allowNull: true },
}, {
  tableName: 'study_plan_card_states',
  indexes: [
    { unique: true, fields: ['user_id', 'card_type', 'ref_id'] },
    { fields: ['user_id', 'state'] },
    { fields: ['user_id', 'is_difficult'] },
  ],
});

// ────────── Content Version (for client sync) ──────────
const ContentVersion = sequelize.define('ContentVersion', {
  id: { type: DataTypes.INTEGER, primaryKey: true, defaultValue: 1 },
  version: { type: DataTypes.INTEGER, defaultValue: 1 },
  vocab_version: { type: DataTypes.INTEGER, defaultValue: 1 },
  grammar_version: { type: DataTypes.INTEGER, defaultValue: 1 },
  updated_at_ts: { type: DataTypes.BIGINT, defaultValue: () => Date.now() },
}, { tableName: 'content_version', timestamps: false });

// ────────── Game ──────────
const GameScore = sequelize.define('GameScore', {
  id:                  { type: DataTypes.BIGINT,   primaryKey: true, autoIncrement: true },
  user_id:             { type: DataTypes.UUID,    allowNull: false },
  username:            { type: DataTypes.STRING(100) },
  level_num:           { type: DataTypes.INTEGER,  defaultValue: 1 },
  score:               { type: DataTypes.INTEGER,  defaultValue: 0 },
  accuracy:            { type: DataTypes.INTEGER,  defaultValue: 0 },
  max_combo:           { type: DataTypes.INTEGER,  defaultValue: 0 },
  questions_answered:  { type: DataTypes.INTEGER,  defaultValue: 0 },
  passed:              { type: DataTypes.BOOLEAN,  defaultValue: false },
  base_speed_ms:       { type: DataTypes.INTEGER,  defaultValue: 2000, allowNull: true },
  game_type:           { type: DataTypes.STRING(20), defaultValue: 'particles', allowNull: false },
}, { tableName: 'game_scores', updatedAt: false });

const GameConfig = sequelize.define('GameConfig', {
  config_key:   { type: DataTypes.STRING(50), primaryKey: true },
  config_value: { type: DataTypes.TEXT },
  updated_by:   { type: DataTypes.STRING(100) },
}, { tableName: 'game_configs' });

const GameLifeSave = sequelize.define('GameLifeSave', {
  user_id: { type: DataTypes.UUID, primaryKey: true, allowNull: false },
  save_data: { type: DataTypes.JSON, allowNull: false },
  revision: { type: DataTypes.INTEGER, allowNull: false, defaultValue: 1 },
  client_updated_at: { type: DataTypes.DATE, allowNull: true },
  device_id: { type: DataTypes.STRING(120), allowNull: true },
  app_version: { type: DataTypes.STRING(40), allowNull: true },
}, {
  tableName: 'game_life_saves',
  indexes: [
    { fields: ['updated_at'] },
    { fields: ['client_updated_at'] },
  ],
});

// ────────── API Request Log (traffic monitoring) ──────────
const ApiLog = sequelize.define('ApiLog', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  method: { type: DataTypes.STRING(10), allowNull: false },
  path: { type: DataTypes.STRING(500), allowNull: false },
  status_code: { type: DataTypes.INTEGER, allowNull: false },
  response_time_ms: { type: DataTypes.INTEGER, allowNull: true },
  user_id: { type: DataTypes.UUID, allowNull: true },
  ip: { type: DataTypes.STRING(60), allowNull: true },
  user_agent: { type: DataTypes.STRING(300), allowNull: true },
}, { tableName: 'api_logs', timestamps: true, updatedAt: false });

// ────────── Tool Usage Log（官网工具箱使用统计）──────────
const ToolUsageLog = sequelize.define('ToolUsageLog', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  tool_id: { type: DataTypes.STRING(60), allowNull: false, comment: 'screenshot-generator / kokoro-tts / ...' },
  action: { type: DataTypes.STRING(40), allowNull: false, defaultValue: 'open', comment: 'open / generate / export / ...' },
  user_id: { type: DataTypes.UUID, allowNull: true },
  ip: { type: DataTypes.STRING(60), allowNull: true },
  user_agent: { type: DataTypes.STRING(300), allowNull: true },
  referer: { type: DataTypes.STRING(500), allowNull: true },
  meta: { type: DataTypes.JSON, allowNull: true },
}, {
  tableName: 'tool_usage_logs',
  timestamps: true,
  updatedAt: false,
  indexes: [
    { fields: ['tool_id'] },
    { fields: ['action'] },
    { fields: ['user_id'] },
    { fields: ['created_at'] },
  ],
});

// ────────── NHK News Cache (缓存历史NHK新闻) ──────────
const NhkNewsCache = sequelize.define('NhkNewsCache', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  nhk_id: { type: DataTypes.STRING(100), allowNull: false, unique: true },
  title: { type: DataTypes.TEXT, allowNull: false },
  description: { type: DataTypes.TEXT, allowNull: true },
  body: { type: DataTypes.TEXT('long'), allowNull: true },
  image_url: { type: DataTypes.STRING(500), allowNull: true },
  link: { type: DataTypes.STRING(500), allowNull: true },
  category: { type: DataTypes.STRING(10), defaultValue: '0' },
  published_at: { type: DataTypes.DATE, allowNull: true },
}, { tableName: 'nhk_news_cache' });

// ────────── News Favorite (用户收藏新闻) ──────────
const NewsFavorite = sequelize.define('NewsFavorite', {
  id: { type: DataTypes.BIGINT, primaryKey: true, autoIncrement: true },
  user_id: { type: DataTypes.UUID, allowNull: false },
  news_type: { type: DataTypes.ENUM('db', 'nhk'), allowNull: false, comment: 'db=收录新闻, nhk=NHK RSS' },
  news_id: { type: DataTypes.STRING(100), allowNull: false, comment: 'DB article UUID or NHK ID like 20260306-k100150...' },
  title: { type: DataTypes.TEXT, allowNull: false },
  description: { type: DataTypes.TEXT, allowNull: true },
  image_url: { type: DataTypes.STRING(500), allowNull: true },
  link: { type: DataTypes.STRING(500), allowNull: true },
  source: { type: DataTypes.STRING(100), defaultValue: 'NHK' },
  published_at: { type: DataTypes.STRING(50), allowNull: true },
}, {
  tableName: 'news_favorites',
  indexes: [{ unique: true, fields: ['user_id', 'news_type', 'news_id'] }],
});

// ────────── Associations ──────────
GrammarLesson.hasMany(GrammarExample, { foreignKey: 'grammar_lesson_id', as: 'examples' });
GrammarExample.belongsTo(GrammarLesson, { foreignKey: 'grammar_lesson_id' });
JlptExamPaper.hasMany(JlptExamQuestion, { foreignKey: 'paper_id', as: 'questions', onDelete: 'CASCADE' });
JlptExamQuestion.belongsTo(JlptExamPaper, { foreignKey: 'paper_id', as: 'paper' });
JlptExamPaper.hasMany(JlptExamAttempt, { foreignKey: 'paper_id', as: 'attempts', onDelete: 'CASCADE' });
JlptExamAttempt.belongsTo(JlptExamPaper, { foreignKey: 'paper_id', as: 'paper' });
JlptResourceDirectory.hasMany(JlptResourceFile, { foreignKey: 'directory_id', as: 'files', onDelete: 'CASCADE' });
JlptResourceFile.belongsTo(JlptResourceDirectory, { foreignKey: 'directory_id', as: 'directory' });
SharedVocabDeck.hasMany(SharedVocabCard, { foreignKey: 'deck_id', as: 'cards', onDelete: 'CASCADE' });
SharedVocabCard.belongsTo(SharedVocabDeck, { foreignKey: 'deck_id', as: 'deck' });

// ────────── MembershipPlan (会员套餐持久化) ──────────
const MembershipPlan = sequelize.define('MembershipPlan', {
  plan_id:         { type: DataTypes.STRING(50), primaryKey: true },
  name:            { type: DataTypes.STRING(100), allowNull: false },
  price:           { type: DataTypes.FLOAT, defaultValue: 0 },
  period:          { type: DataTypes.STRING(20), defaultValue: 'month' },
  description:     { type: DataTypes.TEXT, allowNull: true },
  features:        { type: DataTypes.JSON, allowNull: true, comment: '功能描述列表' },
  bound_features:  { type: DataTypes.JSON, allowNull: true, comment: '绑定的功能ID列表' },
  apple_product_id:{ type: DataTypes.STRING(100), allowNull: true, comment: 'Apple IAP 产品ID' },
  enabled:         { type: DataTypes.BOOLEAN, defaultValue: true },
  sort_order:      { type: DataTypes.INTEGER, defaultValue: 0 },
}, { tableName: 'membership_plans' });

// ────────── JMdict 词典 ──────────
const DictEntry = sequelize.define('DictEntry', {
  id:          { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
  ent_seq:     { type: DataTypes.INTEGER, allowNull: false, comment: 'JMdict entry sequence number' },
  kanji:       { type: DataTypes.STRING(100), allowNull: true, comment: '汉字书写形式' },
  reading:     { type: DataTypes.STRING(100), allowNull: false, comment: '假名读音' },
  pos:         { type: DataTypes.STRING(200), allowNull: true, comment: '词性 (英文)' },
  meaning_en:  { type: DataTypes.TEXT, allowNull: true, comment: '英文释义 (;分隔)' },
  meaning_zh:  { type: DataTypes.TEXT, allowNull: true, comment: '中文释义 (;分隔)' },
  priority:    { type: DataTypes.TINYINT, defaultValue: 0, comment: '常用度 0-5 (ichi1/news1/spec1=高)' },
  jlpt:        { type: DataTypes.STRING(5), allowNull: true, comment: 'N5-N1' },
}, {
  tableName: 'dict_entries',
  timestamps: false,
  indexes: [
    { fields: ['kanji'] },
    { fields: ['reading'] },
    { fields: ['ent_seq'] },
    { fields: ['priority'] },
    { fields: ['meaning_zh'], type: 'FULLTEXT' },
  ],
});

// ────────── AI 翻译缓存 ──────────
const DictTransCache = sequelize.define('DictTransCache', {
  id:         { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
  word:       { type: DataTypes.STRING(100), allowNull: false },
  reading:    { type: DataTypes.STRING(100), allowNull: true },
  meaning_en: { type: DataTypes.TEXT, allowNull: false, comment: '原始英文释义' },
  meaning_zh: { type: DataTypes.TEXT, allowNull: false, comment: 'AI翻译的中文释义' },
}, {
  tableName: 'dict_trans_cache',
  updatedAt: false,
  indexes: [
    { unique: true, fields: ['word', 'reading'] },
  ],
});

// ────────── 听力频道（磨耳朵） ──────────
const ListeningChannel = sequelize.define('ListeningChannel', {
  id:       { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
  owner_user_id: { type: DataTypes.UUID, allowNull: true, comment: 'null=公共频道，非空=用户私有频道' },
  is_public: { type: DataTypes.BOOLEAN, defaultValue: true },
  platform: { type: DataTypes.ENUM('youtube', 'bilibili'), allowNull: false },
  channel_url: { type: DataTypes.STRING(500), allowNull: false },
  channel_id:  { type: DataTypes.STRING(200), allowNull: true, comment: '平台频道/用户ID' },
  name:     { type: DataTypes.STRING(200), allowNull: false, comment: '博主名称' },
  avatar:   { type: DataTypes.STRING(500), allowNull: true, comment: '头像URL' },
  description: { type: DataTypes.STRING(500), allowNull: true },
  is_active: { type: DataTypes.BOOLEAN, defaultValue: true },
  sort_order: { type: DataTypes.INTEGER, defaultValue: 0 },
  max_videos: { type: DataTypes.INTEGER, defaultValue: 12, comment: '最大抓取视频数' },
  video_cache: { type: DataTypes.JSON, allowNull: true, comment: '缓存的最近视频列表' },
  cache_updated_at: { type: DataTypes.DATE, allowNull: true },
}, {
  tableName: 'listening_channels',
});

// ────────── App Config (配置存储) ──────────
const AppConfig = sequelize.define('AppConfig', {
  key: {
    type: DataTypes.STRING(100),
    primaryKey: true,
    comment: '配置键名 e.g. kokoro_tts_settings'
  },
  value: {
    type: DataTypes.TEXT('medium'),
    allowNull: true,
    comment: 'JSON 格式的配置值'
  },
  description: {
    type: DataTypes.STRING(500),
    allowNull: true,
    comment: '配置说明'
  },
}, {
  tableName: 'app_config',
  timestamps: true,
  comment: '应用全局配置存储'
});

// ────────── 五十音表（含濁音、半濁音、拗音） ──────────
const Kana = sequelize.define('Kana', {
  id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  type: { type: DataTypes.ENUM('hiragana', 'katakana'), allowNull: false, comment: '字符类型：平假名/片假名' },
  character: { type: DataTypes.STRING(10), allowNull: false, comment: '字符本身（如「あ」「ア」「きゃ」）' },
  romanization: { type: DataTypes.STRING(20), allowNull: false, comment: '罗马音（如「a」「kya」）' },
  category: { type: DataTypes.STRING(20), allowNull: false, defaultValue: '五十音', comment: '分类：五十音、濁音、半濁音、拗音' },
  audio_url: { type: DataTypes.STRING(500), allowNull: true, comment: '音频URL，为空表示未生成' },
  order_index: { type: DataTypes.INTEGER, allowNull: false, comment: '顺序索引' },
}, {
  tableName: 'kana',
  comment: '日语五十音表及所有变体（濁音、半濁音、拗音）',
  indexes: [
    { unique: true, fields: ['type', 'character'] },
    { fields: ['type'] },
    { fields: ['category'] },
    { fields: ['audio_url'] },
  ],
});

// ────────── MembershipOrder (支付订单) ──────────
const MembershipOrder = sequelize.define('MembershipOrder', {
  id:              { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
  user_id:         { type: DataTypes.UUID, allowNull: false },
  plan_id:         { type: DataTypes.STRING(50), allowNull: false, comment: 'monthly / yearly / lifetime' },
  amount:          { type: DataTypes.FLOAT, allowNull: false, comment: '订单金额' },
  currency:        { type: DataTypes.STRING(10), defaultValue: 'cny' },
  channel:         { type: DataTypes.STRING(30), allowNull: false, comment: 'apple_iap / stripe / alipay_online / qrcode_alipay / qrcode_wechat' },
  status:          { type: DataTypes.ENUM('pending', 'paid', 'rejected', 'expired', 'refunded'), defaultValue: 'pending' },
  // Apple IAP 字段
  apple_transaction_id:           { type: DataTypes.STRING(200), allowNull: true },
  apple_original_transaction_id:  { type: DataTypes.STRING(200), allowNull: true, comment: '同一订阅跨续费共享' },
  apple_environment:              { type: DataTypes.STRING(20), allowNull: true, comment: 'Production / Sandbox' },
  apple_expires_at:               { type: DataTypes.DATE, allowNull: true, comment: 'Apple 返回的订阅到期时间' },
  apple_auto_renew_status:        { type: DataTypes.BOOLEAN, allowNull: true },
  apple_notification_type:        { type: DataTypes.STRING(60), allowNull: true, comment: '若来自服务端通知则记录' },
  apple_receipt:                  { type: DataTypes.TEXT('medium'), allowNull: true },
  // Stripe 字段
  stripe_session_id:     { type: DataTypes.STRING(200), allowNull: true },
  // Alipay online 字段
  alipay_out_trade_no:   { type: DataTypes.STRING(100), allowNull: true, comment: '支付宝商户订单号' },
  alipay_trade_no:       { type: DataTypes.STRING(100), allowNull: true, comment: '支付宝交易号' },
  // 二维码付款截图
  proof_image_url:       { type: DataTypes.STRING(500), allowNull: true, comment: '用户上传的付款截图' },
  user_note:       { type: DataTypes.TEXT, allowNull: true, comment: '用户提交时的文字说明' },
  // 审核
  admin_note:      { type: DataTypes.TEXT, allowNull: true },
  reviewed_by:     { type: DataTypes.UUID, allowNull: true },
  reviewed_at:     { type: DataTypes.DATE, allowNull: true },
  // 通用
  paid_at:         { type: DataTypes.DATE, allowNull: true },
  expire_at:       { type: DataTypes.DATE, allowNull: true, comment: '此次购买对应的到期时间' },
}, {
  tableName: 'membership_orders',
  indexes: [
    { fields: ['user_id'] },
    { fields: ['status'] },
    { fields: ['channel'] },
    { fields: ['apple_transaction_id'] },
    { fields: ['apple_original_transaction_id'] },
    { fields: ['stripe_session_id'] },
    { fields: ['alipay_out_trade_no'] },
    { fields: ['alipay_trade_no'] },
  ],
});

const AppRelease = require('./AppRelease');

module.exports = {
  Vocabulary,
  UserVocabulary,
  SharedVocabDeck,
  SharedVocabCard,
  GrammarLesson,
  GrammarExample,
  ListeningTrack,
  SrsCard,
  QuizQuestion,
  QuizSession,
  JlptExamPaper,
  JlptExamQuestion,
  JlptExamAttempt,
  JlptResourceDirectory,
  JlptResourceFile,
  NewsArticle,
  NhkNewsCache,
  NewsFavorite,
  UserProgress,
  StudyPlanDailyTask,
  StudyPlanCardState,
  ContentVersion,
  ApiLog,
  ToolUsageLog,
  AppRelease,
  AppConfig,
  GameScore,
  GameConfig,
  GameLifeSave,
  MembershipPlan,
  MembershipOrder,
  DictEntry,
  DictTransCache,
  ListeningChannel,
  Kana,  // ✅ 添加五十音表
};
