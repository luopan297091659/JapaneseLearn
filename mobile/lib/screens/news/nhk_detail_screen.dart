import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../utils/tts_helper.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';

class NhkDetailScreen extends StatefulWidget {
  final String newsId;
  final NewsArticleModel? article;
  const NhkDetailScreen({super.key, required this.newsId, this.article});
  @override
  State<NhkDetailScreen> createState() => _NhkDetailScreenState();
}

class _NhkDetailScreenState extends State<NhkDetailScreen> {
  String _body = '';
  bool _loading = true;
  bool _showRuby = true;
  double _fontSize = 18;
  bool _isFav = false;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initTts();
    _load();
    _checkFav();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
    await _tts.setSpeechRate(0.4);
  }

  @override
  void dispose() { _tts.stop(); super.dispose(); }

  Future<void> _load() async {
    try {
      final body = await apiService.getNhkArticleBody(widget.newsId);
      setState(() { _body = body; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _checkFav() async {
    try {
      final fav = await apiService.checkNewsFavorite('nhk', widget.newsId);
      setState(() => _isFav = fav);
    } catch (_) {}
  }

  Future<void> _toggleFav() async {
    try {
      if (_isFav) {
        await apiService.removeNewsFavorite('nhk', widget.newsId);
        setState(() => _isFav = false);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消收藏'), duration: Duration(seconds: 1)));
      } else {
        final title = widget.article?.title ?? _plainText(_body);
        await apiService.addNewsFavorite(
          newsType: 'nhk', newsId: widget.newsId,
          title: title.isNotEmpty ? title : 'NHK Easy News',
          description: widget.article?.body ?? _plainText(_body),
          source: 'NHK', publishedAt: widget.article?.publishedAt,
        );
        setState(() => _isFav = true);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已收藏'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  // 从 HTML 中提取纯文本，保留 ruby 标注
  List<InlineSpan> _parseHtml(String html) {
    final spans = <InlineSpan>[];
    // 简单解析：移除所有 HTML 标签但保留 ruby 结构
    // <ruby>漢字<rt>かんじ</rt></ruby>
    final rubyReg = RegExp(r'<ruby[^>]*>(.*?)<rt>(.*?)</rt>.*?</ruby>', dotAll: true);
    final tagReg = RegExp(r'<[^>]+>');
    
    int lastEnd = 0;
    for (final match in rubyReg.allMatches(html)) {
      // 添加 match 之前的普通文本
      if (match.start > lastEnd) {
        final plain = html.substring(lastEnd, match.start).replaceAll(tagReg, '').replaceAll('&nbsp;', ' ');
        if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
      }
      final kanji = match.group(1)!.replaceAll(tagReg, '');
      final reading = match.group(2)!.replaceAll(tagReg, '');
      if (_showRuby) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _RubyText(kanji: kanji, reading: reading, fontSize: _fontSize),
        ));
      } else {
        spans.add(TextSpan(text: kanji));
      }
      lastEnd = match.end;
    }
    if (lastEnd < html.length) {
      final plain = html.substring(lastEnd).replaceAll(tagReg, '').replaceAll('&nbsp;', ' ');
      if (plain.isNotEmpty) spans.add(TextSpan(text: plain));
    }
    return spans;
  }

  String _plainText(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.article?.title ?? 'NHK Easy News';
    return Scaffold(
      appBar: AppBar(
        title: const Text('NHK Easy News'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/news'),
        ),
        actions: [
          IconButton(
            icon: Icon(_isFav ? Icons.star_rounded : Icons.star_border_rounded, size: 20),
            tooltip: _isFav ? '取消收藏' : '收藏',
            color: _isFav ? Colors.amber : null,
            onPressed: _toggleFav,
          ),
          IconButton(
            icon: Icon(_showRuby ? Icons.text_fields : Icons.translate, size: 20),
            tooltip: _showRuby ? '隐藏读音' : '显示读音',
            onPressed: () => setState(() => _showRuby = !_showRuby),
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, size: 20),
            tooltip: '朗读',
            onPressed: () async {
              final text = _plainText(_body);
              if (text.isEmpty) return;
              try {
                try { await _tts.setLanguage('ja-JP'); } catch (_) {}
                await _tts.setVolume(1.0);
                final result = await _tts.speak(text.substring(0, text.length.clamp(0, 500)));
                if (result != 1 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('语音引擎不可用，请检查系统TTS设置'), duration: Duration(seconds: 3)),
                  );
                }
              } catch (e) {
                debugPrint('TTS speak error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('朗读出错：$e'), duration: const Duration(seconds: 3)),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.pop(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body.isEmpty
              ? const Center(child: Text('文章加载失败'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 图片
                    if (widget.article?.imageUrl != null && widget.article!.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(widget.article!.imageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox()),
                      ),
                    const SizedBox(height: 12),
                    // 来源 + 日期
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0077B6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('NHK Easy', style: TextStyle(fontSize: 12, color: Color(0xFF0077B6), fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(_formatDate(widget.article?.publishedAt), style: TextStyle(fontSize: 12, color: cs.outline)),
                    ]),
                    const SizedBox(height: 10),
                    // 标题
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4)),
                    const SizedBox(height: 16),
                    // 字号调节
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('字号', style: TextStyle(fontSize: 12, color: cs.outline)),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.text_decrease, size: 18),
                          onPressed: () => setState(() => _fontSize = (_fontSize - 2).clamp(14, 28)),
                          visualDensity: VisualDensity.compact,
                        ),
                        Text('${_fontSize.toInt()}', style: TextStyle(fontSize: 13, color: cs.outline)),
                        IconButton(
                          icon: const Icon(Icons.text_increase, size: 18),
                          onPressed: () => setState(() => _fontSize = (_fontSize + 2).clamp(14, 28)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    // 正文（带 Ruby 注音）
                    RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: _fontSize, height: 2.0, color: cs.onSurface),
                        children: _parseHtml(_body),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
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

// ── Ruby 注音组件 ──────────────────────────────────────────────────────────────
class _RubyText extends StatelessWidget {
  final String kanji;
  final String reading;
  final double fontSize;
  const _RubyText({required this.kanji, required this.reading, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(reading, style: TextStyle(fontSize: fontSize * 0.45, color: cs.primary, height: 1.0)),
        Text(kanji, style: TextStyle(fontSize: fontSize, height: 1.0)),
      ],
    );
  }
}
