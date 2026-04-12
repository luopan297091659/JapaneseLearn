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

  List<Map<String, dynamic>> _myChannels = const [];
  bool _channelBusy = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadVideos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      // Use watch page instead of embed to avoid error 153 (embedding disabled)
      playerUrl = videoId.isNotEmpty
          ? 'https://m.youtube.com/watch?v=$videoId'
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
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openChannelConfigSheet,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                ),
                child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: _buildChannelTab(cs),
    );
  }

  Future<void> _loadMyChannels() async {
    setState(() => _channelBusy = true);
    try {
      final channels = await _api.getMyImmersionChannels();
      if (!mounted) return;
      setState(() {
        _myChannels = channels;
        _channelBusy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _channelBusy = false);
    }
  }

  Future<void> _addMyChannel(String url) async {
    await _api.addMyImmersionChannel(channelUrl: url);
    await _loadMyChannels();
    await _loadVideos(forceRefresh: true);
  }

  Future<void> _deleteMyChannel(dynamic id) async {
    await _api.deleteMyImmersionChannel(id);
    await _loadMyChannels();
    await _loadVideos(forceRefresh: true);
  }

  Future<void> _openChannelConfigSheet() async {
    await _loadMyChannels();
    if (!mounted) return;
    final linkCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自定义频道', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '仅当前账号生效，可添加 YouTube 或 Bilibili 频道链接',
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.outline),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkCtrl,
                    decoration: const InputDecoration(
                      hintText: '粘贴频道链接，例如 youtube.com/channel/... 或 space.bilibili.com/...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    minLines: 1,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: submitting
                          ? null
                          : () async {
                              final url = linkCtrl.text.trim();
                              if (url.isEmpty) return;
                              setSheet(() => submitting = true);
                              try {
                                await _addMyChannel(url);
                                if (!mounted) return;
                                linkCtrl.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('频道已添加并开始同步')),
                                );
                                setSheet(() => submitting = false);
                              } catch (e) {
                                if (!mounted) return;
                                setSheet(() => submitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('添加失败：$e')),
                                );
                              }
                            },
                      icon: submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add_link_rounded),
                      label: Text(submitting ? '添加中...' : '添加频道'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('我的频道', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  if (_channelBusy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_myChannels.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('暂未配置频道'),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _myChannels.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = _myChannels[i];
                          final name = item['name'] as String? ?? '我的频道';
                          final url = item['channel_url'] as String? ?? '';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              onPressed: () async {
                                try {
                                  await _deleteMyChannel(item['id']);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('频道已删除')),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('删除失败：$e')),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
    linkCtrl.dispose();
  }

  Widget _buildChannelTab(ColorScheme cs) {
    final screenWidth = MediaQuery.of(context).size.width;
    final colCount = screenWidth >= 900 ? 4 : screenWidth >= 600 ? 3 : 2;
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
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: colCount,
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
    final channelScope = video['channelScope'] as String? ?? 'public';
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
              child: LayoutBuilder(
                builder: (ctx, box) {
                  final iconSize = (box.maxWidth * 0.15).clamp(28.0, 60.0);
                  return Stack(
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
                      if (channelScope == 'custom')
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.pink.shade400.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('我的频道', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      // 播放图标 - 按卡片宽度自适应大小
                      Center(
                        child: Container(
                          width: iconSize * 1.6,
                          height: iconSize * 1.6,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: iconSize),
                        ),
                      ),
                    ],
                  );
                },
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
