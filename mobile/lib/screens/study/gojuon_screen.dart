import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';

// ── 五十音数据 ──
// 每行: [平假名, 片假名, 罗马音]
const _gojuon = <List<List<String>>>[
  [['あ','ア','a'],['い','イ','i'],['う','ウ','u'],['え','エ','e'],['お','オ','o']],
  [['か','カ','ka'],['き','キ','ki'],['く','ク','ku'],['け','ケ','ke'],['こ','コ','ko']],
  [['さ','サ','sa'],['し','シ','shi'],['す','ス','su'],['せ','セ','se'],['そ','ソ','so']],
  [['た','タ','ta'],['ち','チ','chi'],['つ','ツ','tsu'],['て','テ','te'],['と','ト','to']],
  [['な','ナ','na'],['に','ニ','ni'],['ぬ','ヌ','nu'],['ね','ネ','ne'],['の','ノ','no']],
  [['は','ハ','ha'],['ひ','ヒ','hi'],['ふ','フ','fu'],['へ','ヘ','he'],['ほ','ホ','ho']],
  [['ま','マ','ma'],['み','ミ','mi'],['む','ム','mu'],['め','メ','me'],['も','モ','mo']],
  [['や','ヤ','ya'],[],['ゆ','ユ','yu'],[],['よ','ヨ','yo']],
  [['ら','ラ','ra'],['り','リ','ri'],['る','ル','ru'],['れ','レ','re'],['ろ','ロ','ro']],
  [['わ','ワ','wa'],[],[],[],['を','ヲ','wo']],
  [['ん','ン','n'],[],[],[],[]],
];

// ── 浊音/半浊音 ──
const _dakuon = <List<List<String>>>[
  [['が','ガ','ga'],['ぎ','ギ','gi'],['ぐ','グ','gu'],['げ','ゲ','ge'],['ご','ゴ','go']],
  [['ざ','ザ','za'],['じ','ジ','ji'],['ず','ズ','zu'],['ぜ','ゼ','ze'],['ぞ','ゾ','zo']],
  [['だ','ダ','da'],['ぢ','ヂ','di'],['づ','ヅ','du'],['で','デ','de'],['ど','ド','do']],
  [['ば','バ','ba'],['び','ビ','bi'],['ぶ','ブ','bu'],['べ','ベ','be'],['ぼ','ボ','bo']],
  [['ぱ','パ','pa'],['ぴ','ピ','pi'],['ぷ','プ','pu'],['ぺ','ペ','pe'],['ぽ','ポ','po']],
];

// ── 拗音 ──
const _youon = <List<List<String>>>[
  [['きゃ','キャ','kya'],['きゅ','キュ','kyu'],['きょ','キョ','kyo']],
  [['しゃ','シャ','sha'],['しゅ','シュ','shu'],['しょ','ショ','sho']],
  [['ちゃ','チャ','cha'],['ちゅ','チュ','chu'],['ちょ','チョ','cho']],
  [['にゃ','ニャ','nya'],['にゅ','ニュ','nyu'],['にょ','ニョ','nyo']],
  [['ひゃ','ヒャ','hya'],['ひゅ','ヒュ','hyu'],['ひょ','ヒョ','hyo']],
  [['みゃ','ミャ','mya'],['みゅ','ミュ','myu'],['みょ','ミョ','myo']],
  [['りゃ','リャ','rya'],['りゅ','リュ','ryu'],['りょ','リョ','ryo']],
  [['ぎゃ','ギャ','gya'],['ぎゅ','ギュ','gyu'],['ぎょ','ギョ','gyo']],
  [['じゃ','ジャ','ja'],['じゅ','ジュ','ju'],['じょ','ジョ','jo']],
  [['びゃ','ビャ','bya'],['びゅ','ビュ','byu'],['びょ','ビョ','byo']],
  [['ぴゃ','ピャ','pya'],['ぴゅ','ピュ','pyu'],['ぴょ','ピョ','pyo']],
];

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
    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
  }

  @override
  void dispose() { _tts.stop(); _tabCtrl.dispose(); super.dispose(); }

  void _speak(String text) => _tts.speak(text);

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
          _buildGrid(_gojuon, 5),
          _buildGrid(_dakuon, 5),
          _buildGrid(_youon, 3),
        ],
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
                onTap: () => _speak(kana[0]),
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
