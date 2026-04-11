import 'package:just_audio/just_audio.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 全局音频管理器：确保同一时间只有一个音频在播放
class AudioManager {
  static final AudioManager instance = AudioManager._();
  AudioManager._();

  AudioPlayer? _currentPlayer;
  FlutterTts? _currentTts;

  /// 播放 AudioPlayer 前调用，停止之前的音频
  Future<void> requestPlay(AudioPlayer player) async {
    if (_currentPlayer != null && _currentPlayer != player) {
      try { await _currentPlayer!.stop(); } catch (_) {}
    }
    if (_currentTts != null) {
      try { await _currentTts!.stop(); } catch (_) {}
      _currentTts = null;
    }
    _currentPlayer = player;
  }

  /// 播放 TTS 前调用，停止之前的音频
  Future<void> requestTts(FlutterTts tts) async {
    if (_currentPlayer != null) {
      try { await _currentPlayer!.stop(); } catch (_) {}
      _currentPlayer = null;
    }
    if (_currentTts != null && _currentTts != tts) {
      try { await _currentTts!.stop(); } catch (_) {}
    }
    _currentTts = tts;
  }

  /// 停止所有音频
  Future<void> stopAll() async {
    if (_currentPlayer != null) {
      try { await _currentPlayer!.stop(); } catch (_) {}
      _currentPlayer = null;
    }
    if (_currentTts != null) {
      try { await _currentTts!.stop(); } catch (_) {}
      _currentTts = null;
    }
  }
}
