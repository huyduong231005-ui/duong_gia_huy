import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';
import 'auth_widgets.dart';

/// Sinh viên: viết / sửa / rút đơn. Giảng viên, admin: duyệt hoặc từ chối.
class LeavesScreen extends StatefulWidget {
  const LeavesScreen({super.key, required this.me});
  final AppUser me;

  @override
  State<LeavesScreen> createState() => _LeavesScreenState();
}

class _LeavesScreenState extends State<LeavesScreen> with ApiListState {
  bool get _isStudent => widget.me.role == 'student';

  @override
  Future<List> load() async => await api.get('/leaves') as List;

  Future<void> _write(Json? leave) async {
    var options = <String, String>{};
    if (leave == null) {
      late List classes;
      if (!await runApi(context, () async => classes = await api.get('/classes') as List)) return;
      options = {for (final c in classes) c['id'] as String: '${c['code']} · ${c['subject']?['name'] ?? ''}'};
      if (!mounted) return;
      if (options.isEmpty) return showError(context, 'Bạn chưa được ghi danh vào lớp nào');
    }
    final saved = await showFormSheet(
      context,
      title: leave == null ? 'Viết đơn xin nghỉ' : 'Sửa đơn xin nghỉ',
      fields: [
        if (leave == null) FieldSpec('classId', 'Lớp học phần', kind: FieldKind.select, options: options),
        FieldSpec('date', 'Ngày nghỉ', kind: FieldKind.date, initial: leave?['date'] ?? today()),
        FieldSpec('reason', 'Lý do', kind: FieldKind.multiline, initial: leave?['reason']),
      ],
      onSubmit: (v) async =>
          leave == null ? await api.post('/leaves', v) : await api.patch('/leaves/${leave['id']}', v),
    );
    if (saved) reload();
  }

  Future<void> _withdraw(Json leave) async {
    if (!await confirmDelete(context, 'đơn xin nghỉ ngày ${leave['date']}')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/leaves/${leave['id']}'), done: 'Đã rút đơn')) reload();
  }

  Future<void> _review(Json leave, String status) async {
    final ok = await runApi(context, () => api.patch('/leaves/${leave['id']}', {'status': status}),
        done: status == 'approved' ? 'Đã duyệt, buổi học ngày đó chuyển thành "có phép"' : 'Đã từ chối');
    if (ok) reload();
  }

  Widget _item(BuildContext context, Json l) {
    final cls = l['classSection'];
    final pending = l['status'] == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                cls is Map ? '${cls['code']} · ${cls['subject']?['name'] ?? ''}' : '(lớp đã xoá)',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            StatusChip(l['status'] as String?),
            if (_isStudent && pending)
              EditDeleteMenu(onEdit: () => _write(l), onDelete: () => _withdraw(l))
            else
              const SizedBox(width: 12),
          ]),
          const SizedBox(height: 4),
          Text([if (!_isStudent) nameOf(l['student']), 'Nghỉ ngày ${l['date']}'].join(' · ')),
          const SizedBox(height: 4),
          Text(l['reason'] ?? '', style: Theme.of(context).textTheme.bodyMedium),
          if (!_isStudent && pending)
            OverflowBar(alignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => _review(l, 'rejected'),
                icon: const Icon(Icons.close),
                label: const Text('Từ chối'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              ),
              TextButton.icon(
                onPressed: () => _review(l, 'approved'),
                icon: const Icon(Icons.check),
                label: const Text('Duyệt'),
              ),
            ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_isStudent ? 'Đơn xin nghỉ của tôi' : 'Duyệt đơn xin nghỉ')),
        floatingActionButton: _isStudent
            ? FloatingActionButton.extended(
                onPressed: () => _write(null), icon: const Icon(Icons.edit_note), label: const Text('Viết đơn'))
            : null,
        body: AsyncList(
          future: items,
          onRefresh: reload,
          emptyText: _isStudent ? 'Bạn chưa gửi đơn nào' : 'Không có đơn xin nghỉ nào',
          itemBuilder: _item,
        ),
      );
}
