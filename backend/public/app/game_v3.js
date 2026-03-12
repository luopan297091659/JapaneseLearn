// ══════════════════════════════════════════════════════════════════
//  GAME v3 (助词方块 · 闯关模式)  up to 30 levels, leaderboard
// ══════════════════════════════════════════════════════════════════

// ── 题库（3种类型：助词·动词活用·词义） ──
const GAME_QS = [
  // ═══ 助词题库 (t:'p') — 覆盖全部日语助词 ═══
  // ── 格助词：は ──
  {t:'p',s:'私＿学生です',a:'は',o:['は','が','も'],e:'「は」表示话题（主题标记）。'},
  {t:'p',s:'この部屋＿広いです',a:'は',o:['は','が','の'],e:'「は」表示话题。'},
  {t:'p',s:'朝ご飯＿食べないです',a:'は',o:['は','を','が'],e:'「は」用于对比或否定强调。'},
  {t:'p',s:'東京＿便利ですが、大阪＿楽しい',a:'は',o:['は','が','も'],e:'「は」用于对比两个话题。'},
  // ── 格助词：が ──
  {t:'p',s:'コーヒー＿好きです',a:'が',o:['が','を','の'],e:'「が」与「好き/嫌い」搭配。'},
  {t:'p',s:'日本語＿上手です',a:'が',o:['が','は','を'],e:'「が」与「上手/下手」搭配。'},
  {t:'p',s:'猫＿好きです',a:'が',o:['が','は','を'],e:'「が」与「好き」搭配。'},
  {t:'p',s:'雨＿降っています',a:'が',o:['が','は','を'],e:'「が」表示自然现象主语。'},
  {t:'p',s:'誰＿来ましたか',a:'が',o:['が','は','を'],e:'疑问词做主语时用「が」。'},
  // ── 格助词：を ──
  {t:'p',s:'水＿飲みます',a:'を',o:['を','に','で'],e:'「を」表示动作直接对象。'},
  {t:'p',s:'本＿読みます',a:'を',o:['を','に','で'],e:'「を」表示动作对象。'},
  {t:'p',s:'ご飯＿食べます',a:'を',o:['を','に','で'],e:'「を」表示动作对象。'},
  {t:'p',s:'公園＿散歩します',a:'を',o:['を','で','に'],e:'「を」表示经过/移动的场所。'},
  {t:'p',s:'大学＿卒業しました',a:'を',o:['を','に','で'],e:'「を」表示离开的起点。'},
  // ── 格助词：に ──
  {t:'p',s:'東京＿行きます',a:'に',o:['に','を','で'],e:'「に」表示移动目的地。'},
  {t:'p',s:'電車＿乗ります',a:'に',o:['に','を','で'],e:'「に」乗る：乘坐交通工具。'},
  {t:'p',s:'3時＿始まります',a:'に',o:['に','で','から'],e:'「に」表示具体时间点。'},
  {t:'p',s:'友達＿会います',a:'に',o:['に','と','で'],e:'「に」会う：与某人见面。'},
  {t:'p',s:'妹＿お菓子をあげます',a:'に',o:['に','へ','と'],e:'「に」あげる：给予某人。'},
  {t:'p',s:'先生＿もらいました',a:'に',o:['に','から','で'],e:'「に」もらう：从…收到。'},
  {t:'p',s:'部屋の中＿入ります',a:'に',o:['に','を','で'],e:'「に」表示进入目的地。'},
  {t:'p',s:'壁＿絵がかかっています',a:'に',o:['に','で','が'],e:'「に」表示存在的位置。'},
  // ── 格助词：へ ──
  {t:'p',s:'学校＿行きます',a:'へ',o:['へ','に','で'],e:'「へ」表示移动方向。'},
  {t:'p',s:'南＿向かいます',a:'へ',o:['へ','に','を'],e:'「へ」表示朝向的方向。'},
  // ── 格助词：で ──
  {t:'p',s:'図書館＿勉強します',a:'で',o:['で','に','を'],e:'「で」表示动作场所。'},
  {t:'p',s:'公園＿遊びます',a:'で',o:['で','に','を'],e:'「で」表示活动场所。'},
  {t:'p',s:'バス＿来ます',a:'で',o:['で','を','に'],e:'「で」表示交通手段。'},
  {t:'p',s:'ペン＿書きます',a:'で',o:['で','を','に'],e:'「で」表示使用的工具。'},
  {t:'p',s:'電話＿連絡します',a:'で',o:['で','に','を'],e:'「で」表示联系手段。'},
  {t:'p',s:'一人＿行きます',a:'で',o:['で','と','に'],e:'「で」～人で：以…人数。'},
  {t:'p',s:'地震＿家が壊れました',a:'で',o:['で','に','が'],e:'「で」表示原因。'},
  // ── 格助词：と ──
  {t:'p',s:'山田さん＿話します',a:'と',o:['と','に','で'],e:'「と」表示共同动作对象。'},
  {t:'p',s:'友達＿映画を見ます',a:'と',o:['と','に','で'],e:'「と」表示一起做某事的对象。'},
  {t:'p',s:'りんご＿みかんを買いました',a:'と',o:['と','や','も'],e:'「と」表示完全列举。'},
  // ── 格助词：の ──
  {t:'p',s:'私＿本です',a:'の',o:['の','は','が'],e:'「の」表示所属关系。'},
  {t:'p',s:'日本語＿先生です',a:'の',o:['の','は','が'],e:'「の」表示修饰限定。'},
  {t:'p',s:'赤い＿がほしいです',a:'の',o:['の','は','を'],e:'「の」代替名词（形式名词用法）。'},
  // ── 格助词：から ──
  {t:'p',s:'どこ＿来ましたか',a:'から',o:['から','に','で'],e:'「から」表示来源地/起点。'},
  {t:'p',s:'日本＿来ました',a:'から',o:['から','に','を'],e:'「から」表示移动起点。'},
  {t:'p',s:'9時＿働きます',a:'から',o:['から','に','まで'],e:'「から」表示开始时间。'},
  {t:'p',s:'先生＿習います',a:'から',o:['から','に','で'],e:'「から」表示获取来源。'},
  // ── 格助词：まで ──
  {t:'p',s:'駅＿歩いて行きます',a:'まで',o:['まで','から','で'],e:'「まで」表示移动终点。'},
  {t:'p',s:'5時＿仕事をします',a:'まで',o:['まで','に','から'],e:'「まで」表示终止时间。'},
  {t:'p',s:'東京から大阪＿3時間かかります',a:'まで',o:['まで','に','で'],e:'「まで」表示到达终点。'},
  // ── 格助词：より ──
  {t:'p',s:'東京は大阪＿大きいです',a:'より',o:['より','から','まで'],e:'「より」表示比较的基准。'},
  {t:'p',s:'電車はバス＿速いです',a:'より',o:['より','から','ほど'],e:'「より」表示比较对象。'},
  // ── 並立助詞：や ──
  {t:'p',s:'りんご＿みかんなどを買いました',a:'や',o:['や','と','の'],e:'「や」表示不完全列举（等等）。'},
  {t:'p',s:'本＿雑誌を読みます',a:'や',o:['や','と','か'],e:'「や」部分列举，暗示还有其他。'},
  // ── 並立助詞：とか ──
  {t:'p',s:'寿司＿ラーメンとかが好きです',a:'とか',o:['とか','や','と'],e:'「とか」口语的不完全列举。'},
  {t:'p',s:'映画を見る＿音楽を聴くとかします',a:'とか',o:['とか','や','し'],e:'「とか」列举动作（口语）。'},
  // ── 並立助詞：だの ──
  {t:'p',s:'あれが欲しい＿これが欲しいだの言っている',a:'だの',o:['だの','とか','や'],e:'「だの」带有不满语气的列举。'},
  // ── 副助詞：も ──
  {t:'p',s:'私＿学生です',a:'も',o:['も','は','が'],e:'「も」表示"也"。'},
  {t:'p',s:'どこに＿行きません',a:'も',o:['も','は','か'],e:'疑问词＋「も」＋否定＝全否定。'},
  {t:'p',s:'何＿食べたくないです',a:'も',o:['も','を','は'],e:'何＋「も」＋否定＝什么都不…'},
  // ── 副助詞：だけ ──
  {t:'p',s:'一つ＿ください',a:'だけ',o:['だけ','しか','ばかり'],e:'「だけ」表示"仅仅、只"。'},
  {t:'p',s:'日本語＿話せます',a:'だけ',o:['だけ','しか','も'],e:'「だけ」限定范围。'},
  // ── 副助詞：しか ──
  {t:'p',s:'100円＿ありません',a:'しか',o:['しか','だけ','も'],e:'「しか」＋否定＝只有…（强调少）。'},
  {t:'p',s:'水＿飲めません',a:'しか',o:['しか','だけ','ばかり'],e:'「しか」＋否定＝只能喝水。'},
  // ── 副助詞：さえ ──
  {t:'p',s:'子供＿知っている',a:'でさえ',o:['でさえ','でも','だけ'],e:'「さえ」表示"连…都"（极端例子）。'},
  {t:'p',s:'名前＿書けない',a:'さえ',o:['さえ','しか','だけ'],e:'「さえ」连名字都不会写。'},
  // ── 副助詞：でも ──
  {t:'p',s:'コーヒー＿飲みませんか',a:'でも',o:['でも','を','は'],e:'「でも」表示举例提议（…之类的）。'},
  {t:'p',s:'誰＿できます',a:'でも',o:['でも','も','か'],e:'疑问词＋「でも」＝任何人都…'},
  // ── 副助詞：ばかり ──
  {t:'p',s:'甘いもの＿食べています',a:'ばかり',o:['ばかり','だけ','しか'],e:'「ばかり」表示"净是、老是"。'},
  {t:'p',s:'ゲーム＿していないで勉強しなさい',a:'ばかり',o:['ばかり','だけ','でも'],e:'「ばかり」尽是做游戏。'},
  // ── 副助詞：ほど ──
  {t:'p',s:'死ぬ＿疲れた',a:'ほど',o:['ほど','くらい','まで'],e:'「ほど」表示程度（累得要死）。'},
  {t:'p',s:'泣きたい＿嬉しい',a:'ほど',o:['ほど','くらい','ばかり'],e:'「ほど」表示到…程度。'},
  // ── 副助詞：くらい/ぐらい ──
  {t:'p',s:'30分＿かかります',a:'ぐらい',o:['ぐらい','ほど','まで'],e:'「ぐらい/くらい」表示大约。'},
  {t:'p',s:'これ＿は自分でできます',a:'くらい',o:['くらい','ほど','だけ'],e:'「くらい」表示轻视程度（这种程度）。'},
  // ── 副助詞：こそ ──
  {t:'p',s:'今度＿頑張ります',a:'こそ',o:['こそ','は','も'],e:'「こそ」表示强调（这次一定…）。'},
  {t:'p',s:'こちら＿よろしくお願いします',a:'こそ',o:['こそ','も','は'],e:'「こそ」强调"才是我这边…"。'},
  // ── 副助詞：なり ──
  {t:'p',s:'電話する＿メールするなりしてください',a:'なり',o:['なり','とか','か'],e:'「なり」表示"…或…之类"。'},
  // ── 接続助詞：て ──
  {t:'p',s:'朝起き＿顔を洗います',a:'て',o:['て','から','で'],e:'「て」表示动作的顺序连接。'},
  {t:'p',s:'走っ＿学校に行きました',a:'て',o:['て','から','で'],e:'「て」表示方式或连接。'},
  // ── 接続助詞：で（て的浊音） ──
  {t:'p',s:'読ん＿から返します',a:'で',o:['で','て','に'],e:'「で」は「て」的浊音形。'},
  // ── 接続助詞：から（原因） ──
  {t:'p',s:'暑い＿窓を開けます',a:'から',o:['から','ので','けど'],e:'「から」表示原因理由。'},
  {t:'p',s:'時間がない＿急ぎましょう',a:'から',o:['から','ので','のに'],e:'「から」表示理由。'},
  // ── 接続助詞：ので ──
  {t:'p',s:'疲れた＿少し休みます',a:'ので',o:['ので','から','のに'],e:'「ので」表示客观原因（较礼貌）。'},
  {t:'p',s:'雨が降っている＿傘を持って行きます',a:'ので',o:['ので','から','けど'],e:'「ので」客观理由说明。'},
  // ── 接続助詞：が（转折） ──
  {t:'p',s:'高い＿買いました',a:'が',o:['が','から','ので'],e:'「が」表示转折（虽然…但是）。'},
  {t:'p',s:'すみません＿ちょっといいですか',a:'が',o:['が','けど','から'],e:'「が」用于礼貌的引入话题。'},
  // ── 接続助詞：けど/けれど ──
  {t:'p',s:'食べたい＿我慢します',a:'けど',o:['けど','が','ので'],e:'「けど」表示转折（口语）。'},
  {t:'p',s:'行きたかった＿時間がなかった',a:'けれど',o:['けれど','けど','のに'],e:'「けれど」转折（较正式）。'},
  // ── 接続助詞：のに ──
  {t:'p',s:'約束した＿来なかった',a:'のに',o:['のに','けど','ので'],e:'「のに」表示不满（明明…却…）。'},
  {t:'p',s:'薬を飲んだ＿治らない',a:'のに',o:['のに','けど','が'],e:'「のに」表示意外或遗憾。'},
  // ── 接続助詞：し ──
  {t:'p',s:'安い＿おいしいし、この店が好きです',a:'し',o:['し','から','ので'],e:'「し」列举理由（又…又…）。'},
  {t:'p',s:'天気もいい＿どこかに行きましょう',a:'し',o:['し','から','ので'],e:'「し」列举理由。'},
  // ── 接続助詞：ながら ──
  {t:'p',s:'音楽を聴き＿勉強します',a:'ながら',o:['ながら','て','つつ'],e:'「ながら」表示同时进行两个动作。'},
  {t:'p',s:'歩き＿スマホを見るのは危ない',a:'ながら',o:['ながら','て','つつ'],e:'「ながら」边走边看…'},
  // ── 接続助詞：ば ──
  {t:'p',s:'安けれ＿買います',a:'ば',o:['ば','たら','と'],e:'「ば」表示假定条件。'},
  {t:'p',s:'時間があれ＿行きたいです',a:'ば',o:['ば','たら','と'],e:'「ば」如果有时间的话…'},
  // ── 接続助詞：と ──
  {t:'p',s:'ボタンを押す＿ドアが開きます',a:'と',o:['と','ば','たら'],e:'「と」表示必然条件/自然结果。'},
  {t:'p',s:'春になる＿桜が咲きます',a:'と',o:['と','ば','たら'],e:'「と」表示自然规律。'},
  // ── 接続助詞：たら ──
  {t:'p',s:'家に帰っ＿電話します',a:'たら',o:['たら','ば','と'],e:'「たら」表示条件（回家后就…）。'},
  {t:'p',s:'雨が降っ＿試合は中止です',a:'たら',o:['たら','ば','と'],e:'「たら」如果下雨的话…'},
  // ── 接続助詞：ても ──
  {t:'p',s:'雨が降っ＿行きます',a:'ても',o:['ても','たら','のに'],e:'「ても」即使下雨也去。'},
  {t:'p',s:'何回読ん＿わからない',a:'でも',o:['でも','ても','のに'],e:'「でも」即使读了几遍也不懂。'},
  // ── 接続助詞：つつ ──
  {t:'p',s:'悪いと思い＿やめられない',a:'つつ',o:['つつ','ながら','ても'],e:'「つつ」虽然知道不好却无法停止（书面语）。'},
  // ── 終助詞：か ──
  {t:'p',s:'これはいくらです＿',a:'か',o:['か','よ','ね'],e:'「か」表示疑问。'},
  {t:'p',s:'明日来ます＿',a:'か',o:['か','よ','ね'],e:'「か」句尾疑问。'},
  // ── 終助詞：よ ──
  {t:'p',s:'これはおいしいです＿',a:'よ',o:['よ','ね','か'],e:'「よ」表示告知/强调。'},
  {t:'p',s:'早く行きましょう＿',a:'よ',o:['よ','ね','な'],e:'「よ」催促。'},
  // ── 終助詞：ね ──
  {t:'p',s:'今日は暑いです＿',a:'ね',o:['ね','よ','か'],e:'「ね」表示确认/同意。'},
  {t:'p',s:'この花は綺麗です＿',a:'ね',o:['ね','よ','な'],e:'「ね」寻求共感。'},
  // ── 終助詞：な ──
  {t:'p',s:'きれいだ＿（感叹）',a:'な',o:['な','ね','よ'],e:'「な」表示感叹（男性用语）。'},
  {t:'p',s:'触る＿（禁止）',a:'な',o:['な','よ','ね'],e:'「な」接动词终止形表示禁止。'},
  // ── 終助詞：ぞ ──
  {t:'p',s:'行く＿（决意）',a:'ぞ',o:['ぞ','ぜ','よ'],e:'「ぞ」表示决心/强调（男性用语）。'},
  // ── 終助詞：ぜ ──
  {t:'p',s:'やろう＿（呼吁）',a:'ぜ',o:['ぜ','ぞ','よ'],e:'「ぜ」呼吁/振奋（男性用语）。'},
  // ── 終助詞：さ ──
  {t:'p',s:'大丈夫＿（轻松语气）',a:'さ',o:['さ','よ','ね'],e:'「さ」表示轻描淡写、无所谓。'},
  // ── 終助詞：わ ──
  {t:'p',s:'もう帰る＿（柔和语气）',a:'わ',o:['わ','よ','ね'],e:'「わ」句末柔和语气。'},
  // ── 終助詞：かな ──
  {t:'p',s:'明日は晴れる＿',a:'かな',o:['かな','かしら','ね'],e:'「かな」表示自问（不知道…呢）。'},
  // ── 終助詞：かしら ──
  {t:'p',s:'間に合う＿',a:'かしら',o:['かしら','かな','ね'],e:'「かしら」自问（女性用语较多）。'},
  // ── 終助詞：とも ──
  {t:'p',s:'もちろん行きます＿',a:'とも',o:['とも','よ','さ'],e:'「とも」表示"当然"的强调。'},
  // ═══ 动词活用 (t:'v') — 全11种变形 ═══
  // ── ます形 ──
  {t:'v',s:'書く → ます形',a:'書きます',o:['書きます','書くます','書けます'],e:'五段く→き+ます。'},
  {t:'v',s:'泳ぐ → ます形',a:'泳ぎます',o:['泳ぎます','泳ぐます','泳げます'],e:'五段ぐ→ぎ+ます。'},
  {t:'v',s:'話す → ます形',a:'話します',o:['話します','話すます','話せます'],e:'五段す→し+ます。'},
  {t:'v',s:'待つ → ます形',a:'待ちます',o:['待ちます','待つます','待てます'],e:'五段つ→ち+ます。'},
  {t:'v',s:'遊ぶ → ます形',a:'遊びます',o:['遊びます','遊ぶます','遊べます'],e:'五段ぶ→び+ます。'},
  {t:'v',s:'死ぬ → ます形',a:'死にます',o:['死にます','死ぬます','死ねます'],e:'五段ぬ→に+ます。'},
  {t:'v',s:'買う → ます形',a:'買います',o:['買います','買うます','買えます'],e:'五段う→い+ます。'},
  {t:'v',s:'読む → ます形',a:'読みます',o:['読みます','読むます','読めます'],e:'五段む→み+ます。'},
  {t:'v',s:'帰る → ます形',a:'帰ります',o:['帰ります','帰るます','帰れます'],e:'五段る→り+ます。帰る是五段动词。'},
  {t:'v',s:'食べる → ます形',a:'食べます',o:['食べます','食べります','食べるます'],e:'一段：去る+ます。'},
  {t:'v',s:'起きる → ます形',a:'起きます',o:['起きます','起きります','起きるます'],e:'一段：去る+ます。'},
  {t:'v',s:'する → ます形',a:'します',o:['します','すます','するます'],e:'サ変：する→します。'},
  {t:'v',s:'来る → ます形',a:'来ます',o:['来ます','来ります','来るます'],e:'カ変：来る→来（き）ます。'},
  // ── ない形 ──
  {t:'v',s:'書く → ない形',a:'書かない',o:['書かない','書きない','書くない'],e:'五段く→か+ない。'},
  {t:'v',s:'聞く → ない形',a:'聞かない',o:['聞かない','聞きない','聞くない'],e:'五段く→か+ない。'},
  {t:'v',s:'話す → ない形',a:'話さない',o:['話さない','話しない','話すない'],e:'五段す→さ+ない。'},
  {t:'v',s:'待つ → ない形',a:'待たない',o:['待たない','待ちない','待つない'],e:'五段つ→た+ない。'},
  {t:'v',s:'遊ぶ → ない形',a:'遊ばない',o:['遊ばない','遊びない','遊ぶない'],e:'五段ぶ→ば+ない。'},
  {t:'v',s:'買う → ない形',a:'買わない',o:['買わない','買あない','買うない'],e:'五段う→わ+ない（特殊）。'},
  {t:'v',s:'飲む → ない形',a:'飲まない',o:['飲まない','飲みない','飲むない'],e:'五段む→ま+ない。'},
  {t:'v',s:'見る → ない形',a:'見ない',o:['見ない','見らない','見るない'],e:'一段：去る+ない。'},
  {t:'v',s:'食べる → ない形',a:'食べない',o:['食べない','食べらない','食べるない'],e:'一段：去る+ない。'},
  {t:'v',s:'する → ない形',a:'しない',o:['しない','さない','すない'],e:'サ変：する→しない。'},
  {t:'v',s:'来る → ない形',a:'来ない',o:['来ない','来らない','来るない'],e:'カ変：来る→来（こ）ない。'},
  // ── た形 ──
  {t:'v',s:'書く → た形',a:'書いた',o:['書いた','書きた','書った'],e:'五段く→いた：イ音便。'},
  {t:'v',s:'泳ぐ → た形',a:'泳いだ',o:['泳いだ','泳ぎた','泳った'],e:'五段ぐ→いだ：濁音イ音便。'},
  {t:'v',s:'飲む → た形',a:'飲んだ',o:['飲んだ','飲みた','飲った'],e:'五段む→んだ：撥音便。'},
  {t:'v',s:'話す → た形',a:'話した',o:['話した','話いた','話った'],e:'五段す→した。'},
  {t:'v',s:'待つ → た形',a:'待った',o:['待った','待ちた','待いた'],e:'五段つ→った：促音便。'},
  {t:'v',s:'遊ぶ → た形',a:'遊んだ',o:['遊んだ','遊びた','遊いだ'],e:'五段ぶ→んだ：撥音便。'},
  {t:'v',s:'行く → た形',a:'行った',o:['行った','行いた','行きた'],e:'行く例外：行った（不是行いた）。'},
  {t:'v',s:'買う → た形',a:'買った',o:['買った','買うた','買いた'],e:'五段う→った：促音便。'},
  {t:'v',s:'食べる → た形',a:'食べた',o:['食べた','食べった','食べりた'],e:'一段：去る+た。'},
  {t:'v',s:'する → た形',a:'した',o:['した','すた','しった'],e:'サ変：する→した。'},
  {t:'v',s:'来る → た形',a:'来た',o:['来た','来った','来りた'],e:'カ変：来る→来（き）た。'},
  // ── て形 ──
  {t:'v',s:'飲む → て形',a:'飲んで',o:['飲んで','飲みて','飲いて'],e:'五段む→んで：撥音便。'},
  {t:'v',s:'書く → て形',a:'書いて',o:['書いて','書きて','書えて'],e:'五段く→いて：イ音便。'},
  {t:'v',s:'泳ぐ → て形',a:'泳いで',o:['泳いで','泳ぎて','泳って'],e:'五段ぐ→いで：濁音イ音便。'},
  {t:'v',s:'話す → て形',a:'話して',o:['話して','話いて','話って'],e:'五段す→して。'},
  {t:'v',s:'行く → て形',a:'行って',o:['行って','行いて','行きて'],e:'行く例外：行って（不是行いて）。'},
  {t:'v',s:'持つ → て形',a:'持って',o:['持って','持ちて','持いて'],e:'五段つ→って：促音便。'},
  {t:'v',s:'遊ぶ → て形',a:'遊んで',o:['遊んで','遊びて','遊ぶて'],e:'五段ぶ→んで：撥音便。'},
  {t:'v',s:'買う → て形',a:'買って',o:['買って','買うて','買いて'],e:'五段う→って：促音便。'},
  {t:'v',s:'食べる → て形',a:'食べて',o:['食べて','食べりて','食べって'],e:'一段：去る+て。'},
  {t:'v',s:'する → て形',a:'して',o:['して','すて','しいて'],e:'サ変：する→して。'},
  {t:'v',s:'来る → て形',a:'来て',o:['来て','来りて','来って'],e:'カ変：来る→来（き）て。'},
  // ── 可能形 ──
  {t:'v',s:'書く → 可能形',a:'書ける',o:['書ける','書かれる','書きれる'],e:'五段く→ける（え段+る）。'},
  {t:'v',s:'読む → 可能形',a:'読める',o:['読める','読まれる','読みれる'],e:'五段む→める（え段+る）。'},
  {t:'v',s:'話す → 可能形',a:'話せる',o:['話せる','話される','話しれる'],e:'五段す→せる（え段+る）。'},
  {t:'v',s:'泳ぐ → 可能形',a:'泳げる',o:['泳げる','泳がれる','泳ぎれる'],e:'五段ぐ→げる（え段+る）。'},
  {t:'v',s:'待つ → 可能形',a:'待てる',o:['待てる','待たれる','待ちれる'],e:'五段つ→てる（え段+る）。'},
  {t:'v',s:'飲む → 可能形',a:'飲める',o:['飲める','飲まれる','飲みれる'],e:'五段む→める（え段+る）。'},
  {t:'v',s:'食べる → 可能形',a:'食べられる',o:['食べられる','食べれる','食べえる'],e:'一段：去る+られる。'},
  {t:'v',s:'見る → 可能形',a:'見られる',o:['見られる','見れる','見える'],e:'一段：去る+られる。見える是自发态。'},
  {t:'v',s:'する → 可能形',a:'できる',o:['できる','される','しれる'],e:'サ変：する→できる（特殊）。'},
  {t:'v',s:'来る → 可能形',a:'来られる',o:['来られる','来れる','来える'],e:'カ変：来る→来（こ）られる。'},
  // ── 受身形（被動形） ──
  {t:'v',s:'書く → 受身形',a:'書かれる',o:['書かれる','書きれる','書ける'],e:'五段く→かれる（あ段+れる）。'},
  {t:'v',s:'読む → 受身形',a:'読まれる',o:['読まれる','読みれる','読める'],e:'五段む→まれる（あ段+れる）。'},
  {t:'v',s:'話す → 受身形',a:'話される',o:['話される','話しれる','話せる'],e:'五段す→される（あ段+れる）。'},
  {t:'v',s:'叱る → 受身形',a:'叱られる',o:['叱られる','叱りれる','叱れる'],e:'五段る→られる（あ段+れる）。'},
  {t:'v',s:'食べる → 受身形',a:'食べられる',o:['食べられる','食べれる','食べさせる'],e:'一段：去る+られる。'},
  {t:'v',s:'する → 受身形',a:'される',o:['される','しれる','すれる'],e:'サ変：する→される。'},
  {t:'v',s:'来る → 受身形',a:'来られる',o:['来られる','来れる','来させる'],e:'カ変：来る→来（こ）られる。'},
  // ── 使役形 ──
  {t:'v',s:'書く → 使役形',a:'書かせる',o:['書かせる','書きせる','書ける'],e:'五段く→かせる（あ段+せる）。'},
  {t:'v',s:'読む → 使役形',a:'読ませる',o:['読ませる','読みせる','読める'],e:'五段む→ませる（あ段+せる）。'},
  {t:'v',s:'飲む → 使役形',a:'飲ませる',o:['飲ませる','飲みせる','飲める'],e:'五段む→ませる（あ段+せる）。'},
  {t:'v',s:'行く → 使役形',a:'行かせる',o:['行かせる','行きせる','行ける'],e:'五段く→かせる（あ段+せる）。'},
  {t:'v',s:'食べる → 使役形',a:'食べさせる',o:['食べさせる','食べせる','食べられる'],e:'一段：去る+させる。'},
  {t:'v',s:'見る → 使役形',a:'見させる',o:['見させる','見せる','見られる'],e:'一段：去る+させる。注意見せる是别的词。'},
  {t:'v',s:'する → 使役形',a:'させる',o:['させる','しせる','される'],e:'サ変：する→させる。'},
  {t:'v',s:'来る → 使役形',a:'来させる',o:['来させる','来せる','来かせる'],e:'カ変：来る→来（こ）させる。'},
  // ── 使役受身形 ──
  {t:'v',s:'書く → 使役受身',a:'書かされる',o:['書かされる','書きされる','書くされる'],e:'五段短縮形：く→かされる。書かせられるも可。'},
  {t:'v',s:'飲む → 使役受身',a:'飲まされる',o:['飲まされる','飲みされる','飲むされる'],e:'五段短縮形：む→まされる。飲ませられるも可。'},
  {t:'v',s:'読む → 使役受身',a:'読まされる',o:['読まされる','読みされる','読むされる'],e:'五段短縮形：む→まされる。読ませられるも可。'},
  {t:'v',s:'走る → 使役受身',a:'走らされる',o:['走らされる','走りされる','走るされる'],e:'五段短縮形：る→らされる。走らせられるも可。'},
  {t:'v',s:'食べる → 使役受身',a:'食べさせられる',o:['食べさせられる','食べされる','食べさされる'],e:'一段：去る+させられる。无短縮形。'},
  {t:'v',s:'する → 使役受身',a:'させられる',o:['させられる','しされる','すされる'],e:'サ変：する→させられる。'},
  // ── 命令形 ──
  {t:'v',s:'書く → 命令形',a:'書け',o:['書け','書き','書こ'],e:'五段く→け（え段）。'},
  {t:'v',s:'読む → 命令形',a:'読め',o:['読め','読み','読も'],e:'五段む→め（え段）。'},
  {t:'v',s:'走る → 命令形',a:'走れ',o:['走れ','走り','走ろ'],e:'五段る→れ（え段）。'},
  {t:'v',s:'話す → 命令形',a:'話せ',o:['話せ','話し','話そ'],e:'五段す→せ（え段）。'},
  {t:'v',s:'食べる → 命令形',a:'食べろ',o:['食べろ','食べれ','食べよ'],e:'一段：去る+ろ。'},
  {t:'v',s:'する → 命令形',a:'しろ',o:['しろ','すれ','され'],e:'サ変：する→しろ（せよ）。'},
  {t:'v',s:'来る → 命令形',a:'来い',o:['来い','来ろ','来れ'],e:'カ変：来る→来（こ）い。'},
  // ── 意向形 ──
  {t:'v',s:'書く → 意向形',a:'書こう',o:['書こう','書きう','書けう'],e:'五段く→こう（お段+う）。'},
  {t:'v',s:'読む → 意向形',a:'読もう',o:['読もう','読みう','読めう'],e:'五段む→もう（お段+う）。'},
  {t:'v',s:'話す → 意向形',a:'話そう',o:['話そう','話しう','話せう'],e:'五段す→そう（お段+う）。'},
  {t:'v',s:'泳ぐ → 意向形',a:'泳ごう',o:['泳ごう','泳ぎう','泳げう'],e:'五段ぐ→ごう（お段+う）。'},
  {t:'v',s:'遊ぶ → 意向形',a:'遊ぼう',o:['遊ぼう','遊びう','遊べう'],e:'五段ぶ→ぼう（お段+う）。'},
  {t:'v',s:'食べる → 意向形',a:'食べよう',o:['食べよう','食べろう','食べう'],e:'一段：去る+よう。'},
  {t:'v',s:'する → 意向形',a:'しよう',o:['しよう','すよう','しろう'],e:'サ変：する→しよう。'},
  {t:'v',s:'来る → 意向形',a:'来よう',o:['来よう','来ろう','来う'],e:'カ変：来る→来（こ）よう。'},
  // ── 条件形（ば形） ──
  {t:'v',s:'書く → 条件形',a:'書けば',o:['書けば','書きば','書くば'],e:'五段く→けば（え段+ば）。'},
  {t:'v',s:'読む → 条件形',a:'読めば',o:['読めば','読みば','読むば'],e:'五段む→めば（え段+ば）。'},
  {t:'v',s:'話す → 条件形',a:'話せば',o:['話せば','話しば','話すば'],e:'五段す→せば（え段+ば）。'},
  {t:'v',s:'待つ → 条件形',a:'待てば',o:['待てば','待ちば','待つば'],e:'五段つ→てば（え段+ば）。'},
  {t:'v',s:'飲む → 条件形',a:'飲めば',o:['飲めば','飲みば','飲むば'],e:'五段む→めば（え段+ば）。'},
  {t:'v',s:'食べる → 条件形',a:'食べれば',o:['食べれば','食べば','食べるば'],e:'一段：去る+れば。'},
  {t:'v',s:'する → 条件形',a:'すれば',o:['すれば','しれば','するば'],e:'サ変：する→すれば。'},
  {t:'v',s:'来る → 条件形',a:'来れば',o:['来れば','来りば','来るば'],e:'カ変：来る→来（く）れば。'},
  // 词义选择 (t:'w')
  {t:'w',s:'嬉しい の意味は？',a:'高兴',o:['高兴','悲伤','害怕'],e:'嬉しい：高兴、喜悦。'},
  {t:'w',s:'難しい の意味は？',a:'困难',o:['困难','容易','有趣'],e:'難しい：困难的。'},
  {t:'w',s:'寂しい の意味は？',a:'寂寞',o:['寂寞','烦躁','愤怒'],e:'寂しい：寂寞的。'},
  {t:'w',s:'危ない の意味は？',a:'危险',o:['危险','安全','快速'],e:'危ない：危险的。'},
  {t:'w',s:'懐かしい の意味は？',a:'怀念',o:['怀念','陌生','无聊'],e:'懐かしい：怀念的。'},
  {t:'w',s:'諦める の意味は？',a:'放弃',o:['放弃','期待','努力'],e:'諦める：放弃。'},
  {t:'w',s:'褒める の意味は？',a:'表扬',o:['表扬','批评','忽视'],e:'褒める：表扬、夸赞。'},
  {t:'w',s:'慌てる の意味は？',a:'慌张',o:['慌张','镇定','欢呼'],e:'慌てる：慌张。'},
  {t:'w',s:'混む の意味は？',a:'拥挤',o:['拥挤','空旷','清洁'],e:'混む：拥挤。'},
  {t:'w',s:'片付ける の意味は？',a:'整理',o:['整理','破坏','装饰'],e:'片付ける：整理。'},
];

const G_Q_LABELS = { p:'助词填空', v:'动词活用', w:'词义选择' };

// ── 游戏模式 ──
let gGameType = 'particles'; // 'particles' or 'verbs'

// ── 全局状态 ──
let gBoard = null, gBoardTxt = null, gBoardClr = null;
let gScore = 0, gCombo = 0, gMaxCombo = 0, gWrong = 0, gWrongLog = [];
let gCurQ = null, gSelected = 1, gDropCol = 0;
let gBaseMs = 10000, gDropMs = 10000;
let gTimerIv = null, gTimeElapsed = 0, gRunning = false;
// 闯关状态
let gPhase        = 'select';
let gCurrentLevel = 1;
let gMaxLevels    = 30;
let gUnlockedTo   = 1;
let gLevelScores  = {};
let gGRows        = 3;
let gGCols        = 2;   // 动态列数（第1关=2列）
let gLives        = 1,  gLivesMax = 1;
let gPassTarget   = 6,  gPassCount = 0;
let gFever        = false;

// ── 关卡配置生成（cols 从 2 渐增到 6）──
function gLvlCfg(lv) {
  const cols     = lv === 1 ? 2 : lv <= 3 ? 3 : lv <= 6 ? 4 : lv <= 10 ? 5 : 6;
  const rows     = lv === 1 ? 3 : lv <= 3 ? 4 : lv <= 7 ? 5 : lv <= 12 ? 6 : 7;
  const toPass   = rows * cols;
  const livesMax = lv === 1 ? 1 : lv <= 3 ? 99 : lv <= 8 ? 5 : lv <= 15 ? 3 : 2;
  // verbs mode: only verb questions; particles mode: only particle questions
  const qTypes = gGameType === 'verbs'
    ? ['v']
    : ['p'];
  return {
    rows, cols, toPass, livesMax,
    speedMul: Math.max(0.28, 1 - (lv - 1) * 0.028),
    qTypes,
    rowBonus: lv <= 5 ? 5 : lv <= 12 ? 8 : 12,
  };
}

// ── localStorage 存档 ──
function gStorageKey(name) { return name + '_' + gGameType; }
function gLoadLocalSaves() {
  try {
    gUnlockedTo  = parseInt(localStorage.getItem(gStorageKey('gUnlockedTo')) || '1');
    gLevelScores = JSON.parse(localStorage.getItem(gStorageKey('gLevelScores')) || '{}');
  } catch {}
}
function gSaveLocalProgress(lv, score, stars, combo) {
  const prev = gLevelScores[lv] || {};
  if (!prev.stars || score > (prev.score || 0)) {
    gLevelScores[lv] = { score, stars, combo };
    try { localStorage.setItem(gStorageKey('gLevelScores'), JSON.stringify(gLevelScores)); } catch {}
  }
}

// ── 从服务器同步进度（登录用户） ──
function gSyncServerProgress() {
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  if (!token) return;
  fetch('/api/v1/game/my-progress?game_type=' + gGameType, {
    headers: { 'Authorization': 'Bearer ' + token }
  })
    .then(r => r.json())
    .then(d => {
      if (!d.ok) return;
      let changed = false;
      // 合并 unlocked_to（取最大值）
      const serverUnlocked = parseInt(d.unlocked_to) || 1;
      if (serverUnlocked > gUnlockedTo) {
        gUnlockedTo = serverUnlocked;
        try { localStorage.setItem(gStorageKey('gUnlockedTo'), gUnlockedTo); } catch {}
        changed = true;
      }
      // 合并各关分数（取最高分）
      const serverScores = d.level_scores || {};
      for (const lv of Object.keys(serverScores)) {
        const sv = serverScores[lv];
        const lo = gLevelScores[lv];
        if (!lo || (sv.score || 0) > (lo.score || 0)) {
          gLevelScores[lv] = sv;
          changed = true;
        }
      }
      if (changed) {
        try { localStorage.setItem(gStorageKey('gLevelScores'), JSON.stringify(gLevelScores)); } catch {}
        gRenderLevelGrid();
      }
    })
    .catch(() => {});
}

// ── 一次性迁移：把旧的无后缀 localStorage 数据迁移到 particles 命名空间 ──
function gMigrateOldStorage() {
  if (localStorage.getItem('gStorage_migrated')) return;
  try {
    var oldU = localStorage.getItem('gUnlockedTo');
    var oldS = localStorage.getItem('gLevelScores');
    if (oldU) {
      var key = 'gUnlockedTo_particles';
      var cur = parseInt(localStorage.getItem(key) || '1');
      if (parseInt(oldU) > cur) localStorage.setItem(key, oldU);
      localStorage.removeItem('gUnlockedTo');
    }
    if (oldS) {
      var key2 = 'gLevelScores_particles';
      var cur2 = localStorage.getItem(key2);
      if (!cur2 || cur2 === '{}') localStorage.setItem(key2, oldS);
      localStorage.removeItem('gLevelScores');
    }
    localStorage.setItem('gStorage_migrated', '1');
  } catch(e) {}
}

// ── 页面初始化 ──
function gamePageInit(gameType) {
  if (gameType) gGameType = gameType;
  gMigrateOldStorage();
  const titleEl = document.getElementById('g-title');
  if (titleEl) titleEl.textContent = gGameType === 'verbs' ? '🎮 动词方块' : '🎮 助词方块';
  gLoadLocalSaves();
  gameSpeedInit();
  gSyncServerProgress();
  fetch('/api/v1/game/config')
    .then(r => r.json())
    .then(d => {
      if (d.ok) {
        gMaxLevels = parseInt(d.config.max_levels) || 30;
        const mb = document.getElementById('g-max-badge');
        if (mb) mb.textContent = '共 ' + gMaxLevels + ' 关';
      }
    })
    .catch(() => {})
    .finally(() => gRenderLevelGrid());
  // 管理员按钮
  try {
    const u = JSON.parse(localStorage.getItem('user') || 'null');
    if (u && u.role === 'admin') {
      const ab = document.getElementById('g-admin-btn');
      if (ab) ab.style.display = '';
    }
  } catch {}
}

// ── 关卡网格渲染 ──
function gRenderLevelGrid() {
  const grid = document.getElementById('g-lvl-grid');
  if (!grid) return;
  let html = '';
  for (let lv = 1; lv <= gMaxLevels; lv++) {
    const locked  = lv > gUnlockedTo;
    const cfg     = gLvlCfg(lv);
    const saved   = gLevelScores[lv];
    const stars   = saved ? (saved.stars || 0) : 0;
    const starStr = '★'.repeat(stars) + '☆'.repeat(3 - stars);
    const cls     = locked ? 'locked' : saved ? 'done' : '';
    html += '<div class="g-lvl-cell ' + cls + '"' + (locked ? '' : ' onclick="gBeginLevel(' + lv + ')"') + '>' +
      '<div class="g-lvl-n">' + lv + '</div>' +
      '<div class="g-lvl-row">' + cfg.rows + '×' + cfg.cols + '</div>' +
      '<div class="g-lvl-star">' + starStr + '</div>' +
      (saved ? '<div class="g-lvl-hi">' + saved.score + '分</div>' : '') +
      (locked ? '<div class="g-lvl-lock">🔒</div>' : '') +
      '</div>';
  }
  grid.innerHTML = html;
}

// ── 开始关卡 ──
function gBeginLevel(lv) {
  const cfg    = gLvlCfg(lv);
  gCurrentLevel = lv;
  gGRows        = cfg.rows;
  gGCols        = cfg.cols;
  gLives        = cfg.livesMax;
  gLivesMax     = cfg.livesMax;
  gPassTarget   = cfg.toPass;
  gPassCount    = 0;
  gDropMs       = Math.round(gBaseMs * cfg.speedMul);
  gScore = 0; gCombo = 0; gMaxCombo = 0; gWrong = 0; gWrongLog = [];
  gFever = false; gRunning = true;
  document.getElementById('g-sel').style.display  = 'none';
  document.getElementById('g-play').style.display = '';
  document.getElementById('g-hud-title').textContent = '关卡 ' + lv + ' · ' + gGRows + '×' + gGCols;
  document.getElementById('g-pass-bar').style.width  = '0%';
  document.getElementById('g-pass-txt').textContent  = '0/' + cfg.toPass;
  document.getElementById('g-fever-banner').style.display = 'none';
  ['g-score','g-combo','g-wrong'].forEach(id => document.getElementById(id).textContent = 0);
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = '.45'; dp.style.pointerEvents = 'none'; }
  gRenderLives();
  gameInitBoard();
  gameNextQ();
}

// ── 返回关卡选择 ──
function gBackToSelect() {
  if (gTimerIv) { clearInterval(gTimerIv); gTimerIv = null; }
  gRunning = false;
  document.getElementById('g-play').style.display = 'none';
  document.getElementById('g-sel').style.display  = '';
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  gRenderLevelGrid();
}

// ── 生命值渲染 ──
function gRenderLives() {
  const el = document.getElementById('g-lives-row');
  if (!el) return;
  if (gLivesMax >= 99) { el.textContent = '∞'; return; }
  el.textContent = '❤️'.repeat(Math.max(0, gLives)) + '🖤'.repeat(Math.max(0, gLivesMax - gLives));
}

// ── 过关进度条 ──
function gUpdatePassBar() {
  const pct = Math.min(100, gPassCount / gPassTarget * 100);
  const bar = document.getElementById('g-pass-bar');
  const txt = document.getElementById('g-pass-txt');
  if (bar) bar.style.width = pct + '%';
  if (txt) txt.textContent = gPassCount + '/' + gPassTarget;
}

// ── 棋盘初始化 ──
function gameInitBoard() {
  const el = document.getElementById('g-board');
  if (!el) return;
  gBoard    = Array.from({length: gGRows}, () => Array(gGCols).fill(null));
  gBoardTxt = Array.from({length: gGRows}, () => Array(gGCols).fill(''));
  gBoardClr = Array.from({length: gGRows}, () => Array(gGCols).fill(''));
  el.style.gridTemplateRows     = 'repeat(' + gGRows + ', auto)';
  el.style.gridTemplateColumns  = 'repeat(' + gGCols + ', 1fr)';
  el.style.height = '';  // 不固定高度，让格子撑开
  // 格子高度：让总棋盘保持约160px，每格最小22px最大50px
  const ch = Math.max(22, Math.min(50, Math.floor(168 / gGRows)));
  let html = '';
  for (let r = 0; r < gGRows; r++)
    for (let c = 0; c < gGCols; c++)
      html += '<div class="g-cell" style="background:#f1f5f9;border:1px solid #e2e8f0;color:transparent;height:' + ch + 'px;width:100%"></div>';
  el.innerHTML = html;
}

// ── 棋盘刷新 ──
function gameRefreshBoard() {
  const el = document.getElementById('g-board');
  if (!el || !gBoard) return;
  const cells = el.children;
  if (cells.length !== gGRows * gGCols) { gameInitBoard(); return; }
  const ch      = Math.max(22, Math.min(50, Math.floor(168 / gGRows)));
  const fsSz    = gGCols <= 3 ? '14px' : gGCols <= 4 ? '12px' : '10px';
  const selTxt  = (gCurQ && gRunning) ? (gCurQ.o[gSelected] || '') : '';
  for (let r = 0; r < gGRows; r++) {
    for (let c = 0; c < gGCols; c++) {
      const st = gBoard[r][c];
      const d  = cells[r * gGCols + c];
      if (!d) continue;
      const idc = c === gDropCol && gRunning && st !== 'correct' && st !== 'wrong';
      const base = 'border-radius:6px;display:flex;align-items:center;justify-content:center;font-size:' + fsSz + ';font-weight:800;height:' + ch + 'px;width:100%;';
      if (st === 'correct') {
        d.style.cssText = base + 'color:#fff;background:' + gBoardClr[r][c] + ';border:none;box-shadow:0 2px 6px rgba(22,163,74,.5)';
        d.textContent = gBoardTxt[r][c];
      } else if (st === 'wrong') {
        d.style.cssText = base + 'color:#fff;background:linear-gradient(135deg,#dc2626,#ef4444);border:none;box-shadow:0 2px 6px rgba(220,38,38,.45)';
        d.textContent = gBoardTxt[r][c];
      } else if (st === 'active') {
        d.style.cssText = base + 'color:#fff;background:#4361ee;border:none;animation:gpulse .5s infinite alternate;font-size:' + fsSz;
        d.textContent = selTxt;
      } else {
        d.style.cssText = base + 'color:transparent;background:' + (idc ? '#dce7ff' : '#f1f5f9') + ';border:1px solid ' + (idc ? '#90aaff' : '#e2e8f0') + ';animation:none';
        d.textContent = '';
      }
    }
  }
}

// ── 随机取空列 ──
function gamePickCol() {
  const idxs = [...Array(gGCols).keys()].sort(() => Math.random() - .5);
  for (const c of idxs) if (!gBoard[0][c]) return c;
  return -1;
}

// ── 题目池（根据关卡类型） ──
function gQPool() {
  const types = new Set(gLvlCfg(gCurrentLevel).qTypes);
  return GAME_QS.filter(q => types.has(q.t));
}

// ── 下一题 ──
function gameNextQ() {
  if (!gRunning) return;
  gDropCol = gamePickCol();
  if (gDropCol === -1) { gRunning = false; setTimeout(gLevelFail, 300); return; }
  const pool  = gQPool();
  const src   = pool[Math.floor(Math.random() * pool.length)];
  // 深拷贝并随机打乱选项顺序
  const shuffled = [...src.o];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  gCurQ = { t: src.t, s: src.s, a: src.a, o: shuffled, e: src.e };
  gSelected = Math.floor(gCurQ.o.length / 2);
  gTimeElapsed = 0;
  document.getElementById('g-sentence').textContent      = gCurQ.s;
  document.getElementById('g-qtype-badge').textContent   = G_Q_LABELS[gCurQ.t] || '填空';
  gUpdateColHint();
  gameRenderOptions();
  gBoard[0][gDropCol] = 'active';
  gameRefreshBoard();
  if (gTimerIv) clearInterval(gTimerIv);
  const totalMs = gDropMs;
  gTimerIv = setInterval(() => {
    gTimeElapsed += 80;
    const pct = Math.max(0, 100 - gTimeElapsed / totalMs * 100);
    const bar = document.getElementById('g-timebar');
    if (bar) {
      bar.style.width      = pct + '%';
      bar.style.background = pct > 55 ? 'var(--primary)' : pct > 22 ? '#f59e0b' : 'var(--danger)';
    }
    if (gTimeElapsed >= totalMs) gameConfirm();
  }, 80);
}

// ── 列指示器 ──
function gUpdateColHint() {
  const el = document.getElementById('g-col-hint');
  if (!el) return;
  let s = '';
  for (let c = 0; c < gGCols; c++) s += c === gDropCol ? '▼' : '◦';
  el.textContent = s;
}

// ── 选项渲染 ──
function gameRenderOptions() {
  const el = document.getElementById('g-options');
  if (!el || !gCurQ) return;
  const maxLen = Math.max(...gCurQ.o.map(o => o.length));
  const fs = maxLen > 4 ? '12px' : maxLen > 2 ? '14px' : '17px';
  el.innerHTML = gCurQ.o.map((opt, i) =>
    '<div id="gopt-' + i + '" onclick="gameSelect(' + i + ',true)" style="' +
    'padding:8px 4px;border-radius:8px;text-align:center;cursor:pointer;' +
    'font-size:' + fs + ';font-weight:800;transition:all .15s;user-select:none;' +
    'border:2.5px solid ' + (i===gSelected ? 'var(--primary)' : 'var(--border)') + ';' +
    'background:' + (i===gSelected ? 'var(--primary-light,#e8effe)' : 'var(--surface)') + ';' +
    'color:' + (i===gSelected ? 'var(--primary)' : 'var(--text-sub)') + ';' +
    '">' + opt + '</div>'
  ).join('');
}

// ── 切换选项（autoConfirm=true 时点选即提交）──
function gameSelect(i, autoConfirm = false) {
  if (!gRunning) return;
  gSelected = i;
  gameRenderOptions();
  const el = document.getElementById('g-board');
  if (el && gBoard && gBoard[0] && gBoard[0][gDropCol] === 'active') {
    const d = el.children[gDropCol];
    if (d) d.textContent = gCurQ.o[i];
  }
  if (autoConfirm) setTimeout(gameConfirm, 80); // 点选80ms后自动确认
}

// ── 确认答案 ──
function gameConfirm() {
  if (!gRunning || !gCurQ) return;
  if (gTimerIv) { clearInterval(gTimerIv); gTimerIv = null; }
  gBoard[0][gDropCol] = null;
  const ans = gCurQ.o[gSelected];
  const ok  = ans === gCurQ.a;
  // 落点
  let landRow = -1;
  for (let r = gGRows - 1; r >= 0; r--) { if (!gBoard[r][gDropCol]) { landRow = r; break; } }
  if (landRow < 0) { gRunning = false; setTimeout(gLevelFail, 300); return; }
  gBoard[landRow][gDropCol]    = ok ? 'correct' : 'wrong';
  gBoardTxt[landRow][gDropCol] = ans;
  gBoardClr[landRow][gDropCol] = ok ? gComboColor() : 'linear-gradient(135deg,#dc2626,#ef4444)';

  if (ok) {
    gPassCount++;
    gCombo++;
    if (gCombo > gMaxCombo) gMaxCombo = gCombo;
    gDropMs = Math.max(Math.round(gBaseMs * 0.28), gDropMs - Math.round(gCombo * 22));
    const wasFever = gFever;
    gFever = gCombo >= 8;
    const fevBanner = document.getElementById('g-fever-banner');
    if (fevBanner) fevBanner.style.display = gFever ? '' : 'none';
    if (gFever && !wasFever) toast('🔥 FEVER 激活！得分 ×2');
    const mul = gFever ? 2 : 1;
    const pts = mul * (1 + Math.floor(gCombo / 5));
    gScore += pts;
    gameClearRows();
    gameShowFeedback(gSelected, true, pts);
  } else {
    gWrong++;
    gCombo = 0; gFever = false;
    const fevBanner = document.getElementById('g-fever-banner');
    if (fevBanner) fevBanner.style.display = 'none';
    gDropMs = Math.min(Math.round(gBaseMs * 1.1), gDropMs + 100);
    gWrongLog.push({s: gCurQ.s, wrong: ans, correct: gCurQ.a, e: gCurQ.e});
    if (gLivesMax < 99) {
      gLives--;
      gRenderLives();
      if (gLives <= 0) {
        gameShowFeedback(gSelected, false, 0);
        gameRefreshBoard();
        setTimeout(gLevelFail, 700);
        return;
      }
    }
    gameShowFeedback(gSelected, false, 0);
  }

  document.getElementById('g-score').textContent = gScore;
  document.getElementById('g-combo').textContent = gCombo;
  document.getElementById('g-wrong').textContent = gWrong;
  gUpdatePassBar();
  gameRefreshBoard();

  if (gPassCount >= gPassTarget) {
    gRunning = false;
    setTimeout(gLevelClear, 600);
    return;
  }
  // 只有所有列都顶格才判溢出失败；单列满时 gamePickCol 会自动跳过
  if (gBoard[0].every(c => c && c !== 'active')) {
    gRunning = false;
    setTimeout(gLevelFail, 800);
  } else {
    setTimeout(gameNextQ, 480);
  }
}

// ── 选项反馈（使用更醒目的颜色）──
function gameShowFeedback(idx, ok, pts) {
  const el = document.getElementById('g-options');
  if (!el || !gCurQ) return;
  el.querySelectorAll('div').forEach((d, i) => {
    if (i === idx) {
      d.style.background  = ok ? '#dcfce7' : '#fee2e2';
      d.style.borderColor = ok ? '#16a34a' : '#dc2626';
      d.style.color       = ok ? '#15803d' : '#b91c1c';
      d.style.transform   = ok ? 'scale(1.06)' : 'scale(0.96)';
      if (ok && pts > 1) d.textContent += ' +' + pts;
    }
    if (!ok && gCurQ.o[i] === gCurQ.a) {
      d.style.background  = '#dcfce7';
      d.style.borderColor = '#16a34a';
      d.style.color       = '#15803d';
    }
  });
}

// ── 消行（仅全部答对的行才消除并加分，错误格永久留板增加压力）──
function gameClearRows() {
  const bonus = gLvlCfg(gCurrentLevel).rowBonus;
  for (let r = gGRows - 1; r >= 0; r--) {
    if (gBoard[r].every(c => c === 'correct')) {   // 只消全正确行
      gScore += bonus;
      for (let rr = r; rr > 0; rr--) {
        gBoard[rr]    = [...gBoard[rr-1]];
        gBoardTxt[rr] = [...gBoardTxt[rr-1]];
        gBoardClr[rr] = [...gBoardClr[rr-1]];
      }
      gBoard[0]    = Array(gGCols).fill(null);
      gBoardTxt[0] = Array(gGCols).fill('');
      gBoardClr[0] = Array(gGCols).fill('');
      document.getElementById('g-score').textContent = gScore;
      toast('🎉 完美消行！+' + bonus + '分');
      r++;
    }
  }
}

// ── 连击颜色（基础=鲜绿，连击升级到紫蓝、火焰红橙）──
function gComboColor() {
  if (gCombo >= 10) return 'linear-gradient(135deg,#dc2626,#f97316)'; // 火焰
  if (gCombo >= 5)  return 'linear-gradient(135deg,#7c3aed,#4361ee)'; // 紫蓝
  return 'linear-gradient(135deg,#16a34a,#22c55e)';                   // 鲜绿
}

// ── 星级计算 ──
function gCalcStars(acc, maxCombo) {
  if (acc >= 85 && maxCombo >= 5) return 3;
  if (acc >= 65) return 2;
  return 1;
}

// ── 通关 ──
function gLevelClear() {
  const acc   = Math.round(gPassCount / Math.max(1, gPassCount + gWrong) * 100);
  const stars = gCalcStars(acc, gMaxCombo);
  const dp    = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  gSaveLocalProgress(gCurrentLevel, gScore, stars, gMaxCombo);
  if (gCurrentLevel >= gUnlockedTo && gCurrentLevel < gMaxLevels) {
    gUnlockedTo = gCurrentLevel + 1;
    try { localStorage.setItem(gStorageKey('gUnlockedTo'), gUnlockedTo); } catch {}
  }
  gameSaveScore(gCurrentLevel, gScore, acc, gMaxCombo, gPassCount + gWrong, true);
  const starStr = '⭐'.repeat(stars) + '☆'.repeat(3 - stars);
  const nextLv  = gCurrentLevel + 1;
  const hasNext = nextLv <= gMaxLevels;
  const wHtml   = gWrongLog.length
    ? '<div style="font-weight:700;margin-bottom:8px;text-align:left">📋 本关错题</div>' +
      gWrongLog.slice(0,5).map(w =>
        '<div style="padding:8px;background:var(--surface2,#f5f5f5);border-radius:6px;margin-bottom:6px;font-size:12px;text-align:left">' +
        '<div style="font-weight:700">' + escHtml(w.s) + '</div>' +
        '<div style="color:var(--danger)">❌ ' + escHtml(w.wrong) + '</div>' +
        '<div style="color:var(--success)">✅ ' + escHtml(w.correct) + '</div>' +
        '<div style="color:var(--text-sub);font-size:11px">' + escHtml(w.e) + '</div></div>'
      ).join('') : '';
  openModal('🎉 关卡 ' + gCurrentLevel + ' 通关！',
    '<div style="text-align:center;margin-bottom:14px">' +
    '<div style="font-size:44px;margin-bottom:8px">' + starStr + '</div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px">' +
    '<div style="background:var(--primary-light,#e8effe);padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--primary)">' + gScore + '</div><div style="font-size:10px;color:var(--text-sub)">得分</div></div>' +
    '<div style="background:#e8f5e9;padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--success)">' + acc + '%</div><div style="font-size:10px;color:var(--text-sub)">正确率</div></div>' +
    '<div style="background:#fffbeb;padding:12px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:#f59e0b">' + gMaxCombo + '</div><div style="font-size:10px;color:var(--text-sub)">最高连击</div></div>' +
    '</div></div>' + wHtml +
    '<div style="display:flex;gap:8px;justify-content:center;margin-top:12px;flex-wrap:wrap">' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBackToSelect()">关卡列表</button>' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBeginLevel(' + gCurrentLevel + ')">重玩本关</button>' +
    (hasNext
      ? '<button class="btn btn-primary btn-sm" onclick="closeModal();gBeginLevel(' + nextLv + ')">下一关 →</button>'
      : '<button class="btn btn-primary btn-sm" onclick="closeModal();gBackToSelect()">🏆 全部通关！</button>') +
    '</div>');
}

// ── 失败 ──
function gLevelFail() {
  const dp = document.getElementById('g-diff-panel');
  if (dp) { dp.style.opacity = ''; dp.style.pointerEvents = ''; }
  const total = gPassCount + gWrong;
  const acc   = total > 0 ? Math.round(gPassCount / total * 100) : 0;
  gameSaveScore(gCurrentLevel, gScore, acc, gMaxCombo, total, false);
  const reason  = gLives <= 0 ? '💔 生命用尽' : '📦 棋盘溢出';
  const wHtml   = gWrongLog.slice(0,6).map(w =>
    '<div style="padding:8px;background:var(--surface2,#f5f5f5);border-radius:6px;margin-bottom:6px;font-size:12px;text-align:left">' +
    '<div style="font-weight:700">' + escHtml(w.s) + '</div>' +
    '<div style="color:var(--danger)">❌ ' + escHtml(w.wrong) + '</div>' +
    '<div style="color:var(--success)">✅ ' + escHtml(w.correct) + '</div>' +
    '<div style="color:var(--text-sub);font-size:11px">' + escHtml(w.e) + '</div></div>'
  ).join('');
  openModal(reason + ' · 关卡 ' + gCurrentLevel,
    '<div style="text-align:center;margin-bottom:12px">' +
    '<div style="font-size:40px;margin-bottom:8px">😤</div>' +
    '<div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:8px;margin-bottom:10px">' +
    '<div style="background:var(--primary-light,#e8effe);padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--primary)">' + gScore + '</div><div style="font-size:10px;color:var(--text-sub)">得分</div></div>' +
    '<div style="background:#ffebee;padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--danger)">' + gWrong + '</div><div style="font-size:10px;color:var(--text-sub)">错误</div></div>' +
    '<div style="background:#e8f5e9;padding:10px;border-radius:8px"><div style="font-size:20px;font-weight:800;color:var(--success)">' + acc + '%</div><div style="font-size:10px;color:var(--text-sub)">正确率</div></div>' +
    '</div>' +
    '<div style="font-size:13px;color:var(--text-sub)">已答对 ' + gPassCount + '/' + gPassTarget + '，未达过关条件</div>' +
    '</div>' +
    (gWrongLog.length ? '<div style="font-weight:700;margin-bottom:8px">📋 错题回顾</div>' + wHtml : '') +
    '<div style="display:flex;gap:8px;justify-content:center;margin-top:12px;flex-wrap:wrap">' +
    '<button class="btn btn-outline btn-sm" onclick="closeModal();gBackToSelect()">关卡列表</button>' +
    '<button class="btn btn-primary btn-sm" onclick="closeModal();gBeginLevel(' + gCurrentLevel + ')">再试一次</button>' +
    '</div>');
}

// ── 分数上报后端（含速度 speed_ms 用于加权排名）──
function gameSaveScore(lv, score, acc, maxCombo, total, passed) {
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  if (!token) return;
  fetch('/api/v1/game/score', {
    method: 'POST',
    headers: {'Content-Type':'application/json','Authorization':'Bearer ' + token},
    body: JSON.stringify({level_num:lv, score, accuracy:acc, max_combo:maxCombo,
                         questions_answered:total, passed, speed_ms: gBaseMs, game_type: gGameType}),
  }).catch(() => {});
}

// ── 排行榜（全局） ──
function gLeaderboardHeaders() {
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  const h = {};
  if (token) h['Authorization'] = 'Bearer ' + token;
  return h;
}
function gOpenLeaderboard() {
  const label = gGameType === 'verbs' ? '动词方块' : '助词方块';
  openModal('🏆 ' + label + ' 总排行', '<div class="loading"><div class="spinner"></div></div>');
  fetch('/api/v1/game/leaderboard/global?game_type=' + gGameType, { headers: gLeaderboardHeaders() })
    .then(r => r.json())
    .then(d => {
      if (!d.ok || !d.data.length) {
        document.getElementById('modal-body').innerHTML = '<div style="text-align:center;color:var(--text-hint);padding:24px">暂无排行数据，快来成为第一名！</div>';
        return;
      }
      const rows = d.data.map((row, i) => {
        const md  = i===0?'🥇':i===1?'🥈':i===2?'🥉':'#'+(i+1);
        const spd = row.avg_speed_ms ? (row.avg_speed_ms/1000).toFixed(1)+'s' : '-';
        const selfStyle = row.is_self ? 'background:var(--primary-light,#e8effe);font-weight:800' : '';
        const nameExtra = row.is_self ? ' 👈' : '';
        return '<tr style="' + selfStyle + '"><td style="padding:8px 4px;text-align:center;font-size:15px">' + md + '</td>' +
          '<td style="padding:8px 4px;font-weight:700">' + escHtml(row.username||'***') + nameExtra + '</td>' +
          '<td style="padding:8px 4px;text-align:center;font-weight:800;color:var(--primary)">' + (row.max_level||0) + '</td>' +
          '<td style="padding:8px 4px;text-align:center;font-weight:800;color:#16a34a">' + (row.rating||0) + '</td>' +
          '<td style="padding:8px 4px;text-align:center;color:var(--text-sub);font-size:11px">' + spd + '</td>' +
          '<td style="padding:8px 4px;text-align:center;color:#f59e0b">' + (row.best_combo||0) + '</td></tr>';
      }).join('');
      document.getElementById('modal-body').innerHTML =
        '<div style="overflow-x:auto">' +
        '<table style="width:100%;border-collapse:collapse;font-size:13px">' +
        '<thead><tr style="border-bottom:2px solid var(--border);color:var(--text-sub)">' +
        '<th style="padding:6px;text-align:center">名次</th><th style="padding:6px">玩家</th>' +
        '<th style="padding:6px;text-align:center">最高关</th>' +
        '<th style="padding:6px;text-align:center">评分<br><span style="font-size:9px;font-weight:400">得分×速度</span></th>' +
        '<th style="padding:6px;text-align:center">用时</th>' +
        '<th style="padding:6px;text-align:center">最高连击</th></tr></thead>' +
        '<tbody>' + rows + '</tbody></table></div>' +
        '<div style="text-align:center;margin-top:12px">' +
        '<button class="btn btn-sm btn-outline" onclick="gOpenLevelLeaderboard(1)">单关排行 →</button></div>';
    })
    .catch(() => { document.getElementById('modal-body').innerHTML = '<div style="color:var(--danger);text-align:center;padding:16px">加载失败，请检查网络</div>'; });
}

// ── 单关排行榜 ──
function gOpenLevelLeaderboard(lv) {
  const label = gGameType === 'verbs' ? '动词方块' : '助词方块';
  document.getElementById('modal-title').textContent = '🏆 ' + label + ' 关卡 ' + lv;
  document.getElementById('modal-body').innerHTML = '<div class="loading"><div class="spinner"></div></div>';
  const total = Math.min(gMaxLevels, 10);
  const nav   = Array.from({length: total}, (_, i) =>
    '<button class="btn btn-sm ' + (i+1===lv?'btn-primary':'btn-outline') + '" onclick="gOpenLevelLeaderboard(' + (i+1) + ')" style="padding:4px 10px">Lv.' + (i+1) + '</button>'
  ).join('');
  fetch('/api/v1/game/leaderboard?level=' + lv + '&game_type=' + gGameType, { headers: gLeaderboardHeaders() })
    .then(r => r.json())
    .then(d => {
      const navHtml = '<div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:12px">' + nav + '</div>';
      if (!d.ok || !d.data.length) {
        document.getElementById('modal-body').innerHTML = navHtml + '<div style="text-align:center;color:var(--text-hint);padding:16px">该关暂无过关记录</div>';
        return;
      }
      const rows = d.data.map((row, i) => {
        const md = i===0?'🥇':i===1?'🥈':i===2?'🥉':'#'+(i+1);
        const selfStyle = row.is_self ? 'background:var(--primary-light,#e8effe);font-weight:800' : '';
        const nameExtra = row.is_self ? ' 👈' : '';
        return '<tr style="' + selfStyle + '"><td style="padding:7px 4px;text-align:center">' + md + '</td>' +
          '<td style="padding:7px 4px;font-weight:700">' + escHtml(row.username||'***') + nameExtra + '</td>' +
          '<td style="padding:7px 4px;text-align:center;font-weight:800;color:var(--primary)">' + (row.best_score||0) + '</td>' +
          '<td style="padding:7px 4px;text-align:center;color:#f59e0b">' + (row.best_combo||0) + '</td>' +
          '<td style="padding:7px 4px;text-align:center">' + (row.avg_acc||0) + '%</td></tr>';
      }).join('');
      document.getElementById('modal-body').innerHTML = navHtml +
        '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse;font-size:13px">' +
        '<thead><tr style="border-bottom:2px solid var(--border);color:var(--text-sub)">' +
        '<th style="padding:6px;text-align:center">名次</th><th style="padding:6px">玩家</th>' +
        '<th style="padding:6px;text-align:center">最高分</th><th style="padding:6px;text-align:center">最高连击</th>' +
        '<th style="padding:6px;text-align:center">准确率</th></tr></thead><tbody>' + rows + '</tbody></table></div>';
    })
    .catch(() => { document.getElementById('modal-body').innerHTML = '<div style="color:var(--danger);text-align:center;padding:16px">加载失败</div>'; });
}

// ── 管理员关卡设置 ──
function gOpenAdminConfig() {
  openModal('⚙️ 关卡设置（管理员）',
    '<div class="input-group"><label>最大关卡数（1-30）</label>' +
    '<input class="input" id="g-admin-maxlv" type="number" min="1" max="30" value="' + gMaxLevels + '"></div>' +
    '<div style="font-size:12px;color:var(--text-hint);margin-bottom:14px">设置后玩家可见的关卡总数将更新（当前：' + gMaxLevels + ' 关）</div>' +
    '<button class="btn btn-primary" style="width:100%;justify-content:center" onclick="gSaveAdminConfig()">保存</button>');
}
function gSaveAdminConfig() {
  const val   = parseInt(document.getElementById('g-admin-maxlv').value);
  const token = (typeof getToken === 'function') ? getToken() : localStorage.getItem('token');
  if (!token) { toast('请先登录'); return; }
  fetch('/api/v1/game/config', {
    method: 'PUT',
    headers: {'Content-Type':'application/json','Authorization':'Bearer '+token},
    body: JSON.stringify({max_levels: val}),
  }).then(r => r.json()).then(d => {
    if (d.ok) {
      gMaxLevels = d.max_levels;
      const mb = document.getElementById('g-max-badge');
      if (mb) mb.textContent = '共 ' + gMaxLevels + ' 关';
      closeModal();
      toast('✅ 已更新为 ' + gMaxLevels + ' 关');
      gRenderLevelGrid();
    }
  }).catch(() => toast('保存失败'));
}

// ── 速度滑块 ──
function gameSpeedInput(input) {
  const ms = parseInt(input.value);
  gBaseMs = ms;
  if (!gRunning) gDropMs = ms;
  const pct = (ms - 300) / (20000 - 300) * 100;
  input.style.background = 'linear-gradient(to right, var(--primary) ' + pct + '%, var(--border) ' + pct + '%)';
  const secs = (ms / 1000).toFixed(1);
  document.getElementById('g-speed-val').textContent = secs + 's';
  let emoji = '⚡', label = '极速';
  if      (ms >= 15000) { emoji = '🐢'; label = '慢速'; }
  else if (ms >= 8000)  { emoji = '🚶'; label = '正常'; }
  else if (ms >= 4000)  { emoji = '🏃'; label = '快速'; }
  else if (ms >= 1500)  { emoji = '💨'; label = '冲刺'; }
  document.getElementById('g-speed-emoji').textContent = emoji;
  document.getElementById('g-speed-label').textContent = label;
}
function gameSpeedInit() {
  const sl = document.getElementById('g-speed-slider');
  if (sl) gameSpeedInput(sl);
}

// ── 键盘控制 ──
document.addEventListener('keydown', function(e) {
  const ap = document.querySelector('.page.active');
  if (!ap || ap.id !== 'page-game' || !gRunning) return;
  const len = gCurQ ? gCurQ.o.length : 3;
  if      (e.key === 'ArrowLeft')              { gameSelect(Math.max(0, gSelected - 1)); e.preventDefault(); }
  else if (e.key === 'ArrowRight')             { gameSelect(Math.min(len - 1, gSelected + 1)); e.preventDefault(); }
  else if (e.key === 'Enter' || e.key === ' ') { gameConfirm(); e.preventDefault(); }
  else if (e.key >= '1' && e.key <= '3') { const idx=parseInt(e.key)-1; if(gCurQ&&idx<gCurQ.o.length) gameSelect(idx,true); e.preventDefault(); }
});
