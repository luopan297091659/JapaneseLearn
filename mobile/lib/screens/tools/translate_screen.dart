import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../services/api_service.dart';
import '../../utils/tts_helper.dart';

class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});
  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> with SingleTickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _tts = FlutterTts();
  late final TabController _tabCtrl;

  // — 翻译 —
  String _translation = '';
  bool _translating = false;

  // — 分析 —
  List<Map<String, dynamic>> _tokens = [];
  bool _analyzing = false;
  Map<String, dynamic>? _wordDetail;
  bool _wordLoading = false;
  int _selectedTokenIdx = -1;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _initTts();
  }

  Future<void> _initTts() async {
    await TtsHelper.configureForJapanese(_tts);
    await _tts.setSpeechRate(0.45);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _tts.stop();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _doTranslate() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _translating = true; _translation = ''; });
    try {
      final result = await apiService.aiTranslate(text);
      setState(() => _translation = result);
    } catch (e) {
      if (mounted) {
        String msg = '翻译失败';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['error']?.toString() ?? msg;
        } else if (e is DioException) {
          msg = '网络连接失败，请检查网络';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _doAnalyze() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _analyzing = true; _tokens = []; _wordDetail = null; _selectedTokenIdx = -1; });
    try {
      final tokens = await apiService.aiAnalyze(text);
      setState(() => _tokens = tokens);
    } catch (e) {
      if (mounted) {
        String msg = '分析失败';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['error']?.toString() ?? msg;
        } else if (e is DioException) {
          msg = '网络连接失败，请检查网络';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _fetchWordDetail(int idx) async {
    final token = _tokens[idx];
    if (_selectedTokenIdx == idx) {
      setState(() { _selectedTokenIdx = -1; _wordDetail = null; });
      return;
    }
    setState(() { _selectedTokenIdx = idx; _wordLoading = true; _wordDetail = null; });
    try {
      final detail = await apiService.aiWordDetail(
        token['word'] ?? '',
        pos: token['pos'],
        sentence: _inputCtrl.text.trim(),
      );
      if (mounted) setState(() => _wordDetail = detail);
    } catch (e) {
      if (mounted) {
        String msg = '查词失败';
        if (e is DioException && e.response?.data is Map) {
          msg = (e.response!.data as Map)['error']?.toString() ?? msg;
        } else if (e is DioException) {
          msg = '网络连接失败，请检查网络';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _wordLoading = false);
    }
  }

  void _speak(String text) async {
    if (text.isEmpty) return;
    try {
      await _tts.speak(text.substring(0, text.length.clamp(0, 500)));
    } catch (_) {}
  }

  void _onSubmit() {
    if (_tabCtrl.index == 0) {
      _doTranslate();
    } else {
      _doAnalyze();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('翻译 / 解析'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.translate, size: 18), text: '翻译'),
            Tab(icon: Icon(Icons.auto_fix_high, size: 18), text: '句子分析'),
          ],
          onTap: (_) => setState(() {}),
        ),
      ),
      body: Column(
        children: [
          // — 输入区 —
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _inputCtrl,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                hintText: '请输入日语文本...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.volume_up, size: 20),
                      tooltip: '朗读',
                      onPressed: () => _speak(_inputCtrl.text.trim()),
                    ),
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: '清空',
                      onPressed: () {
                        _inputCtrl.clear();
                        setState(() {
                          _translation = '';
                          _tokens = [];
                          _wordDetail = null;
                          _selectedTokenIdx = -1;
                        });
                      },
                    ),
                  ],
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _onSubmit(),
            ),
          ),
          // — 执行按钮 —
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_translating || _analyzing) ? null : _onSubmit,
                icon: (_translating || _analyzing)
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Icon(_tabCtrl.index == 0 ? Icons.translate : Icons.auto_fix_high, size: 18),
                label: Text(_tabCtrl.index == 0 ? '翻译' : '分析'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // — 结果区 —
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTranslationResult(cs),
                _buildAnalysisResult(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 翻译结果 ──────────────────────────────────────────────────────────────
  Widget _buildTranslationResult(ColorScheme cs) {
    if (_translating) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在翻译...')],
      ));
    }
    if (_translation.isEmpty) {
      return Center(child: Text('输入日语文本后点击翻译', style: TextStyle(color: cs.outline)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.translate, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('翻译结果', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.primary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: '复制',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _translation));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
              const Divider(),
              SelectableText(_translation, style: const TextStyle(fontSize: 17, height: 1.8)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 分析结果 ──────────────────────────────────────────────────────────────
  Widget _buildAnalysisResult(ColorScheme cs) {
    if (_analyzing) {
      return const Center(child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在分析...')],
      ));
    }
    if (_tokens.isEmpty) {
      return Center(child: Text('输入日语句子后点击分析', style: TextStyle(color: cs.outline)));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 词法分析结果 - 彩色标注
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 8,
            children: List.generate(_tokens.length, (i) {
              final t = _tokens[i];
              if (t['word'] == '\n') return const SizedBox(width: double.infinity, height: 4);
              final isSelected = i == _selectedTokenIdx;
              final color = _posColor(t['pos'] ?? '');
              return GestureDetector(
                onTap: () => _fetchWordDetail(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withValues(alpha: 0.25) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border(bottom: BorderSide(color: color, width: 2.5)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t['furigana'] != null && t['furigana'].toString().isNotEmpty && t['furigana'] != t['word'])
                        Text(t['furigana'], style: TextStyle(fontSize: 10, color: cs.primary, height: 1.0)),
                      Text(t['word'] ?? '', style: const TextStyle(fontSize: 17, height: 1.3)),
                      if (t['meaning'] != null && t['meaning'].toString().isNotEmpty)
                        Text(t['meaning'], style: TextStyle(fontSize: 9, color: cs.outline, height: 1.2)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        // 词性图例
        _buildPosLegend(cs),
        const SizedBox(height: 12),
        // 单词详解
        if (_wordLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_wordDetail != null && !_wordLoading)
          _buildWordDetailCard(cs),
      ],
    );
  }

  Widget _buildPosLegend(ColorScheme cs) {
    const items = [
      ('名詞', '名词'), ('動詞', '动词'), ('形容詞', '形容词'),
      ('副詞', '副词'), ('助詞', '助词'), ('助動詞', '助动词'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: items.map((e) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: _posColor(e.$1), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(e.$2, style: TextStyle(fontSize: 11, color: cs.outline)),
        ],
      )).toList(),
    );
  }

  Widget _buildWordDetailCard(ColorScheme cs) {
    final d = _wordDetail!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('词汇详解', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: cs.primary)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.volume_up, size: 20),
              onPressed: () => _speak(d['word'] ?? ''),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() { _wordDetail = null; _selectedTokenIdx = -1; }),
              visualDensity: VisualDensity.compact,
            ),
          ]),
          const SizedBox(height: 8),
          // 原文 + 读音
          Row(children: [
            Text(d['word'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            if (d['furigana'] != null && d['furigana'].toString().isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('【${d['furigana']}】', style: TextStyle(fontSize: 15, color: cs.primary)),
            ],
          ]),
          if (d['romaji'] != null && d['romaji'].toString().isNotEmpty)
            Text(d['romaji'], style: TextStyle(fontSize: 13, color: cs.outline)),
          const SizedBox(height: 8),
          // 辞书形
          if (d['dictionaryForm'] != null && d['dictionaryForm'] != d['word'])
            _detailRow('辞书形', d['dictionaryForm']),
          // 词性
          if (d['pos'] != null)
            Wrap(children: [
              const Text('词性  ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _posColor(d['pos']).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(d['pos'], style: TextStyle(fontSize: 13, color: _posColor(d['pos']), fontWeight: FontWeight.w600)),
              ),
            ]),
          const SizedBox(height: 6),
          // 中文释义
          _detailRow('释义', d['meaning'] ?? ''),
          const Divider(height: 20),
          // 详细解释
          if (d['explanation'] != null)
            Text(d['explanation'], style: TextStyle(fontSize: 14, height: 1.7, color: cs.onSurface)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label  ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }

  Color _posColor(String pos) {
    final p = pos.split('-').first;
    switch (p) {
      case '名詞': return const Color(0xFF2196F3);
      case '動詞': return const Color(0xFFE53935);
      case '形容詞': return const Color(0xFFFF9800);
      case '形容動詞': return const Color(0xFFFF9800);
      case '副詞': return const Color(0xFF9C27B0);
      case '助詞': return const Color(0xFF4CAF50);
      case '助動詞': return const Color(0xFF00BCD4);
      case '接続詞': return const Color(0xFF795548);
      case '連体詞': return const Color(0xFF607D8B);
      case '感動詞': return const Color(0xFFE91E63);
      case '記号': return const Color(0xFF9E9E9E);
      default: return const Color(0xFF757575);
    }
  }
}
