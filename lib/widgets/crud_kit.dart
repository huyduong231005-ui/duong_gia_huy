import 'package:flutter/material.dart';

import '../api.dart';
import '../screens/auth_widgets.dart';

typedef Json = Map<String, dynamic>;

const roleLabels = {'admin': 'Quản trị', 'lecturer': 'Giảng viên', 'student': 'Sinh viên'};
const attendanceLabels = {
  'present': 'Có mặt',
  'late': 'Đi muộn',
  'absent': 'Vắng',
  'excused': 'Có phép',
  'left': 'Rời lớp sớm', // không xác minh kịp khi kiểm tra đột xuất
};
const leaveLabels = {'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Từ chối'};

const _statusColors = {
  'present': Colors.green,
  'approved': Colors.green,
  'late': Colors.orange,
  'pending': Colors.orange,
  'absent': Colors.red,
  'rejected': Colors.red,
  'excused': Colors.blue,
  'left': Colors.purple,
};

/// Ngày hôm nay dạng YYYY-MM-DD (giờ máy).
String today() => DateTime.now().toIso8601String().substring(0, 10);

/// Tên hiển thị của 1 user trả về từ API (có thể null nếu đã bị xoá).
String nameOf(dynamic user) {
  if (user is! Map) return '(đã xoá)';
  final full = (user['fullName'] as String?) ?? '';
  return full.isEmpty ? user['username'] as String : full;
}

/// Gọi API, báo lỗi bằng SnackBar. Trả về true nếu thành công.
Future<bool> runApi(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (done != null && context.mounted) showError(context, done);
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

Future<bool> confirmDelete(BuildContext context, String what) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xoá'),
        content: Text('Xoá $what? Thao tác này không hoàn tác được.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    ) ??
    false;

/// State có 1 danh sách tải từ API, tải lại khi kéo xuống hoặc sau khi sửa.
mixin ApiListState<T extends StatefulWidget> on State<T> {
  late Future<List> items = load();

  Future<List> load();

  Future<void> reload() async {
    final next = load();
    setState(() {
      items = next; // không dùng "=>": setState báo lỗi nếu closure trả về Future
    });
    try {
      await next;
    } on ApiException {
      // lỗi đã hiện trong AsyncList
    }
  }
}

/// Danh sách từ API: vòng tải, lỗi + nút thử lại, trạng thái trống, kéo để tải lại.
class AsyncList extends StatelessWidget {
  const AsyncList({
    super.key,
    required this.future,
    required this.onRefresh,
    required this.itemBuilder,
    this.emptyText = 'Chưa có dữ liệu',
    this.header,
  });

  final Future<List> future;
  final Future<void> Function() onRefresh;
  final Widget Function(BuildContext context, Json item) itemBuilder;
  final String emptyText;
  final Widget? header;

  @override
  Widget build(BuildContext context) => FutureBuilder<List>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text('${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: onRefresh, child: const Text('Thử lại')),
                ]),
              ),
            );
          }
          final list = snap.data!.cast<Json>();
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
              children: [
                ?header,
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 64),
                    child: Column(children: [
                      Icon(Icons.inbox_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(emptyText, textAlign: TextAlign.center),
                    ]),
                  )
                else
                  for (final item in list) itemBuilder(context, item),
              ],
            ),
          );
        },
      );
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColors[status] ?? Colors.grey;
    final label = attendanceLabels[status] ?? leaveLabels[status] ?? 'Chưa có';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

/// Menu "⋮" Sửa / Xoá dùng cho các dòng CRUD.
class EditDeleteMenu extends StatelessWidget {
  const EditDeleteMenu({super.key, required this.onEdit, required this.onDelete});
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
        tooltip: 'Tuỳ chọn',
        onSelected: (action) => action(),
        itemBuilder: (_) => [
          if (onEdit != null)
            PopupMenuItem(
              value: onEdit,
              child: const ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa')),
            ),
          if (onDelete != null)
            PopupMenuItem(
              value: onDelete,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                title: Text('Xoá', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ),
        ],
      );
}

// ---------------- Form nhập liệu dạng bottom sheet ----------------

enum FieldKind { text, number, password, multiline, date, select }

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.initial,
    this.options = const {},
    this.required = true,
    this.hint,
  });

  final String key;
  final String label;
  final FieldKind kind;
  final Object? initial;
  final Map<String, String> options; // value → nhãn, cho FieldKind.select
  final bool required;
  final String? hint;
}

/// Mở form; [onSubmit] lỗi thì hiện lỗi ngay trong form và giữ form mở.
/// Trả về true nếu đã lưu thành công.
Future<bool> showFormSheet(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required Future<void> Function(Json values) onSubmit,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormSheet(title: title, fields: fields, onSubmit: onSubmit),
    ) ??
    false;

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.title, required this.fields, required this.onSubmit});
  final String title;
  final List<FieldSpec> fields;
  final Future<void> Function(Json values) onSubmit;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _text = {
    for (final f in widget.fields)
      if (f.kind != FieldKind.select) f.key: TextEditingController(text: f.initial?.toString() ?? ''),
  };
  late final Map<String, String?> _selected = {
    for (final f in widget.fields)
      if (f.kind == FieldKind.select) f.key: f.initial?.toString(),
  };
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Json _values() => {
        for (final f in widget.fields)
          if (f.kind == FieldKind.select)
            f.key: _selected[f.key]
          else if (f.kind == FieldKind.number)
            f.key: int.tryParse(_text[f.key]!.text.trim())
          else if (f.kind != FieldKind.password || _text[f.key]!.text.isNotEmpty)
            f.key: f.kind == FieldKind.password ? _text[f.key]!.text : _text[f.key]!.text.trim(),
      };

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_values());
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate(TextEditingController c) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(c.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) c.text = picked.toIso8601String().substring(0, 10);
  }

  String? _required(FieldSpec f, String? v) =>
      f.required && (v == null || v.trim().isEmpty) ? 'Không được để trống' : null;

  Widget _field(FieldSpec f) {
    final deco = InputDecoration(labelText: f.label, helperText: f.hint);
    switch (f.kind) {
      case FieldKind.select:
        return DropdownButtonFormField<String>(
          initialValue: f.options.containsKey(_selected[f.key]) ? _selected[f.key] : null,
          isExpanded: true,
          decoration: deco,
          items: [
            for (final e in f.options.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => _selected[f.key] = v,
          validator: (v) => _required(f, v),
        );
      case FieldKind.date:
        return TextFormField(
          controller: _text[f.key],
          readOnly: true,
          decoration: deco.copyWith(suffixIcon: const Icon(Icons.calendar_today_outlined)),
          onTap: () => _pickDate(_text[f.key]!),
          validator: (v) => _required(f, v),
        );
      case FieldKind.number:
        return TextFormField(
          controller: _text[f.key],
          keyboardType: TextInputType.number,
          decoration: deco,
          validator: (v) => _required(f, v) ??
              (v!.trim().isNotEmpty && int.tryParse(v.trim()) == null ? 'Phải là số nguyên' : null),
        );
      case FieldKind.password || FieldKind.text || FieldKind.multiline:
        return TextFormField(
          controller: _text[f.key],
          obscureText: f.kind == FieldKind.password,
          minLines: f.kind == FieldKind.multiline ? 3 : 1,
          maxLines: f.kind == FieldKind.multiline ? 6 : 1,
          decoration: deco,
          validator: (v) => _required(f, v),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                for (final f in widget.fields) ...[_field(f), const SizedBox(height: 12)],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                LoadingButton(label: 'Lưu', loading: _saving, onPressed: _submit),
              ],
            ),
          ),
        ),
      );
}
