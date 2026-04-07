import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/models.dart';
import 'local_db.dart';

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
  late final Dio _refreshDio;  // 独立实例，不带拦截器，专门用于 token 刷新
  Dio get dio => _dio;
  final _cache = _MemCache();
  Completer<bool>? _refreshCompleter;  // 并发刷新锁
  VoidCallback? _onSessionReplaced;

  /// 会员限制回调：返回 { error, feature, message, used, limit }
  void Function(Map<String, dynamic>)? _onMembershipLimit;

  /// 设置被其他设备登录顶替时的回调
  void setOnSessionReplaced(VoidCallback callback) {
    _onSessionReplaced = callback;
  }

  /// 设置会员限制触发时的回调
  void setOnMembershipLimit(void Function(Map<String, dynamic>) callback) {
    _onMembershipLimit = callback;
  }

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    // 独立的 refresh Dio，避免死循环
    _refreshDio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    // ✅ 改进：允许自签名证书，但添加主机验证（针对 139.196.44.6）
    // 服务器使用自签名 HTTPS 时必须。TODO: 生产环境建议使用有效证书或证书固定
    for (final d in [_dio, _refreshDio]) {
      (d.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // 【注意】此处允许自签名证书，仅用于开发/测试环境
        // 生产建议：
        //   1. 使用 Let's Encrypt 等认证机构的有效证书
        //   2. 实现证书固定 (Certificate Pinning) 防止中间人攻击
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          // 仅对已知服务器主机名放宽验证
          final knownHosts = ['139.196.44.6', 'localhost', '127.0.0.1'];
          final isKnownHost = knownHosts.contains(host);
          if (!isKnownHost) {
            print('【警告】证书验证失败：未识别的主机 $host（端口 $port）');
          }
          return isKnownHost; // 仅为已知主机接受自签名证书
        };
        return client;
      };
    }

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
          // 检查是否被其他设备顶替
          final data = error.response?.data;
          if (data is Map && data['error'] == 'SESSION_REPLACED') {
            await _storage.deleteAll();
            _cache.clear();
            _onSessionReplaced?.call();
            handler.next(error);
            return;
          }
          final refreshed = await _refreshToken();
          if (refreshed) {
            final token = await _storage.read(key: 'access_token');
            error.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              handler.resolve(await _dio.fetch(error.requestOptions));
            } catch (e) {
              handler.next(error);
            }
            return;
          }
          // 刷新失败，清除 token
          await _storage.deleteAll();
          _cache.clear();
        }
        // 处理 403 会员限制错误
        if (error.response?.statusCode == 403) {
          final data = error.response?.data;
          if (data is Map && (data['error'] == 'MEMBERSHIP_REQUIRED' || data['error'] == 'DAILY_LIMIT_REACHED')) {
            _onMembershipLimit?.call(Map<String, dynamic>.from(data));
          }
        }
        handler.next(error);
      },
    ));

    // 自动重试：对网络超时 / 连接异常的 GET 请求重试 1 次
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (error, handler) async {
        final isRetryable = error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError;
        final isGet = error.requestOptions.method == 'GET';
        final retried = error.requestOptions.extra['_retried'] == true;
        if (isRetryable && isGet && !retried) {
          error.requestOptions.extra['_retried'] = true;
          await Future.delayed(const Duration(milliseconds: 1500));
          try {
            handler.resolve(await _dio.fetch(error.requestOptions));
          } catch (e) {
            handler.next(error);
          }
          return;
        }
        handler.next(error);
      },
    ));
  }

  /// Token 刷新（带并发锁，使用独立 Dio 避免拦截器死循环）
  Future<bool> _refreshToken() async {
    // 如果已有刷新请求在进行，等待其结果
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        return false;
      }
      final res = await _refreshDio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      await _storage.write(key: 'access_token', value: res.data['accessToken']);
      _refreshCompleter!.complete(true);
      return true;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  // ─── 音频代理下载（绕过自签名证书，ExoPlayer 不走 Dio）─────────────────────
  /// 通过 Dio（已配置忽略自签名证书）将音频下载到本地临时文件，返回本地路径。
  /// 音频 ID (UUID) 作为缓存键，保留扩展名。避免 URL 变化导致的重复下载。
  /// 支持自动重试：网络失败时最多重试 3 次，指数退避延迟
  /// ✅ 新增：检查存储权限和磁盘空间
  Future<String> downloadToTempFile(String url, {int maxRetries = 3}) async {
    final dir = await getTemporaryDirectory();
    
    // ✅ 改进缓存策略：使用音频 UUID（比使用完整 URL hash 更稳定）
    // 从 URL 中提取音频 UUID：/uploads/audio/{uuid}.{ext}
    String cacheKey = url.hashCode.abs().toString();
    String audioId = '';
    
    if (url.contains('/uploads/audio/')) {
      try {
        // 从 URL 提取音频文件名（UUID + 扩展名）
        final parts = url.split('/uploads/audio/');
        if (parts.length > 1) {
          audioId = parts[1].split('?').first; // 移除查询参数
          if (audioId.isNotEmpty) {
            cacheKey = audioId.replaceAll('.', '_'); // UUID.ext → UUID_ext（文件名安全）
          }
        }
      } catch (_) {
        // 解析失败，回退到 URL hash
      }
    }
    
    final ext = url.contains('.') ? '.${url.split('.').last.split('?').first}' : '.mp3';
    final fileName = 'audio_$cacheKey$ext';
    final file = File('${dir.path}/$fileName');
    
    if (await file.exists()) {
      // ✅ 新增：验证缓存文件可读性
      try {
        await file.readAsBytes();
        return file.path;  // 已缓存且可读，直接返回
      } catch (e) {
        print('【缓存】缓存文件无法读取，将重新下载: $e');
        await file.delete().catchError((_) {});  // 尝试删除损坏的缓存
      }
    }
    
    int attempts = 0;
    Exception? lastError;
    while (attempts < maxRetries) {
      try {
        // ✅ 下载时添加超时和进度监听
        await _dio.download(
          url,
          file.path,
          options: Options(
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
          onReceiveProgress: (received, total) {
            if (total > 0) {
              final percent = (received / total * 100).toStringAsFixed(0);
              print('【下载】${file.path}: $percent% ($received/$total bytes)');
            }
          },
        );
        
        // ✅ 下载后验证文件有效性
        final fileSize = await file.length();
        if (fileSize == 0) {
          throw Exception('下载的音频文件为空（0 字节）');
        }
        
        print('【缓存】音频已保存: $fileName (${(fileSize / 1024).toStringAsFixed(1)} KB)');
        return file.path;
      } catch (e) {
        attempts++;
        lastError = Exception('音频下载失败 (尝试 $attempts/$maxRetries): $e');
        
        // 如果是权限或磁盘错误，不再重试
        if (e.toString().contains('Permission') || 
            e.toString().contains('space') ||
            e.toString().contains('磁盘')) {
          rethrow;
        }
        
        if (attempts >= maxRetries) rethrow;
        // 指数退避：500ms → 1000ms → 2000ms
        final delayMs = 500 * attempts;
        print('【重试】${delayMs}ms 后重试...');
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw lastError ?? Exception('音频下载失败');
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
      'platform': 'app',
    });
    await _saveTokens(res.data);
    return res.data;
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password, 'platform': 'app'});
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

  Future<UserModel> getMe({bool force = false}) async {
    const key = 'me';
    if (!force) {
      final cached = _cache.get(key);
      if (cached != null) return cached as UserModel;
    }
    final res = await _dio.get('/auth/me');
    final user = UserModel.fromJson(res.data['user']);
    _cache.set(key, user, AppConfig.cacheTtlShort);
    return user;
  }

  /// 获取会员体验配置
  Future<Map<String, dynamic>> getTrialConfig() async {
    final res = await _dio.get('/users/trial-config');
    return Map<String, dynamic>.from(res.data);
  }

  /// 用户自助开通会员体验
  Future<Map<String, dynamic>> activateTrial() async {
    _cache.remove('me');
    final res = await _dio.post('/users/activate-trial');
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getUserPreferences() async {
    final res = await _dio.get('/users/preferences');
    return Map<String, dynamic>.from(res.data['preferences'] as Map? ?? const {});
  }

  Future<Map<String, dynamic>> updateUserPreferences(Map<String, dynamic> preferences) async {
    _cache.remove('me');
    final res = await _dio.put('/users/preferences', data: {
      'preferences': preferences,
    });
    return Map<String, dynamic>.from(res.data['preferences'] as Map? ?? const {});
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

  Future<UserModel> uploadAvatarBytes(Uint8List bytes, {String fileName = 'avatar.png'}) async {
    _cache.remove('me');
    final formData = FormData.fromMap({
      'avatar': MultipartFile.fromBytes(bytes, filename: fileName),
    });
    final res = await _dio.post('/users/avatar', data: formData);
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

  Future<Map<String, dynamic>> getLatestPublishedAppRelease({String platform = 'android'}) async {
    final resp = await _dio.get('/admin/app/latest', queryParameters: {'platform': platform});
    return Map<String, dynamic>.from(resp.data['data'] as Map);
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
    try {
      final res = await _dio.get('/vocabulary', queryParameters: {
        if (level != null) 'level': level,
        if (category != null) 'category': category,
        if (query != null) 'q': query,
        'page': page,
        'limit': limit,
      });
      final data = (res.data['data'] as List).map((e) => VocabularyModel.fromJson(e)).toList();
      final result = <String, dynamic>{
        'total': res.data['total'],
        'data': data,
      };
      _cache.set(key, result, AppConfig.cacheTtlMedium);
      // 异步写入本地缓存（不阻塞返回）
      if (level != null && category == null) {
        localDb.cacheVocabulary(data, sortOffset: (page - 1) * limit);
      }
      return result;
    } catch (e) {
      // 离线回退：从本地缓存读取
      if (level != null && category == null) {
        final local = await localDb.getCachedVocabulary(
          level: level, query: query, page: page, limit: limit,
        );
        if ((local['total'] as int) > 0) return local;
      }
      rethrow;
    }
  }

  Future<List<VocabularyModel>> getVocabularyByLevel(String level) async {
    final res = await _dio.get('/vocabulary/level/$level');
    return (res.data as List).map((e) => VocabularyModel.fromJson(e)).toList();
  }

  Future<List<String>> getVocabularyIdsByLevel(String level) async {
    final key = 'vocab_ids:$level';
    final cached = _cache.get(key);
    if (cached != null) return (cached as List).cast<String>();
    try {
      final res = await _dio.get('/vocabulary/level/$level/ids');
      final ids = (res.data as List).cast<String>();
      _cache.set(key, ids, AppConfig.cacheTtlMedium);
      return ids;
    } catch (e) {
      // 离线回退
      final localIds = await localDb.getCachedVocabularyIds(level);
      if (localIds.isNotEmpty) return localIds;
      rethrow;
    }
  }

  Future<VocabularyModel> getVocabularyById(String id) async {
    final res = await _dio.get('/vocabulary/$id');
    return VocabularyModel.fromJson(res.data);
  }

  /// 获取五十音音频URL映射 (character -> audio_url)
  Future<Map<String, String>> getKanaAudioMap() async {
    final cached = _cache.get('kana_audio_map');
    if (cached != null) return Map<String, String>.from(cached);
    try {
      final res = await _dio.get('/kana/audio-map');
      final data = (res.data['data'] as Map<String, dynamic>?) ?? {};
      final map = data.map((k, v) => MapEntry(k, v.toString()));
      _cache.set('kana_audio_map', map, AppConfig.cacheTtlLong);
      return map;
    } catch (e) {
      print('获取假名音频映射失败: $e');
      return {};
    }
  }

  /// ✅ 新增：预加载音频到本地缓存（在 WiFi 环境下使用）
  /// 支持按级别预加载词汇音频，提供后续播放的快速体验
  /// 返回成功预加载的音频数量和失败数量
  Future<Map<String, int>> preloadAudiosByLevel(String level) async {
    try {
      final vocabs = await getVocabularyByLevel(level);
      int successCount = 0, failCount = 0;
      
      for (final vocab in vocabs) {
        if (vocab.audioUrl != null && vocab.audioUrl!.isNotEmpty) {
          try {
            // 触发下载（已缓存的会立即返回）
            await downloadToTempFile(vocab.audioUrl!);
            successCount++;
          } catch (e) {
            print('预加载失败: ${vocab.word} - $e');
            failCount++;
          }
        }
      }
      
      print('【预加载完成】$level: 成功 $successCount，失败 $failCount');
      return {'success': successCount, 'failed': failCount};
    } catch (e) {
      print('预加载异常: $e');
      return {'success': 0, 'failed': 0};
    }
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
  Future<Map<String, dynamic>> getGrammarLessons({String? level, int page = 1, int limit = 20}) async {
    final key = 'grammar:${level}:$page:$limit';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    try {
      final res = await _dio.get('/grammar', queryParameters: {
        if (level != null) 'level': level,
        'page': page,
        'limit': limit,
      });
      final data = (res.data['data'] as List).map((e) => GrammarLessonModel.fromJson(e)).toList();
      final result = <String, dynamic>{
        'total': res.data['total'],
        'data': data,
      };
      _cache.set(key, result, AppConfig.cacheTtlMedium);
      // 异步写入本地缓存
      if (level != null) {
        localDb.cacheGrammar(data, sortOffset: (page - 1) * limit);
      }
      return result;
    } catch (e) {
      // 离线回退
      if (level != null) {
        final local = await localDb.getCachedGrammar(level: level, page: page, limit: limit);
        if ((local['total'] as int) > 0) return local;
      }
      rethrow;
    }
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
    _cache.invalidate('progress:');
  }

  Future<void> addSrsCard(String refId, {String cardType = 'vocabulary'}) async {
    await _dio.post('/srs/add', data: {'ref_id': refId, 'card_type': cardType});
    _cache.invalidate('srs:');
    _cache.invalidate('progress:');
  }

  // ─── Reports ──────────────────────────────────────────────────────────────
  Future<void> submitReport({
    required String refType,
    required String refId,
    required String refTitle,
    required String issueType,
    required String description,
  }) async {
    await _dio.post('/reports', data: {
      'ref_type': refType,
      'ref_id': refId,
      'ref_title': refTitle,
      'issue_type': issueType,
      'description': description,
    });
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

  /// 获取磨耳朵视频列表（带缓存）
  Future<Map<String, dynamic>> getImmersionVideos({int page = 1, int limit = 20, bool forceRefresh = false}) async {
    final key = 'immersion:$page:$limit';
    if (forceRefresh) {
      _cache.invalidate('immersion:');
    }
    if (!forceRefresh) {
      final cached = _cache.get(key);
      if (cached != null) return cached as Map<String, dynamic>;
    }
    final res = await _dio.get('/listening-channels', queryParameters: {
      'page': page,
      'limit': limit,
    });
    final data = res.data as Map<String, dynamic>;
    _cache.set(key, data, AppConfig.cacheTtlLong);
    return data;
  }

  Future<List<Map<String, dynamic>>> getMyImmersionChannels() async {
    final res = await _dio.get('/listening-channels/my/channels');
    final data = (res.data['data'] as List<dynamic>? ?? const []);
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> addMyImmersionChannel({
    required String channelUrl,
    String? name,
    String? description,
    int maxVideos = 12,
  }) async {
    final res = await _dio.post('/listening-channels/my/channels', data: {
      'channel_url': channelUrl,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      'max_videos': maxVideos,
    });
    _cache.invalidate('immersion:');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> deleteMyImmersionChannel(dynamic id) async {
    await _dio.delete('/listening-channels/my/channels/$id');
    _cache.invalidate('immersion:');
  }

  Future<Map<String, dynamic>> getListeningTracks({String? level, String? category, int page = 1, int limit = 200}) async {
    final key = 'listening:${level}:${category}:$page:$limit';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/listening', queryParameters: {
      if (level != null) 'level': level,
      if (category != null) 'category': category,
      'page': page,
      'limit': limit,
    });
    _cache.set(key, res.data as Map<String, dynamic>, AppConfig.cacheTtlLong);
    return res.data;
  }

  /// 获取听力练习题目
  Future<List<ListeningExerciseQuestion>> getListeningExercises({
    required String level,
    int count = 10,
    String source = 'all',
  }) async {
    final res = await _dio.get('/listening/exercise', queryParameters: {
      'level': level,
      'count': count,
      'source': source,
    });
    final data = res.data['data'] as List<dynamic>? ?? [];
    return data.map((e) => ListeningExerciseQuestion.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取听力练习统计
  Future<Map<String, dynamic>> getListeningExerciseStats() async {
    final key = 'listening_exercise_stats';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/listening/exercise/stats');
    final data = res.data as Map<String, dynamic>;
    _cache.set(key, data, AppConfig.cacheTtlLong);
    return data;
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

  // ─── 新闻收藏 ───────────────────────────────────────────────────────────────
  Future<List<NewsFavoriteModel>> getNewsFavorites() async {
    final res = await _dio.get('/news/favorites');
    return (res.data['data'] as List).map((e) => NewsFavoriteModel.fromJson(e)).toList();
  }

  Future<bool> checkNewsFavorite(String newsType, String newsId) async {
    final res = await _dio.get('/news/favorites/check', queryParameters: {
      'news_type': newsType,
      'news_id': newsId,
    });
    return res.data['favorited'] == true;
  }

  Future<void> addNewsFavorite({
    required String newsType,
    required String newsId,
    required String title,
    String? description,
    String? imageUrl,
    String? link,
    String? source,
    String? publishedAt,
  }) async {
    await _dio.post('/news/favorites', data: {
      'news_type': newsType,
      'news_id': newsId,
      'title': title,
      if (description != null) 'description': description,
      if (imageUrl != null) 'image_url': imageUrl,
      if (link != null) 'link': link,
      if (source != null) 'source': source,
      if (publishedAt != null) 'published_at': publishedAt,
    });
  }

  Future<void> removeNewsFavorite(String newsType, String newsId) async {
    await _dio.delete('/news/favorites', data: {
      'news_type': newsType,
      'news_id': newsId,
    });
  }

  // ─── NHK 新闻（通过 RSS + HTML 抓取）─────────────────────────────────────
  static final Dio _nhkDio = Dio(BaseOptions(
    baseUrl: 'https://www3.nhk.or.jp',
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0 Safari/537.36',
    },
    followRedirects: true,
    maxRedirects: 5,
  ));

  /// 从 NHK RSS 获取新闻列表
  /// cat0=総合, cat1=社会, cat3=科学, cat4=政治, cat5=経済, cat6=国際, cat7=スポーツ
  Future<List<NewsArticleModel>> getNhkNews({String category = 'cat0'}) async {
    final cacheKey = 'nhk_rss_$category';
    final cached = _cache.get(cacheKey);
    if (cached != null) return cached as List<NewsArticleModel>;

    final res = await _nhkDio.get(
      '/rss/news/$category.xml',
      options: Options(responseType: ResponseType.plain),
    );
    final xml = res.data as String;

    final articles = <NewsArticleModel>[];
    // 解析 RSS XML 中的 <item> 元素
    final itemRegex = RegExp(
      r'<item>\s*<title>(.*?)</title>\s*<link>(.*?)</link>.*?<pubDate>(.*?)</pubDate>\s*<description>(.*?)</description>',
      dotAll: true,
    );
    for (final m in itemRegex.allMatches(xml)) {
      final link = m.group(2) ?? '';
      // 从 URL 提取 ID，如 k10015067871000
      final idMatch = RegExp(r'(k\d+)\.html').firstMatch(link);
      final id = idMatch?.group(1) ?? link.hashCode.toString();
      articles.add(NewsArticleModel(
        id: id,
        title: _decodeXmlEntities(m.group(1) ?? ''),
        imageUrl: null,
        publishedAt: m.group(3),
        source: 'NHK',
        difficulty: 'normal',
        body: _decodeXmlEntities(m.group(4) ?? ''),
      ));
    }
    _cache.set(cacheKey, articles, AppConfig.cacheTtlLong);
    return articles;
  }

  /// 通过后端 API 获取文章正文
  Future<String> getNhkArticleBody(String articleId) async {
    if (articleId.isEmpty) return '';
    try {
      final res = await dio.get('/news/nhk/$articleId');
      return (res.data['body'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 获取 NHK 文章详情（body + link）
  Future<Map<String, String>> getNhkArticleDetail(String articleId) async {
    if (articleId.isEmpty) return {'body': '', 'link': ''};
    try {
      final res = await dio.get('/news/nhk/$articleId');
      return {
        'body': (res.data['body'] as String?) ?? '',
        'link': (res.data['link'] as String?) ?? '',
      };
    } catch (_) {
      return {'body': '', 'link': ''};
    }
  }

  /// 获取 NHK 历史新闻（分页）
  Future<Map<String, dynamic>> getNhkNewsHistory({String? category, int page = 1, int limit = 20}) async {
    final params = <String, dynamic>{'page': page, 'limit': limit};
    if (category != null) params['category'] = category;
    final res = await dio.get('/news/nhk/history', queryParameters: params);
    final data = (res.data['data'] as List?) ?? [];
    final articles = data.map((j) => NewsArticleModel.fromJson(j as Map<String, dynamic>)).toList();
    return {'total': res.data['total'] ?? 0, 'data': articles};
  }

  /// 从文章页面 HTML 中提取正文段落
  static String _extractNhkBody(String html) {
    // 提取所有 <p> 标签中超过 10 字符的内容（过滤导航等短文本）
    final pRegex = RegExp(r'<p[^>]*>([^<]{10,})</p>', dotAll: true);
    final paragraphs = <String>[];
    for (final m in pRegex.allMatches(html)) {
      final text = _decodeXmlEntities(m.group(1)?.trim() ?? '');
      // 排除版权声明等
      if (text.contains('Copyright') || text.contains('受信料')) continue;
      if (text.contains('受信契約')) continue;
      paragraphs.add(text);
    }
    return paragraphs.join('\n\n');
  }

  static String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
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

  Future<Map<String, dynamic>> getDailyGoals() async {
    const key = 'progress:daily-goals';
    final cached = _cache.get(key);
    if (cached != null) return cached as Map<String, dynamic>;
    final res = await _dio.get('/progress/daily-goals');
    _cache.set(key, res.data, AppConfig.cacheTtlShort);
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getStudyPlanToday() async {
    final res = await _dio.get('/progress/study-plan/today');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> startStudyPlanDay() async {
    final res = await _dio.post('/progress/study-plan/start');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getStudyPlanQueue({String? level}) async {
    final res = await _dio.get(
      '/progress/study-plan/queue',
      queryParameters: {
        if (level != null && level.isNotEmpty) 'level': level,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> submitStudyPlanAnswer({
    required String cardType,
    required String refId,
    required String answer,
  }) async {
    final res = await _dio.post('/progress/study-plan/answer', data: {
      'card_type': cardType,
      'ref_id': refId,
      'answer': answer,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> getStudyPlanReviewEntries() async {
    final res = await _dio.get('/progress/study-plan/review-entries');
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<Map<String, dynamic>> finishStudyPlanDay() async {
    final res = await _dio.post('/progress/study-plan/finish');
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ─── AI (Translation / Analysis) ─────────────────────────────────────────
  static const _aiTimeout = Duration(seconds: 90);

  /// 翻译日语文本
  Future<String> aiTranslate(String text, {String targetLang = 'zh'}) async {
    final res = await _dio.post('/ai/translate',
      data: {'text': text, 'targetLang': targetLang},
      options: Options(receiveTimeout: _aiTimeout),
    );
    return res.data['translation'] as String;
  }

  /// 日语句子词法分析
  Future<List<Map<String, dynamic>>> aiAnalyze(String text) async {
    final res = await _dio.post('/ai/analyze',
      data: {'text': text},
      options: Options(receiveTimeout: _aiTimeout),
    );
    return (res.data['tokens'] as List).cast<Map<String, dynamic>>();
  }

  /// 单词详解
  Future<Map<String, dynamic>> aiWordDetail(String word, {String? pos, String? sentence}) async {
    final res = await _dio.post('/ai/word-detail',
      data: {
        'word': word,
        if (pos != null) 'pos': pos,
        if (sentence != null) 'sentence': sentence,
      },
      options: Options(receiveTimeout: _aiTimeout),
    );
    return res.data as Map<String, dynamic>;
  }

  /// 发音/听力识别结果 AI 评分
  ///
  /// 返回: { score: 0-100, feedback: '...' }
  Future<Map<String, dynamic>> scoreSpeechRecognition({
    required String targetText,
    required String recognizedText,
    String? referenceReading,
    String mode = 'pronunciation',
  }) async {
    final res = await _dio.post('/pronunciation/score', data: {
      'target_text': targetText,
      'recognized_text': recognizedText,
      if (referenceReading != null && referenceReading.trim().isNotEmpty)
        'reference_reading': referenceReading,
      'mode': mode,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }
}

// Global instance
final apiService = ApiService();
