import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/api_service.dart';

class ImmersionScreen extends StatefulWidget {
  const ImmersionScreen({super.key});

  @override
  State<ImmersionScreen> createState() => _ImmersionScreenState();
}

class _ImmersionScreenState extends State<ImmersionScreen> {
  final _api = ApiService();
  List<dynamic> _videos = [];
  bool _loading = true;
  String? _error;

  // 内嵌播放器状态
  String? _playingTitle;
  String? _playingUrl;
  WebViewController? _webController;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadVideos({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.getImmersionVideos(page: 1, limit: 20, forceRefresh: forceRefresh);
      setState(() {
        _videos = data['data'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _onRefresh() async {
    await _loadVideos(forceRefresh: true);
  }

  void _openVideo(Map<String, dynamic> video) {
    final embedUrl = video['embedUrl'] as String? ?? '';
    final title = video['title'] as String? ?? '';
    final platform = video['platform'] as String? ?? '';

    if (embedUrl.isEmpty) return;

    String playerUrl;
    if (platform == 'bilibili') {
      final bvMatch = RegExp(r'bvid=([^&]+)').firstMatch(embedUrl);
      final bvid = bvMatch?.group(1);
      playerUrl = bvid != null
          ? 'https://player.bilibili.com/player.html?isOutside=true&bvid=$bvid&autoplay=1&danmaku=0'
          : embedUrl;
    } else if (platform == 'youtube') {
      final videoId = video['videoId'] as String? ?? '';
      playerUrl = videoId.isNotEmpty
          ? 'https://www.youtube.com/embed/$videoId?autoplay=1'
          : embedUrl;
    } else {
      playerUrl = embedUrl;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(playerUrl));

    setState(() {
      _playingTitle = title;
      _playingUrl = playerUrl;
      _webController = controller;
    });
  }

  void _closePlayer() {
    setState(() {
      _playingTitle = null;
      _playingUrl = null;
      _webController = null;
    });
  }

  void _enterFullscreen() {
    if (_webController == null || _playingUrl == null) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => _FullscreenPlayerPage(
          controller: _webController!,
          title: _playingTitle ?? '',
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('👂 磨耳朵', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: cs.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // 内嵌视频播放器区域
          if (_playingUrl != null && _webController != null)
            _buildInlinePlayer(cs),
          // 视频列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('加载失败', style: TextStyle(color: cs.error, fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(_error!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                          const SizedBox(height: 16),
                          FilledButton(onPressed: _onRefresh, child: const Text('重试')),
                        ],
                      ))
                    : _videos.isEmpty
                        ? const Center(child: Text('暂无可用视频', style: TextStyle(fontSize: 16, color: Colors.grey)))
                        : RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: GridView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.95,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                              ),
                              itemCount: _videos.length,
                              itemBuilder: (ctx, i) => _buildVideoCard(_videos[i] as Map<String, dynamic>),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlinePlayer(ColorScheme cs) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放器
          AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: _webController!),
          ),
          // 控制条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _playingTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: _enterFullscreen,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.fullscreen, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: _closePlayer,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, color: Colors.white70, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCard(Map<String, dynamic> video) {
    final title = video['title'] as String? ?? '';
    final thumbnail = (video['thumbnail'] as String? ?? '').replaceFirst('http://', 'https://');
    final channelName = video['channelName'] as String? ?? '';
    final platform = video['platform'] as String? ?? '';
    final date = video['publishedAt'] as String? ?? '';
    final dateStr = date.isNotEmpty ? DateTime.tryParse(date)?.toLocal().toString().substring(0, 10) ?? '' : '';

    return GestureDetector(
      onTap: () => _openVideo(video),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbnail.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: thumbnail,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: Colors.grey[900]),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[900],
                            child: const Icon(Icons.play_circle_outline, color: Colors.white54, size: 32),
                          ),
                        )
                      : Container(
                          color: Colors.grey[900],
                          child: const Icon(Icons.play_circle_outline, color: Colors.white54, size: 32),
                        ),
                  // 转载标识
                  if (platform == 'bilibili')
                    Positioned(
                      top: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('网络转载视频', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  // 播放图标
                  const Center(
                    child: Icon(Icons.play_circle_filled, color: Colors.white70, size: 30),
                  ),
                ],
              ),
            ),
            // 标题和信息
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.2),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          platform == 'youtube' ? '▶️' : '📺',
                          style: const TextStyle(fontSize: 10),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            channelName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                    if (dateStr.isNotEmpty)
                      Text(dateStr, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏播放页面 - 通过 rootNavigator 推入，覆盖底部导航栏和 AppBar
class _FullscreenPlayerPage extends StatefulWidget {
  final WebViewController controller;
  final String title;

  const _FullscreenPlayerPage({required this.controller, required this.title});

  @override
  State<_FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<_FullscreenPlayerPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _exit() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            WebViewWidget(controller: widget.controller),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: GestureDetector(
                  onTap: _exit,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.fullscreen_exit, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
