import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/crud_kit.dart';
import 'auth_widgets.dart';
import 'qr_screens.dart';

bool _isTeacher(AppUser u) => u.role == 'lecturer' || u.role == 'admin';

/// Vào thẳng màn chiếu QR của buổi; đóng QR thì về màn điểm danh của buổi đó.
/// Xong (future hoàn tất) khi rời màn buổi học.
Future<void> showSessionWithQr(BuildContext context, String sessionId) async {
  final nav = Navigator.of(context);
  final sessionClosed = nav.push(MaterialPageRoute(builder: (_) => SessionScreen(sessionId: sessionId)));
  await nav.push(MaterialPageRoute(builder: (_) => QrDisplayScreen(sessionId: sessionId)));
  await sessionClosed;
}

/// Tóm tắt TKB cho danh sách lớp: "Thứ 2 07:30, Thứ 5 13:00" hoặc "7 buổi/tuần".
String _meetingsSummary(List meetings) => meetings.length > 3
    ? '${meetings.length} buổi/tuần'
    : meetings.map((m) => '${weekdayLabels[m['weekday']]} ${m['start']}').join(', ');

// ---------------- Danh sách lớp (mọi vai trò, backend tự lọc) ----------------

class ClassesScreen extends StatefulWidget {
  const ClassesScreen({super.key, required this.me, this.title = 'Lớp học phần'});
  final AppUser me;
  final String title;

  @override
  State<ClassesScreen> createState() => _ClassesScreenState();
}

class _ClassesScreenState extends State<ClassesScreen> with ApiListState {
  bool get _isAdmin => widget.me.role == 'admin';

  @override
  Future<List> load() async => await api.get('/classes') as List;

  Future<void> _edit(Json? c) async {
    // Lấy danh sách môn và giảng viên cho 2 ô chọn
    late List subjects, lecturers;
    final ok = await runApi(context, () async {
      (subjects, lecturers) = (
        await api.get('/admin/subjects') as List,
        await api.get('/admin/users', {'role': 'lecturer'}) as List,
      );
    });
    if (!ok || !mounted) return;
    if (subjects.isEmpty || lecturers.isEmpty) {
      return showError(context, 'Cần có ít nhất 1 môn học và 1 giảng viên trước');
    }
    final saved = await showFormSheet(
      context,
      title: c == null ? 'Thêm lớp học phần' : 'Sửa lớp ${c['code']}',
      fields: [
        FieldSpec('code', 'Mã lớp', initial: c?['code'], hint: 'VD: IT008.Q11'),
        FieldSpec('subject', 'Môn học',
            kind: FieldKind.select,
            initial: c?['subject']?['id'],
            options: {for (final s in subjects) s['id']: '${s['code']} – ${s['name']}'}),
        FieldSpec('lecturer', 'Giảng viên',
            kind: FieldKind.select,
            initial: c?['lecturer']?['id'],
            options: {for (final l in lecturers) l['id']: nameOf(l)}),
        FieldSpec('room', 'Phòng', initial: c?['room'], required: false),
        FieldSpec('schedule', 'Lịch học', initial: c?['schedule'], required: false, hint: 'VD: Thứ 2, tiết 1–3'),
        FieldSpec('semester', 'Học kỳ', initial: c?['semester'], required: false, hint: 'VD: HK1 2026–2027'),
        FieldSpec('plannedSessions', 'Số buổi dự kiến',
            kind: FieldKind.number, initial: c?['plannedSessions'] ?? 15, hint: 'Vắng quá 20% số buổi sẽ bị cấm thi'),
      ],
      onSubmit: (v) async =>
          c == null ? await api.post('/admin/classes', v) : await api.patch('/admin/classes/${c['id']}', v),
    );
    if (saved) reload();
  }

  Future<void> _delete(Json c) async {
    if (!await confirmDelete(context, 'lớp ${c['code']} cùng toàn bộ buổi học và đơn nghỉ')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/admin/classes/${c['id']}'), done: 'Đã xoá')) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        floatingActionButton: _isAdmin
            ? FloatingActionButton.extended(
                onPressed: () => _edit(null), icon: const Icon(Icons.add), label: const Text('Thêm lớp'))
            : null,
        body: AsyncList(
          future: items,
          onRefresh: reload,
          emptyText: widget.me.role == 'student' ? 'Bạn chưa được ghi danh vào lớp nào' : 'Chưa có lớp học phần nào',
          itemBuilder: (context, c) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              title: Text('${c['code']} · ${c['subject']?['name'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text([
                'GV: ${nameOf(c['lecturer'])}',
                if ((c['room'] as String).isNotEmpty) 'Phòng ${c['room']}',
                if ((c['meetings'] as List? ?? const []).isNotEmpty)
                  _meetingsSummary(c['meetings'] as List)
                else if ((c['schedule'] as String).isNotEmpty)
                  c['schedule'],
                '${(c['students'] as List).length} sinh viên',
              ].join(' · ')),
              onTap: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => ClassDetailScreen(me: widget.me, classId: c['id'])));
                reload(); // sĩ số có thể đã đổi
              },
              trailing: _isAdmin
                  ? EditDeleteMenu(onEdit: () => _edit(c), onDelete: () => _delete(c))
                  : const Icon(Icons.chevron_right),
            ),
          ),
        ),
      );
}

// ---------------- Chi tiết lớp: tab Buổi học + Sinh viên ----------------

class ClassDetailScreen extends StatefulWidget {
  const ClassDetailScreen({super.key, required this.me, required this.classId});
  final AppUser me;
  final String classId;

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> with ApiListState {
  late Future<Json> _class = _loadClass();

  String get _base => '/classes/${widget.classId}';

  Future<Json> _loadClass() async => await api.get(_base) as Json;

  @override
  Future<List> load() async => await api.get('$_base/sessions') as List; // danh sách buổi học

  void _reloadClass() => setState(() {
        _class = _loadClass();
      });

  Future<void> _openSession() async {
    Json? created;
    await showFormSheet(
      context,
      title: 'Mở buổi điểm danh',
      fields: [
        FieldSpec('date', 'Ngày học', kind: FieldKind.date, initial: today()),
        const FieldSpec('topic', 'Nội dung buổi học', required: false),
      ],
      onSubmit: (v) async => created = await api.post('$_base/sessions', v) as Json,
    );
    final id = created?['id'] as String?;
    if (id == null || !mounted) return;
    if (created?['makeup'] == true) showError(context, 'Ngoài giờ trong thời khoá biểu → ghi là buổi bù');
    reload();
    await showSessionWithQr(context, id);
    if (mounted) reload();
  }

  Future<void> _addStudent(List enrolled) async {
    late List students;
    if (!await runApi(context, () async => students = await api.get('/admin/users', {'role': 'student'}) as List)) {
      return;
    }
    final ids = enrolled.map((s) => s['id']).toSet();
    final options = {for (final s in students) if (!ids.contains(s['id'])) s['id'] as String: '${nameOf(s)} (@${s['username']})'};
    if (!mounted) return;
    if (options.isEmpty) return showError(context, 'Không còn sinh viên nào để thêm');
    final saved = await showFormSheet(
      context,
      title: 'Ghi danh sinh viên',
      fields: [FieldSpec('studentId', 'Sinh viên', kind: FieldKind.select, options: options)],
      onSubmit: (v) => api.post('/admin$_base/students', v),
    );
    if (saved) _reloadClass();
  }

  Future<void> _removeStudent(Json s) async {
    if (!await confirmDelete(context, '${nameOf(s)} khỏi lớp')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/admin$_base/students/${s['id']}'))) _reloadClass();
  }

  Future<void> _deleteSession(Json s) async {
    if (!await confirmDelete(context, 'buổi ${s['date']}')) return;
    if (!mounted) return;
    if (await runApi(context, () => api.delete('/sessions/${s['id']}'), done: 'Đã xoá buổi học')) reload();
  }

  Widget _sessionTile(BuildContext context, Json s) {
    final teacher = _isTeacher(widget.me);
    final records = (s['records'] as List?) ?? const [];
    final here = records.where((r) => r['status'] == 'present' || r['status'] == 'late').length;
    return Card(
      child: ListTile(
        leading: Icon(s['open'] == true ? Icons.lock_open : Icons.lock_outline),
        title: Text(viDate(s['date']) + ((s['topic'] as String? ?? '').isEmpty ? '' : ' · ${s['topic']}')),
        subtitle: Text([
          if (teacher) 'Có mặt $here/${records.length}',
          if (teacher) s['open'] == true ? 'Đang mở' : 'Đã đóng',
          if (s['makeup'] == true) 'Buổi bù',
        ].join(' · ')),
        trailing: teacher
            ? EditDeleteMenu(onEdit: null, onDelete: () => _deleteSession(s))
            : StatusChip(s['myStatus'] as String?),
        onTap: teacher
            ? () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => SessionScreen(sessionId: s['id'])));
                reload();
              }
            : null,
      ),
    );
  }

  Widget _studentsTab(Json cls) {
    final students = (cls['students'] as List).cast<Json>();
    final isAdmin = widget.me.role == 'admin';
    return RefreshIndicator(
      onRefresh: () async => _reloadClass(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (isAdmin)
            FilledButton.tonalIcon(
              onPressed: () => _addStudent(students),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Ghi danh sinh viên'),
            ),
          if (students.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Lớp chưa có sinh viên'))),
          for (final s in students)
            ListTile(
              leading: CircleAvatar(child: Text(nameOf(s).characters.first.toUpperCase())),
              title: Text(nameOf(s)),
              subtitle: Text('@${s['username']} · ${s['email']}'),
              trailing: isAdmin
                  ? IconButton(
                      tooltip: 'Xoá khỏi lớp',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: () => _removeStudent(s),
                    )
                  : null,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
        future: _class,
        builder: (context, snap) {
          final cls = snap.data;
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text(cls == null ? 'Lớp học phần' : '${cls['code']}'),
                bottom: TabBar(tabs: [
                  const Tab(text: 'Buổi học'),
                  Tab(text: 'Sinh viên${cls == null ? '' : ' (${(cls['students'] as List).length})'}'),
                ]),
              ),
              body: snap.hasError
                  ? Center(child: Text('${snap.error}'))
                  : cls == null
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(children: [
                          AsyncList(
                            future: items,
                            onRefresh: reload,
                            emptyText: 'Chưa có buổi học nào',
                            header: _ClassHeader(cls: cls, onOpenSession: _isTeacher(widget.me) ? _openSession : null),
                            itemBuilder: _sessionTile,
                          ),
                          _studentsTab(cls),
                        ]),
            ),
          );
        },
      );
}

class _ClassHeader extends StatelessWidget {
  const _ClassHeader({required this.cls, this.onOpenSession});
  final Json cls;
  final VoidCallback? onOpenSession;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cls['subject']?['name'] ?? ''}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('Giảng viên: ${nameOf(cls['lecturer'])}'),
                if ((cls['room'] as String).isNotEmpty) Text('Phòng: ${cls['room']}'),
                if ((cls['schedule'] as String).isNotEmpty) Text('Lịch: ${cls['schedule']}'),
                if ((cls['meetings'] as List? ?? const []).isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Thời khoá biểu (${viDate(cls['startDate'])} – ${viDate(cls['endDate'])}):',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final m in cls['meetings'] as List) Text('• ${meetingText(m)}'),
                ],
                if ((cls['semester'] as String).isNotEmpty) Text('Học kỳ: ${cls['semester']}'),
                Text('Số buổi dự kiến: ${cls['plannedSessions']}'),
              ]),
            ),
          ),
          if (onOpenSession != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onOpenSession,
              icon: const Icon(Icons.playlist_add_check),
              label: const Text('Mở buổi điểm danh'),
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
}

/// Nút kiểm tra đột xuất + kết quả lượt gần nhất (kéo xuống để cập nhật).
class _SpotCheckPanel extends StatelessWidget {
  const _SpotCheckPanel({required this.session, required this.onStart});
  final Json session;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final checks = ((session['spotChecks'] as List?) ?? const []).cast<Json>();
    final last = checks.isEmpty ? null : checks.last;
    final expires = last == null ? null : DateTime.parse(last['expiresAt'] as String).toLocal();
    final running = expires != null && expires.isAfter(DateTime.now());
    final targets = ((last?['targets'] as List?) ?? const []).cast<Json>();
    final done = targets.where((t) => t['respondedAt'] != null).length;
    String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (last != null) ...[
            Text(
              running
                  ? 'Đang kiểm tra đột xuất (hạn ${hhmm(expires)}): $done/${targets.length} SV đã xác minh'
                  : 'Lượt kiểm tra lúc ${hhmm(DateTime.parse(last['startedAt'] as String).toLocal())}: '
                      '$done/${targets.length} xác minh, ${targets.length - done} rời lớp sớm',
            ),
            const SizedBox(height: 8),
          ],
          FilledButton.tonalIcon(
            onPressed: session['open'] == true && !running ? onStart : null,
            icon: const Icon(Icons.notification_important_outlined),
            label: const Text('Kiểm tra đột xuất giữa giờ'),
          ),
        ]),
      ),
    );
  }
}

// ---------------- Điểm danh 1 buổi (giảng viên) ----------------

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  static const _autoRefresh = Duration(seconds: 5);

  late Future<Json> _session = _load();
  Timer? _timer;
  bool _spotRunning = false;

  String get _path => '/sessions/${widget.sessionId}';

  @override
  void initState() {
    super.initState();
    // Đang có lượt kiểm tra đột xuất thì tự cập nhật ai đã xác minh, không cần kéo tay
    _timer = Timer.periodic(_autoRefresh, (_) {
      if (_spotRunning) _reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<Json> _load() async {
    final s = await api.get(_path) as Json;
    final checks = (s['spotChecks'] as List?) ?? const [];
    _spotRunning = checks.isNotEmpty &&
        DateTime.parse((checks.last as Json)['expiresAt'] as String).isAfter(DateTime.now());
    return s;
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _session = next;
    });
    await next.catchError((_) => <String, dynamic>{});
  }

  Future<void> _change(Future<void> Function() action) async {
    if (await runApi(context, action)) _reload();
  }

  Future<void> _startSpotCheck(Json s) async {
    final saved = await showFormSheet(
      context,
      title: 'Kiểm tra đột xuất',
      fields: [
        const FieldSpec('percent', 'Gọi ngẫu nhiên bao nhiêu SV đang có mặt',
            kind: FieldKind.select,
            initial: '50',
            options: {'30': '30%', '50': '50%', '100': 'Tất cả'},
            hint: 'SV có 2 phút để xác minh lại bằng khuôn mặt + GPS'),
      ],
      onSubmit: (v) => api.post('$_path/spot-checks', {'percent': int.parse(v['percent'] as String)}),
    );
    if (!saved || !mounted) return;
    showError(context, 'Đã gửi yêu cầu xác minh, hạn 2 phút');
    _reload();
  }

  Future<void> _editTopic(Json s) async {
    final saved = await showFormSheet(
      context,
      title: 'Sửa buổi học',
      fields: [
        FieldSpec('date', 'Ngày học', kind: FieldKind.date, initial: s['date']),
        FieldSpec('topic', 'Nội dung buổi học', initial: s['topic'], required: false),
      ],
      onSubmit: (v) => api.patch(_path, v),
    );
    if (saved) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Json>(
        future: _session,
        builder: (context, snap) {
          final s = snap.data;
          final records = ((s?['records'] as List?) ?? const []).cast<Json>();
          final count = {for (final k in attendanceLabels.keys) k: records.where((r) => r['status'] == k).length};
          return Scaffold(
            appBar: AppBar(
              title: Text(s == null ? 'Buổi học' : 'Buổi ${s['date']}'),
              actions: [
                if (s != null) ...[
                  IconButton(
                    tooltip: 'Chiếu QR',
                    icon: const Icon(Icons.qr_code_2),
                    onPressed: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => QrDisplayScreen(sessionId: widget.sessionId)));
                      _reload();
                    },
                  ),
                  IconButton(
                    tooltip: 'Bản đồ vị trí',
                    icon: const Icon(Icons.map_outlined),
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => SessionMapScreen(session: s))),
                  ),
                  IconButton(tooltip: 'Sửa', icon: const Icon(Icons.edit_outlined), onPressed: () => _editTopic(s)),
                  IconButton(
                    tooltip: s['open'] == true ? 'Đóng buổi' : 'Mở lại buổi',
                    icon: Icon(s['open'] == true ? Icons.lock_open : Icons.lock_outline),
                    onPressed: () => _change(() => api.patch(_path, {'open': s['open'] != true})),
                  ),
                ],
              ],
            ),
            body: snap.hasError
                ? Center(child: Text('${snap.error}'))
                : s == null
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          children: [
                            if ((s['topic'] as String).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: Text(s['topic'], style: Theme.of(context).textTheme.titleMedium),
                              ),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              for (final e in attendanceLabels.entries)
                                Chip(label: Text('${e.value}: ${count[e.key]}')),
                            ]),
                            const SizedBox(height: 8),
                            _SpotCheckPanel(session: s, onStart: () => _startSpotCheck(s)),
                            const SizedBox(height: 8),
                            if (records.isEmpty)
                              const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Lớp chưa có sinh viên'))),
                            for (final r in records)
                              Card(
                                child: ListTile(
                                  title: Text(nameOf(r['student'])),
                                  subtitle: Text([
                                    if (r['student'] is Map) '@${r['student']['username']}',
                                    if (r['distance'] != null) 'QR · cách ${r['distance']} m',
                                  ].join(' · ')),
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Đổi trạng thái',
                                    onSelected: (status) => _change(() =>
                                        api.patch('$_path/records/${r['student']['id']}', {'status': status})),
                                    itemBuilder: (_) => [
                                      for (final k in attendanceLabels.keys)
                                        PopupMenuItem(value: k, child: StatusChip(k)),
                                    ],
                                    child: StatusChip(r['status'] as String?),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
          );
        },
      );
}
