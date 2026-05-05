import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

const _emailSuffixes = [
  '@qq.com', '@163.com','@gmail.com', '@outlook.com',
  '@126.com', '@yahoo.com', '@hotmail.com', '@icloud.com',
];

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _inviteCodeCtrl = TextEditingController();
  String _selectedLevel = 'N5';
  bool _loading = false;
  bool _obscure = true;
  bool _codeSent = false;
  int _countdown = 0;
  String? _error;

  void _appendSuffix(String suffix) {
    final text = _emailCtrl.text;
    final at = text.indexOf('@');
    final prefix = at >= 0 ? text.substring(0, at) : text;
    _emailCtrl.text = '$prefix$suffix';
    _emailCtrl.selection = TextSelection.collapsed(offset: _emailCtrl.text.length);
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _inviteCodeCtrl.dispose();
    super.dispose();
  }

  String _extractError(dynamic e) {
    if (e is DioException && e.response?.data is Map) {
      return (e.response!.data as Map)['error']?.toString() ?? '操作失败';
    }
    return '操作失败';
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = S.of(context).pleaseEnterEmail);
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await apiService.sendRegisterCode(email);
      if (!mounted) return;
      setState(() { _codeSent = true; _countdown = 60; });
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await apiService.register(
        username: _usernameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        code: _codeCtrl.text.trim(),
        level: _selectedLevel,
        inviteCode: _inviteCodeCtrl.text.trim(),
      );
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = _extractError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.createAccount),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          tooltip: '返回',
          onPressed: () => context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(labelText: s.username, prefixIcon: const Icon(Icons.person_outline)),
                  validator: (v) => v!.length < 3 ? s.usernameMinLength : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: s.email,
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: PopupMenuButton<String>(
                      icon: const Icon(Icons.alternate_email),
                      tooltip: '选择邮箱后缀',
                      onSelected: _appendSuffix,
                      itemBuilder: (_) => _emailSuffixes.map((s) =>
                        PopupMenuItem(value: s, child: Text(s))).toList(),
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? s.pleaseEnterEmail : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: s.passwordMinLength,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v!.length < 8 ? s.passwordMinLengthError : null,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: s.verificationCode,
                          prefixIcon: const Icon(Icons.verified_outlined),
                          counterText: '',
                        ),
                        validator: (v) {
                          final code = v?.trim() ?? '';
                          return RegExp(r'^\d{6}$').hasMatch(code) ? null : '请输入 6 位验证码';
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: _loading || (_codeSent && _countdown > 0) ? null : _sendCode,
                        child: Text(_countdown > 0 ? '${_countdown}s' : s.sendCode),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedLevel,
                  decoration: InputDecoration(labelText: s.jlptLevel, prefixIcon: const Icon(Icons.bar_chart)),
                  items: ['N5', 'N4', 'N3', 'N2', 'N1'].map((l) => DropdownMenuItem(
                    value: l, child: Text('$l - ${_levelLabel(l, s)}'))).toList(),
                  onChanged: (v) => setState(() => _selectedLevel = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _inviteCodeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '邀请码（选填）',
                    prefixIcon: Icon(Icons.card_giftcard_outlined),
                    hintText: '有邀请码可填写',
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(s.register),
                ),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(s.hasAccount),
                  TextButton(onPressed: () => context.go('/login'), child: Text(s.goLogin)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _levelLabel(String level, S s) {
    final labels = {'N5': s.n5label, 'N4': s.n4label, 'N3': s.n3label, 'N2': s.n2label, 'N1': s.n1label};
    return labels[level] ?? level;
  }
}
