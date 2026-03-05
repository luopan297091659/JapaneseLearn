import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState(false, ProcessingState.idle);

  @override
  void initState() {
    super.initState();
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
      setState(() { _loading = true; _hasError = false; });
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
        await _player.play();
      } catch (e) {
        setState(() { _loading = false; _hasError = true; });
      }
    } else {
      await _player.play();
    }
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
          Text('音频加载失败', style: TextStyle(fontSize: 11, color: cs.error)),
      ]),
    );
  }
}
