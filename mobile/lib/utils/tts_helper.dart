import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'dart:convert';
import '../config/app_config.dart';

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
        String? localPath;
        if (audioUrl.startsWith('/uploads/')) {
          // 下载到本地临时文件
          final dir = await getTemporaryDirectory();
          final fileName = audioUrl.split('/').last;
          localPath = '${dir.path}/$fileName';
          if (!File(localPath).existsSync()) {
            final resp = await Dio().get(
              audioUrl,
              options: Options(responseType: ResponseType.bytes),
            );
            await File(localPath).writeAsBytes(resp.data);
          }
        }
        if (localPath != null && File(localPath).existsSync()) {
          await player.setFilePath(localPath);
        } else {
          await player.setUrl(audioUrl);
        }
        await player.setVolume(1.0);
        await player.setSpeed(slow ? 0.5 : 1.0);
        await player.play();
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
            if (onComplete != null) onComplete();
          }
        });
        return;
      } catch (e) {
        debugPrint('音频播放失败，尝试TTS: $e');
      }
    }

    // 2. 本地TTS（有可用引擎）
    final ttsInst = tts ?? FlutterTts();
    try {
      await configureForJapanese(ttsInst);
      await ttsInst.setVolume(1.0);
      await ttsInst.setSpeechRate(slow ? 0.25 : 0.5);
      ttsInst.setCompletionHandler(() {
        if (onComplete != null) onComplete();
      });
      final result = await ttsInst.speak(text);
      if (result == 1) return;
    } catch (e) {
      debugPrint('本地TTS失败，尝试Kokoro: $e');
    }

    // 3. 后端Kokoro TTS
    try {
      debugPrint('[TTS] 第3层：尝试Kokoro后端合成 - URL: ${AppConfig.kokoroTtsUrl}');
      final dio = Dio();
      final requestData = {
        'text': text,
        'voice': 'a',  // 'a', 'b', 或 'c'
        'emotion': 'neutral',
        'speed': slow ? 0.7 : 1.0,
      };
      debugPrint('[TTS] 请求数据: ${jsonEncode(requestData)}');
      
      final resp = await dio.post(
        AppConfig.kokoroTtsUrl,
        data: jsonEncode(requestData),
        options: Options(headers: {'Content-Type': 'application/json'}),
      );
      
      debugPrint('[TTS] 收到响应: ${resp.statusCode}');
      final kokoroAudioUrl = resp.data['audio_url'] as String?;
      debugPrint('[TTS] 返回的audio_url: $kokoroAudioUrl');
      if (kokoroAudioUrl != null && kokoroAudioUrl.isNotEmpty) {
        // 后端返回相对路径（/api/v1/tts/kokoro/audio/xxx.wav），需要拼接基地址
        // 这样APP永远通过8002来访问，不直接访问8010，满足安全架构要求
        String fullUrl = kokoroAudioUrl;
        if (!kokoroAudioUrl.startsWith('http')) {
          // 从kokoroTtsUrl (https://139.196.44.6:8002/api/v1/tts/kokoro-speak)
          // 提取基地址 (https://139.196.44.6:8002)
          final baseUrl = AppConfig.kokoroTtsUrl.replaceAll(RegExp(r'/api/v1/tts/.*'), '');
          fullUrl = baseUrl + kokoroAudioUrl;
        }
        debugPrint('[TTS] 最终播放URL (通过8002): $fullUrl');
        final player = AudioPlayer();
        debugPrint('[TTS] 开始播放...');
        await player.setUrl(fullUrl);
        await player.setVolume(1.0);
        await player.setSpeed(slow ? 0.5 : 1.0);
        await player.play();
        player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            player.dispose();
            if (onComplete != null) onComplete();
          }
        });
      }
    } catch (e) {
      debugPrint('[TTS] Kokoro TTS后端失败: $e');
      if (onComplete != null) onComplete();
    }
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
        final engineList = engines is List ? engines.cast<String>() : <String>[];
        diag.writeln('TTS引擎: ${engineList.isEmpty ? "无" : engineList.join(", ")}');
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
        final engineList = engines is List ? engines.cast<String>() : <String>[];
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
      // 每次 speak 前重新设置语言（Android TTS 有时会丢失设置）
      await setJapaneseVoice(tts);
      await tts.setVolume(1.0);
      final result = await tts.speak(text);
      return result == 1;
    } catch (e) {
      debugPrint('TTS speak failed: $e');
      return false;
    }
  }
}
