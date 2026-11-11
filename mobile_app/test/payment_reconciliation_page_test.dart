import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/payment_reconciliation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editing reconciliation filters invalidates allocations and successful reconcile clears them', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var reconcileCalls = 0;
    int? invoiceLimitSent;
    int? paymentLimitSent;
    double? reconciledAllocationAmount;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.pathSegments.length == 3 &&
          request.uri.pathSegments[2] == 'Account') {
        request.response.write(jsonEncode({
          'data': [{
            'name': 'Debtors - COMP-1',
            'account_type': 'Receivable',
            'account_currency': 'YER',
            'company': 'COMP-1',
          }],
        }));
      } else if (request.method == 'POST' &&
          request.uri.pathSegments.join('/') == 'api/method/run_doc_method') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
        final method = body['method'] as String;
        final document = jsonDecode(body['docs'] as String) as core.Map<String, dynamic>;
        if (method == 'get_unreconciled_entries') {
          invoiceLimitSent = document['invoice_limit'] as int?;
          paymentLimitSent = document['payment_limit'] as int?;
          document['invoices'] = [{
            'invoice_type': 'Sales Invoice',
            'invoice_number': 'SINV-1',
            'invoice_date': '2026-11-01',
            'outstanding_amount': 100,
            'currency': 'YER',
          }];
          document['payments'] = [{
            'reference_type': 'Payment Entry',
            'reference_name': 'PAY-1',
            'posting_date': '2026-11-02',
            'amount': 75,
            'currency': 'YER',
          }];
        } else if (method == 'allocate_entries') {
          document['allocation'] = [{
            'reference_type': 'Payment Entry',
            'reference_name': 'PAY-1',
            'invoice_type': 'Sales Invoice',
            'invoice_number': 'SINV-1',
            'allocated_amount': 75,
            'currency': 'YER',
          }];
        } else if (method == 'calculate_difference_on_allocation_change') {
          final args = body['args'] as core.Map<String, dynamic>;
          expect(args['allocated_amount'], 50);
          request.response.write(jsonEncode({'docs': [document], 'message': 0}));
          await request.response.close();
          return;
        } else if (method == 'reconcile') {
          reconcileCalls++;
          final allocation = document['allocation'] as List;
          reconciledAllocationAmount = (allocation.first as core.Map)['allocated_amount'] as double;
        } else {
          fail('Unexpected method: $method');
        }
        request.response.write(jsonEncode({
          'docs': [document],
          if (method == 'reconcile') 'message': 'Successfully Reconciled',
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request'}));
      }
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: PaymentReconciliationPage(
          api: api,
          companies: const [ErpCompany(name: 'COMP-1')],
        ),
      ));
      await tester.pumpAndSettle();

      final partyField = find.byType(TextField).first;
      final limits = find.byType(DropdownButtonFormField<int>);
      expect(limits, findsNWidgets(2));
      await tester.tap(limits.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500').last);
      await tester.pumpAndSettle();
      await tester.tap(limits.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('500').last);
      await tester.pumpAndSettle();
      await tester.enterText(partyField, 'CUS-1');
      await tester.tap(find.text('جلب الفواتير والمدفوعات غير المسواة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('معاينة التوزيع التلقائي حسب الأقدمية'));
      await tester.pumpAndSettle();
      expect(find.text('معاينة التخصيصات (1)'), findsOneWidget);

      await tester.enterText(partyField, 'CUS-2');
      await tester.pumpAndSettle();
      expect(find.text('معاينة التخصيصات (1)'), findsNothing);
      expect(find.text('تأكيد التخصيص وترحيل التسوية'), findsNothing);

      await tester.tap(find.text('جلب الفواتير والمدفوعات غير المسواة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('معاينة التوزيع التلقائي حسب الأقدمية'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تعديل مبلغ التخصيص'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.tap(find.text('حفظ المبلغ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد التخصيص وترحيل التسوية'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تأكيد التسوية'));
      await tester.pumpAndSettle();

      expect(invoiceLimitSent, 500);
      expect(paymentLimitSent, 500);
      expect(reconcileCalls, 1);
      expect(reconciledAllocationAmount, 50.0);
      expect(find.text('معاينة التخصيصات (1)'), findsNothing);
      expect(find.text('تأكيد التخصيص وترحيل التسوية'), findsNothing);
      expect(find.textContaining('أكد ERPNext تنفيذ التسوية'), findsOneWidget);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
