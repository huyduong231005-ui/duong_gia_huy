import 'package:flutter/material.dart';

import '../api.dart';
import 'auth_widgets.dart';
import 'otp_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_fullName, _email, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim().toLowerCase();
    Future<String> send() => api.register(
          email: email,
          username: _username.text.trim().toLowerCase(),
          password: _password.text,
          fullName: _fullName.text.trim(),
        );

    setState(() => _loading = true);
    try {
      final masked = await send();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(
          maskedEmail: masked,
          verify: (code) => api.verifyRegister(email, code),
          resend: send, // backend cho đăng ký lại khi chưa xác minh → gửi mã mới
        ),
      ));
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Tạo tài khoản',
        subtitle: 'Mã xác minh sẽ được gửi qua email',
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Họ và tên', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Nhập họ tên' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Icons.alternate_email)),
                validator: (v) => emailRe.hasMatch((v ?? '').trim()) ? null : 'Email không hợp lệ',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _username,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập',
                  helperText: 'Chữ thường, số, dấu _ hoặc . (3–30 ký tự)',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => usernameRe.hasMatch((v ?? '').trim().toLowerCase())
                    ? null
                    : 'Tên đăng nhập không hợp lệ',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) =>
                    (v ?? '').length < minPassword ? 'Tối thiểu $minPassword ký tự' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                obscureText: true,
                onFieldSubmitted: (_) => _register(),
                decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu', prefixIcon: Icon(Icons.lock_reset)),
                validator: (v) => v == _password.text ? null : 'Mật khẩu không khớp',
              ),
              const SizedBox(height: 24),
              LoadingButton(label: 'Đăng ký', loading: _loading, onPressed: _register),
            ],
          ),
        ),
      );
}
