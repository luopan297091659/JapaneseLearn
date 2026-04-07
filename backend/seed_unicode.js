const models = require('./src/models');

// 使用Unicode转义序列确保不会在文件编码中丢失
const kanaData = [
  {type:'hiragana',character:'\u3042',romanization:'a',category:'normal',order_index:1},
  {type:'hiragana',character:'\u3044',romanization:'i',category:'normal',order_index:2},
  {type:'hiragana',character:'\u3046',romanization:'u',category:'normal',order_index:3},
  {type:'hiragana',character:'\u3048',romanization:'e',category:'normal',order_index:4},
  {type:'hiragana',character:'\u304a',romanization:'o',category:'normal',order_index:5},
  {type:'hiragana',character:'\u304b',romanization:'ka',category:'normal',order_index:6},
  {type:'hiragana',character:'\u304d',romanization:'ki',category:'normal',order_index:7},
  {type:'hiragana',character:'\u304f',romanization:'ku',category:'normal',order_index:8},
  {type:'hiragana',character:'\u3051',romanization:'ke',category:'normal',order_index:9},
  {type:'hiragana',character:'\u3053',romanization:'ko',category:'normal',order_index:10},
  {type:'katakana',character:'\u30a2',romanization:'a',category:'normal',order_index:11},
  {type:'katakana',character:'\u30a4',romanization:'i',category:'normal',order_index:12},
  {type:'katakana',character:'\u30a6',romanization:'u',category:'normal',order_index:13},
  {type:'katakana',character:'\u30a8',romanization:'e',category:'normal',order_index:14},
  {type:'katakana',character:'\u30aa',romanization:'o',category:'normal',order_index:15},
  {type:'katakana',character:'\u30ab',romanization:'ka',category:'normal',order_index:16},
  {type:'katakana',character:'\u30ad',romanization:'ki',category:'normal',order_index:17},
  {type:'katakana',character:'\u30af',romanization:'ku',category:'normal',order_index:18},
  {type:'katakana',character:'\u30b1',romanization:'ke',category:'normal',order_index:19},
  {type:'katakana',character:'\u30b3',romanization:'ko',category:'normal',order_index:20},
  {type:'hiragana',character:'\u304c',romanization:'ga',category:'dakuten',order_index:21},
  {type:'hiragana',character:'\u304e',romanization:'gi',category:'dakuten',order_index:22},
  {type:'hiragana',character:'\u3050',romanization:'gu',category:'dakuten',order_index:23},
  {type:'hiragana',character:'\u3052',romanization:'ge',category:'dakuten',order_index:24},
  {type:'hiragana',character:'\u3054',romanization:'go',category:'dakuten',order_index:25},
  {type:'hiragana',character:'\u3056',romanization:'za',category:'dakuten',order_index:26},
  {type:'hiragana',character:'\u3058',romanization:'ji',category:'dakuten',order_index:27},
  {type:'hiragana',character:'\u305a',romanization:'zu',category:'dakuten',order_index:28},
  {type:'hiragana',character:'\u305c',romanization:'ze',category:'dakuten',order_index:29},
  {type:'hiragana',character:'\u305e',romanization:'zo',category:'dakuten',order_index:30},
  {type:'katakana',character:'\u30ac',romanization:'ga',category:'dakuten',order_index:31},
  {type:'katakana',character:'\u30ae',romanization:'gi',category:'dakuten',order_index:32},
  {type:'katakana',character:'\u30b0',romanization:'gu',category:'dakuten',order_index:33},
  {type:'katakana',character:'\u30b2',romanization:'ge',category:'dakuten',order_index:34},
  {type:'katakana',character:'\u30b4',romanization:'go',category:'dakuten',order_index:35},
  {type:'katakana',character:'\u30b6',romanization:'za',category:'dakuten',order_index:36},
  {type:'katakana',character:'\u30b8',romanization:'ji',category:'dakuten',order_index:37},
  {type:'katakana',character:'\u30ba',romanization:'zu',category:'dakuten',order_index:38},
  {type:'katakana',character:'\u30bc',romanization:'ze',category:'dakuten',order_index:39},
  {type:'katakana',character:'\u30be',romanization:'zo',category:'dakuten',order_index:40},
  {type:'hiragana',character:'\u3071',romanization:'pa',category:'handakuten',order_index:41},
  {type:'hiragana',character:'\u3073',romanization:'pi',category:'handakuten',order_index:42},
  {type:'hiragana',character:'\u3075',romanization:'pu',category:'handakuten',order_index:43},
  {type:'hiragana',character:'\u3079',romanization:'pe',category:'handakuten',order_index:44},
  {type:'hiragana',character:'\u307d',romanization:'po',category:'handakuten',order_index:45},
  {type:'katakana',character:'\u30d1',romanization:'pa',category:'handakuten',order_index:46},
  {type:'katakana',character:'\u30d3',romanization:'pi',category:'handakuten',order_index:47},
  {type:'katakana',character:'\u30d7',romanization:'pu',category:'handakuten',order_index:48},
  {type:'katakana',character:'\u30da',romanization:'pe',category:'handakuten',order_index:49},
  {type:'katakana',character:'\u30dd',romanization:'po',category:'handakuten',order_index:50},
  {type:'hiragana',character:'\u304d\u3083',romanization:'kya',category:'youon',order_index:51},
  {type:'hiragana',character:'\u304d\u3085',romanization:'kyu',category:'youon',order_index:52},
  {type:'hiragana',character:'\u304d\u3087',romanization:'kyo',category:'youon',order_index:53},
  {type:'hiragana',character:'\u3057\u3083',romanization:'sha',category:'youon',order_index:54},
  {type:'hiragana',character:'\u3057\u3085',romanization:'shu',category:'youon',order_index:55},
  {type:'hiragana',character:'\u3057\u3087',romanization:'sho',category:'youon',order_index:56},
  {type:'hiragana',character:'\u3061\u3083',romanization:'cha',category:'youon',order_index:57},
  {type:'hiragana',character:'\u3061\u3085',romanization:'chu',category:'youon',order_index:58},
  {type:'hiragana',character:'\u3061\u3087',romanization:'cho',category:'youon',order_index:59},
  {type:'hiragana',character:'\u306b\u3083',romanization:'nya',category:'youon',order_index:60},
  {type:'hiragana',character:'\u306b\u3085',romanization:'nyu',category:'youon',order_index:61},
  {type:'hiragana',character:'\u306b\u3087',romanization:'nyo',category:'youon',order_index:62},
  {type:'hiragana',character:'\u3072\u3083',romanization:'hya',category:'youon',order_index:63},
  {type:'hiragana',character:'\u3072\u3085',romanization:'hyu',category:'youon',order_index:64},
  {type:'hiragana',character:'\u3072\u3087',romanization:'hyo',category:'youon',order_index:65},
  {type:'hiragana',character:'\u307f\u3083',romanization:'mya',category:'youon',order_index:66},
  {type:'hiragana',character:'\u307f\u3085',romanization:'myu',category:'youon',order_index:67},
  {type:'hiragana',character:'\u307f\u3087',romanization:'myo',category:'youon',order_index:68},
  {type:'hiragana',character:'\u308a\u3083',romanization:'rya',category:'youon',order_index:69},
  {type:'hiragana',character:'\u308a\u3085',romanization:'ryu',category:'youon',order_index:70},
  {type:'hiragana',character:'\u308a\u3087',romanization:'ryo',category:'youon',order_index:71},
  {type:'hiragana',character:'\u304e\u3083',romanization:'gya',category:'youon',order_index:72},
  {type:'hiragana',character:'\u304e\u3085',romanization:'gyu',category:'youon',order_index:73},
  {type:'hiragana',character:'\u304e\u3087',romanization:'gyo',category:'youon',order_index:74},
  {type:'hiragana',character:'\u3058\u3083',romanization:'ja',category:'youon',order_index:75},
  {type:'hiragana',character:'\u3058\u3085',romanization:'ju',category:'youon',order_index:76},
  {type:'hiragana',character:'\u3058\u3087',romanization:'jo',category:'youon',order_index:77},
  {type:'hiragana',character:'\u3073\u3083',romanization:'bya',category:'youon',order_index:78},
  {type:'hiragana',character:'\u3073\u3085',romanization:'byu',category:'youon',order_index:79},
  {type:'hiragana',character:'\u3073\u3087',romanization:'byo',category:'youon',order_index:80},
  {type:'hiragana',character:'\u3074\u3083',romanization:'pya',category:'youon',order_index:81},
  {type:'hiragana',character:'\u3074\u3085',romanization:'pyu',category:'youon',order_index:82},
  {type:'hiragana',character:'\u3074\u3087',romanization:'pyo',category:'youon',order_index:83},
  {type:'katakana',character:'\u30ad\u30e3',romanization:'kya',category:'youon',order_index:84},
  {type:'katakana',character:'\u30ad\u30e5',romanization:'kyu',category:'youon',order_index:85},
  {type:'katakana',character:'\u30ad\u30e7',romanization:'kyo',category:'youon',order_index:86},
  {type:'katakana',character:'\u30b7\u30e3',romanization:'sha',category:'youon',order_index:87},
  {type:'katakana',character:'\u30b7\u30e5',romanization:'shu',category:'youon',order_index:88},
  {type:'katakana',character:'\u30b7\u30e7',romanization:'sho',category:'youon',order_index:89},
  {type:'katakana',character:'\u30c1\u30e3',romanization:'cha',category:'youon',order_index:90},
  {type:'katakana',character:'\u30c1\u30e5',romanization:'chu',category:'youon',order_index:91},
  {type:'katakana',character:'\u30c1\u30e7',romanization:'cho',category:'youon',order_index:92},
  {type:'katakana',character:'\u30cb\u30e3',romanization:'nya',category:'youon',order_index:93},
  {type:'katakana',character:'\u30cb\u30e5',romanization:'nyu',category:'youon',order_index:94},
  {type:'katakana',character:'\u30cb\u30e7',romanization:'nyo',category:'youon',order_index:95},
  {type:'katakana',character:'\u30d2\u30e3',romanization:'hya',category:'youon',order_index:96},
  {type:'katakana',character:'\u30d2\u30e5',romanization:'hyu',category:'youon',order_index:97},
  {type:'katakana',character:'\u30d2\u30e7',romanization:'hyo',category:'youon',order_index:98},
  {type:'katakana',character:'\u30df\u30e3',romanization:'mya',category:'youon',order_index:99},
  {type:'katakana',character:'\u30df\u30e5',romanization:'myu',category:'youon',order_index:100},
  {type:'katakana',character:'\u30df\u30e7',romanization:'myo',category:'youon',order_index:101},
  {type:'katakana',character:'\u30ea\u30e3',romanization:'rya',category:'youon',order_index:102},
  {type:'katakana',character:'\u30ea\u30e5',romanization:'ryu',category:'youon',order_index:103},
  {type:'katakana',character:'\u30ea\u30e7',romanization:'ryo',category:'youon',order_index:104},
  {type:'katakana',character:'\u30ae\u30e3',romanization:'gya',category:'youon',order_index:105},
  {type:'katakana',character:'\u30ae\u30e5',romanization:'gyu',category:'youon',order_index:106},
  {type:'katakana',character:'\u30ae\u30e7',romanization:'gyo',category:'youon',order_index:107},
  {type:'katakana',character:'\u30b8\u30e3',romanization:'ja',category:'youon',order_index:108},
  {type:'katakana',character:'\u30b8\u30e5',romanization:'ju',category:'youon',order_index:109},
  {type:'katakana',character:'\u30b8\u30e7',romanization:'jo',category:'youon',order_index:110},
  {type:'katakana',character:'\u30d3\u30e3',romanization:'bya',category:'youon',order_index:111},
  {type:'katakana',character:'\u30d3\u30e5',romanization:'byu',category:'youon',order_index:112},
  {type:'katakana',character:'\u30d3\u30e7',romanization:'byo',category:'youon',order_index:113},
  {type:'katakana',character:'\u30d4\u30e3',romanization:'pya',category:'youon',order_index:114},
  {type:'katakana',character:'\u30d4\u30e5',romanization:'pyu',category:'youon',order_index:115},
  {type:'katakana',character:'\u30d4\u30e7',romanization:'pyo',category:'youon',order_index:116}
];

(async () => {
  try {
    console.log('开始清空并导入...');
    await models.Kana.destroy({where:{}});
    
    for (let i=0; i<kanaData.length; i++) {
      const data = kanaData[i];
      try {
        await models.Kana.create(data);
        if ((i+1) % 20 === 0) console.log(`✓ ${i+1}/${kanaData.length}`);
      } catch(e) {
        console.error(`✗ Failed at index ${i} (${data.type} ${data.character}): ${e.message}`);
        throw e;
      }
    }
    
    const cnt = await models.Kana.count();
    console.log(`✅ Successfully imported ${cnt}/116 kana records`);
    if (cnt === 116) console.log('🎉 完美！');
    process.exit(0);
  } catch(e) {
    console.error('❌', e.message);
    process.exit(1);
  }
})();
