import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../services/sync_service.dart';
import '../../services/payment_service.dart';
import '../../config/app_config.dart';
import '../common/legal_webview_page.dart';

/// 会员功能对比页面 — 展示免费用户与会员用户的功能差异
class MembershipComparisonPage extends StatefulWidget {
  final bool isMember;
  const MembershipComparisonPage({super.key, required this.isMember});

  @override
  State<MembershipComparisonPage> createState() => _MembershipComparisonPageState();
}

class _MembershipComparisonPageState extends State<MembershipComparisonPage> {
  List<Map<String, dynamic>> _tiers = [];
  bool _loading = true;
  bool _isMember = false;
  bool _isTrial = false;
  bool _trialActivated = false;
  int? _daysLeft;
  bool _trialEnabled = false;
  int _trialDays = 3;
  String _trialDesc = '';
  bool _activating = false;
  List<Map<String, dynamic>> _plans = [];
  bool _purchasing = false;
  String _purchasingPlanId = '';
  int _selectedPlanIndex = -1; // 选中的套餐索引（默认选中推荐/年度）
  String? _membershipPlan; // 当前用户会员类型：monthly/yearly/lifetime/trial/null
  // 会员等级：年度 > 月度；终身独立可留。体验不计入等级。
  static const Map<String, int> _planRank = {
    'monthly': 1,
    'yearly': 2,
    'lifetime': 3,
  };
  int get _userPlanRank {
    if (!_isMember || _isTrial) return 0;
    return _planRank[_membershipPlan] ?? 0;
  }
  bool _isPlanDisabled(Map<String, dynamic> plan) {
    if (_isTrial || !_isMember) return false;
    final r = _planRank[plan['id']] ?? 0;
    return r > 0 && _userPlanRank > 0 && r <= _userPlanRank;
  }

  @override
  void initState() {
    super.initState();
    _isMember = widget.isMember;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        syncService.fetchFeatureTiers(force: true),
        apiService.getMe(force: true),
        apiService.getTrialConfig(),
        apiService.dio.get('/sync/membership-plans'),
      ]);
      final tiers = results[0] as List<Map<String, dynamic>>;
      final user = results[1] as dynamic;
      final trialCfg = results[2] as Map<String, dynamic>;
      final plansRes = results[3];
      final plansData = (plansRes as dynamic).data;
      final fetchedPlans = (plansData is Map && plansData['plans'] != null)
          ? List<Map<String, dynamic>>.from(plansData['plans'])
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _tiers = tiers;
          _plans = fetchedPlans;
          _isMember = user.isMember;
          _isTrial = user.isTrial;
          _trialActivated = user.trialActivated;
          _daysLeft = user.membershipDaysLeft;
          _membershipPlan = user.membershipPlan;
          _trialEnabled = trialCfg['enabled'] == true;
          _trialDays = trialCfg['days'] as int? ?? 3;
          _trialDesc = trialCfg['description'] as String? ?? '';
        });
      }
      // iOS: 初始化 IAP，确保 Apple 内购产品已加载
      if (Platform.isIOS) {
        await _initIAP();
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (Platform.isIOS) await _initIAP();
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatCnyPrice(num price) {
    if (price == 0) return '免费';
    if (price == price.toInt()) {
      return '￥${price.toInt()}';
    }
    return '￥${price.toStringAsFixed(2)}';
  }

  String _getPlanDisplayPrice(Map<String, dynamic> plan) {
    final price = plan['price'];
    if (price is num) {
      return _formatCnyPrice(price);
    }
    return '';
  }

  Future<void> _initIAP() async {
    await paymentService.init();
    final productIds = _plans
        .where((p) => p['apple_product_id'] != null && (p['apple_product_id'] as String).isNotEmpty)
        .map((p) => p['apple_product_id'] as String)
        .toList();
    if (productIds.isNotEmpty) {
      await paymentService.loadProducts(productIds);
    }

    paymentService.onPurchaseResult = (planId, success, message) {
      if (mounted) {
        setState(() {
          _purchasing = false;
          _purchasingPlanId = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
        if (success) _loadData();
      }
    };
  }

  Future<void> _purchasePlan(Map<String, dynamic> plan) async {
    final appleProductId = plan['apple_product_id'] as String?;
    if (appleProductId == null || appleProductId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('此套餐暂未配置 Apple 内购产品，请联系客服'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // iOS 月度/年度自动续期订阅：购买前先让用户阅读并同意《自动续费协议》
    if (Platform.isIOS) {
      final period = plan['period'] as String?;
      if (period == 'month' || period == 'year') {
        final agreed = await _showAutoRenewAgreementDialog(plan);
        if (agreed != true) return;
      }
    }

    setState(() {
      _purchasing = true;
      _purchasingPlanId = plan['id'] ?? '';
    });
    final result = await paymentService.purchaseAppleDetailed(appleProductId);
    if (!result.started && mounted) {
      setState(() {
        _purchasing = false;
        _purchasingPlanId = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? '无法发起购买，请稍后重试'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// 自动续费协议确认对话框（iOS 月/年订阅前必读）
  Future<bool?> _showAutoRenewAgreementDialog(Map<String, dynamic> plan) async {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final period = plan['period'] == 'year' ? '年' : '月';
    final price = _getPlanDisplayPrice(plan);
    final String? cnyRefPrice = null;
    bool checked = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: const Text('自动续费服务说明'),
          contentPadding: EdgeInsets.fromLTRB(
            screenWidth < 350 ? 16 : 24,
            16,
            screenWidth < 350 ? 16 : 24,
            8,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${plan['name']} · $period订阅',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              price,
                              style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w900,
                                color: cs.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (cnyRefPrice != null) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                cnyRefPrice,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.outlineVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '请在订阅前确认以下条款：',
                  style: TextStyle(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                _agreementBullet('订阅成功后立即生效，享受对应会员权益'),
                _agreementBullet('Apple 将在到期前 24 小时内自动从您的 Apple ID 关联支付方式扣款，并自动续期 1 个$period'),
                _agreementBullet('如需取消自动续费，请在到期前至少 24 小时通过「设置 → Apple ID → 订阅」关闭'),
                _agreementBullet('iOS 平台的费用由 Apple 收取，退款由 Apple 处理'),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => LegalWebViewPage(
                      title: '自动续费协议',
                      url: '${AppConfig.serverRoot}/app/auto-renew.html',
                    ),
                  )),
                  child: Text(
                    '查看完整《自动续费服务协议》',
                    style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: checked,
                      onChanged: (v) => setLocalState(() => checked = v ?? false),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setLocalState(() => checked = !checked),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            '我已阅读并同意《自动续费服务协议》',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: checked ? () => Navigator.of(ctx).pop(true) : null,
              child: const Text('同意并继续'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _agreementBullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontSize: 13)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5))),
          ],
        ),
      );

  /// 恢复购买（Apple 审核 3.1.1 要求）
  Future<void> _restorePurchases() async {
    if (!Platform.isIOS) return;
    setState(() => _purchasing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在恢复购买…'), duration: Duration(seconds: 2)),
    );
    await paymentService.restorePurchases();
    // 给系统留出时间触发 purchaseStream 回调；若仍无变化则提示
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() => _purchasing = false);
      // 重新拉取会员状态
      _loadData();
    }
  }

  /// 已订阅用户：弹出管理订阅 / 终身会员说明
  Future<void> _showManageSubscription(Map<String, dynamic> plan) async {
    final period = plan['period'] as String?;
    final isLifetime = period == 'forever';
    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isLifetime ? '终身会员' : '会员订阅'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isLifetime)
              const Text('您已购买终身会员，可永久使用全部功能，无需续费。')
            else ...[
              const Text('您已开通该会员，可随时管理或取消订阅。'),
              if (_daysLeft != null) ...[
                const SizedBox(height: 8),
                Text(_isTrial ? '体验剩余 $_daysLeft 天' : '剩余 $_daysLeft 天',
                    style: TextStyle(color: cs.outline, fontSize: 13)),
              ],
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              '首次订阅 7 天内可申请退款，超过期限不可退款',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showRefundEntry();
            },
            child: const Text('申请退款'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          if (!isLifetime && Platform.isIOS)
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final uri = Uri.parse('https://apps.apple.com/account/subscriptions');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('管理订阅'),
            ),
        ],
      ),
    );
  }

  /// 申请退款：判断 7 天期限 → iOS 跳 reportaproblem，其他渠道调后端工单
  Future<void> _showRefundEntry() async {
    // 拉取最近订单判断 7 天期限
    DateTime? lastPaidAt;
    String? lastChannel;
    try {
      final orders = await apiService.getMyOrders();
      for (final o in orders) {
        if (o is Map && o['status'] == 'paid' && o['paid_at'] != null) {
          final t = DateTime.tryParse(o['paid_at'].toString());
          if (t != null) {
            lastPaidAt = t;
            lastChannel = o['channel']?.toString();
            break;
          }
        }
      }
    } catch (_) {/* ignore */}

    if (!mounted) return;
    if (lastPaidAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到可退款的订单')),
      );
      return;
    }
    final daysSince = DateTime.now().difference(lastPaidAt).inDays;
    final daysLeft = 7 - daysSince;
    final canRefund = daysLeft > 0;

    if (!canRefund) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('无法申请退款'),
          content: const Text('您的订阅已超过 7 天退款期限，无法申请退款。\n\n如需取消自动续费以避免下个周期扣款，请在「设置 → Apple ID → 订阅」中关闭。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
      return;
    }

    // iOS 通过 Apple IAP 购买的，必须走 Apple report a problem
    if (lastChannel == 'apple_iap') {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('申请退款'),
          content: Text(
            'Apple 内购的退款须通过 Apple 官方处理。\n\n剩余可申请期限：$daysLeft 天\n\n点击下方按钮跳转到 Apple 退款申请页面。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final uri = Uri.parse('https://reportaproblem.apple.com');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('前往申请'),
            ),
          ],
        ),
      );
      return;
    }

    // 其他渠道（二维码 / Stripe）：填写原因 → 后端工单
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('申请退款'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('剩余可申请期限：$daysLeft 天', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: '请说明退款原因…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('提交')),
        ],
      ),
    );
    if (ok != true) return;
    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) return;
    try {
      await apiService.applyRefund(reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('退款申请已提交，我们将在 3 个工作日内处理'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败：${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 开通失败 - 上传支付截图（人工补单）
  Future<void> _showFailureUploadSheet() async {
    final cs = Theme.of(context).colorScheme;
    final plans = _plans.where((p) => p['enabled'] != false && p['id'] != 'free').toList();
    if (plans.isEmpty) return;

    int planIdx = _selectedPlanIndex >= 0 && _selectedPlanIndex < plans.length
        ? _selectedPlanIndex
        : 0;
    Uint8List? image;
    String? fileName;
    bool submitting = false;
    final noteCtrl = TextEditingController();
    // 根据平台过滤可选渠道：iOS 显示 Apple，安卓显示支付宝/微信/Stripe
    final channelOptions = Platform.isIOS
        ? <Map<String, String>>[
            {'value': 'apple_iap_failed', 'label': 'Apple 支付'},
          ]
        : <Map<String, String>>[
            {'value': 'qrcode_alipay', 'label': '支付宝'},
            {'value': 'qrcode_wechat', 'label': '微信'},
            {'value': 'qrcode_bank', 'label': '银行卡'},
          ];
    String channel = channelOptions.first['value']!;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.report_gmailerrorred_rounded, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('开通失败 · 上传支付截图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(ctx).pop()),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '若您已实际付款但会员未开通，请上传付款截图，我们将在 2 个工作日内人工核实并补开会员。',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 16),
              Text('选择对应套餐', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(plans.length, (i) {
                  final p = plans[i];
                  final selected = i == planIdx;
                  return ChoiceChip(
                    label: Text('${p['name']}'),
                    selected: selected,
                    onSelected: (_) => setLocal(() => planIdx = i),
                  );
                }),
              ),
              const SizedBox(height: 16),
              Text('实际支付方式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: channelOptions.map((opt) {
                  final selected = channel == opt['value'];
                  return ChoiceChip(
                    label: Text(opt['label']!),
                    selected: selected,
                    onSelected: (_) => setLocal(() => channel = opt['value']!),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1200,
                    imageQuality: 85,
                  );
                  if (picked != null) {
                    final bytes = await picked.readAsBytes();
                    setLocal(() {
                      image = bytes;
                      fileName = picked.name;
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: image == null ? 120 : 200,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: image != null ? Colors.green : cs.outlineVariant,
                      width: image != null ? 2 : 1,
                    ),
                  ),
                  child: image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(image!, fit: BoxFit.cover, width: double.infinity),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cloud_upload_outlined, size: 36, color: cs.outline),
                            const SizedBox(height: 6),
                            Text('点击选择支付截图', style: TextStyle(fontSize: 13, color: cs.outline)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: '补充说明（可选）',
                  hintText: '可填写支付时间、订单号、Apple ID、问题描述等，帮助管理员更快核实',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (image == null || submitting)
                      ? null
                      : () async {
                          setLocal(() => submitting = true);
                          try {
                            await apiService.submitPaymentProof(
                              planId: plans[planIdx]['id'] ?? '',
                              channel: channel,
                              imageBytes: image!,
                              fileName: fileName ?? 'proof.jpg',
                              userNote: noteCtrl.text,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已提交，我们将在 1 个工作日内审核'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            setLocal(() => submitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('提交失败：${e.toString().replaceAll('Exception: ', '')}'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: Text(submitting ? '提交中…' : '提交申请'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 380;
    final isTablet = screenWidth >= 600;
    final contentPadding = isSmallScreen ? 12.0 : isTablet ? 24.0 : 16.0;
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('会员权益对比'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(contentPadding, contentPadding, contentPadding, 0),
                    child: Column(
                      children: [
                        // Header banner
                        _buildHeaderBanner(cs, isSmallScreen),
                        const SizedBox(height: 16),
                        // Trial section
                        _buildTrialSection(cs),
                        const SizedBox(height: 20),
                        // Comparison table
                        _buildComparisonTable(cs, isSmallScreen),
                        const SizedBox(height: 24),
                        // Membership plans
                        _buildPlansSection(cs),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _loading ? null : _buildBottomCheckoutBar(cs, isSmallScreen),
    );
  }

  Widget _buildHeaderBanner(ColorScheme cs, bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFF59E0B), const Color(0xFFD97706)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text('👑', style: TextStyle(fontSize: isSmallScreen ? 32 : 40)),
          const SizedBox(height: 12),
          Text(
            '升级会员，解锁全部功能',
            style: TextStyle(
              color: Colors.white,
              fontSize: isSmallScreen ? 18 : 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isMember ? '您已是尊贵会员' : '享受无限制的日语学习体验',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
            ),
          ),
          if (_isMember && _daysLeft != null) ...[
            const SizedBox(height: 6),
            Text(
              _isTrial ? '体验剩余 $_daysLeft 天' : '会员剩余 $_daysLeft 天',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ],
          if (_isMember) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(_isTrial ? '体验中' : '已开通', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrialSection(ColorScheme cs) {
    // Already a member — no trial needed
    if (_isMember) return const SizedBox.shrink();

    // Trial already used
    if (_trialActivated) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: cs.outline, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text('您已使用过会员体验，每个账号仅限一次',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ),
          ],
        ),
      );
    }

    // Trial not enabled by admin
    if (!_trialEnabled) return const SizedBox.shrink();

    // Show trial activation card
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('🎁', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          const Text('免费体验会员',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(_trialDesc.isNotEmpty ? _trialDesc : '免费体验全部会员功能',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
          const SizedBox(height: 4),
          Text('体验时长：$_trialDays 天，每个账号仅限一次',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _activating ? null : _activateTrial,
              icon: _activating
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(_activating ? '开通中...' : '立即开通体验'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateTrial() async {
    setState(() => _activating = true);
    try {
      final result = await apiService.activateTrial();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '已成功开通会员体验！'),
            backgroundColor: Colors.green,
          ),
        );
        // Reload data to reflect new state
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('已使用过') ? '您已使用过会员体验，每个账号仅限一次'
            : e.toString().contains('已经是会员') ? '您已经是会员，无需开通体验'
            : '开通失败，请稍后重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Widget _buildComparisonTable(ColorScheme cs, bool isSmallScreen) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 3,
                  child: Text('功能', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Text('免费用户', style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: cs.outline,
                    )),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('👑 会员',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table rows from tiers
          ..._tiers.asMap().entries.map((entry) {
            final i = entry.key;
            final tier = entry.value;
            final isLast = i == _tiers.length - 1;
            return _buildComparisonRow(
              cs: cs,
              icon: tier['icon'] ?? '⭐',
              name: tier['name'] ?? '',
              freeLabel: tier['free_label'] ?? '',
              memberLabel: tier['member_label'] ?? '',
              type: tier['type'] ?? 'blocked',
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required ColorScheme cs,
    required String icon,
    required String name,
    required String freeLabel,
    required String memberLabel,
    required String type,
    required bool isLast,
  }) {
    // Determine free status icon/color
    Widget freeWidget;
    if (type == 'blocked') {
      freeWidget = const Icon(Icons.close_rounded, color: Colors.red, size: 20);
    } else {
      freeWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check, color: Colors.green, size: 16),
          const SizedBox(width: 2),
          Flexible(
            child: Text(freeLabel,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(child: freeWidget),
          ),
          Expanded(
            flex: 2,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check, color: Colors.green, size: 16),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(memberLabel,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlansSection(ColorScheme cs) {
    const periodLabels = {'month': '/月', 'year': '/年', 'forever': ''};
    final colorMap = {
      0: cs.primary,
      1: const Color(0xFFF59E0B),
      2: const Color(0xFF7C3AED),
    };

    final isIOS = Platform.isIOS;
    // Use fetched plans if available, otherwise fallback to defaults
    final plans = _plans.where((p) => p['enabled'] != false && p['id'] != 'free').toList();
    final usePlans = plans.isNotEmpty
        ? plans
        : [
            {'id': 'monthly', 'name': '月度会员', 'price': 18, 'period': 'month', 'apple_product_id': 'kotabi.sub.monthly'},
            {'id': 'yearly', 'name': '年度会员', 'price': 128, 'period': 'year', 'apple_product_id': 'kotabi.sub.yearly.price'},
            {'id': 'lifetime', 'name': '终身会员', 'price': 398, 'period': 'forever', 'apple_product_id': 'kotabi.vip.lifetime'},
          ];

    // 默认选中：第一个可选套餐（推荐 yearly，否则首个未禁用）
    if (_selectedPlanIndex < 0 || _selectedPlanIndex >= usePlans.length) {
      int idx = usePlans.indexWhere((p) => p['id'] == 'yearly' && !_isPlanDisabled(p));
      if (idx < 0) idx = usePlans.indexWhere((p) => !_isPlanDisabled(p));
      _selectedPlanIndex = idx;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.card_membership_rounded, size: 20, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Text('会员方案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),
        ...usePlans.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final appleId = p['apple_product_id'] as String? ?? '';
          final price = _getPlanDisplayPrice(p);
          final String? cnyRefPrice = null;
          final period = periodLabels[p['period']] ?? '';
          final disabled = _isPlanDisabled(p);
          final isCurrent = _isMember && !_isTrial &&
              _membershipPlan == p['id'];
          final isHighlighted = i == 1; // recommended
          return Padding(
            padding: EdgeInsets.only(top: i > 0 ? 10 : 0),
            child: _PlanCard(
              name: p['name']?.toString() ?? '',
              price: price,
              cnyRefPrice: cnyRefPrice,
              period: period,
              tagline: (p['description'] as String?) ?? _defaultTagline(i),
              color: colorMap[i % 3] ?? cs.primary,
              selected: i == _selectedPlanIndex,
              disabled: disabled,
              isCurrent: isCurrent,
              badge: isHighlighted && !disabled ? '推荐' : null,
              onTap: disabled ? null : () => setState(() => _selectedPlanIndex = i),
            ),
          );
        }),
        if (_isMember && !_isTrial) ...[
          const SizedBox(height: 16),
          Center(
            child: Text(
              '您已是会员，感谢支持！',
              style: TextStyle(fontSize: 13, color: cs.outline),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        // ── 恢复购买（Apple 审核 3.1.1 强制要求，iOS 始终显示） ──
        if (isIOS) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _purchasing ? null : _restorePurchases,
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('恢复购买'),
            ),
          ),
        ],
        // ── 开通会员失败 → 上传支付截图（人工补单，Android 显示） ──
        if (!isIOS) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              onPressed: _showFailureUploadSheet,
              icon: Icon(Icons.report_gmailerrorred_rounded, size: 18, color: cs.error),
              label: Text('开通会员失败？上传支付截图', style: TextStyle(color: cs.error)),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => LegalWebViewPage(
                title: '退款政策',
                url: '${AppConfig.serverRoot}/app/refund.html',
              ),
            )),
            child: Text(
              '订阅前请阅读《退款政策》',
              style: TextStyle(fontSize: 12, color: cs.outline, decoration: TextDecoration.underline),
            ),
          ),
        ),
        // ── iOS 还需要展示自动续费协议链接（合规要求） ──
        if (isIOS) ...[
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => LegalWebViewPage(
                  title: '自动续费协议',
                  url: '${AppConfig.serverRoot}/app/auto-renew.html',
                ),
              )),
              child: Text(
                '订阅前请阅读《自动续费服务协议》',
                style: TextStyle(fontSize: 12, color: cs.outline, decoration: TextDecoration.underline),
              ),
            ),
          ),
          // ── Apple 审核 3.1.2(c) 强制要求：订阅页展示 EULA + Privacy Policy 功能链接 ──
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LegalWebViewPage(
                      title: '用户协议 (EULA)',
                      url: '${AppConfig.serverRoot}/app/terms.html',
                    ),
                  )),
                  child: Text(
                    '《用户协议 (EULA)》',
                    style: TextStyle(fontSize: 12, color: cs.primary, decoration: TextDecoration.underline),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => LegalWebViewPage(
                      title: '隐私政策',
                      url: '${AppConfig.serverRoot}/app/privacy.html',
                    ),
                  )),
                  child: Text(
                    '《隐私政策》',
                    style: TextStyle(fontSize: 12, color: cs.primary, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _defaultTagline(int i) {
    switch (i) {
      case 0: return '按月计费 · 随时取消';
      case 1: return '相当于月付节省更多';
      case 2: return '一次购买永久使用';
      default: return '';
    }
  }

  // ── 底部固定开通栏 ──
  Widget _buildBottomCheckoutBar(ColorScheme cs, bool isSmallScreen) {
    final isIOS = Platform.isIOS;
    final plans = _plans.where((p) => p['enabled'] != false && p['id'] != 'free').toList();
    final usePlans = plans.isNotEmpty
        ? plans
        : [
            {'id': 'monthly', 'name': '月度会员', 'price': 18, 'period': 'month', 'apple_product_id': 'kotabi.sub.monthly'},
            {'id': 'yearly', 'name': '年度会员', 'price': 128, 'period': 'year', 'apple_product_id': 'kotabi.sub.yearly.price'},
            {'id': 'lifetime', 'name': '终身会员', 'price': 398, 'period': 'forever', 'apple_product_id': 'kotabi.vip.lifetime'},
          ];
    if (_selectedPlanIndex < 0 || _selectedPlanIndex >= usePlans.length) {
      return const SizedBox.shrink();
    }
    final selected = usePlans[_selectedPlanIndex];
    final appleId = selected['apple_product_id'] as String? ?? '';
    final price = _getPlanDisplayPrice(selected);
    final disabled = _isPlanDisabled(selected);
    final isCurrent = _isMember && !_isTrial &&
        _membershipPlan == selected['id'];

    String label;
    VoidCallback? onPressed;
    if (isCurrent) {
      label = '当前套餐 · 管理订阅';
      onPressed = () => _showManageSubscription(selected);
    } else if (disabled) {
      label = '已不可降级';
      onPressed = null;
    } else {
      // 升级或首次开通
      label = (_isMember && !_isTrial) ? '升级到${selected['name']}  $price' : '立即开通  $price';
      onPressed = _purchasing
          ? null
          : isIOS
              ? () => _purchasePlan(selected)
              : () => context.push('/qr-payment', extra: selected);
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(isSmallScreen ? 12 : 16, 8, isSmallScreen ? 12 : 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  disabledBackgroundColor: cs.outlineVariant,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _purchasing
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String name;
  final String price;
  final String period;
  final String tagline;
  final Color color;
  final bool selected;
  final bool disabled;
  final bool isCurrent;
  final String? badge;
  final String? cnyRefPrice; // CNY reference price, shown as small text below main price
  final VoidCallback? onTap;

  const _PlanCard({
    required this.name,
    required this.price,
    required this.period,
    required this.tagline,
    required this.color,
    this.selected = false,
    this.disabled = false,
    this.isCurrent = false,
    this.badge,
    this.cnyRefPrice,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 380;
    
    final borderColor = disabled
        ? cs.outlineVariant.withValues(alpha: 0.5)
        : selected
            ? color
            : cs.outlineVariant;
    final bgColor = disabled
        ? cs.surfaceContainerLow.withValues(alpha: 0.5)
        : selected
            ? color.withValues(alpha: 0.06)
            : null;
    final textColor = disabled ? cs.outline : null;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
              color: bgColor,
            ),
            padding: EdgeInsets.fromLTRB(isSmallScreen ? 12 : 14, isSmallScreen ? 12 : 14, isSmallScreen ? 12 : 14, isSmallScreen ? 12 : 14),
            child: Row(
                  children: [
                    // 选中圆点
                    Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? color : cs.outline, width: 2),
                        color: selected ? color : Colors.transparent,
                      ),
                      child: selected
                          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(name,
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 14 : 15, fontWeight: FontWeight.bold,
                                    color: textColor ?? cs.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCurrent) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('当前',
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(tagline,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor ?? cs.onSurfaceVariant,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (badge != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(badge!,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(price,
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.w900,
                                        color: textColor ?? color,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (cnyRefPrice != null && cnyRefPrice!.isNotEmpty)
                                      Text(cnyRefPrice!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: textColor ?? cs.outlineVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (period.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Text(period,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: textColor ?? color.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
  }
}
