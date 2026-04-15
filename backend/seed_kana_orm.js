const models = require('./src/models');

const kana = [
  ['あ','a','hiragana','normal',1],['い','i','hiragana','normal',2],['う','u','hiragana','normal',3],['え','e','hiragana','normal',4],['お','o','hiragana','normal',5],
  ['か','ka','hiragana','normal',6],['き','ki','hiragana','normal',7],['く','ku','hiragana','normal',8],['け','ke','hiragana','normal',9],['こ','ko','hiragana','normal',10],
  ['ア','a','katakana','normal',11],['イ','i','katakana','normal',12],['ウ','u','katakana','normal',13],['エ','e','katakana','normal',14],['オ','o','katakana','normal',15],
  ['カ','ka','katakana','normal',16],['キ','ki','katakana','normal',17],['ク','ku','katakana','normal',18],['ケ','ke','katakana','normal',19],['コ','ko','katakana','normal',20],
  ['が','ga','hiragana','dakuten',21],['ぎ','gi','hiragana','dakuten',22],['ぐ','gu','hiragana','dakuten',23],['げ','ge','hiragana','dakuten',24],['ご','go','hiragana','dakuten',25],
  ['ざ','za','hiragana','dakuten',26],['じ','ji','hiragana','dakuten',27],['ず','zu','hiragana','dakuten',28],['ぜ','ze','hiragana','dakuten',29],['ぞ','zo','hiragana','dakuten',30],
  ['ガ','ga','katakana','dakuten',31],['ギ','gi','katakana','dakuten',32],['グ','gu','katakana','dakuten',33],['ゲ','ge','katakana','dakuten',34],['ゴ','go','katakana','dakuten',35],
  ['ザ','za','katakana','dakuten',36],['ジ','ji','katakana','dakuten',37],['ズ','zu','katakana','dakuten',38],['ゼ','ze','katakana','dakuten',39],['ゾ','zo','katakana','dakuten',40],
  ['ぱ','pa','hiragana','handakuten',41],['ぴ','pi','hiragana','handakuten',42],['ぷ','pu','hiragana','handakuten',43],['ぺ','pe','hiragana','handakuten',44],['ぽ','po','hiragana','handakuten',45],
  ['パ','pa','katakana','handakuten',46],['ピ','pi','katakana','handakuten',47],['プ','pu','katakana','handakuten',48],['ペ','pe','katakana','handakuten',49],['ポ','po','katakana','handakuten',50],
  ['きゃ','kya','hiragana','youon',51],['きゅ','kyu','hiragana','youon',52],['きょ','kyo','hiragana','youon',53],['しゃ','sha','hiragana','youon',54],['しゅ','shu','hiragana','youon',55],
  ['しょ','sho','hiragana','youon',56],['ちゃ','cha','hiragana','youon',57],['ちゅ','chu','hiragana','youon',58],['ちょ','cho','hiragana','youon',59],['にゃ','nya','hiragana','youon',60],
  ['にゅ','nyu','hiragana','youon',61],['にょ','nyo','hiragana','youon',62],['ひゃ','hya','hiragana','youon',63],['ひゅ','hyu','hiragana','youon',64],['ひょ','hyo','hiragana','youon',65],
  ['みゃ','mya','hiragana','youon',66],['みゅ','myu','hiragana','youon',67],['みょ','myo','hiragana','youon',68],['りゃ','rya','hiragana','youon',69],['りゅ','ryu','hiragana','youon',70],
  ['りょ','ryo','hiragana','youon',71],['ぎゃ','gya','hiragana','youon',72],['ぎゅ','gyu','hiragana','youon',73],['ぎょ','gyo','hiragana','youon',74],['じゃ','ja','hiragana','youon',75],
  ['じゅ','ju','hiragana','youon',76],['じょ','jo','hiragana','youon',77],['びゃ','bya','hiragana','youon',78],['びゅ','byu','hiragana','youon',79],['びょ','byo','hiragana','youon',80],
  ['ぴゃ','pya','hiragana','youon',81],['ぴゅ','pyu','hiragana','youon',82],['ぴょ','pyo','hiragana','youon',83],
  ['キャ','kya','katakana','youon',84],['キュ','kyu','katakana','youon',85],['キョ','kyo','katakana','youon',86],['シャ','sha','katakana','youon',87],['シュ','shu','katakana','youon',88],
  ['ショ','sho','katakana','youon',89],['チャ','cha','katakana','youon',90],['チュ','chu','katakana','youon',91],['チョ','cho','katakana','youon',92],['ニャ','nya','katakana','youon',93],
  ['ニュ','nyu','katakana','youon',94],['ニョ','nyo','katakana','youon',95],['ヒャ','hya','katakana','youon',96],['ヒュ','hyu','katakana','youon',97],['ヒョ','hyo','katakana','youon',98],
  ['ミャ','mya','katakana','youon',99],['ミュ','myu','katakana','youon',100],['ミョ','myo','katakana','youon',101],['リャ','rya','katakana','youon',102],['リュ','ryu','katakana','youon',103],
  ['リョ','ryo','katakana','youon',104],['ギャ','gya','katakana','youon',105],['ギュ','gyu','katakana','youon',106],['ギョ','gyo','katakana','youon',107],['ジャ','ja','katakana','youon',108],
  ['ジュ','ju','katakana','youon',109],['ジョ','jo','katakana','youon',110],['ビャ','bya','katakana','youon',111],['ビュ','byu','katakana','youon',112],['ビョ','byo','katakana','youon',113],
  ['ピャ','pya','katakana','youon',114],['ピュ','pyu','katakana','youon',115],['ピョ','pyo','katakana','youon',116]
];

(async () => {
  try {
    await models.Kana.destroy({ where: {} });
    console.log('✓ Cleared existing');
    
    for (let i = 0; i < kana.length; i++) {
      const [ch, r, t, cat, o] = kana[i];
      try {
        await models.Kana.create({
          type: t,
          character: ch,
          romanization: r,
          category: cat,
          order_index: o
        });
      } catch(e) {
        console.error(`❌ Error at index ${i} (${t} ${ch}):`, e.message);
        throw e;
      }
    }
    
    const cnt = await models.Kana.count();
    console.log('✅ Successfully imported ' + cnt + ' kana records');
    process.exit(0);
  } catch(err) {
    console.error('❌ Error:', err.message);
    if (err.errors) console.error('Details:', err.errors);
    process.exit(1);
  }
})();
