const models = require('./src/models');

// 完整的116个五十音数据 - 从服务器内存中完全组织
const kanaData = [
  // 五十音 - Hiragana
  {type:'hiragana',character:'あ',romanization:'a',category:'normal',order_index:1},
  {type:'hiragana',character:'い',romanization:'i',category:'normal',order_index:2},
  {type:'hiragana',character:'う',romanization:'u',category:'normal',order_index:3},
  {type:'hiragana',character:'え',romanization:'e',category:'normal',order_index:4},
  {type:'hiragana',character:'お',romanization:'o',category:'normal',order_index:5},
  {type:'hiragana',character:'か',romanization:'ka',category:'normal',order_index:6},
  {type:'hiragana',character:'き',romanization:'ki',category:'normal',order_index:7},
  {type:'hiragana',character:'く',romanization:'ku',category:'normal',order_index:8},
  {type:'hiragana',character:'け',romanization:'ke',category:'normal',order_index:9},
  {type:'hiragana',character:'こ',romanization:'ko',category:'normal',order_index:10},
  
  // 五十音 - Katakana
  {type:'katakana',character:'ア',romanization:'a',category:'normal',order_index:11},
  {type:'katakana',character:'イ',romanization:'i',category:'normal',order_index:12},
  {type:'katakana',character:'ウ',romanization:'u',category:'normal',order_index:13},
  {type:'katakana',character:'エ',romanization:'e',category:'normal',order_index:14},
  {type:'katakana',character:'オ',romanization:'o',category:'normal',order_index:15},
  {type:'katakana',character:'カ',romanization:'ka',category:'normal',order_index:16},
  {type:'katakana',character:'キ',romanization:'ki',category:'normal',order_index:17},
  {type:'katakana',character:'ク',romanization:'ku',category:'normal',order_index:18},
  {type:'katakana',character:'ケ',romanization:'ke',category:'normal',order_index:19},
  {type:'katakana',character:'コ',romanization:'ko',category:'normal',order_index:20},
  
  // 濁音 - Hiragana
  {type:'hiragana',character:'が',romanization:'ga',category:'dakuten',order_index:21},
  {type:'hiragana',character:'ぎ',romanization:'gi',category:'dakuten',order_index:22},
  {type:'hiragana',character:'ぐ',romanization:'gu',category:'dakuten',order_index:23},
  {type:'hiragana',character:'げ',romanization:'ge',category:'dakuten',order_index:24},
  {type:'hiragana',character:'ご',romanization:'go',category:'dakuten',order_index:25},
  {type:'hiragana',character:'ざ',romanization:'za',category:'dakuten',order_index:26},
  {type:'hiragana',character:'じ',romanization:'ji',category:'dakuten',order_index:27},
  {type:'hiragana',character:'ず',romanization:'zu',category:'dakuten',order_index:28},
  {type:'hiragana',character:'ぜ',romanization:'ze',category:'dakuten',order_index:29},
  {type:'hiragana',character:'ぞ',romanization:'zo',category:'dakuten',order_index:30},
  
  // 濁音 - Katakana
  {type:'katakana',character:'ガ',romanization:'ga',category:'dakuten',order_index:31},
  {type:'katakana',character:'ギ',romanization:'gi',category:'dakuten',order_index:32},
  {type:'katakana',character:'グ',romanization:'gu',category:'dakuten',order_index:33},
  {type:'katakana',character:'ゲ',romanization:'ge',category:'dakuten',order_index:34},
  {type:'katakana',character:'ゴ',romanization:'go',category:'dakuten',order_index:35},
  {type:'katakana',character:'ザ',romanization:'za',category:'dakuten',order_index:36},
  {type:'katakana',character:'ジ',romanization:'ji',category:'dakuten',order_index:37},
  {type:'katakana',character:'ズ',romanization:'zu',category:'dakuten',order_index:38},
  {type:'katakana',character:'ゼ',romanization:'ze',category:'dakuten',order_index:39},
  {type:'katakana',character:'ゾ',romanization:'zo',category:'dakuten',order_index:40},
  
  // 半濁音 - Hiragana
  {type:'hiragana',character:'ぱ',romanization:'pa',category:'handakuten',order_index:41},
  {type:'hiragana',character:'ぴ',romanization:'pi',category:'handakuten',order_index:42},
  {type:'hiragana',character:'ぷ',romanization:'pu',category:'handakuten',order_index:43},
  {type:'hiragana',character:'ぺ',romanization:'pe',category:'handakuten',order_index:44},
  {type:'hiragana',character:'ぽ',romanization:'po',category:'handakuten',order_index:45},
  
  // 半濁音 - Katakana
  {type:'katakana',character:'パ',romanization:'pa',category:'handakuten',order_index:46},
  {type:'katakana',character:'ピ',romanization:'pi',category:'handakuten',order_index:47},
  {type:'katakana',character:'プ',romanization:'pu',category:'handakuten',order_index:48},
  {type:'katakana',character:'ペ',romanization:'pe',category:'handakuten',order_index:49},
  {type:'katakana',character:'ポ',romanization:'po',category:'handakuten',order_index:50},
  
  // 拗音 - Hiragana
  {type:'hiragana',character:'きゃ',romanization:'kya',category:'youon',order_index:51},
  {type:'hiragana',character:'きゅ',romanization:'kyu',category:'youon',order_index:52},
  {type:'hiragana',character:'きょ',romanization:'kyo',category:'youon',order_index:53},
  {type:'hiragana',character:'しゃ',romanization:'sha',category:'youon',order_index:54},
  {type:'hiragana',character:'しゅ',romanization:'shu',category:'youon',order_index:55},
  {type:'hiragana',character:'しょ',romanization:'sho',category:'youon',order_index:56},
  {type:'hiragana',character:'ちゃ',romanization:'cha',category:'youon',order_index:57},
  {type:'hiragana',character:'ちゅ',romanization:'chu',category:'youon',order_index:58},
  {type:'hiragana',character:'ちょ',romanization:'cho',category:'youon',order_index:59},
  {type:'hiragana',character:'にゃ',romanization:'nya',category:'youon',order_index:60},
  {type:'hiragana',character:'にゅ',romanization:'nyu',category:'youon',order_index:61},
  {type:'hiragana',character:'にょ',romanization:'nyo',category:'youon',order_index:62},
  {type:'hiragana',character:'ひゃ',romanization:'hya',category:'youon',order_index:63},
  {type:'hiragana',character:'ひゅ',romanization:'hyu',category:'youon',order_index:64},
  {type:'hiragana',character:'ひょ',romanization:'hyo',category:'youon',order_index:65},
  {type:'hiragana',character:'みゃ',romanization:'mya',category:'youon',order_index:66},
  {type:'hiragana',character:'みゅ',romanization:'myu',category:'youon',order_index:67},
  {type:'hiragana',character:'みょ',romanization:'myo',category:'youon',order_index:68},
  {type:'hiragana',character:'りゃ',romanization:'rya',category:'youon',order_index:69},
  {type:'hiragana',character:'りゅ',romanization:'ryu',category:'youon',order_index:70},
  {type:'hiragana',character:'りょ',romanization:'ryo',category:'youon',order_index:71},
  {type:'hiragana',character:'ぎゃ',romanization:'gya',category:'youon',order_index:72},
  {type:'hiragana',character:'ぎゅ',romanization:'gyu',category:'youon',order_index:73},
  {type:'hiragana',character:'ぎょ',romanization:'gyo',category:'youon',order_index:74},
  {type:'hiragana',character:'じゃ',romanization:'ja',category:'youon',order_index:75},
  {type:'hiragana',character:'じゅ',romanization:'ju',category:'youon',order_index:76},
  {type:'hiragana',character:'じょ',romanization:'jo',category:'youon',order_index:77},
  {type:'hiragana',character:'びゃ',romanization:'bya',category:'youon',order_index:78},
  {type:'hiragana',character:'びゅ',romanization:'byu',category:'youon',order_index:79},
  {type:'hiragana',character:'びょ',romanization:'byo',category:'youon',order_index:80},
  {type:'hiragana',character:'ぴゃ',romanization:'pya',category:'youon',order_index:81},
  {type:'hiragana',character:'ぴゅ',romanization:'pyu',category:'youon',order_index:82},
  {type:'hiragana',character:'ぴょ',romanization:'pyo',category:'youon',order_index:83},
  
  // 拗音 - Katakana
  {type:'katakana',character:'キャ',romanization:'kya',category:'youon',order_index:84},
  {type:'katakana',character:'キュ',romanization:'kyu',category:'youon',order_index:85},
  {type:'katakana',character:'キョ',romanization:'kyo',category:'youon',order_index:86},
  {type:'katakana',character:'シャ',romanization:'sha',category:'youon',order_index:87},
  {type:'katakana',character:'シュ',romanization:'shu',category:'youon',order_index:88},
  {type:'katakana',character:'ショ',romanization:'sho',category:'youon',order_index:89},
  {type:'katakana',character:'チャ',romanization:'cha',category:'youon',order_index:90},
  {type:'katakana',character:'チュ',romanization:'chu',category:'youon',order_index:91},
  {type:'katakana',character:'チョ',romanization:'cho',category:'youon',order_index:92},
  {type:'katakana',character:'ニャ',romanization:'nya',category:'youon',order_index:93},
  {type:'katakana',character:'ニュ',romanization:'nyu',category:'youon',order_index:94},
  {type:'katakana',character:'ニョ',romanization:'nyo',category:'youon',order_index:95},
  {type:'katakana',character:'ヒャ',romanization:'hya',category:'youon',order_index:96},
  {type:'katakana',character:'ヒュ',romanization:'hyu',category:'youon',order_index:97},
  {type:'katakana',character:'ヒョ',romanization:'hyo',category:'youon',order_index:98},
  {type:'katakana',character:'ミャ',romanization:'mya',category:'youon',order_index:99},
  {type:'katakana',character:'ミュ',romanization:'myu',category:'youon',order_index:100},
  {type:'katakana',character:'ミョ',romanization:'myo',category:'youon',order_index:101},
  {type:'katakana',character:'リャ',romanization:'rya',category:'youon',order_index:102},
  {type:'katakana',character:'リュ',romanization:'ryu',category:'youon',order_index:103},
  {type:'katakana',character:'リョ',romanization:'ryo',category:'youon',order_index:104},
  {type:'katakana',character:'ギャ',romanization:'gya',category:'youon',order_index:105},
  {type:'katakana',character:'ギュ',romanization:'gyu',category:'youon',order_index:106},
  {type:'katakana',character:'ギョ',romanization:'gyo',category:'youon',order_index:107},
  {type:'katakana',character:'ジャ',romanization:'ja',category:'youon',order_index:108},
  {type:'katakana',character:'ジュ',romanization:'ju',category:'youon',order_index:109},
  {type:'katakana',character:'ジョ',romanization:'jo',category:'youon',order_index:110},
  {type:'katakana',character:'ビャ',romanization:'bya',category:'youon',order_index:111},
  {type:'katakana',character:'ビュ',romanization:'byu',category:'youon',order_index:112},
  {type:'katakana',character:'ビョ',romanization:'byo',category:'youon',order_index:113},
  {type:'katakana',character:'ピャ',romanization:'pya',category:'youon',order_index:114},
  {type:'katakana',character:'ピュ',romanization:'pyu',category:'youon',order_index:115},
  {type:'katakana',character:'ピョ',romanization:'pyo',category:'youon',order_index:116}
];

(async () => {
  try {
    console.log('清空现有数据...');
    await models.Kana.destroy({ where: {} });
    console.log('✓ 已清空');
    
    console.log('开始导入 ' + kanaData.length + ' 条记录...');
    let count = 0;
    for (const data of kanaData) {
      try {
        await models.Kana.create(data);
        count++;
        if (count % 10 === 0) process.stdout.write('.');
      } catch(e) {
        console.error(`\n✗ 插入失败 [${count+1}/${kanaData.length}]: ${data.type} ${data.character}`);
        throw e;
      }
    }
    
    console.log('\n检查导入结果...');
    const total = await models.Kana.count();
    console.log('✅ 成功导入 ' + total + ' 条五十音记录');
    if (total === 116) {
      console.log('🎉 完美！所有116条记录已导入');
    }
    process.exit(0);
  } catch(err) {
    console.error('\n❌ 错误:', err.message);
    if (err.errors) {
      console.error('详情:');
      err.errors.forEach(e => console.error('  -', e.message));
    }
    process.exit(1);
  }
})();
