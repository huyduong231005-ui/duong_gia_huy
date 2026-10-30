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
/// Phiên vân tay lưu RIÊNG từng tài khoản: 2 tài khoản trên 1 máy không ghi đè nhau,
/// tài khoản nào tự bật thì mới dùng được.
// ponytail: phiên vân tay dùng lại JWT 7 ngày; hết hạn thì phải đăng nhập mật khẩu + OTP lại.
class QuickLogin {
  static const _usernameKey = 'last_username';
  static const _bioKey = 'bio_tokens'; // JSON {tên đăng nhập: token}

  static Future<String?> lastUsername() => _storage.read(key: _usernameKey);

  static Future<Map<String, String>> _tokens() async {
    final raw = await _storage.read(key: _bioKey);
    return raw == null ? {} : (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  static Future<void> _saveTokens(Map<String, String> tokens) =>
      _storage.write(key: _bioKey, value: jsonEncode(tokens));

  static Future<bool> fingerprintEnabled(String username) async =>
      (await _tokens()).containsKey(username.trim().toLowerCase());

  /// Gọi mỗi lần đăng nhập thành công: chỉ làm mới phiên vân tay nếu CHÍNH tài khoản này đã bật.
  static Future<void> remember(AppUser user) async {
    await _storage.write(key: _usernameKey, value: user.username);
    final tokens = await _tokens();
    final token = api.token;
    if (token != null && tokens.containsKey(user.username)) {
      await _saveTokens({...tokens, user.username: token});
    }
  }

  /// Bật cho tài khoản đang đăng nhập: phải quét vân tay thành công mới lưu phiên.
  static Future<bool> enableFingerprint(AppUser user) async {
    final token = api.token;
    if (token == null) return false;
    if (!await _verify('Quét vân tay để bật đăng nhập bằng vân tay')) return false;
    await _saveTokens({...await _tokens(), user.username: token});
    return true;
  }

  static Future<void> disableFingerprint(String username) async =>
      _saveTokens({...await _tokens()}..remove(username));

  /// Bị đăng xuất bắt buộc (hết phiên / bị khoá): bỏ phiên vân tay đang dùng token đó.
  static Future<void> forgetToken(String? token) async {
    if (token == null) return;
    await _saveTokens({...await _tokens()}..removeWhere((_, t) => t == token));
  }

  /// Đăng nhập bằng vân tay vào [username]; null nếu người dùng huỷ.
  static Future<AppUser?> loginWithFingerprint(String username) async {
    final name = username.trim().toLowerCase();
    final token = (await _tokens())[name];
    if (token == null) throw ApiException('Tài khoản "$name" chưa bật đăng nhập bằng vân tay trên máy này');
    if (!await _verify('Đăng nhập $name bằng vân tay')) return null;
    try {
      return await api.loginWithToken(token);
    } on ApiException catch (e) {
      if (e.status == 401) {
        await disableFingerprint(name);
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
