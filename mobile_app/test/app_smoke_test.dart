import 'package:erpnext_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Arabic ERPNext login screen', (tester) async {
    await tester.pumpWidget(const ErpNextMobileApp());

    expect(find.text('ERPNext للجوال'), findsOneWidget);
    expect(find.text('رابط الخادم'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('rejects insecure non-local server URLs', (tester) async {
    await tester.pumpWidget(const ErpNextMobileApp());

    await tester.enterText(find.byType(TextField).at(0), 'http://erp.example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-user');
    await tester.enterText(find.byType(TextField).at(2), 'test-password');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(find.textContaining('أدخل رابطاً صحيحاً'), findsOneWidget);
  });
}
