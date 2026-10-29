import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';

/// Ô tìm kiếm đặt dưới AppBar.
class _SearchBar extends StatelessWidget implements PreferredSizeWidget {
  const _SearchBar({required this.hint, required this.onSearch, this.extra});
  final String hint;
  final ValueChanged<String> onSearch;
  final Widget? extra;

  @override
  Size get preferredSize => Size.fromHeight(extra == null ? 64 : 112);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(children: [
          SearchBar(
            hintText: hint,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onSubmitted: onSearch,
          ),
          ?extra,
        ]),
      );
}

// ---------------- Tài khoản ----------------

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, required this.me});
  final AppUser me;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> with ApiListState {
  String _q = '';
  String? _role;

  @override
  Future<List> load() async =>
      await api.get('/admin/users', {'q': _q, 'role': ?_role}) as List;

  List<FieldSpec> _fields(Json? u) => [
        FieldSpec('fullName', 'Họ và tên', initial: u?['fullName']),
        if (u == null) ...[
          const FieldSpec('username', 'Tên đăng nhập', hint: 'Chữ thường, số, dấu _ hoặc .'),
          const FieldSpec('email', 'Email'),
        ],
        FieldSpec('password', u == null ? 'Mật khẩu' : 'Mật khẩu mới',
            kind: FieldKind.password,
            required: u == null,
            hint: u == null ? 'Tối thiểu 6 ký tự' : 'Để trống nếu không đổi'),
        if (u?['id'] != widget.me.id) ...[
          FieldSpec('role', 'Vai trò', kind: FieldKind.select, options: roleLabels, initial: u?['role'] ?? 'student'),
          if (u != null)
            FieldSpec('active', 'Trạng thái',
                kind: FieldKind.select,
                options: const {'true': 'Đang hoạt động', 'false': 'Khoá tài khoản'},
                initial: '${u['active']}'),
        ],
      ];

  Future<void> _edit(Json? u) async {
    final saved = await showFormSheet(
      context,
      title: u == null ? 'Thêm tài khoản' : 'Sửa ${nameOf(u)}',
      fields: _fields(u),
      onSubmit: (v) async {
        if (v['active'] != null) v['active'] = v['active'] == 'true';
        u == null ? await api.post('/admin/users', v) : await api.patch('/admin/users/${u['id']}', v);
      },
    );
    if (saved) reload();
  }

  Future<void> _delete(Json u) async {
    if (!await confirmDelete(context, 'tài khoản ${nameOf(u)}')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/admin/users/${u['id']}'), done: 'Đã xoá')) reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài khoản'),
        bottom: _SearchBar(
          hint: 'Tìm theo tên, email…',
          onSearch: (q) {
            _q = q.trim();
            reload();
          },
          extra: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              for (final (value, label) in [(null, 'Tất cả'), ...roleLabels.entries.map((e) => (e.key, e.value))])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _role == value,
                    onSelected: (_) {
                      _role = value;
                      reload();
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Thêm'),
      ),
      body: AsyncList(
        future: items,
        onRefresh: reload,
        emptyText: 'Không có tài khoản nào',
        itemBuilder: (context, u) {
          final active = u['active'] == true;
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: active ? scheme.primaryContainer : scheme.errorContainer,
                child: Text(nameOf(u).characters.first.toUpperCase()),
              ),
              title: Text(nameOf(u)),
              subtitle: Text('@${u['username']} · ${u['email']}\n'
                  '${roleLabels[u['role']]}${active ? '' : ' · Đã khoá'}'),
              isThreeLine: true,
              onTap: () => _edit(u),
              trailing: EditDeleteMenu(
                onEdit: () => _edit(u),
                onDelete: u['id'] == widget.me.id ? null : () => _delete(u),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------- Nhập Excel: thời khoá biểu + danh sách SV ----------------

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  static const sampleUrl = '$apiUrl/mau-import.xlsx';

  bool _busy = false;
  String? _fileName;
  Json? _result;
  String? _error;

  Future<void> _pickAndImport() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['xlsx']);
    if (files.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _fileName = files.first.name;
      _result = null;
      _error = null;
    });
    try {
      final bytes = await files.first.readAsBytes();
      final result = await api.upload('/admin/import', bytes) as Json;
      if (mounted) setState(() => _result = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = _result;
    final errors = ((r?['errors'] as List?) ?? const []).cast<String>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nhập Excel')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('File .xlsx gồm 2 sheet:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('• ThoiKhoaBieu: Mã lớp, Mã môn, Tên môn, Email GV, Tên GV, Thứ, Giờ bắt đầu, '
              'Giờ kết thúc, Phòng, Từ ngày, Đến ngày (mỗi dòng 1 buổi/tuần).'),
          const Text('• SinhVien: Mã lớp, MSSV, Họ tên, Email.'),
          const SizedBox(height: 6),
          const Text('Tài khoản mới: tên đăng nhập = MSSV (GV: phần trước @ của email), '
              'mật khẩu mặc định = tên đăng nhập. Nhập lại cùng file không tạo trùng.'),
          const SizedBox(height: 12),
          Card.outlined(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('File mẫu (20 SV, lớp demo học cả ngày)'),
              subtitle: const SelectableText(sampleUrl),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _pickAndImport,
            icon: _busy
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.upload_file),
            label: Text(_busy ? 'Đang nhập $_fileName…' : 'Chọn file Excel (.xlsx)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (r != null) ...[
            const SizedBox(height: 16),
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Đã nhập $_fileName', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('${r['subjects']} môn · ${r['lecturers']} giảng viên · ${r['classes']} lớp học phần'),
                  Text('${r['students']} sinh viên · ${r['enrollments']} lượt ghi danh'),
                  Text('${r['newAccounts']} tài khoản mới được tạo'),
                ]),
              ),
            ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${errors.length} dòng bị bỏ qua:', style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              for (final e in errors) Text('• $e'),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------- Môn học ----------------

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> with ApiListState {
  String _q = '';

  @override
  Future<List> load() async => await api.get('/admin/subjects', {'q': _q}) as List;

  Future<void> _edit(Json? s) async {
    final saved = await showFormSheet(
      context,
      title: s == null ? 'Thêm môn học' : 'Sửa môn ${s['code']}',
      fields: [
        FieldSpec('code', 'Mã môn', initial: s?['code'], hint: 'VD: IT008'),
        FieldSpec('name', 'Tên môn', initial: s?['name']),
        FieldSpec('credits', 'Số tín chỉ', kind: FieldKind.number, initial: s?['credits'] ?? 3),
      ],
      onSubmit: (v) async =>
          s == null ? await api.post('/admin/subjects', v) : await api.patch('/admin/subjects/${s['id']}', v),
    );
    if (saved) reload();
  }

  Future<void> _delete(Json s) async {
    if (!await confirmDelete(context, 'môn ${s['name']}')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/admin/subjects/${s['id']}'), done: 'Đã xoá')) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Môn học'),
          bottom: _SearchBar(
            hint: 'Tìm theo mã hoặc tên môn…',
            onSearch: (q) {
              _q = q.trim();
              reload();
            },
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(null),
          icon: const Icon(Icons.add),
          label: const Text('Thêm môn'),
        ),
        body: AsyncList(
          future: items,
          onRefresh: reload,
          emptyText: 'Chưa có môn học nào',
          itemBuilder: (context, s) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${s['credits']}')),
              title: Text(s['name']),
              subtitle: Text('${s['code']} · ${s['credits']} tín chỉ'),
              onTap: () => _edit(s),
              trailing: EditDeleteMenu(onEdit: () => _edit(s), onDelete: () => _delete(s)),
            ),
          ),
        ),
      );
}
