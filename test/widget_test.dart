import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = {
  'id': 'u1',
  'username': 'huy',
  'email': 'huy@gmail.com',
  'fullName': 'Dương Gia Huy',
  'role': 'lecturer',
};

http.Response _json(Object body, int status) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json'});

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('xác minh OTP lưu token, lần sau mở app gọi /me kèm token', () async {
    String? authHeader;
    final client = MockClient((req) async {
      if (req.url.path == '/auth/login/verify') {
        return _json({'token': 'abc', 'user': _user}, 200);
      }
      authHeader = req.headers['authorization'];
      return _json(_user, 200);
    });

    final user = await Api(client: client).verifyLogin('huy', '123456');
    expect(user.role, 'lecturer');

    final restored = await Api(client: client).restoreSession();
    expect(restored?.username, 'huy');
    expect(authHeader, 'Bearer abc');
  });

  test('lỗi từ backend thành ApiException có message tiếng Việt', () async {
    final client = MockClient((_) async => _json({'message': 'Mã OTP không đúng'}, 400));
    await expectLater(
      Api(client: client).verifyLogin('huy', '000000'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Mã OTP không đúng')),
    );
  });

  test('token hết hạn (401) thì xoá và về màn đăng nhập', () async {
    FlutterSecureStorage.setMockInitialValues({'token': 'old'});
    final client = MockClient((_) async => http.Response('{"message":"x"}', 401));
    expect(await Api(client: client).restoreSession(), isNull);
    expect(await const FlutterSecureStorage().read(key: 'token'), isNull);
  });

  test('điều hướng đúng trang theo vai trò', () {
    AppUser as(String role) => AppUser.fromJson({..._user, 'role': role});
    expect(homeFor(as('admin')).runtimeType.toString(), 'AdminHome');
    expect(homeFor(as('lecturer')).runtimeType.toString(), 'LecturerHome');
    expect(homeFor(as('student')).runtimeType.toString(), 'StudentHome');
  });

  testWidgets('chưa đăng nhập thì hiện màn đăng nhập', (tester) async {
    await tester.pumpWidget(const DiemDanhApp());
    await tester.pumpAndSettle();
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Tiếp tục với Google'), findsOneWidget);
  });
}
