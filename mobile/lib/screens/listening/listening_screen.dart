import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../widgets/audio_player_widget.dart';

class ListeningScreen extends StatefulWidget {
  const ListeningScreen({super.key});
  @override
  State<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends State<ListeningScreen> {
  String _selectedLevel = 'N5';
  List<dynamic> _tracks = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _restoreLevel(); }

  Future<void> _restoreLevel() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString('listening_selected_level');
    if (saved != null && ['N5','N4','N3','N2','N1'].contains(saved)) {
      _selectedLevel = saved;
    }
    _load();
  }

  Future<void> _saveLevel(String level) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('listening_selected_level', level);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await apiService.getListeningTracks(level: _selectedLevel);
      setState(() { _tracks = res['data'] ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('聴解練習'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
        actions: [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: ['N5','N4','N3','N2','N1'].map((l) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(l),
                  selected: _selectedLevel == l,
                  onSelected: (_) { setState(() => _selectedLevel = l); _saveLevel(l); _load(); },
                ),
              )).toList()),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
              ? const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.headphones_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('暂无听力材料', style: TextStyle(color: Colors.grey)),
                  ],
                ))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tracks.length,
                  itemBuilder: (_, i) {
                    final t = _tracks[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.primaryContainer,
                          child: Icon(Icons.play_arrow_rounded, color: cs.primary),
                        ),
                        title: Text(t['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${t['duration_seconds'] != null ? '${(t['duration_seconds'] / 60).round()}分 ' : ''}${t['category'] ?? ''}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.headphones, size: 14, color: cs.outline),
                          Text(' ${t['play_count'] ?? 0}', style: TextStyle(color: cs.outline, fontSize: 12)),
                        ]),
                        onTap: () => _showPlayer(context, t),
                      ),
                    );
                  },
                ),
    );
  }

  void _showPlayer(BuildContext context, dynamic track) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AudioPlayerSheet(track: track),
    );
  }
}

class _AudioPlayerSheet extends StatefulWidget {
  final dynamic track;
  const _AudioPlayerSheet({required this.track});
  @override
  State<_AudioPlayerSheet> createState() => __AudioPlayerSheetState();
}

class __AudioPlayerSheetState extends State<_AudioPlayerSheet> {
  bool _showTranscript = false;
  late final DateTime _openTime;

  @override
  void initState() {
    super.initState();
    _openTime = DateTime.now();
  }

  @override
  void dispose() {
    final dur = DateTime.now().difference(_openTime).inSeconds;
    if (dur > 3) {
      apiService.logActivity(activityType: 'listening', refId: widget.track['id']?.toString(), durationSeconds: dur);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final audioUrl = widget.track['audio_url'] as String?;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(
            color: cs.outline, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(widget.track['title'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(widget.track['title_zh'] ?? '', style: TextStyle(color: cs.outline)),
          const SizedBox(height: 20),
          // Real audio player
          if (audioUrl != null)
            AudioPlayerWidget(audioUrl: audioUrl, compact: false)
          else
            const Text('暂无音频', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: Icon(_showTranscript ? Icons.visibility_off : Icons.subtitles),
            label: Text(_showTranscript ? '隐藏原文' : '显示原文'),
            onPressed: () => setState(() => _showTranscript = !_showTranscript),
          ),
          if (_showTranscript && widget.track['transcript'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.track['transcript']),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
