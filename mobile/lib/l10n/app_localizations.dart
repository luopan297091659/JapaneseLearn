import 'package:flutter/material.dart';

/// 使用方式: S.of(context).appTitle
class S {
  final Locale locale;
  const S(this.locale);

  static S of(BuildContext context) {
    return Localizations.of<S>(context, S) ?? const S(Locale('zh'));
  }

  static const delegate = _SDelegate();
  static const supportedLocales = [Locale('zh'), Locale('en')];

  bool get isZh => locale.languageCode == 'zh';

  // ── App ─────────────────────────────────────────────────────────────────
  String get appTitle    => isZh ? '言旅 Kotabi' : 'Kotabi';
  String get appSubtitle => isZh ? '每天进步一点点' : 'Improve every day';

  // ── Navigation ───────────────────────────────────────────────────────────
  String get navHome      => isZh ? '首页' : 'Home';
  String get navVocab     => isZh ? '单词' : 'Vocab';
  String get navGrammar   => isZh ? '文法' : 'Grammar';
  String get navListening => isZh ? '听力' : 'Listen';
  String get navNews      => isZh ? '新闻' : 'News';

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get login               => isZh ? '登录' : 'Login';
  String get register            => isZh ? '注册' : 'Register';
  String get logout              => isZh ? '退出登录' : 'Logout';
  String get email               => isZh ? '邮箱' : 'Email';
  String get password            => isZh ? '密码' : 'Password';
  String get username            => isZh ? '用户名' : 'Username';
  String get confirmPwd          => isZh ? '确认密码' : 'Confirm Password';
  String get createAccount       => isZh ? '创建账户' : 'Create Account';
  String get noAccount           => isZh ? '还没有账户？' : "Don't have an account?";
  String get registerNow         => isZh ? '立即注册' : 'Register now';
  String get hasAccount          => isZh ? '已有账户？' : 'Already have an account?';
  String get goLogin             => isZh ? '去登录' : 'Login';
  String get loginSuccess        => isZh ? '登录成功' : 'Login successful';
  String get loginError          => isZh ? '邮箱或密码不正确' : 'Incorrect email or password';
  String get registerError       => isZh ? '注册失败，请检查信息后重试' : 'Registration failed, please check your information';
  String get pleaseEnterEmail    => isZh ? '请输入邮箱' : 'Please enter your email';
  String get pleaseEnterPassword => isZh ? '请输入密码' : 'Please enter your password';
  String get usernameMinLength   => isZh ? '用户名至少3个字符' : 'Username must be at least 3 characters';
  String get passwordMinLength   => isZh ? '密码（至少8位）' : 'Password (min 8 chars)';
  String get passwordMinLengthError => isZh ? '密码至少8个字符' : 'Password must be at least 8 characters';
  String get jlptLevel           => isZh ? '当前日语水平' : 'Current JLPT Level';
  String get n5label             => isZh ? '初级入门' : 'Beginner';
  String get n4label             => isZh ? '初级' : 'Elementary';
  String get n3label             => isZh ? '中级' : 'Intermediate';
  String get n2label             => isZh ? '中高级' : 'Upper-Intermediate';
  String get n1label             => isZh ? '高级' : 'Advanced';

  // ── Common ───────────────────────────────────────────────────────────────
  String get save      => isZh ? '保存' : 'Save';
  String get cancel    => isZh ? '取消' : 'Cancel';
  String get confirm   => isZh ? '确认' : 'Confirm';
  String get retry     => isZh ? '重试' : 'Retry';
  String get loading   => isZh ? '加载中...' : 'Loading...';
  String get noData    => isZh ? '暂无数据' : 'No data';
  String get error     => isZh ? '加载失败' : 'Load failed';
  String get search    => isZh ? '搜索' : 'Search';
  String get copied    => isZh ? '已复制' : 'Copied';
  String get addToSrs  => isZh ? '加入SRS' : 'Add to SRS';
  String get addedSrs  => isZh ? '已加入SRS' : 'Added to SRS';
  String get level     => isZh ? '等级' : 'Level';
  String get back      => isZh ? '返回' : 'Back';

  // ── Home ─────────────────────────────────────────────────────────────────
  String get homeGreeting  => isZh ? '今日も頑張ろう！' : "Let's study today!";
  String get homeStudyStreak => isZh ? '连续学习' : 'Streak';
  String get homeSubVocab    => isZh ? '词汇积累' : 'Vocabulary';
  String get homeSubGrammar  => isZh ? '文法学习' : 'Grammar';
  String get homeSubListen   => isZh ? '听力练习' : 'Listening';
  String get homeSubQuiz     => isZh ? '单词随机测验' : 'Quiz';
  String get homeSubNews     => isZh ? '日语新闻' : 'JP News';
  String get homeSubSrs      => isZh ? '间隔复习' : 'SRS Review';
  String get homeSubDict     => isZh ? '日语查词' : 'Dictionary';
  String get todayGoal       => isZh ? '今日目标' : "Today's Goal";
  String get todayComplete   => isZh ? '今日已完成' : 'Completed today';
  String get dueCards        => isZh ? '待复习卡片' : 'Cards due';
  String get startReview     => isZh ? '开始复习' : 'Start Review';

  // ── Vocabulary ───────────────────────────────────────────────────────────
  String get vocabulary       => isZh ? '单词库' : 'Vocabulary';
  String get vocabDetail      => isZh ? '单词详情' : 'Word Detail';
  String get reading          => isZh ? '读音' : 'Reading';
  String get meaning          => isZh ? '释义' : 'Meaning';
  String get exampleSentence  => isZh ? '例句' : 'Example';
  String get pronunciation    => isZh ? '发音' : 'Pronunciation';
  String get searchHint       => isZh ? '搜索单词、读音、释义...' : 'Search word, reading, meaning...';
  String get allLevels        => isZh ? '全部等级' : 'All Levels';

  // ── Grammar ──────────────────────────────────────────────────────────────
  String get grammar       => isZh ? '文法' : 'Grammar';
  String get grammarDetail => isZh ? '文法详情' : 'Grammar Detail';
  String get pattern       => isZh ? '句型' : 'Pattern';
  String get explanation   => isZh ? '说明' : 'Explanation';
  String get usageNotes    => isZh ? '用法注意' : 'Usage Notes';
  String get examples      => isZh ? '例句' : 'Examples';

  // ── Listening ────────────────────────────────────────────────────────────
  String get listening       => isZh ? '听力' : 'Listening';
  String get transcript      => isZh ? '原文' : 'Transcript';
  String get showTranscript  => isZh ? '显示原文' : 'Show Transcript';
  String get hideTranscript  => isZh ? '隐藏原文' : 'Hide Transcript';
  String get noAudio         => isZh ? '暂无音频' : 'No audio';

  // ── Quiz ─────────────────────────────────────────────────────────────────
  String get quiz          => isZh ? '测验' : 'Quiz';
  String get quizResult    => isZh ? '测验结果' : 'Quiz Result';
  String get correct       => isZh ? '正确' : 'Correct';
  String get wrong         => isZh ? '错误' : 'Wrong';
  String get score         => isZh ? '得分' : 'Score';
  String get showAnswer    => isZh ? '显示答案' : 'Show Answer';
  String get nextQuestion  => isZh ? '下一题' : 'Next';
  String get submit        => isZh ? '提交' : 'Submit';
  String get quizComplete  => isZh ? '测验完成' : 'Quiz Complete';
  String get retryQuiz     => isZh ? '重新测验' : 'Retry';

  // ── SRS ──────────────────────────────────────────────────────────────────
  String get srsReview    => isZh ? 'SRS 间隔复习' : 'SRS Review';
  String get srsNoCards   => isZh ? '今日无需复习 🎉' : 'No cards due today 🎉';
  String get srsDone      => isZh ? '复习完成！' : 'Review Complete!';
  String get srsRateHard  => isZh ? '困难' : 'Hard';
  String get srsRateGood  => isZh ? '记得' : 'Good';
  String get srsRateEasy  => isZh ? '很熟' : 'Easy';
  String get srsRateFail  => isZh ? '不会' : 'Again';

  // ── News ─────────────────────────────────────────────────────────────────
  String get news         => isZh ? '日语新闻' : 'JP News';
  String get newsDetail   => isZh ? '新闻详情' : 'News Detail';
  String get showRuby     => isZh ? '显示读音' : 'Show Furigana';
  String get hideRuby     => isZh ? '隐藏读音' : 'Hide Furigana';

  // ── Dictionary ───────────────────────────────────────────────────────────
  String get dictionary         => isZh ? '辞书' : 'Dictionary';
  String get dictSearchHint     => isZh ? '输入日语、中文或罗马字...' : 'Japanese, English, or romaji...';
  String get dictSearch         => isZh ? '検索' : 'Search';
  String get dictRecentSearch   => isZh ? '最近搜索' : 'Recent';
  String get dictClearHistory   => isZh ? '清空' : 'Clear';
  String get dictTips           => isZh ? '搜索技巧' : 'Search Tips';
  String get dictNoResult       => isZh ? '未找到相关词条' : 'No results found';
  String get dictCommon         => isZh ? '常用' : 'Common';
  String get dictExpand         => isZh ? '展开更多' : 'Show more';
  String get dictCollapse       => isZh ? '收起' : 'Collapse';
  String get dictOtherForms     => isZh ? '其他形式' : 'Other forms';
  String get viaJisho           => isZh ? 'via Jisho ↗' : 'via Jisho ↗';

  // ── Profile ──────────────────────────────────────────────────────────────
  String get profile         => isZh ? '个人中心' : 'Profile';
  String get settings        => isZh ? '设置' : 'Settings';
  String get studyGoal       => isZh ? '学习目标' : 'Study Goal';
  String get dailyGoalFmt    => isZh ? '每日 %d 分钟' : '%d min/day';
  String get notifications   => isZh ? '学习提醒' : 'Notifications';
  String get changePassword  => isZh ? '修改密码' : 'Change Password';
  String get language        => isZh ? '语言' : 'Language';
  String get theme           => isZh ? '外观' : 'Appearance';
  String get langZh          => isZh ? '简体中文' : 'Simplified Chinese';
  String get langEn          => isZh ? 'English' : 'English';
  String get streakDays      => isZh ? '连续天数' : 'Streak Days';
  String get totalMinutes    => isZh ? '总学习时长' : 'Total Minutes';
  String get avgScore        => isZh ? '平均分' : 'Avg Score';
  String get srsCards        => isZh ? 'SRS 记忆卡片' : 'SRS Cards';
  String get total           => isZh ? '总卡片' : 'Total';
  String get graduated       => isZh ? '已毕业' : 'Graduated';
  String get inProgress      => isZh ? '学习中' : 'In Progress';
  String get day             => isZh ? '天' : 'd';
  String get minute          => isZh ? '分钟' : 'min';
  String get reset           => isZh ? '重新开始' : 'Reset';
  String get meaningZh       => isZh ? '中文释义' : 'Chinese Meaning';
  String get meaningEn       => isZh ? '英文释义' : 'English Meaning';
  String get partOfSpeech    => isZh ? '词性' : 'Part of Speech';
  String get word            => isZh ? '单词' : 'Word';

  // ── Anki Import ──────────────────────────────────────────────────────────
  String get ankiImport         => isZh ? '导入 Anki 词库' : 'Import Anki Deck';
  String get ankiImportSubtitle => isZh ? '从 .apkg / .txt / .csv 文件导入词汇' : 'Import from .apkg / .txt / .csv';
  String get ankiImportHint     => isZh ? '将您的 Anki 词库导入到本地词汇表，支持 Anki 标准导出格式' : 'Import your Anki vocabulary cards into the local word list';
  String get apkgDesc           => isZh ? 'Anki 牌组导出包（推荐）' : 'Anki deck export package (recommended)';
  String get tsvDesc            => isZh ? 'Anki 文本导出（制表符分隔）' : 'Anki text export (tab-separated)';
  String get csvDesc            => isZh ? 'CSV 格式文件' : 'CSV format file';
  String get selectFile         => isZh ? '选择 Anki 文件' : 'Select Anki File';
  String get fieldMapping       => isZh ? '字段映射' : 'Field Mapping';
  String get fieldMappingHint   => isZh ? '将 Anki 字段对应到词汇字段（* 表示必填）' : 'Map Anki fields to vocabulary fields (* required)';
  String get notMapped          => isZh ? '— 不导入 —' : '— Skip —';
  String get importSettings     => isZh ? '导入设置' : 'Import Settings';
  String get deckName           => isZh ? '牌组名称' : 'Deck Name';
  String get dataPreview        => isZh ? '数据预览（前5条）' : 'Data Preview (first 5)';
  String get startImport        => isZh ? '开始导入' : 'Start Import';
  String get importing          => isZh ? '正在导入，请稍候...' : 'Importing, please wait...';
  String get importDone         => isZh ? '导入完成！' : 'Import Complete!';
  String get importFailed       => isZh ? '导入失败' : 'Import Failed';
  String get importMore         => isZh ? '继续导入' : 'Import More';
  String get viewVocabulary     => isZh ? '查看词汇' : 'View Vocabulary';
  String get importedCount      => isZh ? '成功导入' : 'Imported';
  String get skippedCount       => isZh ? '跳过（重复）' : 'Skipped (duplicate)';
  String get cards              => isZh ? '张卡片' : 'cards';
  String get parsedLocally      => isZh ? '已在本地解析' : 'Parsed locally';
  String get parsing            => isZh ? '正在解析文件...' : 'Parsing file...';
  // 同步相关
  String get savedLocally       => isZh ? '已保存到本地' : 'Saved locally';
  String get syncedToServer     => isZh ? '已同步到服务器' : 'Synced to server';
  String get pendingSync        => isZh ? '等待同步' : 'Pending sync';
  String get syncNow            => isZh ? '立即同步' : 'Sync Now';
  String get syncing            => isZh ? '同步中...' : 'Syncing...';
  String get syncSuccess        => isZh ? '同步成功' : 'Sync successful';
  String get syncFailed         => isZh ? '同步失败，请检查网络后重试' : 'Sync failed, retry when online';
  String get viewLocalVocab     => isZh ? '查看本地词汇' : 'View Local Vocab';
  String get localVocab         => isZh ? '本地词汇（Anki）' : 'Local Vocab (Anki)';
  String get localOnly          => isZh ? '仅本地' : 'Local only';
  String get pendingCards       => isZh ? '待同步卡片' : 'Pending cards';
  String get allSynced          => isZh ? '全部已同步' : 'All synced';
}

// ── Localizations Delegate ───────────────────────────────────────────────────
class _SDelegate extends LocalizationsDelegate<S> {
  const _SDelegate();

  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);

  @override
  Future<S> load(Locale locale) async => S(locale);

  @override
  bool shouldReload(_SDelegate old) => false;
}
