import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../main.dart';
import 'auth_widgets.dart';

const _resendCooldown = 30;

/// Nhập mã OTP 6 số gửi qua email. Dùng chung cho đăng ký và đăng nhập.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.maskedEmail,
    required this.verify,
    required this.resend,
  });

  final String maskedEmail;
  final Future<AppUser> Function(String code) verify;
  final Future<void> Function() resend;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _loading = false;
  int _wait = _resendCooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _wait = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_wait <= 1) t.cancel();
      setState(() => _wait--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.length != 6 || _loading) return;
    setState(() => _loading = true);
    try {
      final user = await widget.verify(_code.text);
      if (mounted) goHome(context, user);
    } on ApiException catch (e) {
      _code.clear();
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await widget.resend();
      _startCooldown();
      if (mounted) showError(context, 'Đã gửi mã mới');
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        icon: Icons.mark_email_read_outlined,
        title: 'Nhập mã OTP',
        subtitle: 'Mã 6 số đã gửi tới ${widget.maskedEmail}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(letterSpacing: 12, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(counterText: '', hintText: '••••••'),
              onChanged: (v) => v.length == 6 ? _submit() : null,
            ),
            const SizedBox(height: 20),
            LoadingButton(label: 'Xác nhận', loading: _loading, onPressed: _submit),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _wait > 0 ? null : _resend,
              child: Text(_wait > 0 ? 'Gửi lại mã sau $_wait giây' : 'Gửi lại mã'),
            ),
          ],
        ),
      );
}
