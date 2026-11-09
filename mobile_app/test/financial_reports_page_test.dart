import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/financial_reports_page.dart';

void main() {
  testWidgets('financial aging report loads receivables and switches to payables', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedTypes = <String>[];
    server.listen((request) async {
      final segments = request.uri.pathSegments;
      final doctype = segments.last;
      requestedTypes.add(doctype);
      expect(request.method, 'GET');
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, contains(['docstatus', '=', 1]));
      expect(filters, contains(['outstanding_amount', '>', 0]));
      expect(filters, contains(['is_return', '=', 0]));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': doctype == 'Sales Invoice'
            ? [
                {
                  'name': 'SINV-AGING-1',
                  'customer': 'CUST-1',
                  'customer_name': 'عميل تجريبي',
                  'company': 'Company A',
                  'due_date': '2026-10-01',
                  'currency': 'YER',
                  'outstanding_amount': 1250,
                },
                {
                  'name': 'SINV-AGING-2',
                  'customer': 'CUST-2',
                  'company': 'Company A',
                  'due_date': '2099-01-01',
                  'currency': 'USD',
                  'outstanding_amount': 20,
                },
              ]
            : [
                {
                  'name': 'PINV-AGING-1',
                  'supplier': 'SUP-1',
                  'supplier_name': 'مورد تجريبي',
                  'company': 'Company A',
                  'due_date': '2026-10-01',
                  'currency': 'YER',
                  'outstanding_amount': 800,
                },
              ],
      }));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: FinancialReportsPage(api: api, companies: const []),
      ));
      await tester.pumpAndSettle();
      expect(find.text('SINV-AGING-1'), findsOneWidget);
      expect(find.text('عميل تجريبي'), findsOneWidget);
      expect(find.textContaining('1250.00 YER'), findsOneWidget);
      expect(find.textContaining('20.00 USD'), findsOneWidget);

      await tester.tap(find.text('ذمم الموردين'));
      await tester.pumpAndSettle();
      expect(find.text('PINV-AGING-1'), findsOneWidget);
      expect(find.text('مورد تجريبي'), findsOneWidget);
      expect(requestedTypes, ['Sales Invoice', 'Purchase Invoice']);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
