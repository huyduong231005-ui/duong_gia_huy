import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/screens/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _row(String code, {required bool inProgress, Map<String, dynamic>? session}) => {
      'classSection': {'id': code, 'code': code, 'subject': 'Môn $code', 'lecturer': {'username': 'gv', 'fullName': 'Thầy A'}},
      'meetings': [
        {'weekday': 4, 'start': '07:30', 'end': '09:45', 'room': 'A2.03'},
      ],
      'inProgress': inProgress,
      'session': ?session,
    };

Future<void> _pump(WidgetTester tester, String role, List<Map<String, dynamic>> rows) async {
  api = Api(client: MockClient((_) async => http.Response.bytes(
      utf8.encode(jsonEncode({'date': '2026-10-29', 'weekday': 4, 'classes': rows})), 200,
      headers: {'content-type': 'application/json'})));
  final me = AppUser(id: 'u', username: 'u', email: 'u@x.vn', fullName: 'U', role: role);
  await tester.pumpWidget(MaterialApp(home: TodayScreen(me: me)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('GV: trong giờ thì mở buổi chính thức, ngoài giờ thì mở buổi bù, đã mở thì chiếu QR', (tester) async {
    await _pump(tester, 'lecturer', [
      _row('IT008.DEMO', inProgress: true),
      _row('IT008.Q11', inProgress: false),
      _row('SE104.Q12', inProgress: true, session: {'id': 's1', 'open': true, 'makeup': false}),
    ]);
    expect(find.text('Hôm nay · Thứ 5, 29/10/2026'), findsOneWidget);
    expect(find.text('Đang trong giờ'), findsNWidgets(2));
    expect(find.text('Mở buổi & chiếu QR'), findsOneWidget);
    expect(find.text('Mở buổi bù (ngoài giờ học)'), findsOneWidget);
    expect(find.text('Chiếu QR'), findsOneWidget);
    expect(find.text('07:30–09:45 · Phòng A2.03'), findsNWidgets(3));
  });

  testWidgets('SV: buổi đang mở mà chưa điểm danh thì có nút Quét QR, đã có mặt thì không', (tester) async {
    await _pump(tester, 'student', [
      _row('IT008.DEMO', inProgress: true, session: {'id': 's1', 'open': true, 'makeup': false, 'myStatus': 'absent'}),
      _row('SE104.Q12', inProgress: true, session: {'id': 's2', 'open': true, 'makeup': false, 'myStatus': 'present'}),
      _row('IT008.Q11', inProgress: false),
    ]);
    expect(find.text('Quét QR'), findsOneWidget);
    expect(find.text('Có mặt'), findsOneWidget);
    expect(find.text('Giảng viên chưa mở điểm danh'), findsOneWidget);
    expect(find.text('GV: Thầy A'), findsNWidgets(3));
  });

  testWidgets('không có lịch hôm nay', (tester) async {
    await _pump(tester, 'student', []);
    expect(find.text('Hôm nay không có lịch học nào'), findsOneWidget);
  });
}
