import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Địa chỉ API đã deploy. Đổi khi build: --dart-define=API_URL=https://...
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://duong-gia-huy-api.onrender.com',
);

/// Web client ID của Google Cloud (trùng GOOGLE_CLIENT_ID ở backend). Không phải bí mật.
const googleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '75402119088-8aukujb89r7m96koo09lcig17hl6fo1e.apps.googleusercontent.com',
);

class ApiException implements Exception {
  ApiException(this.message, [this.status]);
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        fullName: j['fullName'] as String? ?? '',
        role: j['role'] as String,
      );

  final String id;
  final String username;
  final String email;
  final String fullName;
  final String role; // admin | lecturer | student

  String get displayName => fullName.isEmpty ? username : fullName;
}

class Api {
  Api({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'token';
  // Render free ngủ sau 15 phút, lần gọi đầu có thể mất ~50 giây để thức dậy.
  static const _timeout = Duration(seconds: 70);

  final http.Client _client;
  final FlutterSecureStorage _storage;
  String? _token;

  Future<Map<String, dynamic>> _send(String method, String path,
      [Map<String, dynamic>? body]) async {
    final req = http.Request(method, Uri.parse('$apiUrl$path'))
      ..headers['content-type'] = 'application/json';
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _client.send(req).timeout(_timeout));
    } on TimeoutException {
      throw ApiException('Máy chủ phản hồi quá lâu, hãy thử lại');
    } on http.ClientException {
      throw ApiException('Không kết nối được máy chủ, kiểm tra mạng');
    }

    Map<String, dynamic> data;
    try {
      // JSON luôn là UTF-8; không dùng res.body vì thiếu charset thì http giải mã latin1.
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      data = {};
    }
    if (res.statusCode >= 400) {
      throw ApiException(
          data['message'] as String? ?? 'Lỗi máy chủ (${res.statusCode})',
          res.statusCode);
    }
    return data;
  }

  Future<AppUser> _saveSession(Map<String, dynamic> data) async {
    _token = data['token'] as String;
    await _storage.write(key: _tokenKey, value: _token);
    return AppUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Trả về email đã che (VD: h***@gmail.com) để hiện ở màn OTP.
  Future<String> register({
    required String email,
    required String username,
    required String password,
    required String fullName,
  }) async {
    final data = await _send('POST', '/auth/register', {
      'email': email,
      'username': username,
      'password': password,
      'fullName': fullName,
    });
    return data['email'] as String;
  }

  Future<AppUser> verifyRegister(String email, String code) async =>
      _saveSession(await _send(
          'POST', '/auth/register/verify', {'email': email, 'code': code}));

  Future<String> login(String username, String password) async {
    final data = await _send(
        'POST', '/auth/login', {'username': username, 'password': password});
    return data['email'] as String;
  }

  Future<AppUser> verifyLogin(String username, String code) async =>
      _saveSession(await _send(
          'POST', '/auth/login/verify', {'username': username, 'code': code}));

  Future<AppUser> loginWithGoogle(String idToken) async =>
      _saveSession(await _send('POST', '/auth/google', {'idToken': idToken}));

  /// Mở app: còn token hợp lệ thì vào thẳng, không thì về màn đăng nhập.
  Future<AppUser?> restoreSession() async {
    _token = await _storage.read(key: _tokenKey);
    if (_token == null) return null;
    try {
      return AppUser.fromJson(await _send('GET', '/me'));
    } on ApiException catch (e) {
      if (e.status == 401) await logout();
      return null;
    }
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
  }
}

final api = Api();
