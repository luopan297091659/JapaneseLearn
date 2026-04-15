import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/api_service.dart';

/// Stripe Checkout WebView 页面 (仅 Android)
/// 打开 Stripe Hosted Checkout，支付完成后自动返回并刷新会员状态
class StripeCheckoutPage extends StatefulWidget {
  final String planId;
  final String planName;
  const StripeCheckoutPage({super.key, required this.planId, required this.planName});

  @override
  State<StripeCheckoutPage> createState() => _StripeCheckoutPageState();
}

class _StripeCheckoutPageState extends State<StripeCheckoutPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _paying = false;
  String? _error;
  String? _sessionId;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onNavigationRequest: (request) {
          // 检测支付成功/取消的回调 URL
          final uri = Uri.tryParse(request.url);
          if (uri != null && uri.path.contains('membership')) {
            final status = uri.queryParameters['status'];
            final sid = uri.queryParameters['session_id'];
            if (status == 'success' && sid != null) {
              _onPaymentSuccess(sid);
              return NavigationDecision.prevent;
            } else if (status == 'cancel') {
              _onPaymentCancel();
              return NavigationDecision.prevent;
            }
          }
          return NavigationDecision.navigate;
        },
      ));
    _initCheckout();
  }

  Future<void> _initCheckout() async {
    try {
      final result = await apiService.createStripeCheckout(widget.planId);
      final url = result['url'] as String?;
      _sessionId = result['sessionId'] as String?;
      if (url == null || url.isEmpty) {
        setState(() {
          _error = 'Stripe 未配置，请联系管理员';
          _loading = false;
        });
        return;
      }
      _controller.loadRequest(Uri.parse(url));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  void _onPaymentSuccess(String sessionId) {
    setState(() => _paying = true);
    // Webhook 会自动开通会员，这里等待 1 秒后提示成功
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _paying = false);
        _showResult(true, '支付成功，会员已开通！');
      }
    });
  }

  void _onPaymentCancel() {
    _showResult(false, '支付已取消');
  }

  void _showResult(bool success, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle : Icons.cancel,
              size: 56,
              color: success ? Colors.green : Colors.red,
            ),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // 返回会员页并刷新
              context.pop(success);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(false),
        ),
        title: Text('支付 — ${widget.planName}'),
      ),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(_error!, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: () => context.pop(false), child: const Text('返回')),
                  ],
                ),
              ),
            )
          else
            WebViewWidget(controller: _controller),
          if (_loading || _paying)
            Container(
              color: Colors.white.withValues(alpha: 0.7),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_paying ? '正在确认支付...' : '加载支付页面...', style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
