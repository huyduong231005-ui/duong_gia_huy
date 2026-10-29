import 'package:flutter/material.dart';

import '../api.dart';
import 'admin_screens.dart';
import 'attendance_history_screen.dart';
import 'class_screens.dart';
import 'leaves_screen.dart';
import 'login_screen.dart';

/// Ô chức năng trên trang chủ; [open] null = chưa làm (QR, thống kê… gắn ở bước sau).
typedef HomeItem = (IconData icon, String label, Widget Function()? open);

class AdminHome extends StatelessWidget {
  const AdminHome({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => _RoleHome(
        user: user,
        title: 'Trang quản trị',
        roleLabel: 'Quản trị viên',
        icon: Icons.admin_panel_settings_outlined,
        items: [
          (Icons.people_alt_outlined, 'Tài khoản', () => UsersScreen(me: user)),
          (Icons.menu_book_outlined, 'Môn học', () => const SubjectsScreen()),
          (Icons.class_outlined, 'Lớp học phần\n& ghi danh', () => ClassesScreen(me: user)),
          (Icons.fact_check_outlined, 'Đơn xin nghỉ', () => LeavesScreen(me: user)),
        ],
      );
}

class LecturerHome extends StatelessWidget {
  const LecturerHome({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => _RoleHome(
        user: user,
        title: 'Dashboard giảng viên',
        roleLabel: 'Giảng viên',
        icon: Icons.co_present_outlined,
        items: [
          (Icons.class_outlined, 'Lớp của tôi\n& điểm danh', () => ClassesScreen(me: user, title: 'Lớp của tôi')),
          (Icons.fact_check_outlined, 'Duyệt đơn nghỉ', () => LeavesScreen(me: user)),
          (Icons.qr_code_2, 'Điểm danh QR', null),
          (Icons.insights_outlined, 'Thống kê', null),
        ],
      );
}

class StudentHome extends StatelessWidget {
  const StudentHome({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => _RoleHome(
        user: user,
        title: 'Sinh viên',
        roleLabel: 'Sinh viên',
        icon: Icons.school_outlined,
        items: [
          (Icons.calendar_month_outlined, 'Lớp & lịch học', () => ClassesScreen(me: user, title: 'Lớp của tôi')),
          (Icons.history, 'Lịch sử chuyên cần', () => const AttendanceHistoryScreen()),
          (Icons.edit_note, 'Xin nghỉ phép', () => LeavesScreen(me: user)),
          (Icons.qr_code_scanner, 'Quét QR điểm danh', null),
        ],
      );
}

class _RoleHome extends StatelessWidget {
  const _RoleHome({
    required this.user,
    required this.title,
    required this.roleLabel,
    required this.icon,
    required this.items,
  });

  final AppUser user;
  final String title;
  final String roleLabel;
  final IconData icon;
  final List<HomeItem> items;

  Future<void> _logout(BuildContext context) async {
    await api.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  void _open(BuildContext context, HomeItem item) {
    final (_, label, open) = item;
    if (open == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label: đang phát triển')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => open()));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.primaryContainer,
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primary,
                child: Icon(icon, color: scheme.onPrimary),
              ),
              title: Text('Xin chào, ${user.displayName}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('$roleLabel · ${user.email}'),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              for (final item in items)
                Card.outlined(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _open(context, item),
                    child: Opacity(
                      opacity: item.$3 == null ? 0.5 : 1,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(item.$1, size: 34, color: scheme.primary),
                          const SizedBox(height: 10),
                          Text(item.$2, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
