import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/screens/admin_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), status,
    headers: {'content-type': 'application/json'});

/// Ghi lại các request gửi lên để kiểm tra body.
final sent = <String, Map<String, dynamic>>{};

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    sent.clear();
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Môn học: hiện danh sách và thêm môn gửi đúng dữ liệu', (tester) async {
    final subjects = [
      {'id': 's1', 'code': 'IT001', 'name': 'Lập trình di động', 'credits': 3},
    ];
    api = Api(client: MockClient((req) async {
      if (req.method == 'POST') {
        sent['POST ${req.url.path}'] = jsonDecode(req.body) as Map<String, dynamic>;
        subjects.add({'id': 's2', ...sent['POST ${req.url.path}']!});
        return _json(subjects.last, 201);
      }
      return _json(subjects);
    }));

    await _pump(tester, const SubjectsScreen());
    expect(find.text('Lập trình di động'), findsOneWidget);

    await tester.tap(find.text('Thêm môn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Mã môn'), 'IT002');
    await tester.enterText(find.widgetWithText(TextFormField, 'Tên môn'), '  Mạng máy tính ');
    await tester.enterText(find.widgetWithText(TextFormField, 'Số tín chỉ'), '4');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(sent['POST /admin/subjects'], {'code': 'IT002', 'name': 'Mạng máy tính', 'credits': 4});
    expect(find.text('Mạng máy tính'), findsOneWidget, reason: 'danh sách tải lại sau khi thêm');
  });

  testWidgets('Môn học: thiếu tên thì không gửi, lỗi từ API hiện trong form', (tester) async {
    api = Api(client: MockClient((req) async => req.method == 'POST'
        ? _json({'message': 'Dữ liệu bị trùng (mã hoặc tên đã tồn tại)'}, 409)
        : _json([])));

    await _pump(tester, const SubjectsScreen());
    expect(find.text('Chưa có môn học nào'), findsOneWidget);

    await tester.tap(find.text('Thêm môn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Mã môn'), 'IT001');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Không được để trống'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Tên môn'), 'Trùng');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Dữ liệu bị trùng (mã hoặc tên đã tồn tại)'), findsOneWidget);
    expect(find.text('Lưu'), findsOneWidget, reason: 'form vẫn mở để sửa lại');
  });

  testWidgets('Tài khoản: sửa không nhập mật khẩu thì không gửi password, trạng thái gửi dạng bool',
      (tester) async {
    api = Api(client: MockClient((req) async {
      if (req.method == 'PATCH') {
        sent['PATCH ${req.url.path}'] = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({});
      }
      return _json([
        {'id': 'u2', 'username': 'sv1', 'email': 'sv1@x.vn', 'fullName': 'Sinh Viên Một', 'role': 'student', 'active': true},
      ]);
    }));
    final me = AppUser(id: 'u1', username: 'admin', email: 'a@x.vn', fullName: 'Admin', role: 'admin');

    await _pump(tester, UsersScreen(me: me));
    await tester.tap(find.text('Sinh Viên Một'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    expect(sent['PATCH /admin/users/u2'], {'fullName': 'Sinh Viên Một', 'role': 'student', 'active': true});
  });
}
