import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/api_service.dart';
import '../../config/app_config.dart';

class ImmersionScreen extends StatefulWidget {
  const ImmersionScreen({super.key});

  @override
  State<ImmersionScreen> createState() => _ImmersionScreenState();
}

class _ImmersionScreenState extends State<ImmersionScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _scrollController = ScrollController();
  List<dynamic> _videos = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;

  // 内嵌播放器状态
  String? _playingTitle;
  String? _playingUrl;
  String? _playingPlatform;
  bool _isFullscreen = false;
  WebViewController? _webController;

  // Tab
  late TabController _tabController;

  // 短文阅读
  List<dynamic> _tracks = [];
  bool _tracksLoading = true;
  String? _tracksError;
  String _trackLevel = 'all';
  // 视频播放
  String? _playingTrackId;
  String? _playingTrackTitle;
  WebViewController? _trackWebController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _tracks.isEmpty && _tracksLoading) {
        _loadTracks();
      }
    });
    _scrollController.addListener(_onScroll);
    _loadVideos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadVideos({bool forceRefresh = false}) async {
    setState(() { _loading = true; _error = null; _page = 1; });
    try {
      final data = await _api.getImmersionVideos(page: 1, limit: 20, forceRefresh: forceRefresh);
      final list = data['data'] as List<dynamic>? ?? [];
      final total = data['total'] as int? ?? 0;
      setState(() {
        _videos = list;
        _hasMore = _videos.length < total;
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() { _loadingMore = true; });
    try {
      final nextPage = _page + 1;
      final data = await _api.getImmersionVideos(page: nextPage, limit: 20);
      final list = data['data'] as List<dynamic>? ?? [];
      final total = data['total'] as int? ?? 0;
      setState(() {
        _page = nextPage;
        _videos.addAll(list);
        _hasMore = _videos.length < total;
        _loadingMore = false;
      });
    } catch (_) {
      setState(() { _loadingMore = false; });
    }
  }

  Future<void> _onRefresh() async {
    await _loadVideos(forceRefresh: true);
  }

  // ── 短文阅读 ──
  Future<void> _loadTracks() async {
    setState(() { _tracksLoading = true; _tracksError = null; });
    try {
      final data = await _api.getListeningTracks(
        level: _trackLevel == 'all' ? null : _trackLevel,
        category: '日语短文',
      );
      final rows = data['rows'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
      setState(() { _tracks = rows; _tracksLoading = false; });
    } catch (e) {
      setState(() { _tracksError = e.toString(); _tracksLoading = false; });
    }
  }

  void _selectTrackLevel(String level) {
    if (_trackLevel == level) return;
    setState(() { _trackLevel = level; });
    _loadTracks();
  }

  void _playTrackVideo(Map<String, dynamic> track) {
    final id = track['id']?.toString() ?? '';
    final audioUrl = track['audio_url'] as String? ?? '';
    final title = (track['title_zh'] ?? track['title'] ?? '').toString();
    if (audioUrl.isEmpty) return;

    if (_playingTrackId == id) {
      _closeTrackVideo();
      return;
    }

    final origin = AppConfig.baseUrl.replaceAll('/api/v1', '');
    final url = audioUrl.startsWith('http') ? audioUrl : '$origin$audioUrl';
    final html = '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>*{margin:0;padding:0}body{background:#000;display:flex;align-items:center;justify-content:center;height:100vh}
video{width:100%;max-height:100vh;object-fit:contain}</style></head>
<body><video src="$url" autoplay controls playsinline></video></body></html>
''';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onSslAuthError: (error) => error.proceed(),
      ))
      ..loadHtmlString(html);

    setState(() {
      _playingTrackId = id;
      _playingTrackTitle = title;
      _trackWebController = controller;
    });
  }

  void _closeTrackVideo() {
    setState(() {
      _playingTrackId = null;
      _playingTrackTitle = null;
      _trackWebController = null;
    });
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
      _playingPlatform = platform;
      _webController = controller;
    });
  }

  void _closePlayer() {
    setState(() {
      _playingTitle = null;
      _playingUrl = null;
      _playingPlatform = null;
      _webController = null;
    });
  }

  void _enterFullscreen() {
    if (_webController == null || _playingUrl == null) return;
    // 先隐藏小屏WebView，避免两个WebViewWidget共享controller导致黑屏
    setState(() { _isFullscreen = true; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (_, __, ___) => _FullscreenPlayerPage(
            controller: _webController!,
            title: _playingTitle ?? '',
            platform: _playingPlatform ?? '',
          ),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      ).then((_) {
        if (!mounted) return;
        // 退出全屏后重建WebViewController，避免共享controller导致黑屏
        final url = _playingUrl;
        if (url != null) {
          final newController = WebViewController()
            ..setJavaScriptMode(JavaScriptMode.unrestricted)
            ..loadRequest(Uri.parse(url));
          setState(() {
            _webController = newController;
            _isFullscreen = false;
          });
        } else {
          setState(() { _isFullscreen = false; });
        }
      });
    });
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [
            Tab(text: '📺 频道视频'),
            Tab(text: '📖 短文阅读'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChannelTab(cs),
          _buildTracksTab(cs),
        ],
      ),
    );
  }

  Widget _buildChannelTab(ColorScheme cs) {
    return Column(
      children: [
        // 内嵌视频播放器区域
        if (_playingUrl != null && _webController != null && !_isFullscreen)
          _buildInlinePlayer(cs)
        else if (_isFullscreen)
          Container(
            color: Colors.black,
            child: const AspectRatio(
              aspectRatio: 16 / 9,
              child: Center(child: Text('全屏播放中…', style: TextStyle(color: Colors.white54, fontSize: 13))),
            ),
          ),
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
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.0,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: _videos.length + (_hasMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i >= _videos.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                  ),
                                );
                              }
                              return _buildVideoCard(_videos[i] as Map<String, dynamic>);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildTracksTab(ColorScheme cs) {
    const levels = ['all', 'N5', 'N4', 'N3', 'N2', 'N1'];
    const levelLabels = {'all': '全部', 'N5': 'N5', 'N4': 'N4', 'N3': 'N3', 'N2': 'N2', 'N1': 'N1'};
    return Column(
      children: [
        // 级别筛选
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: levels.map((lv) {
                final selected = _trackLevel == lv;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(levelLabels[lv]!, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                    selected: selected,
                    onSelected: (_) => _selectTrackLevel(lv),
                    selectedColor: cs.primary.withValues(alpha: 0.15),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // 视频播放器区域
        if (_playingTrackId != null && _trackWebController != null)
          _buildTrackVideoPlayer(cs),
        // 曲目网格
        Expanded(
          child: _tracksLoading
              ? const Center(child: CircularProgressIndicator())
              : _tracksError != null
                  ? Center(child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('加载失败', style: TextStyle(color: cs.error)),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _loadTracks, child: const Text('重试')),
                      ],
                    ))
                  : _tracks.isEmpty
                      ? const Center(child: Text('暂无短文', style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadTracks,
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 1.0,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 2,
                            ),
                            itemCount: _tracks.length,
                            itemBuilder: (ctx, i) => _buildTrackCard(_tracks[i] as Map<String, dynamic>, i, cs),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildTrackVideoPlayer(ColorScheme cs) {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: WebViewWidget(controller: _trackWebController!),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey[900],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _playingTrackTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                GestureDetector(
                  onTap: _closeTrackVideo,
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

  Widget _buildTrackCard(Map<String, dynamic> track, int index, ColorScheme cs) {
    final id = track['id']?.toString() ?? '';
    final title = (track['title_zh'] ?? track['title'] ?? '').toString();
    final level = track['jlpt_level'] as String? ?? '';
    final isPlaying = _playingTrackId == id;

    final levelColor = {
      'N5': const Color(0xFF22c55e),
      'N4': const Color(0xFF3b82f6),
      'N3': const Color(0xFFf59e0b),
      'N2': const Color(0xFFf97316),
      'N1': const Color(0xFFef4444),
    }[level] ?? Colors.grey;

    return GestureDetector(
      onTap: () => _playTrackVideo(track),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: isPlaying ? Border.all(color: cs.primary, width: 2) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 1))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视频缩略图区域
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.grey[900],
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Icon(
                        isPlaying ? Icons.videocam : Icons.play_circle_filled,
                        color: isPlaying ? cs.primary : Colors.white54,
                        size: 32,
                      ),
                    ),
                    // 级别标签
                    Positioned(
                      top: 4, right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: levelColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(level, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                    // 序号
                    Positioned(
                      bottom: 4, left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${index + 1}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                  color: isPlaying ? cs.primary : null,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlinePlayer(ColorScheme cs) {
    final isRepost = _playingPlatform == 'bilibili';
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 播放器
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                WebViewWidget(controller: _webController!),
                if (isRepost)
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('网络转载视频', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 3, 6, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.15),
                  ),
                  const SizedBox(height: 1),
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
                      if (dateStr.isNotEmpty)
                        Text(dateStr, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ],
                  ),
                ],
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
  final String platform;

  const _FullscreenPlayerPage({required this.controller, required this.title, required this.platform});

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
            if (widget.platform == 'bilibili')
              Positioned(
                top: 8,
                left: 8,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade700.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('网络转载视频', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
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
