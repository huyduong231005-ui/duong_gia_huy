import 'package:flutter/material.dart';
import '../api.dart';
import '../device_prefs.dart';
import '../google_auth.dart';
import '../main.dart';
import 'auth_widgets.dart';
import 'face_scan_screen.dart';
import 'otp_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  bool _fingerprint = false; // chỉ hiện nút vân tay khi người dùng đã bật trong Cài đặt

  @override
  void initState() {
    super.initState();
    _username.addListener(_refreshFingerprint); // đổi tài khoản trong ô thì hiện/ẩn vân tay theo
    _loadQuickLogin();
  }

  /// Điền sẵn tài khoản lần trước để bấm khuôn mặt / vân tay là vào luôn.
  Future<void> _loadQuickLogin() async {
    final last = await QuickLogin.lastUsername();
    if (mounted && _username.text.isEmpty && last != null) _username.text = last;
  }

  /// Vân tay lưu riêng từng tài khoản: chỉ hiện biểu tượng khi tài khoản trong ô đã tự bật.
  Future<void> _refreshFingerprint() async {
    final name = _username.text;
    final enabled = name.trim().isNotEmpty && await QuickLogin.fingerprintEnabled(name);
    if (mounted && name == _username.text && enabled != _fingerprint) setState(() => _fingerprint = enabled);
  }

  Future<void> _loginWithFingerprint() => _run(() async {
        final user = await QuickLogin.loginWithFingerprint(_username.text);
        if (user != null && mounted) goHome(context, user);
      });

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final username = _username.text.trim().toLowerCase();
    final password = _password.text;
    await _run(() async {
      final masked = await api.login(username, password);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpScreen(
          maskedEmail: masked,
          verify: (code) => api.verifyLogin(username, code),
          resend: () => api.login(username, password),
        ),
      ));
    });
  }

  Future<void> _loginWithFace() async {
    final username = _username.text.trim().toLowerCase();
    if (username.isEmpty) return showError(context, 'Nhập tên đăng nhập trước, rồi bấm đăng nhập bằng khuôn mặt');
    final shots = await Navigator.of(context).push<List<List<double>>>(MaterialPageRoute(
      builder: (_) => const FaceScanScreen(title: 'Đăng nhập bằng khuôn mặt', shots: 2),
    ));
    if (shots == null || !mounted) return;
    await _run(() async {
      final user = await api.loginWithFace(username, shots);
      if (mounted) goHome(context, user);
    });
  }

  Future<void> _loginWithGoogle() => _run(() async {
        final idToken = await googleIdToken();
        if (idToken == null) return; // huỷ chọn tài khoản
        final user = await api.loginWithGoogle(idToken);
        if (mounted) goHome(context, user);
      });

  @override
  Widget build(BuildContext context) => AuthScaffold(
        icon: Icons.how_to_reg_rounded,
        title: 'Điểm danh SV',
        subtitle: 'Đăng nhập để tiếp tục',
        child: Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _username,
                  autofillHints: const [AutofillHints.username],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Tên đăng nhập',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Nhập tên đăng nhập' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _hidePassword,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _hidePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                      icon: Icon(_hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _hidePassword = !_hidePassword),
                    ),
                  ),
                  validator: (v) => (v ?? '').isEmpty ? 'Nhập mật khẩu' : null,
                ),
                const SizedBox(height: 24),
                // Nút đăng nhập + 2 biểu tượng đăng nhập nhanh cùng hàng, cùng chiều cao
                Row(children: [
                  Expanded(child: LoadingButton(label: 'Đăng nhập', loading: _loading, onPressed: _login)),
                  const SizedBox(width: 8),
                  _QuickIcon(
                    icon: Icons.face_retouching_natural,
                    tooltip: 'Đăng nhập bằng khuôn mặt',
                    onPressed: _loading ? null : _loginWithFace,
                  ),
                  if (_fingerprint) ...[
                    const SizedBox(width: 8),
                    _QuickIcon(
                      icon: Icons.fingerprint,
                      tooltip: 'Đăng nhập bằng vân tay',
                      onPressed: _loading ? null : _loginWithFingerprint,
                    ),
                  ],
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('hoặc', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _loginWithGoogle,
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 32),
                  label: const Text('Tiếp tục với Google'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('Chưa có tài khoản? Đăng ký bằng email'),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Nút vuông nhỏ cạnh nút Đăng nhập (khuôn mặt / vân tay), cao bằng nút chính.
class _QuickIcon extends StatelessWidget {
  const _QuickIcon({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        style: IconButton.styleFrom(
          fixedSize: const Size(52, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
}
