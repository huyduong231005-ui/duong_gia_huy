import 'dart:convert';

import 'package:duong_gia_huy/api.dart';
import 'package:duong_gia_huy/device_prefs.dart';
import 'package:duong_gia_huy/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _me = {'id': 'u1', 'username': 'huy', 'email': 'huy@x.vn', 'fullName': 'Dương Gia Huy', 'role': 'student'};

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    settings.value = const AppSettings();
  });

  Future<Map<String, dynamic>?> pumpSettings(WidgetTester tester) async {
    Map<String, dynamic>? patched;
    api = Api(client: MockClient((req) async {
      patched = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response.bytes(utf8.encode(jsonEncode({..._me, ...patched!})), 200,
          headers: {'content-type': 'application/json'});
    }));
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(user: AppUser.fromJson(_me))));
    await tester.pumpAndSettle();
    return patched;
  }

  testWidgets('đổi cỡ chữ, nền, màu: áp dụng ngay và lưu lại', (tester) async {
    await pumpSettings(tester);
    for (final target in [find.text('Lớn'), find.text('Tối'), find.byTooltip('Tím')]) {
      await tester.ensureVisible(target); // phần Giao diện nằm dưới, cuộn tới rồi mới bấm
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    expect(settings.value.textScale, 1.15);
    expect(settings.value.themeMode, ThemeMode.dark);
    expect(settings.value.seed, seedChoices['Tím']);

    settings.value = const AppSettings();
    await loadSettings(); // đọc lại từ bộ nhớ máy
    expect(settings.value.textScale, 1.15);
    expect(settings.value.themeMode, ThemeMode.dark);
  });

  testWidgets('cập nhật họ tên gửi PATCH /me và hiện tên mới', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Dương Gia Huy'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Họ và tên'), 'Huy Mới');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Huy Mới'), findsOneWidget);
  });

  testWidgets('khuôn mặt và vân tay là tuỳ chọn, mặc định đang tắt', (tester) async {
    await pumpSettings(tester);
    final switches = tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).toList();
    expect(switches.map((s) => s.value), [false, false]);
  });
}
