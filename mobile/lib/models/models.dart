import 'dart:convert';

// ─── User Model ──────────────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String username;
  final String email;
  final String? avatarUrl;
  final String level;
  final int streakDays;
  final int totalStudyMinutes;
  final String? lastStudyDate;
  final int dailyGoalMinutes;
  final bool notificationEnabled;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatarUrl,
    required this.level,
    required this.streakDays,
    required this.totalStudyMinutes,
    this.lastStudyDate,
    required this.dailyGoalMinutes,
    required this.notificationEnabled,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        username: json['username'],
        email: json['email'],
        avatarUrl: json['avatar_url'],
        level: json['level'] ?? 'N5',
        streakDays: json['streak_days'] ?? 0,
        totalStudyMinutes: json['total_study_minutes'] ?? 0,
        lastStudyDate: json['last_study_date'],
        dailyGoalMinutes: json['daily_goal_minutes'] ?? 15,
        notificationEnabled: json['notification_enabled'] ?? true,
      );
}

// ─── Vocabulary Model ────────────────────────────────────────────────────────
class VocabularyModel {
  final String id;
  final String word;
  final String reading;
  final String meaningZh;
  final String? meaningEn;
  final String partOfSpeech;
  final String? partOfSpeechRaw;
  final String jlptLevel;
  final String? exampleSentence;
  final String? exampleReading;
  final String? exampleMeaningZh;
  final String? exampleAudioUrl;
  final String? audioUrl;
  final String? imageUrl;
  final String? category;

  const VocabularyModel({
    required this.id,
    required this.word,
    required this.reading,
    required this.meaningZh,
    this.meaningEn,
    required this.partOfSpeech,
    this.partOfSpeechRaw,
    required this.jlptLevel,
    this.exampleSentence,
    this.exampleReading,
    this.exampleMeaningZh,
    this.exampleAudioUrl,
    this.audioUrl,
    this.imageUrl,
    this.category,
  });

  factory VocabularyModel.fromJson(Map<String, dynamic> json) => VocabularyModel(
        id: json['id'],
        word: json['word'],
        reading: json['reading'],
        meaningZh: json['meaning_zh'],
        meaningEn: json['meaning_en'],
        partOfSpeech: json['part_of_speech'] ?? 'noun',
        partOfSpeechRaw: json['part_of_speech_raw'],
        jlptLevel: json['jlpt_level'],
        exampleSentence: json['example_sentence'],
        exampleReading: json['example_reading'],
        exampleMeaningZh: json['example_meaning_zh'],
        exampleAudioUrl: json['example_audio_url'],
        audioUrl: json['audio_url'],
        imageUrl: json['image_url'],
        category: json['category'],
      );
}

// ─── Grammar Lesson Model ────────────────────────────────────────────────────
class GrammarLessonModel {
  final String id;
  final String title;
  final String? titleZh;
  final String jlptLevel;
  final String pattern;
  final String explanation;
  final String? explanationZh;
  final String? usageNotes;
  final List<GrammarExampleModel> examples;

  const GrammarLessonModel({
    required this.id,
    required this.title,
    this.titleZh,
    required this.jlptLevel,
    required this.pattern,
    required this.explanation,
    this.explanationZh,
    this.usageNotes,
    required this.examples,
  });

  factory GrammarLessonModel.fromJson(Map<String, dynamic> json) => GrammarLessonModel(
        id: json['id'],
        title: json['title'],
        titleZh: json['title_zh'],
        jlptLevel: json['jlpt_level'],
        pattern: json['pattern'],
        explanation: json['explanation'],
        explanationZh: json['explanation_zh'],
        usageNotes: json['usage_notes'],
        examples: (json['examples'] as List<dynamic>?)
                ?.map((e) => GrammarExampleModel.fromJson(e))
                .toList() ??
            [],
      );
}

class GrammarExampleModel {
  final String id;
  final String sentence;
  final String? reading;
  final String meaningZh;
  final String? audioUrl;

  const GrammarExampleModel({
    required this.id,
    required this.sentence,
    this.reading,
    required this.meaningZh,
    this.audioUrl,
  });

  factory GrammarExampleModel.fromJson(Map<String, dynamic> json) => GrammarExampleModel(
        id: json['id'],
        sentence: json['sentence'],
        reading: json['reading'],
        meaningZh: json['meaning_zh'],
        audioUrl: json['audio_url'],
      );
}

// ─── SRS Card Model ──────────────────────────────────────────────────────────
class SrsCardModel {
  final String id;
  final String cardType;
  final String refId;
  final int repetitions;
  final double easeFactor;
  final int intervalDays;
  final String dueDate;
  final bool isGraduated;
  final dynamic content; // VocabularyModel or GrammarLessonModel

  const SrsCardModel({
    required this.id,
    required this.cardType,
    required this.refId,
    required this.repetitions,
    required this.easeFactor,
    required this.intervalDays,
    required this.dueDate,
    required this.isGraduated,
    this.content,
  });

  factory SrsCardModel.fromJson(Map<String, dynamic> json) => SrsCardModel(
        id: json['id'],
        cardType: json['card_type'],
        refId: json['ref_id'],
        repetitions: json['repetitions'] ?? 0,
        easeFactor: (json['ease_factor'] ?? 2.5).toDouble(),
        intervalDays: json['interval_days'] ?? 0,
        dueDate: json['due_date'],
        isGraduated: json['is_graduated'] ?? false,
        content: json['content'] != null
            ? (json['card_type'] == 'vocabulary'
                ? VocabularyModel.fromJson(json['content'])
                : GrammarLessonModel.fromJson(json['content']))
            : null,
      );
}

// ─── Quiz Question Model ─────────────────────────────────────────────────────
class QuizQuestionModel {
  final String id;
  final String questionType;
  final String question;
  final String correctAnswer;
  final List<String>? options;
  final String? explanation;
  final String jlptLevel;
  String? userAnswer;

  QuizQuestionModel({
    required this.id,
    required this.questionType,
    required this.question,
    required this.correctAnswer,
    this.options,
    this.explanation,
    required this.jlptLevel,
    this.userAnswer,
  });

  factory QuizQuestionModel.fromJson(Map<String, dynamic> json) {
    // 服务端有时将 options 序列化为 JSON 字符串而非数组，兼容两种情况
    List<String>? optionsList;
    final raw = json['options'];
    if (raw is List) {
      optionsList = raw.cast<String>();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) optionsList = decoded.cast<String>();
      } catch (_) {
        // 解析失败则忽略
      }
    }
    return QuizQuestionModel(
      id:            json['id']?.toString() ?? '',
      questionType:  json['question_type']?.toString() ?? 'vocabulary',
      question:      json['question']?.toString() ?? '',
      correctAnswer: json['correct_answer']?.toString() ?? '',
      options:       optionsList,
      explanation:   json['explanation']?.toString(),
      jlptLevel:     json['jlpt_level']?.toString() ?? 'N5',
    );
  }

  bool get isCorrect => userAnswer == correctAnswer;
}

// ─── News Favorite Model ─────────────────────────────────────────────────────
class NewsFavoriteModel {
  final int id;
  final String newsType;
  final String newsId;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? link;
  final String? source;
  final String? publishedAt;

  const NewsFavoriteModel({
    required this.id,
    required this.newsType,
    required this.newsId,
    required this.title,
    this.description,
    this.imageUrl,
    this.link,
    this.source,
    this.publishedAt,
  });

  factory NewsFavoriteModel.fromJson(Map<String, dynamic> json) => NewsFavoriteModel(
        id: json['id'] ?? 0,
        newsType: json['news_type'] ?? 'db',
        newsId: json['news_id']?.toString() ?? '',
        title: json['title'] ?? '',
        description: json['description'],
        imageUrl: json['image_url'],
        link: json['link'],
        source: json['source'],
        publishedAt: json['published_at'],
      );
}

// ─── News Article Model ──────────────────────────────────────────────────────
class NewsArticleModel {
  final String id;
  final String title;
  final String? titleWithRuby;
  final String? body;
  final String? bodyWithRuby;
  final String? audioUrl;
  final String? imageUrl;
  final String? publishedAt;
  final String source;
  final String difficulty;

  const NewsArticleModel({
    required this.id,
    required this.title,
    this.titleWithRuby,
    this.body,
    this.bodyWithRuby,
    this.audioUrl,
    this.imageUrl,
    this.publishedAt,
    required this.source,
    required this.difficulty,
  });

  factory NewsArticleModel.fromJson(Map<String, dynamic> json) => NewsArticleModel(
        id: json['id']?.toString() ?? '',
        title: json['title'] ?? '',
        titleWithRuby: json['titleWithRuby'] ?? json['title_with_ruby'],
        body: json['body'],
        bodyWithRuby: json['body_with_ruby'] ?? json['bodyWithRuby'],
        audioUrl: json['audio_url'] ?? json['audioUrl'],
        imageUrl: json['image_url'] ?? json['imageUrl'],
        publishedAt: json['published_at'] ?? json['publishedAt'],
        source: json['source'] ?? 'NHK Easy',
        difficulty: json['difficulty'] ?? 'easy',
      );
}

// ─── Progress Summary ────────────────────────────────────────────────────────
class ProgressSummaryModel {
  final int streakDays;
  final int totalStudyMinutes;
  final String level;
  final int totalXp;
  final List<DailyStatModel> dailyStats;
  final QuizStatModel? quizStats;
  final SrsStatModel? srsStats;
  final WeeklyStatModel? weeklyStats;

  const ProgressSummaryModel({
    required this.streakDays,
    required this.totalStudyMinutes,
    required this.level,
    required this.totalXp,
    required this.dailyStats,
    this.quizStats,
    this.srsStats,
    this.weeklyStats,
  });

  factory ProgressSummaryModel.fromJson(Map<String, dynamic> json) => ProgressSummaryModel(
        streakDays: json['user']?['streak_days'] ?? 0,
        totalStudyMinutes: json['user']?['total_study_minutes'] ?? 0,
        level: json['user']?['level'] ?? 'N5',
        totalXp: int.tryParse(json['user']?['total_xp']?.toString() ?? '0') ?? 0,
        dailyStats: (json['daily_stats'] as List<dynamic>?)
                ?.map((e) => DailyStatModel.fromJson(e))
                .toList() ??
            [],
        quizStats: json['quiz_stats'] != null ? QuizStatModel.fromJson(json['quiz_stats']) : null,
        srsStats: json['srs_stats'] != null ? SrsStatModel.fromJson(json['srs_stats']) : null,
        weeklyStats: json['weekly_stats'] != null ? WeeklyStatModel.fromJson(json['weekly_stats']) : null,
      );
}

class DailyStatModel {
  final String date;
  final int totalSeconds;
  final int totalXp;
  final int activityCount;

  const DailyStatModel({
    required this.date,
    required this.totalSeconds,
    required this.totalXp,
    required this.activityCount,
  });

  factory DailyStatModel.fromJson(Map<String, dynamic> json) => DailyStatModel(
        date: json['studied_at'],
        totalSeconds: int.tryParse(json['total_seconds'].toString()) ?? 0,
        totalXp: int.tryParse(json['total_xp'].toString()) ?? 0,
        activityCount: int.tryParse(json['activity_count'].toString()) ?? 0,
      );
}

class WeeklyStatModel {
  final int xp;
  final int studySeconds;
  final int activities;
  final int studyDays;
  final int quizCount;
  final int quizAvgScore;

  const WeeklyStatModel({
    required this.xp,
    required this.studySeconds,
    required this.activities,
    required this.studyDays,
    required this.quizCount,
    required this.quizAvgScore,
  });

  factory WeeklyStatModel.fromJson(Map<String, dynamic> json) => WeeklyStatModel(
        xp: int.tryParse(json['xp']?.toString() ?? '0') ?? 0,
        studySeconds: int.tryParse(json['study_seconds']?.toString() ?? '0') ?? 0,
        activities: int.tryParse(json['activities']?.toString() ?? '0') ?? 0,
        studyDays: int.tryParse(json['study_days']?.toString() ?? '0') ?? 0,
        quizCount: int.tryParse(json['quiz_count']?.toString() ?? '0') ?? 0,
        quizAvgScore: int.tryParse(json['quiz_avg_score']?.toString() ?? '0') ?? 0,
      );
}

class QuizStatModel {
  final double avgScore;
  final int totalQuizzes;

  const QuizStatModel({required this.avgScore, required this.totalQuizzes});

  factory QuizStatModel.fromJson(Map<String, dynamic> json) => QuizStatModel(
        avgScore: (json['avg_score'] ?? 0).toDouble(),
        totalQuizzes: int.tryParse(json['total_quizzes'].toString()) ?? 0,
      );
}

class SrsStatModel {
  final int total;
  final int graduated;

  const SrsStatModel({required this.total, required this.graduated});

  factory SrsStatModel.fromJson(Map<String, dynamic> json) => SrsStatModel(
        total: int.tryParse(json['total'].toString()) ?? 0,
        graduated: int.tryParse(json['graduated'].toString()) ?? 0,
      );
}

// ─── Dictionary / Jisho Online API Models ────────────────────────────────────

class DictionarySearchResult {
  final int total;
  final List<DictionaryEntry> data;
  final String source; // 'jisho'

  const DictionarySearchResult({
    required this.total,
    required this.data,
    required this.source,
  });

  factory DictionarySearchResult.fromJson(Map<String, dynamic> json) =>
      DictionarySearchResult(
        total: json['total'] ?? 0,
        data: (json['data'] as List<dynamic>? ?? [])
            .map((e) => DictionaryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: json['source'] ?? 'jisho',
      );
}

class DictionaryEntry {
  final String slug;
  final String? url;
  final bool isCommon;
  final List<String> tags;
  final List<String> jlpt;
  final List<JapaneseForm> japanese;
  final String word;
  final String reading;
  final List<DictionaryMeaning> meanings;
  final String? exampleReading;
  final String? exampleMeaningZh;

  const DictionaryEntry({
    required this.slug,
    this.url,
    required this.isCommon,
    required this.tags,
    required this.jlpt,
    required this.japanese,
    required this.word,
    required this.reading,
    required this.meanings,
    this.exampleReading,
    this.exampleMeaningZh,
  });
  factory DictionaryEntry.fromJson(Map<String, dynamic> json) {
    final japList = (json['japanese'] as List<dynamic>? ?? [])
        .map((e) => JapaneseForm.fromJson(e as Map<String, dynamic>))
        .toList();
    return DictionaryEntry(
      slug: json['slug'] ?? '',
      url: json['url'],
      isCommon: json['is_common'] ?? false,
      tags: List<String>.from(json['tags'] ?? []),
      jlpt: List<String>.from(json['jlpt'] ?? []),
      japanese: japList,
      word: json['word'] ?? (japList.isNotEmpty ? (japList[0].word ?? '') : ''),
      reading: json['reading'] ?? (japList.isNotEmpty ? (japList[0].reading ?? '') : ''),
      meanings: (json['meanings'] as List<dynamic>? ?? [])
          .map((e) => DictionaryMeaning.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 英文释义列表（Jisho 原始数据）
  List<String> get allEnglishDefinitions =>
      meanings.expand((m) => m.englishDefinitions).toList();

  String get displayWord => word.isNotEmpty ? word : (japanese.isNotEmpty ? (japanese[0].word ?? slug) : slug);
  String get displayReading => japanese.isNotEmpty ? (japanese[0].reading ?? reading) : reading;
  String get jishoUrl => 'https://jisho.org/word/${Uri.encodeComponent(slug)}';
}

class JapaneseForm {
  final String? word;
  final String? reading;

  const JapaneseForm({this.word, this.reading});

  factory JapaneseForm.fromJson(Map<String, dynamic> json) =>
      JapaneseForm(word: json['word'], reading: json['reading']);
}

class DictionaryMeaning {
  final List<String> partsOfSpeech;
  final List<String> englishDefinitions;
  final List<String> chineseDefinitions; // 后端返回中文时填充，否则为空
  final List<String> tags;
  final List<String> info;

  const DictionaryMeaning({
    required this.partsOfSpeech,
    required this.englishDefinitions,
    this.chineseDefinitions = const [],
    required this.tags,
    required this.info,
  });

  factory DictionaryMeaning.fromJson(Map<String, dynamic> json) => DictionaryMeaning(
        partsOfSpeech: List<String>.from(json['parts_of_speech'] ?? []),
        englishDefinitions: List<String>.from(json['english_definitions'] ?? []),
        chineseDefinitions: List<String>.from(json['chinese_definitions'] ?? []),
        tags: List<String>.from(json['tags'] ?? []),
        info: List<String>.from(json['info'] ?? []),
      );

  /// 按语言取释义：zh 优先返回中文，无中文时 fallback 英文
  List<String> definitions(String lang) {
    if (lang == 'zh' && chineseDefinitions.isNotEmpty) return chineseDefinitions;
    return englishDefinitions;
  }

  /// 词性的中文显示（Jisho 词性为英文，映射常用词性）
  String get posZh {
    const map = {
      'noun': '名词',
      'verb': '动词',
      'adjective': '形容词',
      'adverb': '副词',
      'particle': '助词',
      'conjunction': '接续词',
      'interjection': '感叹词',
      'suffix': '接尾词',
      'prefix': '接头词',
      'expression': '表达',
      'i-adjective': 'い形容词',
      'na-adjective': 'な形容词',
      'suru verb': 'する动词',
      'Ichidan verb': '一段动词',
      'Godan verb': '五段动词',
      'Transitive verb': '他动词',
      'Intransitive verb': '自动词',
    };
    if (partsOfSpeech.isEmpty) return '';
    final pos = partsOfSpeech.first;
    for (final entry in map.entries) {
      if (pos.toLowerCase().contains(entry.key.toLowerCase())) return entry.value;
    }
    return pos;
  }
}

