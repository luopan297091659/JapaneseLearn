import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key});
  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  // ── DB 新闻 ──
  List<NewsArticleModel> _dbArticles = [];
  bool _dbLoading = true;
  String? _difficulty;
  final _searchCtrl = TextEditingController();

  // ── NHK Easy ──
  List<NewsArticleModel> _nhkArticles = [];
  bool _nhkLoading = true;

  // ── 收藏 ──
  List<NewsFavoriteModel> _favArticles = [];
  bool _favLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadDb();
    _loadNhk();
  }

  @override
  void dispose() { _tabCtrl.dispose(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _loadDb() async {
    setState(() => _dbLoading = true);
    try {
      final news = await apiService.getNews(
        difficulty: _difficulty,
        query: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
      );
      setState(() { _dbArticles = news; _dbLoading = false; });
    } catch (_) { setState(() => _dbLoading = false); }
  }

  Future<void> _loadNhk() async {
    setState(() => _nhkLoading = true);
    try {
      final news = await apiService.getNhkNews();
      setState(() { _nhkArticles = news; _nhkLoading = false; });
    } catch (_) { setState(() => _nhkLoading = false); }
  }

  Future<void> _loadFav() async {
    setState(() => _favLoading = true);
    try {
      final favs = await apiService.getNewsFavorites();
      setState(() { _favArticles = favs; _favLoading = false; });
    } catch (_) { setState(() => _favLoading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日本語ニュース'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.pop(),
        ),

        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '新闻'),
            Tab(icon: Icon(Icons.public, size: 18), text: 'NHK Easy'),
            Tab(icon: Icon(Icons.star_rounded, size: 18), text: '收藏'),
          ],
          onTap: (index) {
            if (index == 2) _loadFav();
          },
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildDbTab(),
          _buildNhkTab(),
          _buildFavTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => launchUrl(
          Uri.parse('https://www3.nhk.or.jp/news/movie.html'),
          mode: LaunchMode.externalApplication,
        ),
        icon: const Icon(Icons.ondemand_video_rounded),
        label: const Text('视频新闻'),
      ),
    );
  }

  // ─── DB 新闻标签页 ─────────────────────────────────────────────────
  Widget _buildDbTab() {
    return Column(
      children: [
        // 搜索 + 筛选
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索新闻...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear),
                      onPressed: () { _searchCtrl.clear(); _loadDb(); })
                  : null,
              isDense: true,
            ),
            onSubmitted: (_) => _loadDb(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(label: const Text('全部'), selected: _difficulty == null,
                    onSelected: (_) { setState(() => _difficulty = null); _loadDb(); }),
              ),
              ...['easy', 'medium', 'hard'].map((d) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_diffLabel(d)), selected: _difficulty == d,
                  onSelected: (_) { setState(() => _difficulty = d); _loadDb(); }),
              )),
            ]),
          ),
        ),
        Expanded(
          child: _dbLoading
              ? const Center(child: CircularProgressIndicator())
              : _dbArticles.isEmpty
                  ? const Center(child: Text('暂无新闻'))
                  : RefreshIndicator(
                      onRefresh: _loadDb,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _dbArticles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final a = _dbArticles[i];
                          return _NewsCard(article: a, onTap: () => context.push('/news/${a.id}'));
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // ─── NHK Easy 标签页 ───────────────────────────────────────────────
  Widget _buildNhkTab() {
    if (_nhkLoading) return const Center(child: CircularProgressIndicator());
    if (_nhkArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('暂无 NHK 新闻'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadNhk,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadNhk,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _nhkArticles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final a = _nhkArticles[i];
          return _NhkNewsCard(article: a, onTap: () => context.push('/nhk-news/${a.id}'));
        },
      ),
    );
  }

  // ─── 收藏标签页 ─────────────────────────────────────────────────
  Widget _buildFavTab() {
    if (_favLoading) return const Center(child: CircularProgressIndicator());
    if (_favArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_border_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('暂无收藏新闻'),
            const SizedBox(height: 4),
            Text('浏览新闻时点击 ⭐ 即可收藏', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadFav,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadFav,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _favArticles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final f = _favArticles[i];
          return _FavNewsCard(
            fav: f,
            onTap: () {
              if (f.newsType == 'nhk') {
                context.push('/nhk-news/${f.newsId}');
              } else {
                context.push('/news/${f.newsId}');
              }
            },
            onRemove: () async {
              try {
                await apiService.removeNewsFavorite(f.newsType, f.newsId);
                _loadFav();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)),
                  );
                }
              } catch (_) {}
            },
          );
        },
      ),
    );
  }

  String _diffLabel(String d) => {'easy': '简单', 'medium': '中等', 'hard': '困难'}[d] ?? d;
}

// ── DB 新闻卡片 ──────────────────────────────────────────────────────────────
class _NewsCard extends StatelessWidget {
  final NewsArticleModel article;
  final VoidCallback onTap;
  const _NewsCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl != null)
              Image.network(article.imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _diffColor(article.difficulty).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_diffLabel(article.difficulty),
                          style: TextStyle(fontSize: 11, color: _diffColor(article.difficulty))),
                    ),
                    const SizedBox(width: 8),
                    Text(article.source, style: TextStyle(fontSize: 11, color: cs.outline)),
                    const Spacer(),
                    if (article.audioUrl != null)
                      Icon(Icons.volume_up_rounded, size: 16, color: cs.outline),
                  ]),
                  const SizedBox(height: 6),
                  Text(article.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _diffColor(String d) =>
      {'easy': Colors.green, 'medium': Colors.orange, 'hard': Colors.red}[d] ?? Colors.grey;
  String _diffLabel(String d) => {'easy': '易', 'medium': '中', 'hard': '难'}[d] ?? d;
}

// ── NHK 新闻卡片 ─────────────────────────────────────────────────────────────
class _NhkNewsCard extends StatelessWidget {
  final NewsArticleModel article;
  final VoidCallback onTap;
  const _NhkNewsCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dateStr = _formatDate(article.publishedAt);
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrl != null && article.imageUrl!.isNotEmpty)
              Image.network(article.imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0077B6).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('NHK Easy', style: TextStyle(fontSize: 11, color: Color(0xFF0077B6))),
                    ),
                    const Spacer(),
                    Text(dateStr, style: TextStyle(fontSize: 11, color: cs.outline)),
                  ]),
                  const SizedBox(height: 6),
                  Text(article.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dt) {
    if (dt == null) return '';
    try {
      final d = DateTime.parse(dt);
      return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    } catch (_) { return dt.length > 10 ? dt.substring(0, 10) : dt; }
  }
}

// ── 收藏新闻卡片 ─────────────────────────────────────────────────────────────
class _FavNewsCard extends StatelessWidget {
  final NewsFavoriteModel fav;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  const _FavNewsCard({required this.fav, required this.onTap, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isNhk = fav.newsType == 'nhk';
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (fav.imageUrl != null && fav.imageUrl!.isNotEmpty)
              Image.network(fav.imageUrl!, height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isNhk ? const Color(0xFF0077B6) : cs.primary).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(isNhk ? 'NHK' : (fav.source ?? ''),
                          style: TextStyle(fontSize: 11, color: isNhk ? const Color(0xFF0077B6) : cs.primary)),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.star_rounded, size: 16, color: Colors.amber),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: '取消收藏',
                      onPressed: onRemove,
                      visualDensity: VisualDensity.compact,
                      color: cs.outline,
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(fav.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  if (fav.description != null && fav.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(fav.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.outline)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
