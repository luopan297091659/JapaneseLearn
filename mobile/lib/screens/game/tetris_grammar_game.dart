import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

// ══════════════════════════════════════════════════════════════════
//  题库（50题，3种类型：助词/动词活用/词义）
// ══════════════════════════════════════════════════════════════════
class _Q {
  final String t; // 'p' 助词  'v' 动词  'w' 词义
  final String s, a;
  final List<String> o;
  final String e;
  const _Q(this.t, this.s, this.a, this.o, this.e);
}
const _kQs = <_Q>[
  // ═══ 助词题库 — 覆盖全部日语助词 ═══
  // ── は ──
  _Q('p','私＿学生です','は',['は','が','も'],'「は」表示话题（主题标记）。'),
  _Q('p','この部屋＿広いです','は',['は','が','の'],'「は」表示话题。'),
  _Q('p','朝ご飯＿食べないです','は',['は','を','が'],'「は」用于对比或否定强调。'),
  _Q('p','東京＿便利ですが、大阪＿楽しい','は',['は','が','も'],'「は」用于对比两个话题。'),
  // ── が ──
  _Q('p','コーヒー＿好きです','が',['が','を','の'],'「が」与「好き/嫌い」搭配。'),
  _Q('p','日本語＿上手です','が',['が','は','を'],'「が」与「上手/下手」搭配。'),
  _Q('p','猫＿好きです','が',['が','は','を'],'「が」与「好き」搭配。'),
  _Q('p','雨＿降っています','が',['が','は','を'],'「が」表示自然现象主语。'),
  _Q('p','誰＿来ましたか','が',['が','は','を'],'疑问词做主语时用「が」。'),
  // ── を ──
  _Q('p','水＿飲みます','を',['を','に','で'],'「を」表示动作直接对象。'),
  _Q('p','本＿読みます','を',['を','に','で'],'「を」表示动作对象。'),
  _Q('p','ご飯＿食べます','を',['を','に','で'],'「を」表示动作对象。'),
  _Q('p','公園＿散歩します','を',['を','で','に'],'「を」表示经过/移动的场所。'),
  _Q('p','大学＿卒業しました','を',['を','に','で'],'「を」表示离开的起点。'),
  // ── に ──
  _Q('p','東京＿行きます','に',['に','を','で'],'「に」表示移动目的地。'),
  _Q('p','電車＿乗ります','に',['に','を','で'],'「に」乗る：乘坐交通工具。'),
  _Q('p','3時＿始まります','に',['に','で','から'],'「に」表示具体时间点。'),
  _Q('p','友達＿会います','に',['に','と','で'],'「に」会う：与某人见面。'),
  _Q('p','妹＿お菓子をあげます','に',['に','へ','と'],'「に」あげる：给予某人。'),
  _Q('p','先生＿もらいました','に',['に','から','で'],'「に」もらう：从…收到。'),
  _Q('p','部屋の中＿入ります','に',['に','を','で'],'「に」表示进入目的地。'),
  _Q('p','壁＿絵がかかっています','に',['に','で','が'],'「に」表示存在的位置。'),
  // ── へ ──
  _Q('p','学校＿行きます','へ',['へ','に','で'],'「へ」表示移动方向。'),
  _Q('p','南＿向かいます','へ',['へ','に','を'],'「へ」表示朝向的方向。'),
  // ── で ──
  _Q('p','図書館＿勉強します','で',['で','に','を'],'「で」表示动作场所。'),
  _Q('p','公園＿遊びます','で',['で','に','を'],'「で」表示活动场所。'),
  _Q('p','バス＿来ます','で',['で','を','に'],'「で」表示交通手段。'),
  _Q('p','ペン＿書きます','で',['で','を','に'],'「で」表示使用的工具。'),
  _Q('p','電話＿連絡します','で',['で','に','を'],'「で」表示联系手段。'),
  _Q('p','一人＿行きます','で',['で','と','に'],'「で」～人で：以…人数。'),
  _Q('p','地震＿家が壊れました','で',['で','に','が'],'「で」表示原因。'),
  // ── と ──
  _Q('p','山田さん＿話します','と',['と','に','で'],'「と」表示共同动作对象。'),
  _Q('p','友達＿映画を見ます','と',['と','に','で'],'「と」表示一起做某事的对象。'),
  _Q('p','りんご＿みかんを買いました','と',['と','や','も'],'「と」表示完全列举。'),
  // ── の ──
  _Q('p','私＿本です','の',['の','は','が'],'「の」表示所属关系。'),
  _Q('p','日本語＿先生です','の',['の','は','が'],'「の」表示修饰限定。'),
  _Q('p','赤い＿がほしいです','の',['の','は','を'],'「の」代替名词（形式名词用法）。'),
  // ── から ──
  _Q('p','どこ＿来ましたか','から',['から','に','で'],'「から」表示来源地/起点。'),
  _Q('p','日本＿来ました','から',['から','に','を'],'「から」表示移动起点。'),
  _Q('p','9時＿働きます','から',['から','に','まで'],'「から」表示开始时间。'),
  _Q('p','先生＿習います','から',['から','に','で'],'「から」表示获取来源。'),
  // ── まで ──
  _Q('p','駅＿歩いて行きます','まで',['まで','から','で'],'「まで」表示移动终点。'),
  _Q('p','5時＿仕事をします','まで',['まで','に','から'],'「まで」表示终止时间。'),
  _Q('p','東京から大阪＿3時間かかります','まで',['まで','に','で'],'「まで」表示到达终点。'),
  // ── より ──
  _Q('p','東京は大阪＿大きいです','より',['より','から','まで'],'「より」表示比较的基准。'),
  _Q('p','電車はバス＿速いです','より',['より','から','ほど'],'「より」表示比较对象。'),
  // ── や ──
  _Q('p','りんご＿みかんなどを買いました','や',['や','と','の'],'「や」表示不完全列举。'),
  _Q('p','本＿雑誌を読みます','や',['や','と','か'],'「や」部分列举，暗示还有其他。'),
  // ── とか ──
  _Q('p','寿司＿ラーメンとかが好きです','とか',['とか','や','と'],'「とか」口语的不完全列举。'),
  _Q('p','映画を見る＿音楽を聴くとかします','とか',['とか','や','し'],'「とか」列举动作（口语）。'),
  // ── だの ──
  _Q('p','あれが欲しい＿これが欲しいだの言っている','だの',['だの','とか','や'],'「だの」带有不满语气的列举。'),
  // ── も ──
  _Q('p','私＿学生です','も',['も','は','が'],'「も」表示"也"。'),
  _Q('p','どこに＿行きません','も',['も','は','か'],'疑问词＋「も」＋否定＝全否定。'),
  _Q('p','何＿食べたくないです','も',['も','を','は'],'何＋「も」＋否定＝什么都不…'),
  // ── だけ ──
  _Q('p','一つ＿ください','だけ',['だけ','しか','ばかり'],'「だけ」表示"仅仅、只"。'),
  _Q('p','日本語＿話せます','だけ',['だけ','しか','も'],'「だけ」限定范围。'),
  // ── しか ──
  _Q('p','100円＿ありません','しか',['しか','だけ','も'],'「しか」＋否定＝只有…（强调少）。'),
  _Q('p','水＿飲めません','しか',['しか','だけ','ばかり'],'「しか」＋否定＝只能喝水。'),
  // ── さえ ──
  _Q('p','子供＿知っている','でさえ',['でさえ','でも','だけ'],'「さえ」表示"连…都"。'),
  _Q('p','名前＿書けない','さえ',['さえ','しか','だけ'],'「さえ」连名字都不会写。'),
  // ── でも ──
  _Q('p','コーヒー＿飲みませんか','でも',['でも','を','は'],'「でも」表示举例提议。'),
  _Q('p','誰＿できます','でも',['でも','も','か'],'疑问词＋「でも」＝任何人都…'),
  // ── ばかり ──
  _Q('p','甘いもの＿食べています','ばかり',['ばかり','だけ','しか'],'「ばかり」表示"净是、老是"。'),
  _Q('p','ゲーム＿していないで勉強しなさい','ばかり',['ばかり','だけ','でも'],'「ばかり」尽是做游戏。'),
  // ── ほど ──
  _Q('p','死ぬ＿疲れた','ほど',['ほど','くらい','まで'],'「ほど」表示程度。'),
  _Q('p','泣きたい＿嬉しい','ほど',['ほど','くらい','ばかり'],'「ほど」表示到…程度。'),
  // ── くらい/ぐらい ──
  _Q('p','30分＿かかります','ぐらい',['ぐらい','ほど','まで'],'「ぐらい/くらい」表示大约。'),
  _Q('p','これ＿は自分でできます','くらい',['くらい','ほど','だけ'],'「くらい」表示轻视程度。'),
  // ── こそ ──
  _Q('p','今度＿頑張ります','こそ',['こそ','は','も'],'「こそ」表示强调。'),
  _Q('p','こちら＿よろしくお願いします','こそ',['こそ','も','は'],'「こそ」强调"才是我这边…"。'),
  // ── なり ──
  _Q('p','電話する＿メールするなりしてください','なり',['なり','とか','か'],'「なり」表示"…或…之类"。'),
  // ── て ──
  _Q('p','朝起き＿顔を洗います','て',['て','から','で'],'「て」表示动作连接。'),
  _Q('p','走っ＿学校に行きました','て',['て','から','で'],'「て」表示方式或连接。'),
  // ── から（原因） ──
  _Q('p','暑い＿窓を開けます','から',['から','ので','けど'],'「から」表示原因理由。'),
  _Q('p','時間がない＿急ぎましょう','から',['から','ので','のに'],'「から」表示理由。'),
  // ── ので ──
  _Q('p','疲れた＿少し休みます','ので',['ので','から','のに'],'「ので」表示客观原因。'),
  _Q('p','雨が降っている＿傘を持って行きます','ので',['ので','から','けど'],'「ので」客观理由说明。'),
  // ── が（转折） ──
  _Q('p','高い＿買いました','が',['が','から','ので'],'「が」表示转折。'),
  _Q('p','すみません＿ちょっといいですか','が',['が','けど','から'],'「が」用于礼貌引入话题。'),
  // ── けど/けれど ──
  _Q('p','食べたい＿我慢します','けど',['けど','が','ので'],'「けど」表示转折（口语）。'),
  _Q('p','行きたかった＿時間がなかった','けれど',['けれど','けど','のに'],'「けれど」转折（较正式）。'),
  // ── のに ──
  _Q('p','約束した＿来なかった','のに',['のに','けど','ので'],'「のに」表示不满。'),
  _Q('p','薬を飲んだ＿治らない','のに',['のに','けど','が'],'「のに」表示意外或遗憾。'),
  // ── し ──
  _Q('p','安い＿おいしいし、この店が好きです','し',['し','から','ので'],'「し」列举理由。'),
  _Q('p','天気もいい＿どこかに行きましょう','し',['し','から','ので'],'「し」列举理由。'),
  // ── ながら ──
  _Q('p','音楽を聴き＿勉強します','ながら',['ながら','て','つつ'],'「ながら」同时进行两个动作。'),
  _Q('p','歩き＿スマホを見るのは危ない','ながら',['ながら','て','つつ'],'「ながら」边走边看…'),
  // ── ば ──
  _Q('p','安けれ＿買います','ば',['ば','たら','と'],'「ば」表示假定条件。'),
  _Q('p','時間があれ＿行きたいです','ば',['ば','たら','と'],'「ば」如果有时间的话…'),
  // ── と（条件） ──
  _Q('p','ボタンを押す＿ドアが開きます','と',['と','ば','たら'],'「と」表示必然条件。'),
  _Q('p','春になる＿桜が咲きます','と',['と','ば','たら'],'「と」表示自然规律。'),
  // ── たら ──
  _Q('p','家に帰っ＿電話します','たら',['たら','ば','と'],'「たら」表示条件。'),
  _Q('p','雨が降っ＿試合は中止です','たら',['たら','ば','と'],'「たら」如果下雨的话…'),
  // ── ても ──
  _Q('p','雨が降っ＿行きます','ても',['ても','たら','のに'],'「ても」即使下雨也去。'),
  _Q('p','何回読ん＿わからない','でも',['でも','ても','のに'],'「でも」即使读了几遍也不懂。'),
  // ── つつ ──
  _Q('p','悪いと思い＿やめられない','つつ',['つつ','ながら','ても'],'「つつ」虽然知道不好却无法停止。'),
  // ── か ──
  _Q('p','これはいくらです＿','か',['か','よ','ね'],'「か」表示疑问。'),
  _Q('p','明日来ます＿','か',['か','よ','ね'],'「か」句尾疑问。'),
  // ── よ ──
  _Q('p','これはおいしいです＿','よ',['よ','ね','か'],'「よ」表示告知/强调。'),
  _Q('p','早く行きましょう＿','よ',['よ','ね','な'],'「よ」催促。'),
  // ── ね ──
  _Q('p','今日は暑いです＿','ね',['ね','よ','か'],'「ね」表示确认/同意。'),
  _Q('p','この花は綺麗です＿','ね',['ね','よ','な'],'「ね」寻求共感。'),
  // ── な ──
  _Q('p','きれいだ＿（感叹）','な',['な','ね','よ'],'「な」表示感叹。'),
  _Q('p','触る＿（禁止）','な',['な','よ','ね'],'「な」接动词终止形表示禁止。'),
  // ── ぞ ──
  _Q('p','行く＿（决意）','ぞ',['ぞ','ぜ','よ'],'「ぞ」表示决心/强调。'),
  // ── ぜ ──
  _Q('p','やろう＿（呼吁）','ぜ',['ぜ','ぞ','よ'],'「ぜ」呼吁/振奋。'),
  // ── さ ──
  _Q('p','大丈夫＿（轻松语气）','さ',['さ','よ','ね'],'「さ」轻描淡写、无所谓。'),
  // ── わ ──
  _Q('p','もう帰る＿（柔和语气）','わ',['わ','よ','ね'],'「わ」句末柔和语气。'),
  // ── かな ──
  _Q('p','明日は晴れる＿','かな',['かな','かしら','ね'],'「かな」表示自问。'),
  // ── かしら ──
  _Q('p','間に合う＿','かしら',['かしら','かな','ね'],'「かしら」自问（女性用语较多）。'),
  // ── とも ──
  _Q('p','もちろん行きます＿','とも',['とも','よ','さ'],'「とも」表示"当然"的强调。'),
  // ═══ 动词活用 (t:'v') ═══
  _Q('v','飲む → て形','飲んで',['飲んで','飲みて','飲いて'],'む→んで：撥音変形。'),
  _Q('v','書く → て形','書いて',['書いて','書いで','書えて'],'く→いて：イ音便。'),
  _Q('v','食べる → て形','食べて',['食べて','食べりて','食べって'],'一段動詞：直接加て。'),
  _Q('v','行く → て形','行って',['行って','行いて','行きて'],'行く例外：行って。'),
  _Q('v','持つ → て形','持って',['持って','持ちて','持いて'],'つ→って：促音変。'),
  _Q('v','遊ぶ → て形','遊んで',['遊んで','遊びて','遊ぶて'],'ぶ→んで：撥音変形。'),
  _Q('v','聞く → ない形','聞かない',['聞かない','聞きない','聞くない'],'五段：く→か+ない。'),
  _Q('v','見る → ない形','見ない',['見ない','見りない','見えない'],'一段：る→ない。'),
  _Q('v','来る → て形','来て',['来て','来りて','来って'],'来る不规则：来て。'),
  _Q('v','する → て形','して',['して','すて','しいて'],'する不规则：して。'),
  _Q('v','読む → ます形','読みます',['読みます','読ます','読えます'],'む→み+ます。'),
  _Q('v','起きる → ます形','起きます',['起きます','起ります','起えます'],'一段：る→ます。'),
  // ═══ 词义选择 (t:'w') ═══
  _Q('w','嬉しい の意味は？','高兴',['高兴','悲伤','害怕'],'嬉しい：高兴、喜悦。'),
  _Q('w','難しい の意味は？','困难',['困难','容易','有趣'],'難しい：困难的。'),
  _Q('w','寂しい の意味は？','寂寞',['寂寞','烦躁','愤怒'],'寂しい：寂寞的。'),
  _Q('w','危ない の意味は？','危险',['危险','安全','快速'],'危ない：危险的。'),
  _Q('w','懐かしい の意味は？','怀念',['怀念','陌生','无聊'],'懐かしい：怀念的。'),
  _Q('w','諦める の意味は？','放弃',['放弃','期待','努力'],'諦める：放弃。'),
  _Q('w','褒める の意味は？','表扬',['表扬','批评','忽视'],'褒める：表扬、夸赞。'),
  _Q('w','慌てる の意味は？','慌张',['慌张','镇定','欢呼'],'慌てる：慌张。'),
  _Q('w','混む の意味は？','拥挤',['拥挤','空旷','清洁'],'混む：拥挤。'),
  _Q('w','片付ける の意味は？','整理',['整理','破坏','装饰'],'片付ける：整理。'),
];
const _qTypeLabel = {'p': '助词填空', 'v': '动词活用', 'w': '词义选择'};

// ── 关卡配置 ──
int _lvCols(int lv)  => lv == 1 ? 2 : lv <= 3 ? 3 : lv <= 6 ? 4 : lv <= 10 ? 5 : 6;
int _lvRows(int lv)  => lv == 1 ? 3 : lv <= 3 ? 4 : lv <= 7 ? 5 : lv <= 12 ? 6 : 7;
int _lvLives(int lv) => lv == 1 ? 1 : lv <= 3 ? 99 : lv <= 8 ? 5 : lv <= 15 ? 3 : 2;
List<String> _lvQTypes(int lv, {String gameType = 'particles'}) {
  if (gameType == 'verbs') return ['v']; // 动词方块：只包含动词变形
  return ['p']; // 助词方块：只包含助词
}
int _lvRowBonus(int lv) => lv <= 5 ? 5 : lv <= 12 ? 8 : 12;

// ── 颜色 ──
const _clrCorrect = <Color>[Color(0xFF16a34a), Color(0xFF22c55e)];
const _clrWrong   = <Color>[Color(0xFFdc2626), Color(0xFFef4444)];
List<Color> _comboColor(int combo) {
  if (combo >= 10) return [const Color(0xFFdc2626), const Color(0xFFf97316)];
  if (combo >= 5)  return [const Color(0xFF7c3aed), const Color(0xFF4361ee)];
  return _clrCorrect;
}

// ══════════════════════════════════════════════════════════════════
enum _Phase { select, play }

class TetrisGrammarGame extends StatefulWidget {
  final String gameType; // 'particles' 或 'verbs'
  const TetrisGrammarGame({super.key, this.gameType = 'particles'});
  @override
  State<TetrisGrammarGame> createState() => _TetrisGrammarGameState();
}

class _TetrisGrammarGameState extends State<TetrisGrammarGame> {
  // ── 速度档位 ──
  static const _speedOptions = [
    {'label': '慢速', 'ms': 3500, 'icon': '🐢'},
    {'label': '普通', 'ms': 2000, 'icon': '▶️'},
    {'label': '快速', 'ms': 1200, 'icon': '⚡'},
    {'label': '极速', 'ms': 700,  'icon': '🔥'},
  ];
  int _speedIdx = 1; // 默认普通

  // ── 关卡全局 ──
  _Phase _phase     = _Phase.select;
  int _currentLevel = 1;
  int _maxLevels    = 30;
  int _unlockedTo   = 1;
  Map<int, Map<String, dynamic>> _levelScores = {};

  // ── 棋盘状态 ──
  late List<List<String?>> _board;     // null | 'correct' | 'wrong'
  late List<List<String>>  _boardTxt;
  late List<List<List<Color>>> _boardClr;
  int _gCols = 2, _gRows = 3;

  // ── 统计 ──
  int _score = 0, _combo = 0, _maxCombo = 0, _wrong = 0;
  final List<Map<String, String>> _wrongLog = [];
  int _lives = 1, _livesMax = 1;
  int _passCount = 0, _passTarget = 6;
  bool _fever = false, _running = false;

  // ── 当前题 ──
  int  _dropCol = 0;
  _Q?  _curQ;
  int  _selected = 0;
  int? _feedbackIdx;
  bool _feedbackOk = false;

  // ── 计时 ──
  int    _baseMs = 2000, _dropMs = 2000;
  double _timeProgress = 1.0;
  Timer? _tickTimer;
  static const _tickMs = 50;

  // ── 存储 key 按游戏类型区分 ──
  String get _keyPrefix => widget.gameType;
  String get _keyUnlocked => 'g_unlocked_to_$_keyPrefix';
  String get _keyScores => 'g_level_scores_$_keyPrefix';
  String get _gameTitle => widget.gameType == 'verbs' ? '🎮 动词方块' : '🎮 助词方块';

  @override
  void initState() { super.initState(); _loadLocal(); _fetchConfig(); }
  @override
  void dispose() { _tickTimer?.cancel(); super.dispose(); }

  Future<void> _fetchConfig() async {
    try {
      final res = await ApiService().get('/game/config');
      if (res['ok'] == true) setState(() => _maxLevels = int.tryParse(res['config']['max_levels'].toString()) ?? 30);
    } catch (_) {}
  }

  Future<void> _loadLocal() async {
    final p = await SharedPreferences.getInstance();
    _unlockedTo = p.getInt(_keyUnlocked) ?? 1;
    _speedIdx   = p.getInt('g_speed_idx') ?? 1;
    if (_speedIdx < 0 || _speedIdx >= _speedOptions.length) _speedIdx = 1;
    final js = p.getString(_keyScores);
    if (js != null) {
      final raw = jsonDecode(js) as Map<String, dynamic>;
      _levelScores = raw.map((k, v) => MapEntry(int.parse(k), Map<String, dynamic>.from(v as Map)));
    }
    if (mounted) setState(() {});
    // 登录后从服务器同步进度，取本地和服务端的最大値
    _syncServerProgress();
  }

  Future<void> _syncServerProgress() async {
    try {
      final res = await ApiService().get('/game/my-progress?game_type=${widget.gameType}');
      if (res['ok'] != true) return;
      final serverUnlocked = (res['unlocked_to'] as num?)?.toInt() ?? 1;
      final serverScores   = (res['level_scores'] as Map<String, dynamic>?) ?? {};
      bool changed = false;
      if (serverUnlocked > _unlockedTo) { _unlockedTo = serverUnlocked; changed = true; }
      serverScores.forEach((k, v) {
        final lv = int.tryParse(k); if (lv == null) return;
        final sv    = v as Map<String, dynamic>;
        final local = _levelScores[lv];
        if (local == null || (sv['score'] as num? ?? 0) > (local['score'] as num? ?? 0)) {
          _levelScores[lv] = {'score': (sv['score'] as num?)?.toInt() ?? 0, 'stars': (sv['stars'] as num?)?.toInt() ?? 1, 'combo': (sv['combo'] as num?)?.toInt() ?? 0};
          changed = true;
        }
      });
      if (changed) {
        final p = await SharedPreferences.getInstance();
        await p.setInt(_keyUnlocked, _unlockedTo);
        await p.setString(_keyScores, jsonEncode(_levelScores.map((k, v) => MapEntry(k.toString(), v))));
        if (mounted) setState(() {});
      }
    } catch (_) {} // 未登录或网络失败时静默降级为本地模式
  }

  Future<void> _saveProgress(int lv, int score, int stars, int combo) async {
    final prev = _levelScores[lv];
    if (prev == null || score > (prev['score'] as int? ?? 0)) {
      _levelScores[lv] = {'score': score, 'stars': stars, 'combo': combo};
      final p = await SharedPreferences.getInstance();
      await p.setString(_keyScores, jsonEncode(_levelScores.map((k, v) => MapEntry(k.toString(), v))));
    }
  }

  Future<void> _saveUnlocked(int lv) async {
    if (lv > _unlockedTo) {
      _unlockedTo = lv;
      final p = await SharedPreferences.getInstance();
      await p.setInt(_keyUnlocked, lv);
    }
  }

  void _beginLevel(int lv) {
    _tickTimer?.cancel();
    _currentLevel = lv;
    _gCols = _lvCols(lv); _gRows = _lvRows(lv);
    _livesMax = _lvLives(lv); _lives = _livesMax;
    _passTarget = _gRows * _gCols; _passCount = 0;
    _score = 0; _combo = 0; _maxCombo = 0; _wrong = 0;
    _wrongLog.clear(); _fever = false; _feedbackIdx = null;
    _baseMs = _speedOptions[_speedIdx]['ms'] as int;
    _dropMs = _baseMs;
    _board    = List.generate(_gRows, (_) => List.filled(_gCols, null));
    _boardTxt = List.generate(_gRows, (_) => List.filled(_gCols, ''));
    _boardClr = List.generate(_gRows, (_) => List.generate(_gCols, (_) => <Color>[const Color(0xFFf1f5f9), const Color(0xFFf1f5f9)]));
    _running = true; _phase = _Phase.play;
    setState(() {}); _nextQ();
  }

  void _backToSelect() { _tickTimer?.cancel(); _running = false; setState(() => _phase = _Phase.select); }

  void _nextQ() {
    if (!_running) return;
    if (_board[0].every((c) => c != null)) { _running = false; Future.delayed(const Duration(milliseconds: 300), _levelFail); return; }
    final cols = List.generate(_gCols, (i) => i)..shuffle();
    int col = -1;
    for (final c in cols) { if (_board[0][c] == null) { col = c; break; } }
    if (col == -1) { _running = false; Future.delayed(const Duration(milliseconds: 300), _levelFail); return; }
    final pool = _kQs.where((q) => _lvQTypes(_currentLevel, gameType: widget.gameType).contains(q.t)).toList();
    _curQ = pool[Random().nextInt(pool.length)];
    _dropCol = col; _selected = _curQ!.o.length ~/ 2; _feedbackIdx = null; _timeProgress = 1.0;
    _startTimer(); setState(() {});
  }

  void _startTimer() {
    _tickTimer?.cancel();
    double elapsed = 0;
    _tickTimer = Timer.periodic(const Duration(milliseconds: _tickMs), (t) {
      if (!_running) { t.cancel(); return; }
      elapsed += _tickMs;
      final prog = 1.0 - elapsed / _dropMs;
      if (prog <= 0) { t.cancel(); _confirm(); }
      else if (mounted) setState(() => _timeProgress = prog);
    });
  }

  void _onOptionTap(int i) {
    if (!_running || _feedbackIdx != null) return;
    _tickTimer?.cancel();
    setState(() => _selected = i);
    Future.delayed(const Duration(milliseconds: 60), _confirm);
  }

  void _confirm() {
    if (!_running || _curQ == null) return;
    _tickTimer?.cancel();
    final ans = _curQ!.o[_selected];
    final ok  = ans == _curQ!.a;
    int landRow = -1;
    for (int r = _gRows - 1; r >= 0; r--) { if (_board[r][_dropCol] == null) { landRow = r; break; } }
    if (landRow < 0) { _running = false; Future.delayed(const Duration(milliseconds: 300), _levelFail); return; }
    setState(() {
      _feedbackIdx = _selected; _feedbackOk = ok;
      _board[landRow][_dropCol]    = ok ? 'correct' : 'wrong';
      _boardTxt[landRow][_dropCol] = ans;
      _boardClr[landRow][_dropCol] = ok ? _comboColor(_combo) : _clrWrong;
      if (ok) {
        _passCount++; _combo++;
        if (_combo > _maxCombo) _maxCombo = _combo;
        final wasFever = _fever; _fever = _combo >= 8;
        if (_fever && !wasFever) _showSnack('🔥 FEVER 激活！得分 ×2');
        _score += (_fever ? 2 : 1) * (1 + _combo ~/ 5);
        _dropMs = max(400, _dropMs - _combo * 22);
        _clearRows();
      } else {
        _wrong++; _combo = 0; _fever = false;
        _dropMs = min((_baseMs * 1.1).round(), _dropMs + 100);
        _wrongLog.add({'s': _curQ!.s, 'wrong': ans, 'correct': _curQ!.a, 'e': _curQ!.e});
        if (_livesMax < 99) {
          _lives--;
        }
      }
    });
    // 生命耗尽 → 立即终止，延迟弹出失败弹窗（return 在 setState 外才能真正退出 _confirm）
    if (_lives <= 0 && _livesMax < 99) {
      _running = false;
      _tickTimer?.cancel();
      Future.delayed(const Duration(milliseconds: 700), _levelFail);
      return;
    }
    if (_passCount >= _passTarget) { Future.delayed(const Duration(milliseconds: 600), () { _running = false; _levelClear(); }); return; }
    // 只有所有列都顶格才判溢出；单列满时 _nextQ 里的 gamePickCol 逻辑会跳过
    if (_board[0].every((c) => c != null)) { Future.delayed(const Duration(milliseconds: 800), () { _running = false; _levelFail(); }); return; }
    Future.delayed(const Duration(milliseconds: 480), _nextQ);
  }

  void _clearRows() {
    for (int r = 0; r < _gRows; r++) {
      if (_board[r].every((c) => c == 'correct')) {
        final bonus = _lvRowBonus(_currentLevel);
        _score += bonus;
        for (int rr = r; rr > 0; rr--) {
          _board[rr]    = List.from(_board[rr - 1]);
          _boardTxt[rr] = List.from(_boardTxt[rr - 1]);
          _boardClr[rr] = List.from(_boardClr[rr - 1]);
        }
        _board[0]    = List.filled(_gCols, null);
        _boardTxt[0] = List.filled(_gCols, '');
        _boardClr[0] = List.generate(_gCols, (_) => <Color>[const Color(0xFFf1f5f9), const Color(0xFFf1f5f9)]);
        _showSnack('🎉 完美消行！+$bonus 分');
      }
    }
  }

  void _levelClear() {
    final stars = _wrong == 0 ? 3 : _wrong <= 2 ? 2 : 1;
    _saveProgress(_currentLevel, _score, stars, _maxCombo);
    if (_currentLevel + 1 <= _maxLevels) _saveUnlocked(_currentLevel + 1);
    _submitScore();
    showDialog(
      context: context, barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(children: [
          const Text('🎊 关卡通关！', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('★' * stars + '☆' * (3 - stars), style: const TextStyle(fontSize: 26, letterSpacing: 3, color: Color(0xFFf59e0b))),
        ]),
        content: _reportContent(),
        actions: [
          TextButton(
            onPressed: () { 
              Navigator.pop(dialogContext); 
              if (mounted) _beginLevel(_currentLevel); 
            }, 
            child: const Text('再挑战')
          ),
          if (_currentLevel < _maxLevels)
            FilledButton(
              onPressed: () { 
                Navigator.pop(dialogContext); 
                if (mounted) _beginLevel(_currentLevel + 1); 
              }, 
              child: const Text('下一关 →')
            ),
          if (_currentLevel >= _maxLevels)
            FilledButton(
              onPressed: () { 
                Navigator.pop(dialogContext); 
                if (mounted) setState(() => _phase = _Phase.select); 
              }, 
              child: const Text('返回')
            ),
        ],
      ),
    );
  }

  void _levelFail() {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('💔 关卡失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        content: _reportContent(),
        actions: [
          TextButton(
            onPressed: () { 
              Navigator.pop(dialogContext); 
              if (mounted) setState(() => _phase = _Phase.select); 
            }, 
            child: const Text('返回选关')
          ),
          FilledButton(
            onPressed: () { 
              Navigator.pop(dialogContext); 
              if (mounted) _beginLevel(_currentLevel); 
            }, 
            child: const Text('重试')
          ),
        ],
      ),
    );
  }

  Widget _reportContent() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _statRow('得分', '$_score'), _statRow('最高连击', '$_maxCombo'), _statRow('错误', '$_wrong'),
      if (_wrongLog.isNotEmpty) ...[
        const Divider(height: 16),
        const Align(alignment: Alignment.centerLeft, child: Text('错题回顾', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        const SizedBox(height: 4),
        ..._wrongLog.take(3).map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${w['s']}\n✗ ${w['wrong']}  ✓ ${w['correct']}', style: const TextStyle(fontSize: 12)),
        )),
      ],
    ],
  );

  Widget _statRow(String label, String val) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label, style: const TextStyle(color: Colors.black54)), Text(val, style: const TextStyle(fontWeight: FontWeight.bold))],
    ),
  );

  Future<void> _submitScore() async {
    try {
      final total = _passCount + _wrong;
      final acc   = total > 0 ? ((_passCount / total) * 100).round() : 100;
      await ApiService().dio.post('/game/score', data: {
        'game_type':             widget.gameType,
        'level_num':           _currentLevel,
        'score':               _score,
        'accuracy':            acc,
        'max_combo':           _maxCombo,
        'questions_answered':  total,
        'passed':              true,
        'speed_ms':            _baseMs,
      });
      // 同步游戏学习记录
      apiService.logActivity(activityType: 'grammar', durationSeconds: 0, score: acc.toDouble());
    } catch (_) {}
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1200), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(child: _phase == _Phase.select ? _buildSelect() : _buildPlay()),
    );
  }

  // ─── 关卡选择 ─────────────────────────────────────────────
  Widget _buildSelect() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    GoRouter.of(context).go('/games');
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Text(_gameTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('共 $_maxLevels 关', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _showLeaderboard,
                icon: const Icon(Icons.leaderboard, size: 16),
                label: const Text('排行榜', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ),
        // ── 速度选择器 ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Text('速度  ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748b))),
              ...List.generate(_speedOptions.length, (i) {
                final opt = _speedOptions[i];
                final sel = i == _speedIdx;
                return Expanded(child: GestureDetector(
                  onTap: () async {
                    setState(() => _speedIdx = i);
                    final p = await SharedPreferences.getInstance();
                    await p.setInt('g_speed_idx', i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: EdgeInsets.only(right: i < _speedOptions.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFF4361ee) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? const Color(0xFF4361ee) : const Color(0xFFe2e8f0), width: 1.5),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(opt['icon'] as String, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 2),
                      Text(opt['label'] as String,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : const Color(0xFF64748b))),
                    ]),
                  ),
                ));
              }),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4, childAspectRatio: 0.78, crossAxisSpacing: 8, mainAxisSpacing: 8,
            ),
            itemCount: _maxLevels,
            itemBuilder: (_, idx) {
              final lv = idx + 1;
              final locked = lv > _unlockedTo;
              final saved  = _levelScores[lv];
              final stars  = saved?['stars'] as int? ?? 0;
              return GestureDetector(
                onTap: locked ? null : () => _beginLevel(lv),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: locked ? Colors.grey.shade200 : (saved != null ? const Color(0xFFdcfce7) : Colors.white),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: locked ? Colors.grey.shade300 : (saved != null ? const Color(0xFF16a34a) : const Color(0xFF4361ee)),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (locked) const Icon(Icons.lock, size: 18, color: Colors.grey),
                      Text('$lv', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                        color: locked ? Colors.grey : (saved != null ? const Color(0xFF15803d) : const Color(0xFF4361ee)))),
                      Text('${_lvRows(lv)}×${_lvCols(lv)}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      Text('★' * stars + '☆' * (3 - stars),
                        style: TextStyle(fontSize: 11, color: stars > 0 ? const Color(0xFFf59e0b) : Colors.grey.shade400)),
                      if (saved != null) Text('${saved['score']}分', style: const TextStyle(fontSize: 9, color: Color(0xFF15803d))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showLeaderboard() async {
    showDialog(
      context: context,
        builder: (_) => FutureBuilder<Response<dynamic>>(
        future: ApiService().dio.get('/game/leaderboard'),
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done)
            return const AlertDialog(content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())));
          final rows = (snap.data?.data['rows'] ?? []) as List;
          return AlertDialog(
            title: const Text('🏆 全球排行榜'),
            content: SizedBox(
              width: 300,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i] as Map;
                  final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i+1}.';
                  return ListTile(
                    dense: true,
                    leading: Text(medal, style: const TextStyle(fontSize: 16)),
                    title: Text(r['username']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('连击 ${r['max_combo'] ?? 0}'),
                    trailing: Text('${r['rating'] ?? r['total_score'] ?? 0}分',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF4361ee))),
                  );
                },
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
          );
        },
      ),
    );
  }

  // ─── 游戏进行页 ───────────────────────────────────────────
  Widget _buildPlay() {
    final q     = _curQ;
    final cellH = max(26.0, min(52.0, 168.0 / _gRows));
    return Column(
      children: [
        // HUD
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _backToSelect,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('返回', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
              Expanded(child: Text('关卡 $_currentLevel · ${_gRows}×$_gCols',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF4361ee)))),
              _livesMax >= 99
                ? const Text('∞', style: TextStyle(fontSize: 14))
                : Text('❤️' * max(0, _lives) + '🖤' * max(0, _livesMax - _lives), style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
        // 进度条
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _passTarget > 0 ? _passCount / _passTarget : 0, minHeight: 6,
                  backgroundColor: const Color(0xFFe2e8f0),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF22c55e)),
                ),
              )),
              const SizedBox(width: 6),
              Text('$_passCount/$_passTarget', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF16a34a))),
            ],
          ),
        ),
        // 统计卡
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Row(children: [
            _hudCard('$_score', '得分', const Color(0xFF4361ee)),
            const SizedBox(width: 6),
            _hudCard('$_combo', '连击', const Color(0xFFf59e0b)),
            const SizedBox(width: 6),
            _hudCard('$_wrong', '错误', const Color(0xFFdc2626)),
          ]),
        ),
        // 题目卡
        if (q != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.05), blurRadius: 4)]),
              child: Column(
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFF4361ee), borderRadius: BorderRadius.circular(10)),
                      child: Text(_qTypeLabel[q.t] ?? '填空', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(q.s, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _timeProgress, minHeight: 5,
                      backgroundColor: const Color(0xFFe2e8f0),
                      valueColor: AlwaysStoppedAnimation(
                        _timeProgress > 0.5 ? const Color(0xFF4361ee) : _timeProgress > 0.25 ? const Color(0xFFf59e0b) : const Color(0xFFdc2626)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Fever
        if (_fever)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFdc2626), Color(0xFFf97316)]),
              borderRadius: BorderRadius.circular(8)),
            child: const Text('🔥 FEVER MODE · 得分 ×2 🔥',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        // 选项
        if (q != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: Row(
              children: List.generate(q.o.length, (i) {
                final isSel = i == _selected;
                final isFb  = _feedbackIdx == i;
                Color bg  = isSel ? const Color(0xFFe8effe) : Colors.white;
                Color bdr = isSel ? const Color(0xFF4361ee) : const Color(0xFFe2e8f0);
                Color txt = isSel ? const Color(0xFF4361ee) : const Color(0xFF64748b);
                if (isFb)  { bg = _feedbackOk ? const Color(0xFFdcfce7) : const Color(0xFFfee2e2); bdr = _feedbackOk ? const Color(0xFF16a34a) : const Color(0xFFdc2626); txt = _feedbackOk ? const Color(0xFF15803d) : const Color(0xFFb91c1c); }
                if (_feedbackIdx != null && !_feedbackOk && q.o[i] == q.a) { bg = const Color(0xFFdcfce7); bdr = const Color(0xFF16a34a); txt = const Color(0xFF15803d); }
                final maxLen = q.o.fold(0, (m, s) => s.length > m ? s.length : m);
                final fs = maxLen > 4 ? 12.0 : maxLen > 2 ? 14.0 : 17.0;
                return Expanded(child: GestureDetector(
                  onTap: () => _onOptionTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: EdgeInsets.only(right: i < q.o.length - 1 ? 6 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: bdr, width: 2)),
                    child: Text(q.o[i], textAlign: TextAlign.center,
                      style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: txt)),
                  ),
                ));
              }),
            ),
          ),
        // 棋盘
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
          child: Container(
            decoration: BoxDecoration(color: const Color(0xFFe2e8f0), borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.all(3),
            child: Column(
              children: List.generate(_gRows, (r) => Row(
                children: List.generate(_gCols, (c) {
                  final st = _board[r][c]; final txt = _boardTxt[r][c]; final clr = _boardClr[r][c];
                  // 只在落点行（该列最低空位）显示当前方块，而非整列所有空格
                  bool isActive = false;
                  if (c == _dropCol && _running && st == null) {
                    // 找到该列最低空位
                    int landRow = -1;
                    for (int rr = _gRows - 1; rr >= 0; rr--) {
                      if (_board[rr][c] == null) { landRow = rr; break; }
                    }
                    isActive = (r == landRow);
                  }
                  List<Color> gradClr;
                  if (st == 'correct')     gradClr = clr;
                  else if (st == 'wrong')  gradClr = _clrWrong;
                  else if (isActive)       gradClr = const [Color(0xFF4361ee), Color(0xFF4361ee)];
                  else                     gradClr = const [Color(0xFFf1f5f9), Color(0xFFf1f5f9)];
                  return Expanded(child: Container(
                    height: cellH,
                    margin: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradClr),
                      borderRadius: BorderRadius.circular(6),
                      border: st == null && !isActive ? Border.all(color: const Color(0xFFe2e8f0)) : null,
                      boxShadow: st != null ? [BoxShadow(
                        color: (st == 'correct' ? const Color(0xFF16a34a) : const Color(0xFFdc2626)).withOpacity(.3),
                        blurRadius: 4, offset: const Offset(0,2),
                      )] : null,
                    ),
                    child: Center(child: Text(
                      st != null ? txt : (isActive && q != null ? q.o[_selected] : ''),
                      style: TextStyle(
                        color: st != null || isActive ? Colors.white : Colors.transparent,
                        fontWeight: FontWeight.w800,
                        fontSize: _gCols <= 3 ? 14 : _gCols <= 4 ? 12 : 10,
                      ),
                    )),
                  ));
                }),
              )),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('点击选项即确认答案', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ],
    );
  }

  Widget _hudCard(String val, String label, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    ),
  );
}
