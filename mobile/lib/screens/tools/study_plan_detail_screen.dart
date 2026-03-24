import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';

class StudyPlanDetailScreen extends ConsumerStatefulWidget {
  final String planId;
  
  const StudyPlanDetailScreen({super.key, required this.planId});

  @override
  ConsumerState<StudyPlanDetailScreen> createState() => _StudyPlanDetailScreenState();
}

class _StudyPlanDetailScreenState extends ConsumerState<StudyPlanDetailScreen> {
  late Map<String, dynamic> _plan;
  late Map<String, dynamic> _progress;
  bool _isLoading = true;
  String? _error;
  String _selectedStage = 'learning'; // learning, review, mastered

  @override
  void initState() {
    super.initState();
    _loadPlanAndProgress();
  }

  Future<void> _loadPlanAndProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final plansJson = prefs.getString('study_plans_v1') ?? '[]';
      final plans = (jsonDecode(plansJson) as List)
          .cast<Map<String, dynamic>>();
      
      final plan = plans.firstWhere((p) => p['id'].toString() == widget.planId,
          orElse: () => {});
      
      if (plan.isEmpty) {
        setState(() {
          _error = '学习计划不存在';
          _isLoading = false;
        });
        return;
      }
      
      _plan = plan;
      
      // Load progress from backend API
      final apiService = ApiService();
      
      final level = _plan['vocabularyLevel'] ?? _plan['grammarLevel'] ?? 'N5';
      final type = _determinePlanType(_plan);
      
      try {
        final response = await apiService.dio.get(
          '/progress/study-plan-progress',
          queryParameters: {'level': level, 'type': type},
        );
        
        if (response.statusCode == 200) {
          final data = response.data;
          // Support both wrapped { success: true, data: {...} } and direct response
          if (data is Map && data['success'] == true && data['data'] != null) {
            _progress = data['data'] as Map<String, dynamic>;
          } else if (data is Map && data['progress'] != null) {
            _progress = Map<String, dynamic>.from(data);
          } else {
            _progress = _emptyProgress();
          }
        } else {
          _progress = _emptyProgress();
        }
      } catch (e) {
        // If API call fails, show zeros
        debugPrint('StudyPlanDetail API call failed: $e');
        _progress = _emptyProgress();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _emptyProgress() => {
    'total': 0,
    'progress': {'new': 0, 'learning': 0, 'review': 0, 'mastered': 0},
    'overdue_count': 0,
  };

  String _determinePlanType(Map<String, dynamic> plan) {
    if (plan['includeVocabulary'] == true) return 'vocabulary';
    if (plan['includeGrammar'] == true) return 'grammar';
    if (plan['includeAnki'] == true) return 'anki';
    return 'vocabulary';
  }

  String _typeText(String type) {
    switch (type) {
      case 'grammar':
        return '语法';
      case 'anki':
        return 'Anki';
      default:
        return '单词';
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'in_progress':
        return '进行中';
      case 'ended':
        return '已结束';
      default:
        return '未开始';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'in_progress':
        return Colors.blue;
      case 'ended':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _targetText(Map<String, dynamic> plan, String type) {
    if (type == 'vocabulary') {
      return '等级 ${plan['vocabularyLevel'] ?? 'N5'}';
    }
    if (type == 'grammar') {
      return '等级 ${plan['grammarLevel'] ?? 'N5'}';
    }
    final deckRoot = (plan['ankiDeckRoot'] ?? plan['ankiDeck'] ?? '').toString();
    final deck = deckRoot == '__all__' ? '全部词牌' : (deckRoot.isEmpty ? '词牌' : deckRoot);
    return '词牌 $deck';
  }

  void _goToStudy(String stage) {
    final type = _determinePlanType(_plan);
    final planId = _plan['id']?.toString() ?? widget.planId;
    final deckRoot = (_plan['ankiDeckRoot'] ?? _plan['ankiDeck'] ?? '__all__').toString();

    if (stage == 'review' || stage == 'overdue') {
      context.push('/srs-review');
      return;
    }
    
    if (type == 'vocabulary' || type == 'grammar') {
      context.push('/study-plan/$planId/run?stage=$stage');
      return;
    }

    if (type == 'anki') {
      final localStage = (stage == 'new') ? 0 : (stage == 'mastered' ? 2 : 1);
      context.push('/local-vocab?deck=${Uri.encodeComponent(deckRoot)}&stage=$localStage&planId=$planId');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('学习计划')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('学习计划')),
        body: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    final plan = _plan;
    final progress = _progress;
    final total = progress['total'] as int? ?? 0;
    final progressMap = progress['progress'] as Map<String, dynamic>? ?? {};
    final apiNewCount = progressMap['new'] as int? ?? 0;
    final learningCount = progressMap['learning'] as int? ?? 0;
    final reviewCount = progressMap['review'] as int? ?? 0;
    final masteredCount = progressMap['mastered'] as int? ?? 0;

    final planName = plan['name'] as String? ?? 'Unknown';
    final planType = _determinePlanType(plan);
    final status = (plan['status'] ?? 'not_started').toString();
    final isEnded = status == 'ended';
    final dailyTarget = (plan['dailyTarget'] as int?) ?? 20;
    final estimatedDays = (plan['estimatedDays'] as int?) ?? 0;
    final importedCount = (plan['importedCount'] as int?) ?? 0;
    final totalCount = total > 0 ? total : importedCount;
    final newCount = (apiNewCount > 0 || total > 0) ? apiNewCount : importedCount;
    final description = plan['description'] as String? ?? '';

    // Dynamic estimated end date based on remaining cards
    final remainingCards = newCount + learningCount + reviewCount;
    final dynamicDaysLeft = dailyTarget > 0 ? (remainingCards / dailyTarget).ceil() : 0;
    final estimatedEndDate = DateTime.now().add(Duration(days: dynamicDaysLeft));

    return Scaffold(
      appBar: AppBar(
        title: const Text('学习计划详情'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Header
            Container(
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          planName,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _statusText(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '学习类型：${_typeText(planType)} · ${_targetText(plan, planType)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    '每日学习：$dailyTarget · 预计周期：${estimatedDays == 0 ? '- ' : '$estimatedDays 天'} · 总卡片：$importedCount 张',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '预计完成日期：${dynamicDaysLeft > 0 ? '${estimatedEndDate.year}-${estimatedEndDate.month.toString().padLeft(2, '0')}-${estimatedEndDate.day.toString().padLeft(2, '0')}（剩余 $dynamicDaysLeft 天）' : '已全部掌握 🎉'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: dynamicDaysLeft > 0 ? Colors.orange.shade700 : Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProgressBar(
                    label: '总卡片数',
                    current: learningCount + reviewCount + masteredCount,
                    total: totalCount,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatChip('新卡片', newCount, Colors.grey, null),
                      const SizedBox(width: 8),
                      _buildStatChip('学习中', learningCount, Colors.orange, 'learning'),
                      const SizedBox(width: 8),
                      _buildStatChip('待复习', reviewCount, Colors.blue, 'review'),
                      const SizedBox(width: 8),
                      _buildStatChip('已掌握', masteredCount, Colors.green, 'mastered'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Builder(builder: (_) {
                final int stageCount;
                final String buttonLabel;
                final String stage;
                final IconData buttonIcon;

                switch (_selectedStage) {
                  case 'review':
                    stageCount = reviewCount;
                    buttonLabel = '复习学习中（$reviewCount 张）';
                    stage = 'review';
                    buttonIcon = Icons.replay_rounded;
                    break;
                  case 'mastered':
                    stageCount = masteredCount;
                    buttonLabel = '待复习（$masteredCount 张）';
                    stage = 'mastered';
                    buttonIcon = Icons.check_circle_outline;
                    break;
                  default: // learning
                    final todayCount = (newCount + learningCount) > 0 ? dailyTarget : 0;
                    stageCount = todayCount;
                    buttonLabel = '继续学习（每日 $dailyTarget 张）';
                    stage = 'new';
                    buttonIcon = Icons.play_arrow_rounded;
                }

                return SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isEnded || stageCount == 0 ? null : () => _goToStudy(stage),
                    icon: Icon(buttonIcon),
                    label: Text(buttonLabel),
                  ),
                );
              }),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar({
    required String label,
    required int current,
    required int total,
    required Color color,
  }) {
    final percentage = total > 0 ? current / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              '$current / $total',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 8,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, int count, Color color, String? stageKey) {
    final isSelected = stageKey != null && _selectedStage == stageKey;
    return Expanded(
      child: GestureDetector(
        onTap: stageKey != null ? () => setState(() => _selectedStage = stageKey) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: color, width: 2) : null,
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

}
