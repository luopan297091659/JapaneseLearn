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
  jlpt_level: { type: DataTypes.ENUM('N5','N4','N3','N2','N1'), allowNull: false },
  example_sentence: { type: DataTypes.TEXT, allowNull: true },
  example_reading: { type: DataTypes.TEXT, allowNull: true },
  example_meaning_zh: { type: DataTypes.TEXT, allowNull: true },
  audio_url: { type: DataTypes.STRING(500), allowNull: true },
  image_url: { type: DataTypes.STRING(500), allowNull: true },
  category: { type: DataTypes.STRING(50), allowNull: true, comment: 'e.g. food, travel, body' },
  tags: { type: DataTypes.JSON, allowNull: true },
}, { tableName: 'vocabulary' });

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

// ────────── News ──────────
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
    type: DataTypes.ENUM('vocabulary','grammar','listening','quiz','news','srs_review'),
    allowNull: false,
  },
  ref_id: { type: DataTypes.UUID, allowNull: true },
  duration_seconds: { type: DataTypes.INTEGER, defaultValue: 0 },
  score: { type: DataTypes.FLOAT, allowNull: true },
  xp_earned: { type: DataTypes.INTEGER, defaultValue: 0 },
  studied_at: { type: DataTypes.DATEONLY, allowNull: false, defaultValue: DataTypes.NOW },
}, { tableName: 'user_progress' });

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

const AppRelease = require('./AppRelease');

module.exports = {
  Vocabulary,
  GrammarLesson,
  GrammarExample,
  ListeningTrack,
  SrsCard,
  QuizQuestion,
  QuizSession,
  NewsArticle,
  NewsFavorite,
  UserProgress,
  ContentVersion,
  ApiLog,
  AppRelease,
  GameScore,
  GameConfig,
};
