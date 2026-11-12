import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/process_payment_reconciliation_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('payment reconciliation log screen renders search and status filters', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.pathSegments.join('/') == 'api/resource/Process Payment Reconciliation Log') {
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
        home: ProcessPaymentReconciliationLogPage(api: api),
      ));
      await tester.pumpAndSettle();
      expect(find.text('سجلات التسوية الآلية'), findsOneWidget);
      expect(find.text('بحث برقم السجل أو المهمة'), findsOneWidget);
      expect(find.text('حالة سجل التنفيذ'), findsOneWidget);
      expect(find.text('لا توجد سجلات تسوية مطابقة للفلاتر.'), findsOneWidget);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
