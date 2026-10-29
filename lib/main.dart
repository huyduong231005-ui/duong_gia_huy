import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';

void main() => runApp(const DiemDanhApp());

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
