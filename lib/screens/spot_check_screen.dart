import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';
import 'face_scan_screen.dart';
import 'qr_screens.dart';

const _pollEvery = Duration(seconds: 10);

/// Bọc trang chủ sinh viên: hỏi server định kỳ, bị gọi kiểm tra đột xuất thì tự mở màn xác minh.
// ponytail: chỉ hoạt động khi app đang mở; muốn báo cả lúc tắt app thì thêm push FCM.
class SpotCheckWatcher extends StatefulWidget {
  const SpotCheckWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<SpotCheckWatcher> createState() => _SpotCheckWatcherState();
}

class _SpotCheckWatcherState extends State<SpotCheckWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  // Không hỏi khi app ở nền (đỡ tốn pin, mạng); quay lại app thì hỏi ngay.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPolling();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _check();
    _timer = Timer.periodic(_pollEvery, (_) => _check());
  }

  Future<void> _check() async {
    if (_showing) return;
    Json? pending;
    try {
      pending = await api.get('/me/spot-check') as Json?;
    } on ApiException {
      return; // mất mạng thoáng qua: lần hỏi sau thử lại
    }
    if (pending == null || !mounted || _showing) return;
    _showing = true;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SpotCheckScreen(pending: pending!),
    ));
    _showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class SpotCheckScreen extends StatefulWidget {
  const SpotCheckScreen({super.key, required this.pending});
  final Json pending;

  @override
  State<SpotCheckScreen> createState() => _SpotCheckScreenState();
}

class _SpotCheckScreenState extends State<SpotCheckScreen> {
  late final DateTime _deadline = DateTime.parse(widget.pending['expiresAt'] as String).toLocal();
  late Duration _left = _deadline.difference(DateTime.now());
  Timer? _tick;
  bool _busy = false;
  bool _done = false;
  String? _error;

  bool get _requireFace => widget.pending['requireFace'] == true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _left = _deadline.difference(DateTime.now()));
      if (_left.isNegative) _tick?.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      List<List<double>>? faces;
      if (_requireFace) {
        faces = await Navigator.of(context).push<List<List<double>>>(MaterialPageRoute(
          builder: (_) => const FaceScanScreen(title: 'Xác minh khuôn mặt', shots: 2),
        ));
        if (faces == null) return; // huỷ quét
      }
      final pos = await currentPosition();
      await api.post('/spot-checks/respond', {
        'sessionId': widget.pending['sessionId'],
        'lat': pos.latitude,
        'lng': pos.longitude,
        'mocked': pos.isMocked,
        'embeddings': ?faces,
      });
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expired = _left.isNegative && !_done;
    final seconds = _left.isNegative ? 0 : _left.inSeconds;
    final (icon, color, title) = _done
        ? (Icons.verified, Colors.green, 'Đã xác minh, bạn vẫn được tính có mặt')
        : expired
            ? (Icons.timer_off_outlined, scheme.error, 'Hết giờ – bạn bị ghi "rời lớp sớm"')
            : (Icons.notification_important, scheme.tertiary, 'Kiểm tra đột xuất!');

    return Scaffold(
      appBar: AppBar(title: const Text('Kiểm tra giữa giờ'), automaticallyImplyLeading: _done || expired),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${widget.pending['classCode']} · ${widget.pending['subject']}', textAlign: TextAlign.center),
            if (!_done && !expired) ...[
              const SizedBox(height: 24),
              Text('${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(color: color)),
              const SizedBox(height: 8),
              Text(
                _requireFace
                    ? 'Giảng viên yêu cầu xác minh bạn vẫn đang trong lớp: quét khuôn mặt và gửi vị trí GPS.'
                    : 'Giảng viên yêu cầu xác minh bạn vẫn đang trong lớp: gửi vị trí GPS.',
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _verify,
                icon: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Icon(_requireFace ? Icons.face_retouching_natural : Icons.my_location),
                label: const Text('Xác minh ngay'),
              ),
            ] else ...[
              const SizedBox(height: 24),
              OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
            ],
          ]),
        ),
      ),
    );
  }
}
