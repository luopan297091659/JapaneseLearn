import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/tts_helper.dart';
import '../../widgets/kana_stroke_widget.dart';
import '../../data/kana_data.dart';
import 'package:go_router/go_router.dart';

class GojuonScreen extends StatefulWidget {
  const GojuonScreen({super.key});
  @override
  State<GojuonScreen> createState() => _GojuonScreenState();
}

class _GojuonScreenState extends State<GojuonScreen> with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  bool _showKata = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _initTts();
  }

  Future<void> _initTts() async {
    _tts.setErrorHandler((err) => debugPrint('TTS error: $err'));
    await TtsHelper.configureForJapanese(_tts);
  }

  @override
  void dispose() { _tts.stop(); _tabCtrl.dispose(); super.dispose(); }

  Future<void> _speak(String text) async {
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      final result = await _tts.speak(text);
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
  }

  Future<void> _speakSlow(String text) async {
    try {
      try { await _tts.setLanguage('ja-JP'); } catch (_) {}
      await _tts.setVolume(1.0);
      final prefs = await SharedPreferences.getInstance();
      final slowRate = prefs.getDouble('slow_speed') ?? 0.5;
      await _tts.setSpeechRate(slowRate * 0.5);
      final result = await _tts.speak(text);
      await _tts.setSpeechRate(0.5);
      if (result != 1 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音引擎不可用，请检查系统TTS设置'), duration: Duration(seconds: 3)),
        );
      }
    } catch (e) {
      await _tts.setSpeechRate(0.5);
      debugPrint('TTS speak slow error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('五十音'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/study'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => setState(() => _showKata = !_showKata),
            icon: Icon(_showKata ? Icons.translate : Icons.text_fields, size: 18),
            label: Text(_showKata ? '片仮名' : '平仮名', style: const TextStyle(fontSize: 13)),
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '清音'),
            Tab(text: '浊音/半浊音'),
            Tab(text: '拗音'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildGrid(gojuonData, 5),
          _buildGrid(dakuonData, 5),
          _buildGrid(youonData, 3),
        ],
      ),
    );
  }

  /// 判断某个假名是否有对应的 strokesvg SVG 文件
  bool _hasSvg(String kana) {
    // 拗音组合（如きゃ）的每个字符都有单独的 SVG
    return kana.runes.every((r) => String.fromCharCode(r).length == 1);
  }

  void _showKanaPractice(List<String> kana) {
    final hira = kana[0];
    final kata = kana[1];
    final roma = kana[2];
    _speak(hira);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _KanaPracticeSheet(
        hiragana: hira,
        katakana: kata,
        romaji: roma,
        showKata: _showKata,
        hasSvg: _hasSvg(_showKata ? kata : hira),
        onSpeak: () => _speak(hira),
        onSpeakSlow: () => _speakSlow(hira),
      ),
    );
  }

  Widget _buildGrid(List<List<List<String>>> data, int colCount) {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: data.length,
      itemBuilder: (_, rowIdx) {
        final row = data[rowIdx];
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(colCount, (colIdx) {
              if (colIdx >= row.length || row[colIdx].isEmpty) {
                return const SizedBox(width: 68, height: 68);
              }
              final kana = row[colIdx];
              final display = _showKata ? kana[1] : kana[0];
              final roma = kana[2];
              return _KanaCell(
                display: display,
                roma: roma,
                onTap: () => _showKanaPractice(kana),
              );
            }),
          ),
        );
      },
    );
  }
}

class _KanaCell extends StatelessWidget {
  final String display;
  final String roma;
  final VoidCallback onTap;
  const _KanaCell({required this.display, required this.roma, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 68,
        height: 68,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(roma, style: TextStyle(fontSize: 11, color: cs.outline)),
            Text(display, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w500, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

// ── 假名详情面板 ──

class _KanaPracticeSheet extends StatefulWidget {
  final String hiragana;
  final String katakana;
  final String romaji;
  final bool showKata;
  final bool hasSvg;
  final VoidCallback onSpeak;
  final VoidCallback onSpeakSlow;

  const _KanaPracticeSheet({
    required this.hiragana,
    required this.katakana,
    required this.romaji,
    required this.showKata,
    required this.hasSvg,
    required this.onSpeak,
    required this.onSpeakSlow,
  });

  @override
  State<_KanaPracticeSheet> createState() => _KanaPracticeSheetState();
}

class _KanaPracticeSheetState extends State<_KanaPracticeSheet> {
  String get _displayKana => widget.showKata ? widget.katakana : widget.hiragana;
  String get _otherKana => widget.showKata ? widget.hiragana : widget.katakana;
  bool get _isKatakana => widget.showKata;
  List<String> get _chars => _displayKana.split('');
  bool get _isMulti => _chars.length > 1;

  // For sequential yo-on animation
  late List<KanaStrokeController> _strokeControllers;
  int _animKey = 0;

  @override
  void initState() {
    super.initState();
    _strokeControllers = List.generate(_chars.length, (_) => KanaStrokeController());
  }

  void _replayAnimation() {
    // Recreate controllers so old dispose() won't detach the new ones
    _strokeControllers = List.generate(_chars.length, (_) => KanaStrokeController());
    setState(() => _animKey++);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: widget.hasSvg ? 0.72 : 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: _buildInfoView(cs, scrollController),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoView(ColorScheme cs, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        // Top hero: stroke animation or static text
        if (widget.hasSvg) ...[
          SizedBox(
            height: _isMulti ? 160 : 200,
            child: _buildStrokeAnimation(),
          ),
        ] else ...[
          Center(
            child: Text(
              _displayKana,
              style: TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.w900,
                color: cs.primary,
                height: 1.1,
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Romaji + other-form compact row
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.romaji,
                style: TextStyle(fontSize: 20, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_isKatakana ? "平仮名" : "片仮名"}: $_otherKana',
                  style: TextStyle(fontSize: 13, color: cs.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // All action buttons in one row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onSpeak,
              icon: const Icon(Icons.volume_up_rounded, size: 18),
              label: const Text('发音'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: widget.onSpeakSlow,
              icon: const Text('🐌', style: TextStyle(fontSize: 14)),
              label: const Text('慢速'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
              ),
            ),
            if (widget.hasSvg) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _replayAnimation,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('重播'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStrokeAnimation() {
    final chars = _chars;
    if (chars.length == 1) {
      return KanaStrokeWidget(
        key: ValueKey('anim-${chars[0]}-$_isKatakana-$_animKey'),
        kana: chars[0],
        isKatakana: _isKatakana,
        animationOnly: true,
      );
    }
    // Multi-char (yo-on): sequential left-to-right animation
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(chars.length, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: KanaStrokeWidget(
              key: ValueKey('anim-${chars[i]}-$_isKatakana-$_animKey'),
              kana: chars[i],
              isKatakana: _isKatakana,
              animationOnly: true,
              autoPlay: i == 0,
              controller: _strokeControllers[i],
              onAnimationComplete: i < chars.length - 1
                  ? () => _strokeControllers[i + 1].play()
                  : null,
            ),
          ),
        );
      }),
    );
  }
}
