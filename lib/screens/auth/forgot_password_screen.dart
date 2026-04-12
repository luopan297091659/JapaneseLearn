import 'package:flutter/material.dart';
import 'package:dio/dio.dart' show DioException;
import 'package:go_router/go_router.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

const _emailSuffixes = [
  '@qq.com', '@163.com', '@gmail.com', '@outlook.com',
  '@126.com', '@yahoo.com', '@hotmail.com', '@icloud.com',
];

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _success;
  int _step = 0; // 0=输入邮箱  1=输入验证码+新密码
  int _countdown = 0;

  void _appendSuffix(String suffix) {
    final text = _emailCtrl.text;
    final at = text.indexOf('@');
    final prefix = at >= 0 ? text.substring(0, at) : text;
    _emailCtrl.text = '$prefix$suffix';
    _emailCtrl.selection = TextSelection.collapsed(offset: _emailCtrl.text.length);
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = S.of(context).pleaseEnterEmail);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await apiService.forgotPassword(email);
      if (!mounted) return;
      setState(() { _step = 1; _success = S.of(context).codeSent; _countdown = 60; });
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

  Future<void> _resetPassword() async {
    final code = _codeCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (code.isEmpty || pwd.isEmpty) {
      setState(() => _error = '请填写验证码和新密码');
      return;
    }
    if (pwd.length < 8) {
      setState(() => _error = S.of(context).passwordMinLengthError);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await apiService.resetPassword(email: _emailCtrl.text.trim(), code: code, newPassword: pwd);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).resetSuccess)));
      context.go('/login');
    } catch (e) {
      if (mounted) setState(() => _error = _extractError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _extractError(dynamic e) {
    if (e is DioException && e.response?.data is Map) {
      return (e.response!.data as Map)['error']?.toString() ?? '操作失败';
    }
    return '网络错误，请重试';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.resetPassword),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_reset_rounded, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                _step == 0 ? '输入注册邮箱，我们将发送验证码' : '请输入邮箱收到的验证码和新密码',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.outline),
              ),
              const SizedBox(height: 24),

              // Email field
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                enabled: _step == 0,
                decoration: InputDecoration(
                  labelText: s.email,
                  prefixIcon: Icon(Icons.email_outlined, color: cs.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  suffixIcon: _step == 0
                      ? PopupMenuButton<String>(
                          icon: Icon(Icons.alternate_email, color: cs.primary),
                          tooltip: '选择邮箱后缀',
                          onSelected: _appendSuffix,
                          itemBuilder: (_) => _emailSuffixes.map((s) =>
                            PopupMenuItem(value: s, child: Text(s))).toList(),
                        )
                      : null,
                ),
              ),

              if (_step == 1) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: s.verificationCode,
                    prefixIcon: Icon(Icons.pin_outlined, color: cs.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '${s.newPassword}（至少8位）',
                    prefixIcon: Icon(Icons.lock_outline, color: cs.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 13), textAlign: TextAlign.center),
              ],
              if (_success != null && _error == null) ...[
                const SizedBox(height: 12),
                Text(_success!, style: TextStyle(color: cs.primary, fontSize: 13), textAlign: TextAlign.center),
              ],

              const SizedBox(height: 24),

              if (_step == 0)
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _sendCode,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(s.sendCode, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),

              if (_step == 1) ...[
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _resetPassword,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(s.resetPassword, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _countdown > 0 || _loading ? null : _sendCode,
                    child: Text(_countdown > 0 ? '重新发送 (${_countdown}s)' : '重新发送验证码'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
