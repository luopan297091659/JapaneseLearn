import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/guest_service.dart';
import '../../config/app_config.dart';
import '../common/legal_webview_page.dart';

const _emailSuffixes = [
  '@qq.com', '@163.com', '@gmail.com', '@outlook.com',
  '@126.com', '@yahoo.com', '@hotmail.com', '@icloud.com',
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _useCode = false; // false=密码登录, true=验证码登录
  bool _codeSent = false;
  int _countdown = 0;

  String _extractError(dynamic e) {
    if (e is DioException && e.response?.data is Map) {
      return (e.response!.data as Map)['error']?.toString() ?? '操作失败';
    }
    return '操作失败';
  }

  void _appendSuffix(String suffix) {
    final text = _emailCtrl.text;
    final at = text.indexOf('@');
    final prefix = at >= 0 ? text.substring(0, at) : text;
    _emailCtrl.text = '$prefix$suffix';
    _emailCtrl.selection =
        TextSelection.collapsed(offset: _emailCtrl.text.length);
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = S.of(context).pleaseEnterEmail);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await apiService.sendLoginCode(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _countdown = 60;
      });
      _startCountdown();
    } catch (e) {
      if (mounted) setState(() => _error = _extractError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_useCode) {
        await apiService.loginWithCode(
            email: _emailCtrl.text.trim(), code: _codeCtrl.text.trim());
      } else {
        await apiService.login(
            email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      }
      await guestService.disableGuestMode();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted)
        setState(() =>
            _error = _useCode ? _extractError(e) : S.of(context).loginError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.primary,
              cs.primary.withValues(alpha: 0.8),
              cs.surfaceContainerLowest,
              cs.surfaceContainerLowest,
            ],
            stops: const [0.0, 0.38, 0.38, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset('assets/images/app_icon.png',
                          fit: BoxFit.cover),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(s.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        )),
                Text(s.appSubtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        )),
                const SizedBox(height: 36),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withValues(alpha: 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 登录方式切换
                      Row(children: [
                        Expanded(
                            child: GestureDetector(
                          onTap: () => setState(() {
                            _useCode = false;
                            _error = null;
                          }),
                          child: Column(children: [
                            Text('密码登录',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: _useCode
                                      ? FontWeight.normal
                                      : FontWeight.bold,
                                  color: _useCode ? cs.outline : cs.primary,
                                )),
                            const SizedBox(height: 4),
                            Container(
                                height: 2,
                                color:
                                    _useCode ? Colors.transparent : cs.primary),
                          ]),
                        )),
                        Expanded(
                            child: GestureDetector(
                          onTap: () => setState(() {
                            _useCode = true;
                            _error = null;
                          }),
                          child: Column(children: [
                            Text('验证码登录',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: _useCode
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: _useCode ? cs.primary : cs.outline,
                                )),
                            const SizedBox(height: 4),
                            Container(
                                height: 2,
                                color:
                                    _useCode ? cs.primary : Colors.transparent),
                          ]),
                        )),
                      ]),
                      const SizedBox(height: 20),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: s.email,
                                prefixIcon: Icon(Icons.email_outlined,
                                    color: cs.primary),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                filled: true,
                                fillColor: cs.surfaceContainerHighest
                                    .withValues(alpha: 0.3),
                                suffixIcon: PopupMenuButton<String>(
                                  icon: Icon(Icons.alternate_email,
                                      color: cs.primary),
                                  tooltip: '选择邮箱后缀',
                                  onSelected: _appendSuffix,
                                  itemBuilder: (_) => _emailSuffixes
                                      .map((suffix) => PopupMenuItem(
                                            value: suffix,
                                            child: Text(suffix),
                                          ))
                                      .toList(),
                                ),
                              ),
                              validator: (v) =>
                                  v!.isEmpty ? s.pleaseEnterEmail : null,
                            ),
                            const SizedBox(height: 16),
                            if (!_useCode)
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: s.password,
                                  prefixIcon: Icon(Icons.lock_outline,
                                      color: cs.primary),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) =>
                                    v!.isEmpty ? s.pleaseEnterPassword : null,
                              ),
                            if (_useCode)
                              TextFormField(
                                controller: _codeCtrl,
                                keyboardType: TextInputType.number,
                                maxLength: 6,
                                decoration: InputDecoration(
                                  labelText: '验证码',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.pin_outlined,
                                      color: cs.primary),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  filled: true,
                                  fillColor: cs.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  suffixIcon: TextButton(
                                    onPressed: (_loading || _countdown > 0)
                                        ? null
                                        : _sendCode,
                                    child: Text(
                                      _countdown > 0
                                          ? '${_countdown}s'
                                          : (_codeSent ? '重新发送' : '发送验证码'),
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: (_loading || _countdown > 0)
                                              ? cs.outline
                                              : cs.primary),
                                    ),
                                  ),
                                ),
                                validator: (v) => v!.isEmpty ? '请输入验证码' : null,
                              ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: TextStyle(color: cs.error, fontSize: 13),
                            textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(s.login,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (!_useCode)
                            TextButton(
                              onPressed: _loading
                                  ? null
                                  : () => context.go('/forgot-password'),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 8),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                s.forgotPassword,
                                style:
                                    TextStyle(fontSize: 13, color: cs.primary),
                              ),
                            )
                          else
                            const SizedBox(width: 4),
                          const Spacer(),
                          TextButton(
                            onPressed:
                                _loading ? null : () => context.go('/register'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              s.registerNow,
                              style: TextStyle(fontSize: 13, color: cs.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (Platform.isIOS)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              await guestService.enableGuestMode();
                              if (mounted) context.go('/home');
                            },
                      child: Text('游客模式', style: TextStyle(color: cs.outline)),
                    ),
                  ]),
                if (false) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              await guestService.enableGuestMode();
                              if (mounted) context.go('/home');
                            },
                      child: Text(
                        '游客模式',
                        style: TextStyle(fontSize: 14, color: cs.outline),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _legalLink(
                        '《用户协议》', '${AppConfig.serverRoot}/app/terms.html'),
                    _legalLink(
                        '《隐私政策》', '${AppConfig.serverRoot}/app/privacy.html'),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legalLink(String label, String url) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LegalWebViewPage(
            title: label.replaceAll('《', '').replaceAll('》', ''), url: url),
      )),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 12, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
