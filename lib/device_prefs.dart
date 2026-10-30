// Cài đặt riêng của máy: giao diện (cỡ chữ, màu, sáng/tối) và đăng nhập nhanh (nhớ tài khoản, vân tay).
// Lưu trong flutter_secure_storage (mã hoá bằng Android Keystore) – dùng lại gói đã có, không thêm gói mới.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'api.dart';

const _storage = FlutterSecureStorage();

// ---------------- Giao diện ----------------

const seedChoices = {
  'Xanh mòng két': 0xFF0F766E,
  'Xanh dương': 0xFF1D4ED8,
  'Tím': 0xFF7C3AED,
  'Cam': 0xFFEA580C,
  'Hồng': 0xFFDB2777,
};

const textScaleChoices = {'Nhỏ': 0.9, 'Vừa': 1.0, 'Lớn': 1.15, 'Rất lớn': 1.3};

class AppSettings {
  const AppSettings({this.seed = 0xFF0F766E, this.themeMode = ThemeMode.system, this.textScale = 1.0});

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        seed: j['seed'] as int? ?? 0xFF0F766E,
        themeMode: ThemeMode.values.asNameMap()[j['themeMode']] ?? ThemeMode.system,
        textScale: (j['textScale'] as num?)?.toDouble() ?? 1.0,
      );

  final int seed;
  final ThemeMode themeMode;
  final double textScale;

  AppSettings copyWith({int? seed, ThemeMode? themeMode, double? textScale}) => AppSettings(
        seed: seed ?? this.seed,
        themeMode: themeMode ?? this.themeMode,
        textScale: textScale ?? this.textScale,
      );

  Map<String, dynamic> toJson() => {'seed': seed, 'themeMode': themeMode.name, 'textScale': textScale};
}

/// MaterialApp lắng nghe để đổi theme / cỡ chữ ngay khi người dùng chọn.
final settings = ValueNotifier(const AppSettings());

Future<void> loadSettings() async {
  final raw = await _storage.read(key: 'settings');
  if (raw != null) settings.value = AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<void> saveSettings(AppSettings value) async {
  settings.value = value;
  await _storage.write(key: 'settings', value: jsonEncode(value.toJson()));
}

// ---------------- Đăng nhập nhanh ----------------

/// Sau lần đăng nhập đầu: nhớ tên đăng nhập (cho nút khuôn mặt) và, nếu bật, giữ phiên để mở bằng vân tay.
// ponytail: phiên vân tay dùng lại JWT 7 ngày; hết hạn thì phải đăng nhập mật khẩu + OTP lại.
class QuickLogin {
  static const _usernameKey = 'last_username';
  static const _bioKey = 'bio_token';

  static Future<String?> lastUsername() => _storage.read(key: _usernameKey);

  static Future<bool> fingerprintEnabled() async => await _storage.read(key: _bioKey) != null;

  /// Gọi mỗi lần đăng nhập thành công.
  static Future<void> remember(AppUser user) async {
    await _storage.write(key: _usernameKey, value: user.username);
    final token = api.token;
    if (token != null && await fingerprintEnabled()) await _storage.write(key: _bioKey, value: token);
  }

  /// Bật: phải quét vân tay thành công mới lưu phiên.
  static Future<bool> enableFingerprint() async {
    final token = api.token;
    if (token == null) return false;
    if (!await _verify('Quét vân tay để bật đăng nhập bằng vân tay')) return false;
    await _storage.write(key: _bioKey, value: token);
    return true;
  }

  static Future<void> disableFingerprint() => _storage.delete(key: _bioKey);

  /// Đăng nhập bằng vân tay; null nếu người dùng huỷ.
  static Future<AppUser?> loginWithFingerprint() async {
    final token = await _storage.read(key: _bioKey);
    if (token == null) throw ApiException('Chưa bật đăng nhập bằng vân tay trên máy này');
    if (!await _verify('Đăng nhập duong_gia_huy bằng vân tay')) return null;
    try {
      return await api.loginWithToken(token);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await disableFingerprint();
        throw ApiException('Phiên vân tay đã hết hạn, hãy đăng nhập bằng mật khẩu rồi bật lại');
      }
      rethrow;
    }
  }

  static Future<bool> _verify(String reason) async {
    final auth = LocalAuthentication();
    if (!await auth.isDeviceSupported() || !await auth.canCheckBiometrics) {
      throw ApiException('Máy chưa cài vân tay. Hãy thêm vân tay trong Cài đặt của điện thoại');
    }
    try {
      return await auth.authenticate(localizedReason: reason, biometricOnly: true, persistAcrossBackgrounding: true);
    } on Exception catch (e) {
      throw ApiException('Không xác thực được vân tay: $e');
    }
  }
}
