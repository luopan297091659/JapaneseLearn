/// Japanese verb conjugation engine
/// Supports 五段 (godan), 一段 (ichidan), and irregular verbs
class VerbConjugation {
  final String form;     // e.g. 'ます形', 'て形'
  final String value;    // conjugated form
  final String? reading; // reading if different
  const VerbConjugation({required this.form, required this.value, this.reading});
}

/// Determine verb group and generate conjugations from dictionary form
List<VerbConjugation> conjugateVerb(String word, String reading) {
  final w = word.trim();
  final r = reading.trim();
  if (w.isEmpty) return [];

  // Irregular verbs
  if (_isIrregularSuru(w)) return _conjugateSuru(w, r);
  if (_isIrregularKuru(w)) return _conjugateKuru(w, r);

  // Ichidan (一段) verbs: end in る, stem ends in い段 or え段
  if (_isIchidan(w, r)) return _conjugateIchidan(w, r);

  // Godan (五段) verbs
  return _conjugateGodan(w, r);
}

/// Check if word is a する verb
bool _isIrregularSuru(String w) {
  return w == 'する' || w.endsWith('する');
}

/// Check if word is a くる verb
bool _isIrregularKuru(String w) {
  return w == '来る' || w == 'くる' || w == 'kuru' ||
         (w.endsWith('来る') && w.length <= 4) ||
         (w.endsWith('くる') && w.length <= 4);
}

/// Check if verb is ichidan (一段)
bool _isIchidan(String w, String r) {
  if (!w.endsWith('る')) return false;
  // Known godan verbs that look like ichidan
  const godanExceptions = {
    '帰る', '切る', '知る', '入る', '走る', '要る', '参る', '散る',
    '滑る', '握る', '練る', '蹴る', '減る', '照る', '焦る', '限る',
    '嘲る', '覆る', '遮る', '罵る', '捻る', '翻る', '滅入る',
    'しゃべる', 'かえる', 'きる', 'しる', 'はいる', 'はしる', 'いる',
  };
  if (godanExceptions.contains(w)) return false;
  // Use reading to check the vowel before る
  final rd = r.isNotEmpty ? r : w;
  if (rd.length < 2) return false;
  final beforeRu = rd[rd.length - 2];
  const iDan = 'いきしちにひみりぎじぢびぴ';
  const eDan = 'えけせてねへめれげぜでべぺ';
  return iDan.contains(beforeRu) || eDan.contains(beforeRu);
}

// ── Godan conjugation ────────────────────────────────────────────────────

const _godanMap = {
  'う': ('い', 'わ', 'え', 'お', 'っ'),
  'く': ('き', 'か', 'け', 'こ', 'い'),
  'ぐ': ('ぎ', 'が', 'げ', 'ご', 'い'),
  'す': ('し', 'さ', 'せ', 'そ', 'し'),
  'つ': ('ち', 'た', 'て', 'と', 'っ'),
  'ぬ': ('に', 'な', 'ね', 'の', 'ん'),
  'ぶ': ('び', 'ば', 'べ', 'ぼ', 'ん'),
  'む': ('み', 'ま', 'め', 'も', 'ん'),
  'る': ('り', 'ら', 'れ', 'ろ', 'っ'),
};

// て形 suffix for godan
const _godanTeMap = {
  'う': 'って', 'く': 'いて', 'ぐ': 'いで', 'す': 'して',
  'つ': 'って', 'ぬ': 'んで', 'ぶ': 'んで', 'む': 'んで', 'る': 'って',
};

// た形 suffix for godan
const _godanTaMap = {
  'う': 'った', 'く': 'いた', 'ぐ': 'いだ', 'す': 'した',
  'つ': 'った', 'ぬ': 'んだ', 'ぶ': 'んだ', 'む': 'んだ', 'る': 'った',
};

List<VerbConjugation> _conjugateGodan(String w, String r) {
  final ending = w[w.length - 1];
  final rd = r.isNotEmpty ? r : w;
  final rEnding = rd[rd.length - 1];

  final m = _godanMap[rEnding];
  if (m == null) return [];

  final (iForm, aForm, eForm, _, teReplace) = m;
  final stem = w.substring(0, w.length - 1);
  final rStem = rd.substring(0, rd.length - 1);

  // Special case: 行く → 行って (not 行いて)
  final isIku = w == '行く' || (w.endsWith('行く'));
  final te = isIku ? '$stemって' : '$stem${_godanTeMap[rEnding]}';
  final ta = isIku ? '$stemった' : '$stem${_godanTaMap[rEnding]}';
  final teR = isIku ? '$rStemって' : '$rStem${_godanTeMap[rEnding]}';
  final taR = isIku ? '$rStemった' : '$rStem${_godanTaMap[rEnding]}';

  return [
    VerbConjugation(form: 'ます形', value: '$stem${_forKanji(w, ending, iForm)}ます', reading: '$rStem$iFormます'),
    VerbConjugation(form: 'ない形', value: '$stem${_forKanji(w, ending, aForm)}ない', reading: '$rStem$aFormない'),
    VerbConjugation(form: 'て形', value: te, reading: teR),
    VerbConjugation(form: 'た形', value: ta, reading: taR),
    VerbConjugation(form: '可能形', value: '$stem${_forKanji(w, ending, eForm)}る', reading: '$rStem$eFormる'),
    VerbConjugation(form: '意向形', value: '$stem${_forKanji(w, ending, m.$4)}う', reading: '$rStem${m.$4}う'),
    VerbConjugation(form: '命令形', value: '$stem${_forKanji(w, ending, eForm)}', reading: '$rStem$eForm'),
    VerbConjugation(form: '受身形', value: '$stem${_forKanji(w, ending, aForm)}れる', reading: '$rStem$aFormれる'),
  ];
}

/// For kanji verbs, the conjugation suffix changes only the kana ending
String _forKanji(String w, String ending, String newEnding) {
  // If the word ends with a kanji+kana pattern, just replace the kana
  return newEnding;
}

// ── Ichidan conjugation ──────────────────────────────────────────────────

List<VerbConjugation> _conjugateIchidan(String w, String r) {
  final stem = w.substring(0, w.length - 1);
  final rStem = (r.isNotEmpty ? r : w).substring(0, (r.isNotEmpty ? r : w).length - 1);

  return [
    VerbConjugation(form: 'ます形', value: '$stemます', reading: '$rStemます'),
    VerbConjugation(form: 'ない形', value: '$stemない', reading: '$rStemない'),
    VerbConjugation(form: 'て形', value: '$stemて', reading: '$rStemて'),
    VerbConjugation(form: 'た形', value: '$stemた', reading: '$rStemた'),
    VerbConjugation(form: '可能形', value: '$stemられる', reading: '$rStemられる'),
    VerbConjugation(form: '意向形', value: '$stemよう', reading: '$rStemよう'),
    VerbConjugation(form: '命令形', value: '$stemろ', reading: '$rStemろ'),
    VerbConjugation(form: '受身形', value: '$stemられる', reading: '$rStemられる'),
  ];
}

// ── Irregular: する ──────────────────────────────────────────────────────

List<VerbConjugation> _conjugateSuru(String w, String r) {
  final prefix = w.endsWith('する') ? w.substring(0, w.length - 2) : '';
  final rPrefix = r.isNotEmpty && r.endsWith('する') ? r.substring(0, r.length - 2) : prefix;

  return [
    VerbConjugation(form: 'ます形', value: '$prefixします', reading: '$rPrefixします'),
    VerbConjugation(form: 'ない形', value: '$prefixしない', reading: '$rPrefixしない'),
    VerbConjugation(form: 'て形', value: '$prefixして', reading: '$rPrefixして'),
    VerbConjugation(form: 'た形', value: '$prefixした', reading: '$rPrefixした'),
    VerbConjugation(form: '可能形', value: '$prefixできる', reading: '$rPrefixできる'),
    VerbConjugation(form: '意向形', value: '$prefixしよう', reading: '$rPrefixしよう'),
    VerbConjugation(form: '命令形', value: '$prefixしろ', reading: '$rPrefixしろ'),
    VerbConjugation(form: '受身形', value: '$prefixされる', reading: '$rPrefixされる'),
  ];
}

// ── Irregular: 来る ──────────────────────────────────────────────────────

List<VerbConjugation> _conjugateKuru(String w, String r) {
  final prefix = w.endsWith('来る') ? w.substring(0, w.length - 2) : 
                 w.endsWith('くる') ? w.substring(0, w.length - 2) : '';

  return [
    VerbConjugation(form: 'ます形', value: '$prefix来ます', reading: '$prefixきます'),
    VerbConjugation(form: 'ない形', value: '$prefix来ない', reading: '$prefixこない'),
    VerbConjugation(form: 'て形', value: '$prefix来て', reading: '$prefixきて'),
    VerbConjugation(form: 'た形', value: '$prefix来た', reading: '$prefixきた'),
    VerbConjugation(form: '可能形', value: '$prefix来られる', reading: '$prefixこられる'),
    VerbConjugation(form: '意向形', value: '$prefix来よう', reading: '$prefixこよう'),
    VerbConjugation(form: '命令形', value: '$prefix来い', reading: '$prefixこい'),
    VerbConjugation(form: '受身形', value: '$prefix来られる', reading: '$prefixこられる'),
  ];
}
