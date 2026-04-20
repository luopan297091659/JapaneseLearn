import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// 应用内 WebView，用于显示 NHK 新闻全文（阅读模式）
class NhkWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  const NhkWebViewScreen({super.key, required this.url, this.title = 'NHK ニュース'});

  @override
  State<NhkWebViewScreen> createState() => _NhkWebViewScreenState();
}

class _NhkWebViewScreenState extends State<NhkWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  double _progress = 0;

  // 注入 JS：自动关闭 NHK 同意弹窗 + 隐藏导航/侧栏/页脚，纯净阅读模式
  static const _cleanupJs = '''
(function() {
  // 1) 自动点击"サービスの利用を開始する"按钮关闭同意弹窗
  function dismissConsent() {
    var btns = document.querySelectorAll('button, a');
    for (var i = 0; i < btns.length; i++) {
      var t = btns[i].textContent || '';
      if (t.indexOf('サービスの利用を開始する') !== -1 || t.indexOf('同意') !== -1) {
        btns[i].click();
        return true;
      }
    }
    // 直接移除弹窗层
    var dialogs = document.querySelectorAll('[role="dialog"], [class*="modal"], [class*="consent"], [class*="agreement"]');
    dialogs.forEach(function(el) { el.remove(); });
    // 移除 overflow hidden
    document.body.style.overflow = 'auto';
    document.documentElement.style.overflow = 'auto';
    return false;
  }

  // 2) 隐藏不需要的 UI 元素
  function hideClutter() {
    var css = document.createElement('style');
    css.textContent = [
      'header, nav, [class*="header"], [class*="Header"] { display: none !important; }',
      'footer, [class*="footer"], [class*="Footer"] { display: none !important; }',
      '[class*="sidebar"], [class*="Sidebar"], [class*="side-bar"] { display: none !important; }',
      '[class*="breadcrumb"], [class*="Breadcrumb"] { display: none !important; }',
      '[class*="share"], [class*="Share"], [class*="sns"] { display: none !important; }',
      '[class*="related"], [class*="Related"] { display: none !important; }',
      '[class*="recommend"], [class*="Recommend"] { display: none !important; }',
      '[class*="ranking"], [class*="Ranking"] { display: none !important; }',
      '[class*="banner"], [class*="Banner"], [class*="ad-"] { display: none !important; }',
      '[class*="consent"], [class*="Consent"], [class*="agreement"] { display: none !important; }',
      '[class*="modal"], [class*="overlay"] { display: none !important; }',
      '[class*="navigation"], [class*="Navigation"], [class*="gnav"] { display: none !important; }',
      '[class*="menu"][class*="global"] { display: none !important; }',
      'body { overflow: auto !important; padding-top: 0 !important; margin-top: 0 !important; }',
    ].join('\\n');
    document.head.appendChild(css);
  }

  // 多次尝试（NHK 动态加载）
  dismissConsent();
  hideClutter();
  setTimeout(function() { dismissConsent(); }, 1000);
  setTimeout(function() { dismissConsent(); }, 3000);
  setTimeout(function() { dismissConsent(); hideClutter(); }, 5000);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress / 100.0);
        },
        onPageFinished: (_) {
          _controller.runJavaScript(_cleanupJs);
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          final uri = Uri.parse(request.url);
          if (uri.host.contains('nhk')) {
            return NavigationDecision.navigate;
          }
          launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
          return NavigationDecision.prevent;
        },
      ))
      ..setUserAgent('Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Mobile Safari/537.36')
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 20),
            tooltip: '在浏览器中打开',
            onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              ],
            ),
        ],
      ),
    );
  }
}
