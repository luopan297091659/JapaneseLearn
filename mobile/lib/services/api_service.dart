import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/models.dart';

// ─── 简单内存缓存 ─────────────────────────────────────────────────────────────

class _CacheEntry {
  final dynamic data;
  final DateTime expiry;
  _CacheEntry(this.data, Duration ttl) : expiry = DateTime.now().add(ttl);
  bool get isValid => DateTime.now().isBefore(expiry);
}

class _MemCache {
  final _store = <String, _CacheEntry>{};

  dynamic get(String key) {
    final e = _store[key];
    if (e == null || !e.isValid) { _store.remove(key); return null; }
    return e.data;
  }

  void set(String key, dynamic data, Duration ttl) {
    _store[key] = _CacheEntry(data, ttl);
  }

  void invalidate(String prefix) {
    _store.removeWhere((k, _) => k.startsWith(prefix));
  }

  void remove(String key) => _store.remove(key);

  void clear() => _store.clear();
}

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio;
  final _cache = _MemCache();

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    // 允许自签名证书（服务器使用自签名 HTTPS 时必须）
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    };

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'access_token');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh token
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            handler.resolve(await _dio.fetch(error.requestOptions));
            return;
          }
        }
        handler.next(error);
      },
    ));
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return false;
      final res = await _dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      await _storage.write(key: 'access_token', value: res.data['accessToken']);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── 音频代理下载（绕过自签名证书，ExoPlayer 不走 Dio）─────────────────────
  /// 通过 Dio（已配置忽略自签名证书）将音频下载到本地临时文件，返回本地路径。
  /// 同一 URL 会缓存到同一文件，避免重复下载。
  Future<String> downloadToTempFile(String url) async {
    final dir = await getTemporaryDirectory();
    // 用 URL hash 作文件名，保留扩展名
    final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.mp3';
    final fileName = 'audio_${url.hashCode.abs()}$ext';
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) return file.path;  // 已缓存直接返回
    await _dio.download(url, file.path);
    return file.path;
  }

  // ─── Auth ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String level = 'N5',
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'username': username,
      'email': email,
      'password': password,
      'level': level,
    });
    await _saveTokens(res.data);
    return res.data;
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    await _saveTokens(res.data);
    return res.data;
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    if (data['accessToken'] != null) {
      await _storage.write(key: 'access_token', value: data['accessToken']);
    }
    if (data['refreshToken'] != null) {
      await _storage.write(key: 'refresh_token', value: data['refreshToken']);
    }
  }

  Future<UserModel> getMe() async {
    const key = 'me';
    final cached = _cache.get(key);
    if (cached != null) return cached as UserModel;
    final res = await _dio.get('/auth/me');
    final user = UserModel.fromJson(res.data['user']);
    _cache.set(key, user, AppConfig.cacheTtlShort);
    return user;
  }

  /// 更新用户设置（daily_goal_minutes / notification_enabled / level 等）
  Future<UserModel> updateProfile({
    int? dailyGoalMinutes,
    bool? notificationEnabled,
    String? level,
    String? username,
  }) async {
    _cache.remove('me');
    final res = await _dio.put('/users/profile', data: {
      if (dailyGoalMinutes  != null) 'daily_goal_minutes':   dailyGoalMinutes,
      if (notificationEnabled != null) 'notification_enabled': notificationEnabled,
      if (level    != null) 'level':    level,
      if (username != null) 'username': username,
    });
    return UserModel.fromJson(res.data);
  }

  /// 修改密码
  Future<void> changePassword(String currentPassword, String newPassword) async {
    await _dio.put('/users/change-password', data: {
      'currentPassword': currentPassword,
      'newPassword':     newPassword,
    });
  }

  // logout 时清缓存
  Future<void> logout() async {
    _cache.clear();
    await _storage.deleteAll();
  }

  /// 清除所有内存缓存（管理员发布更新后调用）
  void invalidateCache() => _cache.clear();

  /// 通用 GET 请求（用于同步版本检测等场景）
  Future<Map<String, dynamic>> get(String path) async {
    final resp = await _dio.get(path);
    return Map<String, dynamic>.from(resp.data);
  }

  // ─── Vocabulary ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getVocabulary({
    String? level,
    String? category,
    String? query,
    int page = 1,
    int limit = 20,
  }) async {
    final key = 'vocab:${level}:${category}:${query}:$page:$limit';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/vocabulary', queryParameters: {
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      if (query != null) 'q': query,
      'page': page,
      'limit': limit,
    });
    final result = {
      'total': res.data['total'],
      'data': (res.data['data'] as List).map((e) => VocabularyModel.fromJson(e)).toList(),
    };
    _cache.set(key, result, AppConfig.cacheTtlMedium);
    return result;
  }

  Future<List<VocabularyModel>> getVocabularyByLevel(String level) async {
    final res = await _dio.get('/vocabulary/level/$level');
    return (res.data as List).map((e) => VocabularyModel.fromJson(e)).toList();
  }

  Future<VocabularyModel> getVocabularyById(String id) async {
    final res = await _dio.get('/vocabulary/$id');
    return VocabularyModel.fromJson(res.data);
  }

  // ─── Dictionary ───────────────────────────────────────────────────────────
  /// Search using Jisho API (proxied through backend)
  /// Returns list of DictionaryEntry
  Future<DictionarySearchResult> searchDictionary(String query, {int page = 1, String lang = 'zh'}) async {
    final res = await _dio.get('/dictionary/search', queryParameters: {
      'q': query,
      'page': page,
      'lang': lang,
    });
    return DictionarySearchResult.fromJson(res.data);
  }

  Future<Map<String, dynamic>> getDictionaryWordDetail(String word) async {
    final res = await _dio.get('/dictionary/word/${Uri.encodeComponent(word)}');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> kanjiDetail(String char) async {
    final res = await _dio.get('/dictionary/kanji/${Uri.encodeComponent(char)}');
    return res.data as Map<String, dynamic>;
  }

  // ─── Grammar ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getGrammarLessons({String? level, int page = 1}) async {
    final key = 'grammar:${level}:$page';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/grammar', queryParameters: {
      if (level != null) 'level': level,
      'page': page,
    });
    final result = {
      'total': res.data['total'],
      'data': (res.data['data'] as List).map((e) => GrammarLessonModel.fromJson(e)).toList(),
    };
    _cache.set(key, result, AppConfig.cacheTtlMedium);
    return result;
  }

  Future<GrammarLessonModel> getGrammarLesson(String id) async {
    final res = await _dio.get('/grammar/$id');
    return GrammarLessonModel.fromJson(res.data);
  }

  // ─── SRS ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDueCards({int limit = 20}) async {
    final res = await _dio.get('/srs/due', queryParameters: {'limit': limit});
    return {
      'due_count': res.data['due_count'],
      'cards': (res.data['cards'] as List).map((e) => SrsCardModel.fromJson(e)).toList(),
    };
  }

  Future<Map<String, dynamic>> getSrsStats() async {
    const key = 'srs:stats';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/srs/stats');
    _cache.set(key, res.data as Map<String, dynamic>, AppConfig.cacheTtlShort);
    return res.data;
  }

  /// 查询某词汇是否在当前用户的 SRS 卡组，返回卡片 Map（含 id），不存在则返回 null
  Future<Map<String, dynamic>?> getSrsCardByRef(String refId) async {
    try {
      final res = await _dio.get('/srs/card/$refId');
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  // SRS 写操作后手动清 stats 缓存
  Future<void> submitSrsReview(String cardId, int quality) async {
    await _dio.post('/srs/review', data: {'card_id': cardId, 'quality': quality});
    _cache.invalidate('srs:');
  }

  Future<void> addSrsCard(String refId, {String cardType = 'vocabulary'}) async {
    await _dio.post('/srs/add', data: {'ref_id': refId, 'card_type': cardType});
    _cache.invalidate('srs:');
  }

  // ─── Quiz ─────────────────────────────────────────────────────────────────
  Future<List<QuizQuestionModel>> generateQuiz({
    String level = 'N5',
    String quizType = 'vocabulary',
    int count = 10,
  }) async {
    final res = await _dio.get('/quiz/generate', queryParameters: {
      'level': level,
      'quiz_type': quizType,
      'count': count,
    });
    final raw = res.data;
    // 兼容后端返回格式: { questions: [...] } 或直接 [...]
    final list = (raw is Map ? raw['questions'] : raw) as List?;
    if (list == null || list.isEmpty) return [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => QuizQuestionModel.fromJson(e))
        .toList();
  }

  Future<Map<String, dynamic>> submitQuiz({
    required String level,
    required String quizType,
    required List<Map<String, dynamic>> answers,
    required int timeSpentSeconds,
  }) async {
    final res = await _dio.post('/quiz/submit', data: {
      'level': level,
      'quiz_type': quizType,
      'answers': answers,
      'time_spent_seconds': timeSpentSeconds,
    });
    return res.data;
  }

  // ─── Listening ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getListeningTracks({String? level, String? category, int page = 1}) async {
    final key = 'listening:${level}:${category}:$page';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/listening', queryParameters: {
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      'page': page,
    });
    _cache.set(key, res.data as Map<String, dynamic>, AppConfig.cacheTtlLong);
    return res.data;
  }

  // ─── News ─────────────────────────────────────────────────────────────────
  Future<List<NewsArticleModel>> getNews({String? difficulty, String? query, int page = 1}) async {
    final key = 'news:${difficulty}:${query}:$page';
    final cached = _cache.get(key);
    if (cached != null) return cached as List<NewsArticleModel>;
    final res = await _dio.get('/news', queryParameters: {
      if (difficulty != null) 'difficulty': difficulty,
      if (query != null) 'q': query,
      'page': page,
    });
    final list = (res.data['data'] as List).map((e) => NewsArticleModel.fromJson(e)).toList();
    _cache.set(key, list, AppConfig.cacheTtlLong);
    return list;
  }

  Future<NewsArticleModel> getNewsDetail(String id) async {
    final res = await _dio.get('/news/$id');
    return NewsArticleModel.fromJson(res.data);
  }

  // ─── Anki Import ────────────────────────────────────────────────────────────
  /// 客户端解析完成后，将卡片 JSON 批量提交到后端
  Future<Map<String, dynamic>> bulkImportVocabulary({
    required List<Map<String, dynamic>> cards,
    String deckName = 'Anki Import',
    String jlptLevel = 'N3',
    String partOfSpeech = 'other',
  }) async {
    final res = await _dio.post('/vocabulary/bulk', data: {
      'cards': cards,
      'deck_name': deckName,
      'jlpt_level': jlptLevel,
      'part_of_speech': partOfSpeech,
    });
    return res.data as Map<String, dynamic>;
  }

  /// 获取已导入的 Anki 牌组列表
  Future<List<Map<String, dynamic>>> getAnkiDecks() async {
    final res = await _dio.get('/anki/decks');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  // ─── Progress ─────────────────────────────────────────────────────────────
  Future<void> logActivity({
    required String activityType,
    String? refId,
    int durationSeconds = 0,
    double? score,
  }) async {
    await _dio.post('/progress/log', data: {
      'activity_type': activityType,
      if (refId != null) 'ref_id': refId,
      'duration_seconds': durationSeconds,
      if (score != null) 'score': score,
    });
  }

  Future<ProgressSummaryModel> getProgressSummary() async {
    final res = await _dio.get('/progress/summary');
    return ProgressSummaryModel.fromJson(res.data);
  }
}

// Global instance
final apiService = ApiService();
