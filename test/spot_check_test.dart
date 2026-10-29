import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/screens/spot_check_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json'});

Future<void> _pumpWatcher(WidgetTester tester, Object? pending) async {
  api = Api(client: MockClient((_) async => _json(pending)));
  await tester.pumpWidget(const MaterialApp(home: SpotCheckWatcher(child: Text('Trang chủ SV'))));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('bị gọi kiểm tra đột xuất thì tự mở màn xác minh có đếm ngược', (tester) async {
    await _pumpWatcher(tester, {
      'sessionId': 's1',
      'expiresAt': DateTime.now().add(const Duration(seconds: 90)).toUtc().toIso8601String(),
      'classCode': 'IT001.1',
      'subject': 'Lập trình di động',
      'requireFace': true,
    });
    expect(find.text('Kiểm tra đột xuất!'), findsOneWidget);
    expect(find.text('IT001.1 · Lập trình di động'), findsOneWidget);
    expect(find.textContaining('quét khuôn mặt'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^1:[23]\d$')), findsOneWidget, reason: 'còn khoảng 1 phút rưỡi');

    await tester.pumpWidget(const SizedBox()); // huỷ các Timer
  });

  testWidgets('không bị gọi thì vẫn ở trang chủ', (tester) async {
    await _pumpWatcher(tester, null);
    expect(find.text('Trang chủ SV'), findsOneWidget);
    expect(find.text('Kiểm tra đột xuất!'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
