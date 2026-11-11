import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/financial_reports_page.dart';

void main() {
  testWidgets('inventory valuation groups Bin stock value by company currency', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = <String>[];
    server.listen((request) async {
      requested.add(request.uri.pathSegments.last);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/Warehouse')) {
        request.response.write(jsonEncode({'data': [
          {'name': 'Main - AC', 'warehouse_name': 'Main', 'company': 'Company A', 'is_group': 0},
        ]}));
      } else if (request.uri.path.endsWith('/Bin')) {
        request.response.write(jsonEncode({'data': [
          {'item_code': 'ITEM-1', 'warehouse': 'Main - AC', 'actual_qty': 4, 'stock_uom': 'Nos', 'valuation_rate': 10, 'stock_value': 40},
          {'item_code': 'ITEM-2', 'warehouse': 'Main - AC', 'actual_qty': 3, 'stock_uom': 'Nos', 'valuation_rate': 20, 'stock_value': 60},
        ]}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not found'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: Material(
          child: FinancialReportsPage(
          api: api,
          companies: const [ErpCompany(name: 'Company A', defaultCurrency: 'YER')],
          ),
        ),
      ));
      await tester.tap(find.text('فتح تقرير قيمة المخزون'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('Company A'), findsOneWidget);
      expect(find.textContaining('100.00 YER'), findsOneWidget);
      expect(find.text('ITEM-1'), findsOneWidget);
      expect(find.text('ITEM-2'), findsOneWidget);
      expect(requested, containsAll(['Warehouse', 'Bin']));

      await tester.tap(find.text('العودة إلى تقارير الذمم'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('ذمم العملاء'), findsOneWidget);
      expect(requested.where((type) => type == 'Sales Invoice').length, greaterThanOrEqualTo(2));
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

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
        home: Material(child: FinancialReportsPage(api: api, companies: const [])),
      ));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('SINV-AGING-1'), findsOneWidget);
      expect(find.textContaining('عميل تجريبي'), findsOneWidget);
      expect(find.textContaining('1250.00 YER'), findsWidgets);
      expect(find.textContaining('20.00 USD'), findsWidgets);

      await tester.tap(find.text('ذمم الموردين'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      expect(find.text('PINV-AGING-1'), findsOneWidget);
      expect(find.textContaining('مورد تجريبي'), findsOneWidget);
      expect(requestedTypes, ['Sales Invoice', 'Purchase Invoice']);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
