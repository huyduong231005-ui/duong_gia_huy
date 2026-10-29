import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';
import 'class_screens.dart';
import 'qr_screens.dart';

/// Lịch học hôm nay theo thời khoá biểu (giờ Việt Nam, server tính).
/// GV: 1 chạm mở buổi + chiếu QR. SV: biết hôm nay học gì, đã điểm danh chưa, quét QR.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.me});
  final AppUser me;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<Json> _today = _load();
  late Future<List> _rows = _rowsOf(_today); // giữ cố định giữa các lần build để danh sách không nháy

  bool get _isStudent => widget.me.role == 'student';

  Future<Json> _load() async => await api.get('/me/today') as Json;

  Future<List> _rowsOf(Future<Json> today) async => ((await today)['classes'] as List?) ?? const [];

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _today = next;
      _rows = _rowsOf(next);
    });
    await next.catchError((_) => <String, dynamic>{});
  }

  Future<void> _openSession(Json row) async {
    Json? created;
    final ok = await runApi(context, () async {
      created = await api.post('/classes/${row['classSection']['id']}/sessions', {}) as Json;
    });
    if (!ok || !mounted) return;
    await showSessionWithQr(context, created!['id'] as String);
    if (mounted) _reload();
  }

  Future<void> _push(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  Widget _action(Json row) {
    final session = row['session'] as Json?;
    final inProgress = row['inProgress'] == true;
    if (_isStudent) {
      if (session == null) return const Text('Giảng viên chưa mở điểm danh');
      final status = session['myStatus'] as String?;
      final canScan = session['open'] == true && (status == null || status == 'absent');
      return Row(children: [
        StatusChip(status),
        if (session['makeup'] == true) const Text('  Buổi bù'),
        const Spacer(),
        if (canScan)
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => _push(const ScanCheckinScreen()),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Quét QR'),
          ),
      ]);
    }
    if (session == null) {
      return FilledButton.icon(
        onPressed: () => _openSession(row),
        icon: Icon(inProgress ? Icons.qr_code_2 : Icons.event_repeat),
        label: Text(inProgress ? 'Mở buổi & chiếu QR' : 'Mở buổi bù (ngoài giờ học)'),
      );
    }
    final id = session['id'] as String;
    return session['open'] == true
        ? FilledButton.icon(
            onPressed: () async {
              await showSessionWithQr(context, id);
              if (mounted) _reload();
            },
            icon: const Icon(Icons.qr_code_2),
            label: Text(session['makeup'] == true ? 'Chiếu QR (buổi bù)' : 'Chiếu QR'),
          )
        : OutlinedButton.icon(
            onPressed: () => _push(SessionScreen(sessionId: id)),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Xem điểm danh (đã đóng)'),
          );
  }

  Widget _row(BuildContext context, Json row) {
    final cls = row['classSection'] as Json;
    final inProgress = row['inProgress'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('${cls['code']} · ${cls['subject']}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            if (inProgress)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: const Text('Đang trong giờ',
                    style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ]),
          const SizedBox(height: 4),
          for (final m in row['meetings'] as List) Text(meetingText(m, withDay: false)),
          if (_isStudent) Text('GV: ${nameOf(cls['lecturer'])}'),
          const SizedBox(height: 12),
          _action(row),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
        future: _today,
        builder: (context, snap) {
          final data = snap.data;
          return Scaffold(
            appBar: AppBar(
              title: Text(data == null
                  ? 'Hôm nay'
                  : 'Hôm nay · ${weekdayLabels[data['weekday']]}, ${viDate(data['date'] as String?)}'),
            ),
            body: AsyncList(
              future: _rows,
              onRefresh: _reload,
              emptyText: 'Hôm nay không có lịch học nào',
              itemBuilder: _row,
            ),
          );
        },
      );
}
