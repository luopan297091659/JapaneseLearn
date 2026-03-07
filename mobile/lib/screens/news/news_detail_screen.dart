import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../../widgets/audio_player_widget.dart';

class NewsDetailScreen extends StatefulWidget {
  final String id;
  const NewsDetailScreen({super.key, required this.id});
  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  NewsArticleModel? _article;
  bool _loading = true;
  bool _showRuby = true;
  bool _isFav = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final article = await apiService.getNewsDetail(widget.id);
      setState(() { _article = article; _loading = false; });
      apiService.logActivity(activityType: 'news', refId: widget.id, durationSeconds: 0);
      _checkFav();
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _checkFav() async {
    try {
      final fav = await apiService.checkNewsFavorite('db', widget.id);
      setState(() => _isFav = fav);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    if (_article == null) return;
    try {
      if (_isFav) {
        await apiService.removeNewsFavorite('db', widget.id);
        setState(() => _isFav = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)));
      } else {
        await apiService.addNewsFavorite(
          newsType: 'db', newsId: widget.id, title: _article!.title,
          description: _article!.body?.substring(0, (_article!.body!.length).clamp(0, 200)),
          imageUrl: _article!.imageUrl, source: _article!.source, publishedAt: _article!.publishedAt,
        );
        setState(() => _isFav = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已收藏'), duration: Duration(seconds: 1)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ニュース'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/news'),
        ),
        actions: [
          if (_article?.audioUrl != null)
            AudioPlayerWidget(audioUrl: _article!.audioUrl, compact: true),
          IconButton(
            icon: Icon(_isFav ? Icons.star_rounded : Icons.star_border_rounded),
            tooltip: _isFav ? '取消收藏' : '收藏',
            color: _isFav ? Colors.amber : null,
            onPressed: _toggleFav,
          ),
          IconButton(
            icon: Icon(_showRuby ? Icons.text_fields : Icons.translate),
            tooltip: _showRuby ? '隐藏读音' : '显示读音',
            onPressed: () => setState(() => _showRuby = !_showRuby),
          ),

        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _article == null
              ? const Center(child: Text('加载失败'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_article!.imageUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(_article!.imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                    const SizedBox(height: 16),
                    // Difficulty badge
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer, borderRadius: BorderRadius.circular(6)),
                        child: Text(_article!.source, style: TextStyle(color: cs.primary, fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      Text(_article!.publishedAt ?? '', style: TextStyle(color: cs.outline, fontSize: 12)),
                    ]),
                    const SizedBox(height: 12),
                    // Title
                    Text(_article!.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    // Audio player (if audio exists)
                    if (_article!.audioUrl != null)
                      Card(
                        color: cs.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            Icon(Icons.headphones, color: cs.primary),
                            const SizedBox(width: 8),
                            const Text('聆音', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: AudioPlayerWidget(
                                audioUrl: _article!.audioUrl,
                                compact: false,
                              ),
                            ),
                          ]),
                        ),
                      ),
                    const SizedBox(height: 16),
                    // Article body
                    Text(
                      _article!.body ?? '',
                      style: const TextStyle(fontSize: 16, height: 1.8),
                    ),
                  ],
                ),
    );
  }
}
