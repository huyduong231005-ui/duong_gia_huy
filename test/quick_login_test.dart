import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/device_prefs.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AppUser _user(String username) =>
    AppUser(id: username, username: username, email: '$username@x.vn', fullName: username, role: 'student');

/// Giả lập đăng nhập [username] bằng token [token] (api.token = token).
Future<void> _signIn(String username, String token) async {
  api = Api(client: MockClient((_) async => http.Response(jsonEncode({
        'id': username, 'username': username, 'email': '$username@x.vn', 'fullName': username, 'role': 'student',
      }), 200)));
  await api.loginWithToken(token);
  await QuickLogin.remember(_user(username));
}

Future<Map<String, dynamic>> _stored() async =>
    jsonDecode(await const FlutterSecureStorage().read(key: 'bio_tokens') ?? '{}') as Map<String, dynamic>;

void main() {
  test('2 tài khoản trên 1 máy: B đăng nhập không chiếm vân tay của A, B chưa bật thì không có', () async {
    // A đã tự bật vân tay trước đó
    FlutterSecureStorage.setMockInitialValues({'bio_tokens': jsonEncode({'a': 'token-a-cu'})});

    await _signIn('b', 'token-b');
    expect(await _stored(), {'a': 'token-a-cu'}, reason: 'B chưa bật nên không được lưu, A giữ nguyên');
    expect(await QuickLogin.fingerprintEnabled('a'), isTrue);
    expect(await QuickLogin.fingerprintEnabled('B '), isFalse);
    expect(await QuickLogin.lastUsername(), 'b');

    await _signIn('a', 'token-a-moi');
    expect(await _stored(), {'a': 'token-a-moi'}, reason: 'A đăng nhập lại thì làm mới phiên của chính A');
  });

  test('tắt vân tay của 1 tài khoản không ảnh hưởng tài khoản kia; hết phiên thì bỏ đúng token đó', () async {
    FlutterSecureStorage.setMockInitialValues({'bio_tokens': jsonEncode({'a': 'ta', 'b': 'tb'})});

    await QuickLogin.disableFingerprint('a');
    expect(await _stored(), {'b': 'tb'});

    await QuickLogin.forgetToken('tb');
    expect(await _stored(), isEmpty);
  });

  test('vân tay vào tài khoản chưa bật thì báo rõ tên tài khoản', () async {
    FlutterSecureStorage.setMockInitialValues({'bio_tokens': jsonEncode({'a': 'ta'})});
    await expectLater(
      QuickLogin.loginWithFingerprint('b'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('"b" chưa bật'))),
    );
  });
}
