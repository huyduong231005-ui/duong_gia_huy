import 'package:flutter/material.dart';

import 'api.dart';
import 'google_auth.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() {
  api.onUnauthorized = (message) => logout(message: message);
  runApp(const DiemDanhApp());
}

final navigatorKey = GlobalKey<NavigatorState>();
final messengerKey = GlobalKey<ScaffoldMessengerState>();
bool _loggingOut = false;

/// Đăng xuất (cả Google) và về màn đăng nhập từ bất kỳ đâu; [message] là lý do hiện cho người dùng.
/// Nhiều request cùng gặp 401 một lúc thì chỉ chạy 1 lần.
Future<void> logout({String? message}) async {
  if (_loggingOut) return;
  _loggingOut = true;
  try {
    await api.logout();
    await googleSignOut();
    navigatorKey.currentState
        ?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    if (message != null) messengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  } finally {
    _loggingOut = false;
  }
}

const _seed = Color(0xFF0F766E); // xanh mòng két

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return ThemeData(
    colorScheme: scheme,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Điều hướng theo vai trò sau khi đăng nhập.
Widget homeFor(AppUser user) => switch (user.role) {
      'admin' => AdminHome(user: user),
      'lecturer' => LecturerHome(user: user),
      _ => StudentHome(user: user),
    };

/// Thay toàn bộ ngăn xếp màn hình (không quay lại được màn đăng nhập/OTP).
void goHome(BuildContext context, AppUser user) => Navigator.of(context)
    .pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeFor(user)), (_) => false);

class DiemDanhApp extends StatelessWidget {
  const DiemDanhApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        scaffoldMessengerKey: messengerKey,
        title: 'Điểm danh SV',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: const _StartGate(),
      );
}

class _StartGate extends StatefulWidget {
  const _StartGate();

  @override
  State<_StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<_StartGate> {
  late final Future<AppUser?> _session = api.restoreSession();

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _session,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final user = snap.data;
          return user == null ? const LoginScreen() : homeFor(user);
        },
      );
}
