import 'package:flutter/material.dart';

import '../api.dart';
import 'login_screen.dart';

// ponytail: 3 trang chủ mới là khung theo vai trò; các mục CRUD và chức năng nâng cao gắn vào ở bước sau.

class AdminHome extends StatelessWidget {
  const AdminHome({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) => _RoleHome(
        user: user,
        title: 'Trang quản trị',
        roleLabel: 'Quản trị viên',
        icon: Icons.admin_panel_settings_outlined,
        items: const [
          (Icons.people_alt_outlined, 'Tài khoản'),
          (Icons.menu_book_outlined, 'Môn học'),
          (Icons.class_outlined, 'Lớp học phần'),
          (Icons.group_add_outlined, 'Ghi danh'),
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
        items: const [
          (Icons.qr_code_2, 'Mở buổi điểm danh'),
          (Icons.class_outlined, 'Lớp của tôi'),
          (Icons.fact_check_outlined, 'Đơn xin nghỉ'),
          (Icons.insights_outlined, 'Thống kê'),
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
        items: const [
          (Icons.qr_code_scanner, 'Quét QR điểm danh'),
          (Icons.calendar_month_outlined, 'Lịch học'),
          (Icons.history, 'Lịch sử chuyên cần'),
          (Icons.edit_note, 'Xin nghỉ phép'),
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
  final List<(IconData, String)> items;

  Future<void> _logout(BuildContext context) async {
    await api.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
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
              for (final (itemIcon, label) in items)
                Card.outlined(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$label: đang phát triển'))),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(itemIcon, size: 34, color: scheme.primary),
                        const SizedBox(height: 10),
                        Text(label, textAlign: TextAlign.center),
                      ],
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
