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
    this.hasFace = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        fullName: j['fullName'] as String? ?? '',
        role: j['role'] as String,
        hasFace: j['hasFace'] == true,
      );

  final String id;
  final String username;
  final String email;
  final String fullName;
  final String role; // admin | lecturer | student
  final bool hasFace; // đã bật đăng nhập bằng khuôn mặt

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

  /// Gọi khi đang đăng nhập mà server trả 401 (token hết hạn / tài khoản bị khoá).
  /// Ngoài /auth/*, backend chỉ trả 401 từ bước kiểm token nên không nhầm với lỗi nghiệp vụ.
  void Function(String message)? onUnauthorized;

  // CRUD chung cho các màn hình: trả về JSON đã giải mã (Map, List hoặc null khi 204).
  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, null, query);
  Future<dynamic> post(String path, Map<String, dynamic> body) => _send('POST', path, body);
  Future<dynamic> patch(String path, Map<String, dynamic> body) => _send('PATCH', path, body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Gửi nguyên file (VD: Excel) dạng nhị phân.
  Future<dynamic> upload(String path, List<int> bytes) => _send('POST', path, null, null, bytes);

  Future<dynamic> _send(String method, String path,
      [Map<String, dynamic>? body, Map<String, String>? query, List<int>? bytes]) async {
    var uri = Uri.parse('$apiUrl$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    final req = http.Request(method, uri)
      ..headers['content-type'] = 'application/json';
    if (_token != null) req.headers['authorization'] = 'Bearer $_token';
    if (body != null) req.body = jsonEncode(body);
    if (bytes != null) {
      req.headers['content-type'] = 'application/octet-stream';
      req.bodyBytes = bytes;
    }

    final http.Response res;
    try {
      res = await http.Response.fromStream(
          await _client.send(req).timeout(_timeout));
    } on TimeoutException {
      throw ApiException('Máy chủ phản hồi quá lâu, hãy thử lại');
    } on http.ClientException {
      throw ApiException('Không kết nối được máy chủ, kiểm tra mạng');
    }

    dynamic data;
    try {
      // JSON luôn là UTF-8; không dùng res.body vì thiếu charset thì http giải mã latin1.
      if (res.bodyBytes.isNotEmpty) data = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      data = null;
    }
    if (res.statusCode >= 400) {
      final message = (data is Map ? data['message'] as String? : null) ?? 'Lỗi máy chủ (${res.statusCode})';
      // /me lúc mở app đã có restoreSession xử lý riêng
      if (res.statusCode == 401 && _token != null && !path.startsWith('/auth') && path != '/me') {
        onUnauthorized?.call(message);
      }
      throw ApiException(message, res.statusCode);
    }
    return data;
  }

  Future<AppUser> _saveSession(dynamic data) async {
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
    return (data as Map)['email'] as String;
  }

  Future<AppUser> verifyRegister(String email, String code) async =>
      _saveSession(await _send(
          'POST', '/auth/register/verify', {'email': email, 'code': code}));

  Future<String> login(String username, String password) async {
    final data = await _send(
        'POST', '/auth/login', {'username': username, 'password': password});
    return (data as Map)['email'] as String;
  }

  Future<AppUser> verifyLogin(String username, String code) async =>
      _saveSession(await _send(
          'POST', '/auth/login/verify', {'username': username, 'code': code}));

  Future<AppUser> loginWithGoogle(String idToken) async =>
      _saveSession(await _send('POST', '/auth/google', {'idToken': idToken}));

  /// [embeddings]: vector của các ảnh vừa chụp; server lấy ảnh khớp nhất.
  Future<AppUser> loginWithFace(String username, List<List<double>> embeddings) async =>
      _saveSession(await _send('POST', '/auth/face', {'username': username, 'embeddings': embeddings}));

  Future<AppUser> saveFace(List<double> embedding) async =>
      AppUser.fromJson(await _send('PUT', '/me/face', {'embedding': embedding}) as Map<String, dynamic>);

  Future<AppUser> deleteFace() async =>
      AppUser.fromJson(await _send('DELETE', '/me/face') as Map<String, dynamic>);

  /// Token phiên hiện tại (để lưu cho đăng nhập vân tay).
  String? get token => _token;

  /// Dùng lại 1 phiên đã lưu (đăng nhập vân tay): kiểm tra với /me rồi lưu làm phiên hiện tại.
  Future<AppUser> loginWithToken(String token) async {
    _token = token;
    try {
      final user = AppUser.fromJson(await _send('GET', '/me') as Map<String, dynamic>);
      await _storage.write(key: _tokenKey, value: token);
      return user;
    } on ApiException {
      _token = null;
      rethrow;
    }
  }

  Future<AppUser> updateProfile(Map<String, dynamic> changes) async =>
      AppUser.fromJson(await _send('PATCH', '/me', changes) as Map<String, dynamic>);

  /// Mở app: còn token hợp lệ thì vào thẳng, không thì về màn đăng nhập.
  Future<AppUser?> restoreSession() async {
    _token = await _storage.read(key: _tokenKey);
    if (_token == null) return null;
    try {
      return AppUser.fromJson(await _send('GET', '/me') as Map<String, dynamic>);
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

// Test thay bằng Api(client: MockClient(...)) để không gọi mạng thật.
var api = Api();
