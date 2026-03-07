import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String? audioUrl;
  final bool compact; // compact: icon+bar; full: full controls
  final String? label;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    this.compact = false,
    this.label,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _player;
  bool _loading = false;
  bool _hasError = false;
  String _errorMessage = '';  // 详细错误信息
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);

  @override
  void initState() {
    super.initState();
    _initAudioSession();
    _player = AudioPlayer();
    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _playerState = state);
    });
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
  }

  /// ✅ 新增：初始化音频焦点（确保音频可以正常播放）
  void _initAudioSession() {
    AudioSession.instance.then((session) {
      session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      )).catchError((e) {
        print('【音频】AudioSession 配置失败: $e');
      });
    }).catchError((e) {
      print('【音频】获取 AudioSession 失败: $e');
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (widget.audioUrl == null) return;
    if (_playerState.playing) {
      await _player.pause();
      return;
    }
    if (_playerState.processingState == ProcessingState.idle ||
        _playerState.processingState == ProcessingState.completed) {
      setState(() { _loading = true; _hasError = false; _errorMessage = ''; });
      try {
        final url = widget.audioUrl!;
        // 服务端相对路径（/uploads/audio/...）→ 拼接为完整 URL
        if (url.startsWith('/uploads/')) {
          final fullUrl = AppConfig.serverRoot + url;
          final localPath = await apiService.downloadToTempFile(fullUrl);
          await _player.setFilePath(localPath);
        }
        // 本地文件路径（Anki 导入的音频）
        else if (url.startsWith('/') || url.startsWith('file://')) {
          final localPath = url.startsWith('file://') ? url.substring(7) : url;
          await _player.setFilePath(localPath);
        } else {
          // 来自本应用服务器的 HTTPS 地址，先 Dio 下载绕过自签名证书
          final needsProxy = url.startsWith(AppConfig.baseUrl) ||
              url.startsWith(AppConfig.serverRoot);
          if (needsProxy) {
            final localPath = await apiService.downloadToTempFile(url);
            await _player.setFilePath(localPath);
          } else {
            await _player.setUrl(url);
          }
        }
        setState(() => _loading = false);
        
        // ✅ 新增：播放前设置音量为最大
        await _player.setVolume(1.0);
        print('【音频】开始播放，音量: 100%');
        
        await _player.play();
      } catch (e) {
        setState(() { 
          _loading = false; 
          _hasError = true;
          // 根据异常类型提供有用的错误提示
          _errorMessage = _getErrorMessage(e);
        });
        print('【音频】播放出错: $e');
      }
    } else {
      await _player.play();
    }
  }

  /// 根据异常类型返回用户友好的错误信息
  String _getErrorMessage(Object error) {
    final msg = error.toString().toLowerCase();
    if (msg.contains('connection refused') || msg.contains('failed to connect')) {
      return '网络连接失败，请检查网络';
    } else if (msg.contains('timeoutexception') || msg.contains('timeout')) {
      return '加载超时，网络可能较慢';
    } else if (msg.contains('no route to host') || msg.contains('unreachable')) {
      return '无法连接到服务器';
    } else if (msg.contains('certificate') || msg.contains('ssl')) {
      return '证书验证失败';
    } else if (msg.contains('not found') || msg.contains('404')) {
      return '音频文件不存在';
    } else if (msg.contains('格式不支持') || msg.contains('unsupported')) {
      return '音频格式不支持';
    } else if (msg.contains('权限') || msg.contains('permission')) {
      return '权限不足，无法访问文件，请在设置中授予权限';
    } else if (msg.contains('存储') || msg.contains('storage')) {
      return '存储空间不足或权限被拒绝';
    } else if (msg.contains('磁盘') || msg.contains('disk')) {
      return '磁盘空间不足';
    } else if (msg.contains('音频下载失败')) {
      return '音频下载失败，已重试 3 次';
    } else if (msg.contains('无法读取') || msg.contains('cannot read')) {
      return '缓存文件已损坏，请清理存储后重试';
    }
    return '音频加载失败: ${error.toString().length > 30 ? error.toString().substring(0, 30) + '...' : error.toString()}';
  }

  Future<void> _seek(double value) async {
    await _player.seek(Duration(seconds: value.toInt()));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool get _isPlaying => _playerState.playing;
  // ignore: unused_element
  bool get _isCompleted => _playerState.processingState == ProcessingState.completed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.audioUrl == null) return const SizedBox.shrink();

    if (widget.compact) {
      return Row(children: [
        InkWell(
          onTap: _togglePlay,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
            child: _loading
                ? SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : Icon(
                    _hasError ? Icons.error_outline
                        : _isPlaying ? Icons.pause_rounded : Icons.volume_up_rounded,
                    color: cs.primary, size: 18,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        if (widget.label != null)
          Text(widget.label!, style: TextStyle(fontSize: 12, color: cs.outline)),
      ]);
    }

    // Full player
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primaryContainer),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            onPressed: _togglePlay,
            icon: _loading
                ? SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : Icon(
                    _hasError ? Icons.error_outline
                        : _isPlaying ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_filled_rounded,
                    color: _hasError ? cs.error : cs.primary, size: 36,
                  ),
          ),
          Expanded(
            child: Slider(
              value: _duration.inSeconds > 0
                  ? _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble())
                  : 0,
              max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
              onChanged: _duration.inSeconds > 0 ? _seek : null,
              activeColor: cs.primary,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
              style: TextStyle(fontSize: 11, color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
        if (_hasError)
          Text(_errorMessage, style: TextStyle(fontSize: 11, color: cs.error)),
      ]),
    );
  }
}
