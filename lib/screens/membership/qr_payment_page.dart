import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../services/payment_service.dart';

/// Android 二维码支付页面
/// 流程：选择支付方式 → 展示收款二维码 → 用户扫码支付 → 上传支付截图 → 等待审核
class QrPaymentPage extends StatefulWidget {
  final Map<String, dynamic> plan;
  const QrPaymentPage({super.key, required this.plan});

  @override
  State<QrPaymentPage> createState() => _QrPaymentPageState();
}

class _QrPaymentPageState extends State<QrPaymentPage> {
  bool _loading = true;
  Map<String, dynamic> _alipay = {};
  Map<String, dynamic> _wechat = {};
  bool _stripeEnabled = false;
  String _selectedChannel = ''; // 'qrcode_alipay' | 'qrcode_wechat' | 'stripe'
  Uint8List? _proofImage;
  String? _proofFileName;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      // 并行加载 QR 配置和支付渠道
      final results = await Future.wait([
        paymentService.getQrConfig(),
        apiService.getPaymentPlans(),
      ]);
      final qrConfig = results[0];
      final plansData = results[1];
      final channels = plansData['channels'] as Map<String, dynamic>? ?? {};
      if (mounted) {
        setState(() {
          _alipay = Map<String, dynamic>.from(qrConfig['alipay'] ?? {});
          _wechat = Map<String, dynamic>.from(qrConfig['wechat'] ?? {});
          _stripeEnabled = channels['stripe'] == true;
          // 自动选择第一个可用渠道：优先 Stripe
          if (_stripeEnabled) {
            _selectedChannel = 'stripe';
          } else if (_alipay['enabled'] == true) {
            _selectedChannel = 'qrcode_alipay';
          } else if (_wechat['enabled'] == true) {
            _selectedChannel = 'qrcode_wechat';
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 85);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _proofImage = bytes;
          _proofFileName = picked.name;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_proofImage == null || _selectedChannel.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await apiService.submitPaymentProof(
        planId: widget.plan['id'] ?? '',
        channel: _selectedChannel,
        imageBytes: _proofImage!,
        fileName: _proofFileName ?? 'proof.jpg',
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('提交失败：${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plan = widget.plan;
    final price = (plan['price'] is num) ? (plan['price'] as num).toInt() : 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('扫码支付'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _submitted
              ? _buildSuccessView(cs)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildPlanSummary(cs, plan, price),
                    const SizedBox(height: 20),
                    _buildChannelSelector(cs),
                    const SizedBox(height: 20),
                    if (_selectedChannel == 'stripe')
                      _buildStripeSection(cs)
                    else ...[
                      if (_selectedChannel.isNotEmpty) _buildQrCodeSection(cs, price),
                      const SizedBox(height: 24),
                      _buildUploadSection(cs),
                      const SizedBox(height: 24),
                      _buildSubmitButton(cs),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }

  Widget _buildPlanSummary(ColorScheme cs, Map<String, dynamic> plan, int price) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('👑', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan['name']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(plan['description']?.toString() ?? '', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
              ],
            ),
          ),
          Text('¥$price', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildChannelSelector(ColorScheme cs) {
    final alipayEnabled = _alipay['enabled'] == true;
    final wechatEnabled = _wechat['enabled'] == true;
    final anyEnabled = alipayEnabled || wechatEnabled || _stripeEnabled;
    if (!anyEnabled) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Text('暂无可用支付渠道，请联系客服', style: TextStyle(color: cs.onErrorContainer)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('选择支付方式', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (_stripeEnabled)
              SizedBox(
                width: alipayEnabled || wechatEnabled
                    ? (MediaQuery.of(context).size.width - 42) / 2
                    : double.infinity,
                child: _ChannelChip(
                  label: '银行卡支付',
                  icon: Icons.credit_card,
                  color: const Color(0xFF635BFF),
                  selected: _selectedChannel == 'stripe',
                  onTap: () => setState(() => _selectedChannel = 'stripe'),
                ),
              ),
            if (alipayEnabled)
              SizedBox(
                width: (MediaQuery.of(context).size.width - 42) / 2,
                child: _ChannelChip(
                  label: '支付宝',
                  icon: Icons.account_balance_wallet,
                  color: const Color(0xFF1677FF),
                  selected: _selectedChannel == 'qrcode_alipay',
                  onTap: () => setState(() => _selectedChannel = 'qrcode_alipay'),
                ),
              ),
            if (wechatEnabled)
              SizedBox(
                width: (MediaQuery.of(context).size.width - 42) / 2,
                child: _ChannelChip(
                  label: '微信支付',
                  icon: Icons.chat_bubble,
                  color: const Color(0xFF07C160),
                  selected: _selectedChannel == 'qrcode_wechat',
                  onTap: () => setState(() => _selectedChannel = 'qrcode_wechat'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildStripeSection(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF635BFF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.credit_card, size: 28, color: Color(0xFF635BFF)),
          ),
          const SizedBox(height: 16),
          const Text('安全银行卡支付', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            '支持 Visa、Mastercard、银联等国际卡\n由 Stripe 安全处理，支付成功即刻开通',
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _goStripeCheckout,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outlined, size: 18),
              label: Text(_submitting ? '跳转中...' : '前往安全支付'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF635BFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user, size: 14, color: cs.outline),
              const SizedBox(width: 4),
              Text('SSL 加密 · 无需人工审核 · 即时开通', style: TextStyle(fontSize: 11, color: cs.outline)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _goStripeCheckout() async {
    setState(() => _submitting = true);
    try {
      final plan = widget.plan;
      final result = await context.push<bool>(
        '/stripe-checkout',
        extra: {
          'planId': plan['id'] ?? '',
          'planName': plan['name']?.toString() ?? '',
        },
      );
      if (mounted) {
        setState(() => _submitting = false);
        if (result == true) {
          // 支付成功，返回会员页
          if (mounted) context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开支付页失败：${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildQrCodeSection(ColorScheme cs, int price) {
    final isAlipay = _selectedChannel == 'qrcode_alipay';
    final qrUrl = isAlipay ? _alipay['qr_url'] : _wechat['qr_url'];
    final channelColor = isAlipay ? const Color(0xFF1677FF) : const Color(0xFF07C160);
    final channelName = isAlipay ? '支付宝' : '微信';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        children: [
          Text('请使用$channelName扫描下方二维码', style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text('支付金额：¥$price', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: channelColor)),
          const SizedBox(height: 16),
          // QR 码图片
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: channelColor.withValues(alpha: 0.3), width: 2),
            ),
            child: qrUrl != null && qrUrl.toString().startsWith('http')
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      qrUrl.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2, size: 48, color: cs.outline),
                            const SizedBox(height: 8),
                            Text('二维码加载失败', style: TextStyle(fontSize: 12, color: cs.outline)),
                          ],
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.qr_code_2, size: 48, color: cs.outline),
                        const SizedBox(height: 8),
                        Text('二维码配置中', style: TextStyle(fontSize: 12, color: cs.outline)),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFF92400E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '支付完成后，请截图保存支付凭证，并在下方上传',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadSection(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('上传支付截图', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cs.onSurface)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity,
            height: _proofImage != null ? null : 120,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _proofImage != null ? Colors.green : cs.outlineVariant,
                width: _proofImage != null ? 2 : 1,
                style: _proofImage != null ? BorderStyle.solid : BorderStyle.none,
              ),
            ),
            child: _proofImage != null
                ? Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_proofImage!, width: double.infinity, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.refresh, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ],
                  )
                : DashedBorderContainer(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload_outlined, size: 36, color: cs.outline),
                        const SizedBox(height: 8),
                        Text('点击选择支付截图', style: TextStyle(fontSize: 13, color: cs.outline)),
                        const SizedBox(height: 2),
                        Text('支持 JPG、PNG 格式', style: TextStyle(fontSize: 11, color: cs.outlineVariant)),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmitButton(ColorScheme cs) {
    final canSubmit = _proofImage != null && _selectedChannel.isNotEmpty && !_submitting;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: canSubmit ? _submit : null,
        icon: _submitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.upload_file_rounded, size: 20),
        label: Text(_submitting ? '提交中...' : '提交支付凭证'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF59E0B),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          disabledBackgroundColor: cs.surfaceContainerHighest,
        ),
      ),
    );
  }

  Widget _buildSuccessView(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Center(child: Text('✅', style: TextStyle(fontSize: 40))),
            ),
            const SizedBox(height: 24),
            const Text('支付凭证已提交', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              '管理员将在24小时内审核您的订单\n审核通过后会员权益将自动生效',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.pop(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('返回'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 支付渠道选择芯片
class _ChannelChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ChannelChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? color : Theme.of(context).colorScheme.outline),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? color : Theme.of(context).colorScheme.onSurface,
            )),
          ],
        ),
      ),
    );
  }
}

/// 虚线边框容器
class DashedBorderContainer extends StatelessWidget {
  final Widget child;
  const DashedBorderContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: Theme.of(context).colorScheme.outlineVariant),
      child: SizedBox(
        width: double.infinity,
        height: 120,
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14));
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, end > metric.length ? metric.length : end), paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
