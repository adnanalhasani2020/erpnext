import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/process_payment_reconciliation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('background payment reconciliation screen renders job filters and creation form', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.pathSegments.join('/') == 'api/resource/Process Payment Reconciliation') {
        request.response.write(jsonEncode({'data': []}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request'}));
      }
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: ProcessPaymentReconciliationPage(
          api: api,
          companies: const [ErpCompany(name: 'COMP-1')],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('التسوية الآلية للمدفوعات'), findsOneWidget);
      expect(find.text('تصفية حسب الشركة'), findsOneWidget);
      expect(find.text('تصفية حالة المهمة'), findsOneWidget);
      expect(find.text('إنشاء مهمة تسوية جماعية'), findsOneWidget);
      expect(find.text('لا توجد مهام تسوية مطابقة للفلاتر.'), findsOneWidget);

      await tester.tap(find.text('إنشاء مهمة تسوية جماعية'));
      await tester.pumpAndSettle();
      expect(find.text('رمز الطرف'), findsOneWidget);
      expect(find.text('حساب الذمم'), findsOneWidget);
      expect(find.text('حفظ مسودة المهمة'), findsOneWidget);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
