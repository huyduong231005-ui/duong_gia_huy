import 'package:flutter/material.dart';

import '../api.dart';
import '../device_prefs.dart';
import '../face/face_math.dart';
import '../widgets/crud_kit.dart';
import 'face_scan_screen.dart';

/// Cài đặt: hồ sơ cá nhân, đăng nhập nhanh (khuôn mặt, vân tay – tuỳ chọn), giao diện.
/// Đóng màn hình trả về AppUser mới nhất để trang chủ cập nhật họ tên.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _enrollShots = 5; // mẫu khuôn mặt = trung bình 5 ảnh

  late AppUser _user = widget.user;
  bool _fingerprint = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    QuickLogin.fingerprintEnabled(widget.user.username).then((v) {
      if (mounted) setState(() => _fingerprint = v);
    });
  }

  Future<void> _busyWhile(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    await runApi(context, action, done: done);
    if (mounted) setState(() => _busy = false);
  }

  // ---- Hồ sơ ----

  Future<void> _editName() async {
    await showFormSheet(
      context,
      title: 'Cập nhật hồ sơ',
      fields: [FieldSpec('fullName', 'Họ và tên', initial: _user.fullName)],
      onSubmit: (v) async {
        final user = await api.updateProfile(v);
        if (mounted) setState(() => _user = user);
      },
    );
  }

  Future<void> _changePassword() async {
    final saved = await showFormSheet(
      context,
      title: 'Đổi mật khẩu',
      fields: const [
        FieldSpec('currentPassword', 'Mật khẩu hiện tại', kind: FieldKind.password, required: false,
            hint: 'Tài khoản tạo bằng Google thì để trống'),
        FieldSpec('newPassword', 'Mật khẩu mới', kind: FieldKind.password, hint: 'Tối thiểu 6 ký tự'),
      ],
      onSubmit: (v) => api.updateProfile(v),
    );
    if (saved && mounted) showSnack('Đã đổi mật khẩu');
  }

  // ---- Đăng nhập nhanh ----

  Future<void> _toggleFace(bool on) async {
    if (!on) {
      return _busyWhile(() async {
        final user = await api.deleteFace();
        if (mounted) setState(() => _user = user);
      }, done: 'Đã tắt đăng nhập bằng khuôn mặt');
    }
    final shots = await Navigator.of(context).push<List<List<double>>>(MaterialPageRoute(
      builder: (_) => const FaceScanScreen(title: 'Đăng ký khuôn mặt', shots: _enrollShots),
    ));
    if (shots == null || !mounted) return;
    await _busyWhile(() async {
      final user = await api.saveFace(averageEmbeddings(shots));
      if (mounted) setState(() => _user = user);
    }, done: 'Đã bật đăng nhập bằng khuôn mặt');
  }

  Future<void> _toggleFingerprint(bool on) => _busyWhile(() async {
        if (on) {
          if (!await QuickLogin.enableFingerprint(_user)) return; // huỷ quét
        } else {
          await QuickLogin.disableFingerprint(_user.username);
        }
        if (mounted) setState(() => _fingerprint = on);
      }, done: on ? null : 'Đã tắt đăng nhập bằng vân tay');

  void showSnack(String text) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop(_user);
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Cài đặt'),
            bottom: _busy
                ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator())
                : null,
          ),
          body: ValueListenableBuilder(
            valueListenable: settings,
            builder: (context, s, _) => ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
              children: [
                _section('Hồ sơ cá nhân'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(_user.displayName),
                      subtitle: Text('@${_user.username} · ${_user.email}'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: _editName,
                    ),
                    ListTile(
                      leading: const Icon(Icons.lock_reset),
                      title: const Text('Đổi mật khẩu'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _changePassword,
                    ),
                  ]),
                ),
                _section('Đăng nhập nhanh (tuỳ chọn)'),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.face_retouching_natural),
                      title: const Text('Đăng nhập bằng khuôn mặt'),
                      subtitle: const Text('Chỉ lưu vector 512 số, không lưu ảnh'),
                      value: _user.hasFace,
                      onChanged: _busy ? null : _toggleFace,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.fingerprint),
                      title: const Text('Đăng nhập bằng vân tay'),
                      subtitle: Text('Riêng tài khoản @${_user.username} trên điện thoại này'),
                      value: _fingerprint,
                      onChanged: _busy ? null : _toggleFingerprint,
                    ),
                  ]),
                ),
                _section('Giao diện'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Cỡ chữ'),
                      const SizedBox(height: 8),
                      SegmentedButton<double>(
                        segments: [
                          for (final e in textScaleChoices.entries) ButtonSegment(value: e.value, label: Text(e.key)),
                        ],
                        selected: {s.textScale},
                        onSelectionChanged: (v) => saveSettings(s.copyWith(textScale: v.first)),
                      ),
                      const SizedBox(height: 20),
                      const Text('Nền'),
                      const SizedBox(height: 8),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.light, label: Text('Sáng'), icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Tối'), icon: Icon(Icons.dark_mode_outlined)),
                          ButtonSegment(value: ThemeMode.system, label: Text('Theo máy')),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (v) => saveSettings(s.copyWith(themeMode: v.first)),
                      ),
                      const SizedBox(height: 20),
                      const Text('Màu chủ đạo'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        for (final e in seedChoices.entries)
                          Tooltip(
                            message: e.key,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => saveSettings(s.copyWith(seed: e.value)),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Color(e.value),
                                child: s.seed == e.value ? const Icon(Icons.check, color: Colors.white) : null,
                              ),
                            ),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
