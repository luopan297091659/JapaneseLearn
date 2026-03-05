class AppConfig {
  static const String baseUrl    = 'https://139.196.44.6:8002/api/v1';
  static const String serverRoot = 'https://139.196.44.6:8002'; // 不含 /api/v1，用于拼接静态资源 URL
  static const Duration connectTimeout = Duration(seconds: 6);
  static const Duration receiveTimeout = Duration(seconds: 12);

  // Supported JLPT levels
  static const List<String> jlptLevels = ['N5', 'N4', 'N3', 'N2', 'N1'];

  // Daily study goal options (minutes)
  static const List<int> dailyGoalOptions = [5, 10, 15, 20, 30, 60];

  static const int srsSessionSize = 20;
  static const int quizDefaultCount = 10;

  // Cache TTL
  static const Duration cacheTtlShort  = Duration(minutes: 2);   // 用户信息、SRS stats
  static const Duration cacheTtlMedium = Duration(minutes: 10);  // 词汇列表、语法列表
  static const Duration cacheTtlLong   = Duration(minutes: 30);  // 新闻、听力
}
