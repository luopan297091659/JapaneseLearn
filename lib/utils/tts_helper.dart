import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'dart:convert';
import '../config/app_config.dart';
import 'audio_manager.dart';
import 'japanese_text_utils.dart';

/// 创建支持自签名证书的 Dio 实例
Dio _createTrustingDio() {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) {
      const knownHosts = ['139.196.44.6', 'localhost', '127.0.0.1'];
      return knownHosts.contains(host);
    };
    return client;
  };
  return dio;
}

/// 全局 TTS 辅助工具，确保引擎正确初始化并提供诊断信息

class TtsHelper {
  /// 智能播放日语例句：优先本地音频→本地TTS→后端Kokoro
  /// [audioUrl]：服务器已有音频文件URL（可为null）
  /// [text]：要朗读的日语文本
  /// [slow]：慢速播放
  /// [onComplete]：播放完成回调
  static Future<void> playJapaneseSmart({
    String? audioUrl,
    required String text,
    FlutterTts? tts,
    bool slow = false,
    void Function()? onComplete,
  }) async {
    // 1. 优先本地/服务器音频
    if (audioUrl != null && audioUrl.isNotEmpty) {
      try {
        final player = AudioPlayer();
        await AudioManager.instance.requestPlay(player);
        String? localPath;
        if (audioUrl.startsWith('/uploads/')) {
          // 相对路径，拼接服务器地址后下载到本地临时文件
          final fullUrl = AppConfig.serverRoot + audioUrl;
          final dir = await getTemporaryDirectory();
          final fileName = audioUrl.split('/').last;
          localPath = '${dir.path}/$fileName';
          if (!File(localPath).existsSync()) {
            final dio = _createTrustingDio();
            final resp = await dio.get(
              fullUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            await File(localPath).writeAsBytes(resp.data);
          }
        }
        if (localPath != null && File(localPath).existsSync()) {
          await player.setFilePath(localPath);
        } else if (audioUrl.startsWith('http')) {
          await player.setUrl(audioUrl);
        } else {
          await player.setUrl(AppConfig.serverRoot + audioUrl);
        }
        await player.setVolume(1.0);
        await player.setSpeed(slow ? 0.5 : 1.0);
        // 先注册监听再播放，避免 await play() 阻塞导致 Android 卡死
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
            if (onComplete != null) onComplete();
          }
        }, onError: (e) {
          debugPrint('音频播放流错误: $e');
          player.dispose();
          if (onComplete != null) onComplete();
        });
        // play() 异步执行，捕获其错误防止卡死
        player.play().catchError((e) {
          debugPrint('音频play()失败: $e');
          player.dispose();
          if (onComplete != null) onComplete();
        });
        return;
      } catch (e) {
        debugPrint('音频播放失败，尝试TTS: $e');
      }
    }

    // 2. 本地TTS（有可用引擎）
    final ttsInst = tts ?? FlutterTts();
    try {
      await AudioManager.instance.requestTts(ttsInst);
      await configureForJapanese(ttsInst);
      await ttsInst.setVolume(1.0);
      await ttsInst.setSpeechRate(slow ? 0.25 : 0.5);
      ttsInst.setCompletionHandler(() {
        if (onComplete != null) onComplete();
      });
      final result = await ttsInst.speak(normalizeJapaneseTtsText(text));
      if (result == 1) return;
    } catch (e) {
      debugPrint('本地TTS失败: $e');
    }

    // TTS也失败，直接回调完成
    if (onComplete != null) onComplete();
  }

  /// 预缓存单个音频文件到本地（不播放），已缓存则跳过
  static Future<void> precacheAudioUrl(String audioUrl) async {
    if (audioUrl.isEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      final fileName = audioUrl.split('/').last;
      final localPath = '${dir.path}/$fileName';
      if (File(localPath).existsSync()) return;
      String fullUrl = audioUrl;
      if (audioUrl.startsWith('/uploads/')) {
        fullUrl = AppConfig.serverRoot + audioUrl;
      }
      final dio = _createTrustingDio();
      final resp = await dio.get(fullUrl,
          options: Options(responseType: ResponseType.bytes));
      if ((resp.data as List<int>).isNotEmpty) {
        await File(localPath).writeAsBytes(resp.data);
      }
    } catch (e) {
      debugPrint('预缓存音频失败: $e');
    }
  }

  /// 批量预缓存音频URL列表（后台逐个下载，不阻塞UI）
  static void precacheAudioUrls(Iterable<String> urls) {
    () async {
      for (final url in urls) {
        if (url.isNotEmpty) await precacheAudioUrl(url);
      }
    }();
  }

  TtsHelper._();
  static final TtsHelper instance = TtsHelper._();

  FlutterTts? _tts;
  bool _initialized = false;
  bool _engineAvailable = false;
  String? _diagInfo;
  List<String> _availableLanguages = [];
  bool _japaneseAvailable = false;

  /// 获取共享的 FlutterTts 实例（仅用于诊断，各屏幕仍使用自己的实例）
  FlutterTts get tts => _tts ??= FlutterTts();

  bool get engineAvailable => _engineAvailable;
  bool get japaneseAvailable => _japaneseAvailable;
  String get diagnosticInfo => _diagInfo ?? '未初始化';

  /// 初始化并检测 TTS 引擎状态（在 app 启动时调用一次）
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final diag = StringBuffer();
    _tts = FlutterTts();

    try {
      // 1. 检查可用引擎
      try {
        final engines = await _tts!.getEngines;
        final engineList =
            engines is List ? engines.cast<String>() : <String>[];
        diag.writeln(
            'TTS引擎: ${engineList.isEmpty ? "无" : engineList.join(", ")}');
        _engineAvailable = engineList.isNotEmpty;

        // 如果有 Google TTS，优先使用
        if (engineList.any((e) => e.contains('google'))) {
          final gEngine = engineList.firstWhere((e) => e.contains('google'));
          await _tts!.setEngine(gEngine);
          diag.writeln('使用引擎: $gEngine');
        }
      } catch (e) {
        diag.writeln('检测引擎失败: $e');
        _engineAvailable = true; // 假设可用，后续speak会验证
      }

      // 2. 检查可用语言
      try {
        final raw = await _tts!.getLanguages;
        final langs = raw is List ? raw : <dynamic>[];
        _availableLanguages = langs.map((l) => l.toString()).toList();
        _japaneseAvailable = _availableLanguages.any(
          (l) => l.toLowerCase().startsWith('ja'),
        );
        diag.writeln('可用语言数: ${_availableLanguages.length}');
        diag.writeln('日语支持: $_japaneseAvailable');
        if (_japaneseAvailable) {
          final jaLangs = _availableLanguages.where(
            (l) => l.toLowerCase().startsWith('ja'),
          );
          diag.writeln('日语变体: ${jaLangs.join(", ")}');
        }
      } catch (e) {
        diag.writeln('检测语言失败: $e');
      }

      // 3. 尝试设置日语
      try {
        final langResult = await _tts!.setLanguage('ja-JP');
        diag.writeln('setLanguage(ja-JP): $langResult');
      } catch (e) {
        diag.writeln('setLanguage失败: $e');
      }

      // 4. 尝试设置通用参数
      await _tts!.awaitSpeakCompletion(false);
      await _tts!.setSpeechRate(0.45);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
    } catch (e) {
      diag.writeln('初始化异常: $e');
    }

    _diagInfo = diag.toString();
    debugPrint('【TTS诊断】\n$_diagInfo');
  }

  /// 配置一个 FlutterTts 实例用于日语播放
  /// 各屏幕仍使用自己的 FlutterTts 实例，用这个方法统一配置
  static Future<bool> configureForJapanese(FlutterTts tts) async {
    try {
      await tts.awaitSpeakCompletion(false);

      // 尝试设置 Google TTS 引擎
      try {
        final engines = await tts.getEngines;
        final engineList =
            engines is List ? engines.cast<String>() : <String>[];
        final google = engineList.where((e) => e.toString().contains('google'));
        if (google.isNotEmpty) {
          await tts.setEngine(google.first);
        }
      } catch (_) {}

      // 设置日语并显式选择日语 voice
      await setJapaneseVoice(tts);

      await tts.setSpeechRate(0.45);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);

      return true;
    } catch (e) {
      debugPrint('configureForJapanese failed: $e');
      return false;
    }
  }

  /// 安全地设置日语 voice
  static Future<void> setJapaneseVoice(FlutterTts tts) async {
    try {
      await tts.setLanguage('ja-JP');
      // 尝试设置日本女性 voice（最常见）
      try {
        final voices = await tts.getVoices;
        if (voices is List && voices.isNotEmpty) {
          // Android: voice 格式 "google ja-jp-x-0 en-US" 这样的字符串
          final jaVoices = voices
              .where((v) => v.toString().toLowerCase().contains('ja'))
              .toList();
          if (jaVoices.isNotEmpty) {
            await tts.setVoice({
              'name': jaVoices.first,
              // voice metadata: "lang-REGION"
              'locale': 'ja-JP',
            });
          }
        }
      } catch (_) {
        // voice 设置失败也没关系，语言设定已经有了
      }
    } catch (e) {
      debugPrint('TTS: 设置voice失败(已忽略): $e');
    }
  }

  /// 安全地朗读文本，返回是否成功
  static Future<bool> speakJapanese(FlutterTts tts, String text) async {
    try {
      final ttsText = normalizeJapaneseTtsText(text);
      if (ttsText.isEmpty) return false;
      // 每次 speak 前重新设置语言（Android TTS 有时会丢失设置）
      await setJapaneseVoice(tts);
      await tts.setVolume(1.0);
      final result = await tts.speak(ttsText);
      return result == 1;
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      return false;
    }
  }
}
