import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';

/// Sinh viên: chuyên cần từng lớp + số buổi còn được vắng trước khi bị cấm thi.
class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> with ApiListState {
  @override
  Future<List> load() async => await api.get('/me/attendance') as List;

  Widget _item(BuildContext context, Json row) {
    final cls = row['classSection'] as Json;
    final sum = row['summary'] as Json;
    final sessions = (row['sessions'] as List).cast<Json>();
    final remaining = sum['remainingAbsences'] as int;
    final color = remaining < 0 ? Colors.red : remaining == 0 ? Colors.orange : Colors.green;
    final warning = remaining < 0
        ? 'Đã vắng quá ${-remaining} buổi – có nguy cơ cấm thi'
        : remaining == 0
            ? 'Hết lượt vắng, vắng thêm sẽ bị cấm thi'
            : 'Còn được vắng $remaining buổi';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text('${cls['code']} · ${cls['subject']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đã học ${sum['total']}/${cls['plannedSessions']} buổi · '
                'có mặt ${sum['present']} · muộn ${sum['late']} · vắng ${sum['absent']} · có phép ${sum['excused']}'),
            const SizedBox(height: 6),
            Row(children: [
              Icon(remaining > 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded, color: color, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(warning, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
            ]),
          ]),
        ),
        children: [
          if (sessions.isEmpty) const ListTile(title: Text('Chưa có buổi học nào')),
          for (final s in sessions)
            ListTile(
              dense: true,
              title: Text(s['date'] + ((s['topic'] as String).isEmpty ? '' : ' · ${s['topic']}')),
              trailing: StatusChip(s['status'] as String?),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Lịch sử chuyên cần')),
        body: AsyncList(
          future: items,
          onRefresh: reload,
          emptyText: 'Bạn chưa được ghi danh vào lớp nào',
          itemBuilder: _item,
        ),
      );
}
