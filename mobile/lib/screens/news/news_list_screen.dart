import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class NewsListScreen extends StatefulWidget {
  const NewsListScreen({super.key});
  @override
  State<NewsListScreen> createState() => _NewsListScreenState();
}

class _NewsListScreenState extends State<NewsListScreen> {
  List<NewsArticleModel> _articles = [];
  bool _loading = true;
  String? _difficulty;
  final _searchCtrl = TextEditingController();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final news = await apiService.getNews(
        difficulty: _difficulty,
        query: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
      );
      setState(() { _articles = news; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日本語ニュース'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: '返回首页',
            onPressed: () => context.go('/home'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(children: [
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索新闻...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(icon: const Icon(Icons.clear),
                          onPressed: () { _searchCtrl.clear(); _load(); })
                      : null,
                  isDense: true,
                ),
                onSubmitted: (_) => _load(),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(label: const Text('全部'), selected: _difficulty == null,
                        onSelected: (_) { setState(() => _difficulty = null); _load(); }),
                  ),
                  ...['easy', 'medium', 'hard'].map((d) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_diffLabel(d)), selected: _difficulty == d,
                      onSelected: (_) { setState(() => _difficulty = d); _load(); }),
                  )),
                ]),
              ),
            ]),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _articles.isEmpty
              ? const Center(child: Text('暂无新闻'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _articles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final a = _articles[i];
                    return _NewsCard(article: a, onTap: () => context.go('/news/${a.id}'));
                  },
                ),
    );
  }

  String _diffLabel(String d) => {'easy': '简单', 'medium': '中等', 'hard': '困难'}[d] ?? d;
}

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
