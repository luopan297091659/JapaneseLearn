import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import '../../config/app_config.dart';
import '../../services/api_service.dart';
import '../../services/local_db.dart';
import '../../utils/japanese_text_utils.dart';
import '../../utils/tts_helper.dart';
import '../../widgets/furigana_text.dart';
import 'vocab_whiteboard_screen.dart';

final _localFuriganaRe = RegExp(
    r'[\u4e00-\u9fff\uff10-\uff19\u3041-\u30ff]+\[[^\]]*[\u3040-\u30ff][^\]]*\]');

bool _localHasKana(String s) => RegExp(r'[\u3040-\u30ff]').hasMatch(s);

bool _localIsSwapped(LocalVocabModel c) =>
    !_localHasKana(c.word) && _localFuriganaRe.hasMatch(c.reading);

String _localDisplayWord(LocalVocabModel c) =>
    _localIsSwapped(c) ? c.reading : c.word;

String _localDisplayReading(LocalVocabModel c) =>
    _localIsSwapped(c) ? c.word : c.reading;

String _localPosLabel(String pos) {
  final raw = pos.trim();
  if (raw.isEmpty) return '其他';
  final text = raw.toLowerCase();
  if (RegExp(r'(代名詞|代名词|pronoun)').hasMatch(text)) return '代词';
  if (RegExp(r'(数詞|数词|numeric|number)').hasMatch(text)) return '数词';
  if (RegExp(r'(名詞|名词|名|noun|^n[\.\s]|^n$)').hasMatch(text)) {
    return '名词';
  }
  if (RegExp(r'(動詞|动词|動|动|verb|^v[\.\s]|^v$|自動|他動|自他|サ変|する)').hasMatch(text)) {
    return '动词';
  }
  if (RegExp(r'(形容動詞|形动|形動|な形容詞|na-adj|adjectival noun)').hasMatch(text)) {
    return '形容动词';
  }
  if (RegExp(r'(形容詞|形容词|い形容詞|adj|adjective|^a$|^i-adj)').hasMatch(text)) {
    return '形容词';
  }
  if (RegExp(r'(副詞|副词|副|adverb|adv)').hasMatch(text)) {
    return '副词';
  }
  if (RegExp(r'(助詞|助词|助|particle|prt)').hasMatch(text)) {
    return '助词';
  }
  if (RegExp(r'(接続詞|接续词|接続|接续|conjunction|conj)').hasMatch(text)) {
    return '连词';
  }
  if (RegExp(r'(感動詞|感叹词|感動|感叹|interjection|int)').hasMatch(text)) {
    return '感叹词';
  }
  if (RegExp(r'(接頭|接头|prefix)').hasMatch(text)) return '接头词';
  if (RegExp(r'(接尾|suffix)').hasMatch(text)) return '接尾词';
  if (RegExp(r'(連体詞|连体词|rentaishi|prenominal)').hasMatch(text)) {
    return '连体词';
  }
  const map = {
    'noun': '名词',
    'verb': '动词',
    'adjective': '形容词',
    'adverb': '副词',
    'particle': '助词',
    'conjunction': '连词',
    'interjection': '感叹词',
    'other': '其他',
  };
  return map[text] ?? raw;
}

class LocalVocabDetailArgs {
  final LocalVocabModel? initialCard;
  final List<LocalVocabModel>? cards;
  final int initialIndex;

  const LocalVocabDetailArgs({
    this.initialCard,
    this.cards,
    this.initialIndex = 0,
  });
}

class LocalVocabDetailScreen extends StatefulWidget {
  final String cardId;
  final LocalVocabDetailArgs? args;

  const LocalVocabDetailScreen({
    super.key,
    required this.cardId,
    this.args,
  });

  @override
  State<LocalVocabDetailScreen> createState() => _LocalVocabDetailScreenState();
}

class _LocalVocabDetailScreenState extends State<LocalVocabDetailScreen> {
  final AudioPlayer _player = AudioPlayer();
  FlutterTts? _tts;
  LocalVocabModel? _card;
  bool _loading = true;
  String? _error;
  late int _currentIndex;
  List<LocalVocabModel> _cards = const [];
  bool _wordPlaying = false;
  bool _examplePlaying = false;
  bool _wordLoading = false;
  bool _exampleLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.args?.initialIndex ?? 0;
    _cards = widget.args?.cards ?? const [];
    _loadCard();
  }

  @override
  void dispose() {
    _player.dispose();
    _tts?.stop();
    super.dispose();
  }

  Future<void> _loadCard() async {
    final initialCard = widget.args?.initialCard;
    if (initialCard != null && initialCard.id == widget.cardId) {
      setState(() {
        _card = initialCard;
        _loading = false;
      });
      return;
    }

    if (_cards.isNotEmpty &&
        _currentIndex >= 0 &&
        _currentIndex < _cards.length) {
      setState(() {
        _card = _cards[_currentIndex];
        _loading = false;
      });
      return;
    }

    final card = await localDb.getCardById(widget.cardId);
    if (!mounted) return;
    setState(() {
      _card = card;
      _loading = false;
      _error = card == null ? '未找到该卡片' : null;
    });
  }

  Future<FlutterTts> _getTts() async {
    if (_tts == null) {
      _tts = FlutterTts();
      await TtsHelper.configureForJapanese(_tts!);
    }
    return _tts!;
  }

  Future<void> _stopAll() async {
    await _player.stop();
    await _tts?.stop();
    if (!mounted) return;
    setState(() {
      _wordLoading = false;
      _exampleLoading = false;
      _wordPlaying = false;
      _examplePlaying = false;
    });
  }

  Future<bool> _playTts(String text,
      {required bool isExample, bool slow = false}) async {
    if (text.trim().isEmpty) return false;
    if (!mounted) return false;
    setState(() {
      if (isExample) {
        _exampleLoading = true;
      } else {
        _wordLoading = true;
      }
    });
    try {
      if (isExample) {
        await _player.stop();
        if (mounted) setState(() => _wordPlaying = false);
      } else {
        await _player.stop();
        if (mounted) setState(() => _examplePlaying = false);
      }
      final tts = await _getTts();
      await tts.stop();
      await tts.setSpeechRate(slow ? 0.25 : 0.45);
      if (mounted) {
        setState(() {
          if (isExample) {
            _exampleLoading = false;
            _examplePlaying = true;
          } else {
            _wordLoading = false;
            _wordPlaying = true;
          }
        });
      }
      tts.setCompletionHandler(() {
        if (!mounted) return;
        setState(() {
          if (isExample) {
            _examplePlaying = false;
          } else {
            _wordPlaying = false;
          }
        });
      });
      return TtsHelper.speakJapanese(tts, text);
    } catch (e) {
      debugPrint('本地词库 TTS 播放失败: $e');
      if (!mounted) return false;
      setState(() {
        if (isExample) {
          _exampleLoading = false;
          _examplePlaying = false;
        } else {
          _wordLoading = false;
          _wordPlaying = false;
        }
      });
      return false;
    }
  }

  Future<String> _resolveAudioPath(String url) async {
    if (url.startsWith('/uploads/') || url.startsWith('/audio/')) {
      return apiService.downloadToTempFile(AppConfig.serverRoot + url);
    }
    if (url.startsWith('file://')) {
      final path = url.substring(7);
      if (!await File(path).exists()) {
        throw Exception('本地音频文件不存在');
      }
      return path;
    }
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url) || url.startsWith('/')) {
      if (!await File(url).exists()) {
        throw Exception('本地音频文件不存在');
      }
      return url;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final needsProxy = url.startsWith(AppConfig.baseUrl) ||
          url.startsWith(AppConfig.serverRoot);
      if (needsProxy) {
        return apiService.downloadToTempFile(url);
      }
      await _player.setUrl(url);
      return '';
    }
    return url;
  }

  Future<void> _playAudio({
    required String? audioUrl,
    required String fallbackText,
    required bool isExample,
    bool slow = false,
    bool notifyOnFallback = false,
  }) async {
    if (audioUrl == null || audioUrl.trim().isEmpty) {
      await _playTts(fallbackText, isExample: isExample, slow: slow);
      return;
    }

    if (!mounted) return;
    setState(() {
      if (isExample) {
        _exampleLoading = true;
      } else {
        _wordLoading = true;
      }
    });
    try {
      if (isExample) {
        await _player.stop();
        if (mounted) setState(() => _wordPlaying = false);
      } else {
        await _player.stop();
        if (mounted) setState(() => _examplePlaying = false);
      }
      await _tts?.stop();

      final localPath = await _resolveAudioPath(audioUrl);
      if (localPath.isNotEmpty) {
        await _player.setFilePath(localPath);
      }
      await _player.setSpeed(slow ? 0.65 : 1.0);
      await _player.setVolume(1.0);

      if (mounted) {
        setState(() {
          if (isExample) {
            _exampleLoading = false;
            _examplePlaying = true;
          } else {
            _wordLoading = false;
            _wordPlaying = true;
          }
        });
      }

      await _player.play();

      if (!mounted) return;
      setState(() {
        if (isExample) {
          _examplePlaying = false;
        } else {
          _wordPlaying = false;
        }
      });
    } catch (e) {
      debugPrint('本地词库音频播放失败，切换 TTS: $e');
      final fallbackOk =
          await _playTts(fallbackText, isExample: isExample, slow: slow);
      if (!mounted) return;
      if (notifyOnFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(fallbackOk ? '音频不可用，已使用 TTS' : '音频和 TTS 暂时都不可用')),
        );
      }
    }
  }

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= _cards.length) return;
    await _stopAll();
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _card = _cards[index];
    });
  }

  Future<void> _promoteCurrentCard() async {
    if (_cards.isEmpty || _currentIndex < 0 || _currentIndex >= _cards.length)
      return;
    final current = _cards[_currentIndex];
    int nextStage = current.learningStage;
    if (current.learningStage == 0) {
      nextStage = 1;
    } else if (current.learningStage == 1) {
      nextStage = 2;
    }
    if (nextStage == current.learningStage) return;

    await localDb.setLearningStage(current.id, stage: nextStage);
    if (!mounted) return;

    final updated = current.copyWithStage(nextStage);
    setState(() {
      _cards[_currentIndex] = updated;
      if (_card?.id == updated.id) {
        _card = updated;
      }
    });
  }

  Future<void> _goToWithPromote(int index) async {
    if (_cards.isNotEmpty && index == _cards.length - 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('进入最后一张'),
          content: Text('即将进入第 ${_cards.length} 张，是否继续？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('继续')),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    await _promoteCurrentCard();
    if (index < 0 || index >= _cards.length) return;
    await _stopAll();
    if (!mounted) return;
    setState(() {
      _currentIndex = index;
      _card = _cards[index];
    });

    final nextCard = _cards[index];
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _card?.id != nextCard.id) return;
      _playAudio(
        audioUrl: nextCard.audioUrl,
        fallbackText: _localDisplayWord(nextCard),
        isExample: false,
      );
    });
  }

  Future<void> _finishCurrentSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完成本轮学习'),
        content: const Text('当前已是最后一张，确认完成本轮学习吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('继续学习')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认完成')),
        ],
      ),
    );

    if (confirmed != true) return;
    await _promoteCurrentCard();
    if (!mounted) return;
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = _card;
    final hasPrev = _cards.isNotEmpty && _currentIndex > 0;
    final hasNext = _cards.isNotEmpty && _currentIndex < _cards.length - 1;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('我的词库详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (card != null)
            IconButton(
              tooltip: '白板练习',
              icon: const Icon(Icons.draw_rounded),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VocabWhiteboardScreen(
                      word: _localDisplayWord(card),
                      reading: _localDisplayReading(card),
                      meaningZh: card.meaningZh,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : card == null
              ? Center(child: Text(_error ?? '加载失败'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primaryContainer, cs.secondaryContainer],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          FuriganaText(
                            text: _localDisplayWord(card),
                            fontSize: 40,
                            color: cs.primary,
                          ),
                          if (_localDisplayReading(card).isNotEmpty &&
                              cleanReading(_localDisplayReading(card)) !=
                                  cleanWord(_localDisplayWord(card)))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                cleanReading(_localDisplayReading(card)),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: cs.primary.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (card.jlptLevel.trim().isNotEmpty)
                                _MetaChip(
                                    label: card.jlptLevel, color: cs.primary),
                              if (card.partOfSpeech.isNotEmpty) ...[
                                if (card.jlptLevel.trim().isNotEmpty)
                                  const SizedBox(width: 8),
                                _MetaChip(
                                    label: _localPosLabel(card.partOfSpeech),
                                    color: cs.secondary),
                              ],
                              const SizedBox(width: 12),
                              _WordAudioButton(
                                loading: _wordLoading,
                                playing: _wordPlaying,
                                onTap: _wordLoading
                                    ? null
                                    : () => _playAudio(
                                          audioUrl: card.audioUrl,
                                          fallbackText: _localDisplayWord(card),
                                          isExample: false,
                                          notifyOnFallback: true,
                                        ),
                                color: cs.primary,
                              ),
                              const SizedBox(width: 6),
                              _WordSlowButton(
                                onTap: _wordLoading
                                    ? null
                                    : () => _playAudio(
                                          audioUrl: card.audioUrl,
                                          fallbackText: _localDisplayWord(card),
                                          isExample: false,
                                          slow: true,
                                          notifyOnFallback: true,
                                        ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _InfoSection(
                      title: '释义',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card.meaningZh,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          if (card.meaningEn != null &&
                              card.meaningEn!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              card.meaningEn!,
                              style: TextStyle(
                                  fontSize: 15, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (card.exampleSentence != null &&
                        card.exampleSentence!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InfoSection(
                        title: '例句',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    card.exampleSentence!,
                                    style: TextStyle(
                                      fontSize: 16,
                                      height: 1.7,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _InlineExampleAudioButton(
                                  loading: _exampleLoading,
                                  playing: _examplePlaying,
                                  onTap: _exampleLoading
                                      ? null
                                      : () => _playAudio(
                                            audioUrl: card.exampleAudioUrl,
                                            fallbackText: card.exampleSentence!,
                                            isExample: true,
                                            notifyOnFallback: true,
                                          ),
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 2),
                                _InlineSlowButton(
                                  onTap: _exampleLoading
                                      ? null
                                      : () => _playAudio(
                                            audioUrl: card.exampleAudioUrl,
                                            fallbackText: card.exampleSentence!,
                                            isExample: true,
                                            slow: true,
                                            notifyOnFallback: true,
                                          ),
                                ),
                              ],
                            ),
                            if (card.exampleReading != null &&
                                card.exampleReading!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                card.exampleReading!,
                                style: TextStyle(
                                    fontSize: 14, color: cs.onSurfaceVariant),
                              ),
                            ],
                            if (card.exampleMeaningZh != null &&
                                card.exampleMeaningZh!.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                card.exampleMeaningZh!,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
      bottomNavigationBar: _cards.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          hasPrev ? () => _goTo(_currentIndex - 1) : null,
                      icon: const Icon(Icons.arrow_back_ios_rounded, size: 16),
                      label: const Text('上一个'),
                    ),
                    const Spacer(),
                    Text(
                      '${_currentIndex + 1} / ${_cards.length}',
                      style: TextStyle(
                          color: cs.outline, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: hasNext
                          ? () => _goToWithPromote(_currentIndex + 1)
                          : _finishCurrentSession,
                      icon: Icon(
                          hasNext
                              ? Icons.arrow_forward_ios_rounded
                              : Icons.check_rounded,
                          size: 16),
                      label: Text(hasNext ? '下一个' : '完成'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _InfoSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.outline,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InlineExampleAudioButton extends StatelessWidget {
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;
  final Color color;

  const _InlineExampleAudioButton({
    required this.loading,
    required this.playing,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: playing && !loading
              ? color.withValues(alpha: 0.15)
              : Colors.transparent,
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
              )
            : Icon(
                playing
                    ? Icons.volume_up_rounded
                    : Icons.play_circle_outline_rounded,
                size: 20,
                color: color,
              ),
      ),
    );
  }
}

class _InlineSlowButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _InlineSlowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.orange.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: Text('🐌', style: TextStyle(fontSize: 14, height: 1.0)),
        ),
      ),
    );
  }
}

class _WordAudioButton extends StatelessWidget {
  final bool loading;
  final bool playing;
  final VoidCallback? onTap;
  final Color color;

  const _WordAudioButton({
    required this.loading,
    required this.playing,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: playing ? color.withValues(alpha: 0.15) : Colors.transparent,
        ),
        child: loading
            ? Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
              )
            : Icon(
                playing
                    ? Icons.volume_up_rounded
                    : Icons.play_circle_outline_rounded,
                color: color,
                size: 28,
              ),
      ),
    );
  }
}

class _WordSlowButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _WordSlowButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.orange.withValues(alpha: 0.1),
        ),
        child: const Center(
          child: Text('🐌', style: TextStyle(fontSize: 14, height: 1.0)),
        ),
      ),
    );
  }
}
