import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import '../../utils/tts_helper.dart';

// ── 47 都道府县数据 ──────────────────────────────────────────────────────────
class _Prefecture {
  final String kanji, hiragana, romaji, region;
  const _Prefecture(this.kanji, this.hiragana, this.romaji, this.region);
}

const _prefectures = <_Prefecture>[
  _Prefecture('北海道','ほっかいどう','hokkaido','北海道'),
  _Prefecture('青森県','あおもりけん','aomori','東北'),
  _Prefecture('岩手県','いわてけん','iwate','東北'),
  _Prefecture('宮城県','みやぎけん','miyagi','東北'),
  _Prefecture('秋田県','あきたけん','akita','東北'),
  _Prefecture('山形県','やまがたけん','yamagata','東北'),
  _Prefecture('福島県','ふくしまけん','fukushima','東北'),
  _Prefecture('茨城県','いばらきけん','ibaraki','関東'),
  _Prefecture('栃木県','とちぎけん','tochigi','関東'),
  _Prefecture('群馬県','ぐんまけん','gunma','関東'),
  _Prefecture('埼玉県','さいたまけん','saitama','関東'),
  _Prefecture('千葉県','ちばけん','chiba','関東'),
  _Prefecture('東京都','とうきょうと','tokyo','関東'),
  _Prefecture('神奈川県','かながわけん','kanagawa','関東'),
  _Prefecture('新潟県','にいがたけん','niigata','中部'),
  _Prefecture('富山県','とやまけん','toyama','中部'),
  _Prefecture('石川県','いしかわけん','ishikawa','中部'),
  _Prefecture('福井県','ふくいけん','fukui','中部'),
  _Prefecture('山梨県','やまなしけん','yamanashi','中部'),
  _Prefecture('長野県','ながのけん','nagano','中部'),
  _Prefecture('岐阜県','ぎふけん','gifu','中部'),
  _Prefecture('静岡県','しずおかけん','shizuoka','中部'),
  _Prefecture('愛知県','あいちけん','aichi','中部'),
  _Prefecture('三重県','みえけん','mie','近畿'),
  _Prefecture('滋賀県','しがけん','shiga','近畿'),
  _Prefecture('京都府','きょうとふ','kyoto','近畿'),
  _Prefecture('大阪府','おおさかふ','osaka','近畿'),
  _Prefecture('兵庫県','ひょうごけん','hyogo','近畿'),
  _Prefecture('奈良県','ならけん','nara','近畿'),
  _Prefecture('和歌山県','わかやまけん','wakayama','近畿'),
  _Prefecture('鳥取県','とっとりけん','tottori','中国'),
  _Prefecture('島根県','しまねけん','shimane','中国'),
  _Prefecture('岡山県','おかやまけん','okayama','中国'),
  _Prefecture('広島県','ひろしまけん','hiroshima','中国'),
  _Prefecture('山口県','やまぐちけん','yamaguchi','中国'),
  _Prefecture('徳島県','とくしまけん','tokushima','四国'),
  _Prefecture('香川県','かがわけん','kagawa','四国'),
  _Prefecture('愛媛県','えひめけん','ehime','四国'),
  _Prefecture('高知県','こうちけん','kochi','四国'),
  _Prefecture('福岡県','ふくおかけん','fukuoka','九州'),
  _Prefecture('佐賀県','さがけん','saga','九州'),
  _Prefecture('長崎県','ながさきけん','nagasaki','九州'),
  _Prefecture('熊本県','くまもとけん','kumamoto','九州'),
  _Prefecture('大分県','おおいたけん','oita','九州'),
  _Prefecture('宮崎県','みやざきけん','miyazaki','九州'),
  _Prefecture('鹿児島県','かごしまけん','kagoshima','九州'),
  _Prefecture('沖縄県','おきなわけん','okinawa','九州'),
];

const _regions = ['全部','北海道','東北','関東','中部','近畿','中国','四国','九州'];

class TodofukenQuizScreen extends StatefulWidget {
  const TodofukenQuizScreen({super.key});
  @override
  State<TodofukenQuizScreen> createState() => _TodofukenQuizScreenState();
}

class _TodofukenQuizScreenState extends State<TodofukenQuizScreen> {
  final FlutterTts _tts = FlutterTts();
  final _random = Random();

  // 设置
  String _selectedRegion = '全部';
  bool _started = false;

  // 测验状态
  late List<_Prefecture> _pool;
  int _qIndex = 0;
  int _correct = 0;
  int _total = 0;
  late _Prefecture _current;
  late List<String> _options;
  int? _selectedIdx;
  bool _answered = false;
  bool _quizDone = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
    await _tts.setSpeechRate(0.4); // 此页面用稍慢的语速
  }

  @override
  void dispose() { _tts.stop(); super.dispose(); }

  void _startQuiz() {
    _pool = _selectedRegion == '全部'
        ? List.of(_prefectures)
        : _prefectures.where((p) => p.region == _selectedRegion).toList();
    _pool.shuffle(_random);
    if (_pool.length > 10) _pool = _pool.sublist(0, 10); // 每轮最多 10 题
    _qIndex = 0; _correct = 0; _total = _pool.length;
    _quizDone = false; _selectedIdx = null; _answered = false;
    _nextQuestion();
    setState(() => _started = true);
  }

  void _nextQuestion() {
    _current = _pool[_qIndex];
    // 生成 4 个选项（含正确答案）
    final allHiragana = _prefectures.map((p) => p.hiragana).toList();
    final optionSet = <String>{_current.hiragana};
    while (optionSet.length < 4) {
      optionSet.add(allHiragana[_random.nextInt(allHiragana.length)]);
    }
    _options = optionSet.toList()..shuffle(_random);
    _selectedIdx = null;
    _answered = false;
  }

  void _onSelect(int idx) {
    if (_answered) return;
    final isCorrect = _options[idx] == _current.hiragana;
    setState(() {
      _selectedIdx = idx;
      _answered = true;
      if (isCorrect) _correct++;
    });
    () async {
      try {
        try { await _tts.setLanguage('ja-JP'); } catch (_) {}
        await _tts.speak(_current.hiragana);
      } catch (e) {
        debugPrint('TTS speak error: $e');
      }
    }();
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      _qIndex++;
      if (_qIndex >= _pool.length) {
        setState(() => _quizDone = true);
      } else {
        _nextQuestion();
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('都道府県クイズ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () {
            if (_started && !_quizDone) {
              setState(() { _started = false; _quizDone = false; });
            } else {
              context.canPop() ? context.pop() : context.go('/tools');
            }
          },
        ),
      ),
      body: !_started
          ? _buildSetup(cs)
          : _quizDone
              ? _buildResult(cs)
              : _buildQuestion(cs),
    );
  }

  // ─── 设置页 ────────────────────────────────────────────────────────
  Widget _buildSetup(ColorScheme cs) {
    final regionCount = _selectedRegion == '全部'
        ? _prefectures.length
        : _prefectures.where((p) => p.region == _selectedRegion).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.map_rounded, size: 64, color: cs.primary),
        const SizedBox(height: 16),
        Text('都道府県クイズ', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 8),
        Text('看汉字选读音，学习 47 个都道府県の名前！', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: cs.outline)),
        const SizedBox(height: 24),
        Text('选择地区', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _regions.map((r) => ChoiceChip(
            label: Text(r),
            selected: _selectedRegion == r,
            onSelected: (_) => setState(() => _selectedRegion = r),
          )).toList(),
        ),
        const SizedBox(height: 8),
        Text('包含 $regionCount 个都道府県，每轮最多 10 题',
            style: TextStyle(fontSize: 12, color: cs.outline)),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startQuiz,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('开始测验', style: TextStyle(fontSize: 16)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  // ─── 答题页 ────────────────────────────────────────────────────────
  Widget _buildQuestion(ColorScheme cs) {
    final progress = (_qIndex + 1) / _total;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 进度
          Row(children: [
            Text('${_qIndex + 1} / $_total', style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
            const SizedBox(width: 8),
            Expanded(child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6,
                  backgroundColor: cs.surfaceContainerHigh,
                  valueColor: AlwaysStoppedAnimation(cs.primary)),
            )),
            const SizedBox(width: 8),
            Text('正确 $_correct', style: TextStyle(fontSize: 13, color: Colors.green.shade700)),
          ]),
          const SizedBox(height: 8),
          // 地区标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
            child: Text(_current.region, style: TextStyle(fontSize: 12, color: cs.primary)),
          ),
          const SizedBox(height: 24),
          // 汉字
          Text(_current.kanji,
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: 4)),
          const SizedBox(height: 8),
          if (_answered)
            Text(_current.romaji, style: TextStyle(fontSize: 14, color: cs.outline)),
          const Spacer(),
          // 选项
          ...List.generate(_options.length, (i) {
            Color bg = cs.surface;
            Color border = cs.outlineVariant;
            Color textColor = cs.onSurface;
            if (_answered) {
              if (_options[i] == _current.hiragana) {
                bg = Colors.green.shade50;
                border = Colors.green;
                textColor = Colors.green.shade800;
              } else if (i == _selectedIdx) {
                bg = Colors.red.shade50;
                border = Colors.red;
                textColor = Colors.red.shade800;
              }
            } else if (i == _selectedIdx) {
              border = cs.primary;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                onTap: () => _onSelect(i),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: border, width: 1.5),
                  ),
                  child: Text(_options[i], textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: textColor)),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── 结果页 ────────────────────────────────────────────────────────
  Widget _buildResult(ColorScheme cs) {
    final pct = _total > 0 ? (_correct / _total * 100).round() : 0;
    final stars = pct >= 90 ? 3 : pct >= 60 ? 2 : pct > 0 ? 1 : 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pct >= 90 ? '🎉' : pct >= 60 ? '👍' : '💪', style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('测验完成！', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('${'⭐' * stars}${'☆' * (3 - stars)}', style: const TextStyle(fontSize: 28, letterSpacing: 4)),
            const SizedBox(height: 16),
            _resultRow('正确', '$_correct / $_total', Colors.green),
            _resultRow('正确率', '$pct%', cs.primary),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() { _started = false; _quizDone = false; }),
                  icon: const Icon(Icons.settings),
                  label: const Text('重新设置'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _startQuiz,
                  icon: const Icon(Icons.refresh),
                  label: const Text('再来一轮'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _resultRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey.shade600))),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
