import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import '../../utils/tts_helper.dart';

// ── 46 都道府县数据（不含冲绳） ───────────────────────────────────────────────
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
];


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
        try { await TtsHelper.setJapaneseVoice(_tts); } catch (_) {}
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
        title: const Text('都道府県测验'),
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
        Text('都道府県测验', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 8),
        Text('看汉字选读音，学习 ${_prefectures.length} 个都道府県の名前！', textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: cs.outline)),
        const SizedBox(height: 24),
        Text('选择地区', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
        const SizedBox(height: 8),
        _ZoomableJapanMap(
          selectedRegion: _selectedRegion,
          onRegionSelected: (region) => setState(() => _selectedRegion = region),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            key: ValueKey(_selectedRegion),
            _selectedRegion == '全部'
              ? '全部 ${_prefectures.length} 个都道府県，每轮最多 10 题'
                : '$_selectedRegion · 包含 $regionCount 个都道府県，每轮最多 10 题',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.outline),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startQuiz,
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            _selectedRegion == '全部' ? '开始测验（全部）' : '开始 $_selectedRegion 测验',
            style: const TextStyle(fontSize: 16),
          ),
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

// ─── Zoomable Japan map with Matrix4 animation ──────────────────────────────

class _ZoomableJapanMap extends StatefulWidget {
  final String selectedRegion;
  final ValueChanged<String> onRegionSelected;
  const _ZoomableJapanMap({required this.selectedRegion, required this.onRegionSelected});

  @override
  State<_ZoomableJapanMap> createState() => _ZoomableJapanMapState();
}

class _ZoomableJapanMapState extends State<_ZoomableJapanMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  Animation<Matrix4>? _matrixAnim;
  Size _size = const Size(300, 236);

  static const _regionFocals = <String, Offset>{
    '全部':   Offset(0.50, 0.48),
    '北海道': Offset(0.81, 0.17),
    '東北':   Offset(0.64, 0.34),
    '関東':   Offset(0.62, 0.47),
    '中部':   Offset(0.52, 0.44),
    '近畿':   Offset(0.42, 0.49),
    '中国':   Offset(0.31, 0.49),
    '四国':   Offset(0.44, 0.65),
    '九州':   Offset(0.23, 0.66),
  };

  static const _hotspots = <({String region, double left, double top, double w, double h})>[
    (region: '北海道', left: 0.68, top: 0.09, w: 0.24, h: 0.20),
    (region: '東北',   left: 0.56, top: 0.24, w: 0.18, h: 0.21),
    (region: '関東',   left: 0.55, top: 0.40, w: 0.17, h: 0.17),
    (region: '中部',   left: 0.43, top: 0.34, w: 0.16, h: 0.17),
    (region: '近畿',   left: 0.34, top: 0.40, w: 0.15, h: 0.16),
    (region: '中国',   left: 0.21, top: 0.40, w: 0.15, h: 0.16),
    (region: '四国',   left: 0.36, top: 0.58, w: 0.16, h: 0.13),
    (region: '九州',   left: 0.11, top: 0.53, w: 0.22, h: 0.24),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_ZoomableJapanMap old) {
    super.didUpdateWidget(old);
    if (old.selectedRegion != widget.selectedRegion) {
      _animateTo(widget.selectedRegion);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Matrix4 _computeMatrix(String region) {
    if (region == '全部') return Matrix4.identity();
    const zoom = 2.3;
    final focal = _regionFocals[region] ?? const Offset(0.5, 0.48);
    final tx = _size.width / 2 - focal.dx * _size.width * zoom;
    final ty = _size.height / 2 - focal.dy * _size.height * zoom;
    return Matrix4.identity()
      ..translate(tx, ty)
      ..scale(zoom);
  }

  void _animateTo(String region) {
    final from = _matrixAnim?.value ?? Matrix4.identity();
    final to = _computeMatrix(region);
    _matrixAnim = Matrix4Tween(begin: from, end: to)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = Size(constraints.maxWidth, constraints.maxHeight);
            final matrix = _matrixAnim?.value ?? _computeMatrix(widget.selectedRegion);
            return Stack(
              children: [
                // 缩放后的地图底图
                Transform(
                  transform: matrix,
                  child: SizedBox.expand(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SvgPicture.asset(
                            'assets/svg/maps/japan_eight_regions_zh_hant.svg',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // 热区 InkWell 层（随地图一同缩放，点击命中正确区域）
                Transform(
                  transform: matrix,
                  child: SizedBox.expand(
                    child: Stack(
                      children: _hotspots.map((zone) {
                        final active = widget.selectedRegion == zone.region;
                        return Positioned(
                          left: constraints.maxWidth * zone.left,
                          top: constraints.maxHeight * zone.top,
                          width: constraints.maxWidth * zone.w,
                          height: constraints.maxHeight * zone.h,
                          child: InkWell(
                            onTap: () => widget.onRegionSelected(
                              widget.selectedRegion == zone.region
                                  ? '全部'
                                  : zone.region,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                color: active
                                    ? cs.primary.withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: active
                                      ? cs.primary
                                      : cs.outline.withValues(alpha: 0.22),
                                  width: active ? 1.5 : 0.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                // 底部提示栏（固定，不参与缩放）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    color: cs.surface.withValues(alpha: 0.88),
                    child: widget.selectedRegion == '全部'
                        ? Text(
                            '点击地图区域选择地区',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: cs.outline),
                          )
                        : GestureDetector(
                            onTap: () => widget.onRegionSelected('全部'),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.zoom_out_rounded,
                                    size: 14, color: cs.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '已选 ${widget.selectedRegion}，点此缩小查看全图',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.primary,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
