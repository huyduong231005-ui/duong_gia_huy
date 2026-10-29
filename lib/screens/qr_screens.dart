import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';

const _gpsTimeout = Duration(seconds: 20);
const _defaultRadius = 100; // mét

/// Lấy vị trí hiện tại; lỗi quyền / tắt GPS báo bằng ApiException để màn hình hiện như lỗi thường.
Future<Position> currentPosition() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw ApiException('Hãy bật Vị trí (GPS) trên điện thoại');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    throw ApiException('App cần quyền Vị trí để điểm danh. Hãy cấp quyền trong Cài đặt');
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: _gpsTimeout),
    );
  } on TimeoutException {
    throw ApiException('Không lấy được vị trí, hãy ra gần cửa sổ và thử lại');
  }
}

// ---------------- Giảng viên: chiếu QR động ----------------

class QrDisplayScreen extends StatefulWidget {
  const QrDisplayScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  String? _token;
  String? _error;
  String _status = 'Đang lấy vị trí lớp học…';
  int _present = 0;
  int _total = 0;
  Timer? _timer;

  String get _path => '/sessions/${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      // Vị trí GV lúc chiếu QR là tâm vòng tròn cho phép điểm danh
      final pos = await currentPosition();
      await api.patch(_path, {'lat': pos.latitude, 'lng': pos.longitude, 'radius': _defaultRadius});
      if (mounted) setState(() => _status = 'Bán kính cho phép: $_defaultRadius m quanh vị trí của bạn');
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Lấy mã mới + sĩ số, rồi hẹn lần sau đúng lúc mã đổi.
  Future<void> _refresh() async {
    try {
      final qr = await api.get('$_path/qr') as Json;
      final session = await api.get(_path) as Json;
      final records = session['records'] as List;
      if (!mounted) return;
      setState(() {
        _token = qr['token'] as String;
        _present = records.where((r) => r['status'] == 'present' || r['status'] == 'late').length;
        _total = records.length;
        _error = null;
      });
      _timer = Timer(Duration(milliseconds: (qr['refreshInMs'] as num).toInt() + 200), _refresh);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Chiếu QR điểm danh')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            if (_error != null) ...[
              Icon(Icons.error_outline, size: 48, color: scheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  setState(() => _error = null);
                  _start();
                },
                child: const Text('Thử lại'),
              ),
            ] else if (_token == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: _token!, size: 280, backgroundColor: Colors.white),
              ),
              const SizedBox(height: 20),
              Text('$_present / $_total sinh viên đã điểm danh',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Mã tự đổi mỗi 10 giây – chụp lại gửi bạn sẽ không dùng được'),
              const SizedBox(height: 4),
              Text(_status, textAlign: TextAlign.center, style: TextStyle(color: scheme.outline)),
            ],
          ]),
        ),
      ),
    );
  }
}

// ---------------- Giảng viên: bản đồ vị trí SV đã điểm danh ----------------

class SessionMapScreen extends StatelessWidget {
  const SessionMapScreen({super.key, required this.session});
  final Json session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCenter = session['lat'] != null && session['lng'] != null;
    final shared = ((session['records'] as List).cast<Json>()).where((r) => r['lat'] != null).toList();
    final points = [for (final r in shared) LatLng((r['lat'] as num).toDouble(), (r['lng'] as num).toDouble())];
    final center = hasCenter
        ? LatLng((session['lat'] as num).toDouble(), (session['lng'] as num).toDouble())
        : points.isNotEmpty
            ? points.first
            : null;

    return Scaffold(
      appBar: AppBar(title: Text('Vị trí điểm danh · ${shared.length} SV')),
      body: center == null
          ? const Center(child: Text('Chưa có vị trí nào. Hãy chiếu QR để sinh viên điểm danh.'))
          : FlutterMap(
              options: MapOptions(initialCenter: center, initialZoom: 18),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.duonggiahuy.duong_gia_huy',
                ),
                if (hasCenter)
                  CircleLayer(circles: [
                    CircleMarker(
                      point: center,
                      radius: (session['radius'] as num? ?? _defaultRadius).toDouble(),
                      useRadiusInMeter: true,
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderColor: scheme.primary,
                      borderStrokeWidth: 2,
                    ),
                  ]),
                MarkerLayer(markers: [
                  if (hasCenter)
                    Marker(point: center, child: Icon(Icons.co_present, color: scheme.primary, size: 32)),
                  for (var i = 0; i < shared.length; i++)
                    Marker(
                      point: points[i],
                      width: 120,
                      height: 52,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: scheme.surface, borderRadius: BorderRadius.circular(8)),
                          child: Text(nameOf(shared[i]['student']),
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                        ),
                        const Icon(Icons.location_on, color: Colors.green, size: 28),
                      ]),
                    ),
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap')]),
              ],
            ),
    );
  }
}

// ---------------- Sinh viên: quét QR ----------------

class ScanCheckinScreen extends StatefulWidget {
  const ScanCheckinScreen({super.key});

  @override
  State<ScanCheckinScreen> createState() => _ScanCheckinScreenState();
}

class _ScanCheckinScreenState extends State<ScanCheckinScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _busy = false; // đang xử lý 1 mã thì bỏ qua các khung hình sau
  String _status = 'Hướng camera vào mã QR trên màn hình của giảng viên';

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final token = capture.barcodes.firstOrNull?.rawValue;
    if (_busy || token == null) return;
    setState(() {
      _busy = true;
      _status = 'Đang lấy vị trí GPS…';
    });
    try {
      final pos = await currentPosition();
      if (mounted) setState(() => _status = 'Đang gửi điểm danh…');
      final res = await api.post('/checkin', {
        'token': token,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'accuracy': pos.accuracy,
        'mocked': pos.isMocked,
      }) as Json;
      if (!mounted) return;
      await _showResult(
        ok: true,
        message: '${res['classCode']} · ${res['subject']}\nBuổi ${res['date']}'
            '${res['distance'] == null ? '' : '\nCách giảng viên ${res['distance']} m'}',
      );
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) await _showResult(ok: false, message: e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Hướng camera vào mã QR trên màn hình của giảng viên';
        });
      }
    }
  }

  Future<void> _showResult({required bool ok, required String message}) => showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? Colors.green : Theme.of(ctx).colorScheme.error, size: 48),
          title: Text(ok ? 'Điểm danh thành công' : 'Chưa điểm danh được'),
          content: Text(message, textAlign: TextAlign.center),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ok ? 'Xong' : 'Quét lại'))],
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Quét QR điểm danh')),
        body: Stack(fit: StackFit.expand, children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          // Khung ngắm
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  if (_busy)
                    const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  else
                    const Icon(Icons.qr_code_scanner),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_status)),
                ]),
              ),
            ),
          ),
        ]),
      );
}
