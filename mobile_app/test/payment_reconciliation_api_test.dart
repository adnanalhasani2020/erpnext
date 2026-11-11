import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('payment reconciliation loads entries, previews FIFO allocation, then confirms reconcile', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.pathSegments, ['api', 'method', 'run_doc_method']);
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
      final method = body['method'] as String;
      calls.add(method);
      final document = jsonDecode(body['docs'] as String) as core.Map<String, dynamic>;
      expect(document['doctype'], 'Payment Reconciliation');
      expect(document['company'], 'COMP-1');
      expect(document['party_type'], 'Customer');
      expect(document['party'], 'CUS-1');
      if (method == 'get_unreconciled_entries') {
        expect(document['receivable_payable_account'], 'Debtors - COMP-1');
        expect(document['bank_cash_account'], 'Cash - COMP-1');
        expect(document['default_advance_account'], 'Advances - COMP-1');
        expect(document['cost_center'], 'Main - COMP-1');
        expect(document['project'], 'PRJ-1');
        expect(document['invoice_name'], 'SINV-7');
        expect(document['payment_name'], 'PAY-8');
        expect(document['minimum_invoice_amount'], 10);
        expect(document['maximum_invoice_amount'], 900);
        expect(document['minimum_payment_amount'], 5);
        expect(document['maximum_payment_amount'], 800);
        document['invoices'] = [{
          'invoice_type': 'Sales Invoice',
          'invoice_number': 'SINV-1',
          'outstanding_amount': 100,
          'currency': 'YER',
        }];
        document['payments'] = [{
          'reference_type': 'Payment Entry',
          'reference_name': 'PAY-1',
          'amount': 75,
          'currency': 'YER',
        }];
      } else if (method == 'allocate_entries') {
        final args = body['args'] as core.Map<String, dynamic>;
        expect(args['invoices'], isA<List>());
        expect(args['payments'], isA<List>());
        expect((args['invoices'] as List).single['invoice_number'], 'SINV-1');
        expect((args['payments'] as List).single['reference_name'], 'PAY-1');
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
        expect(args['payment_entry'], isA<List>());
        expect(args['invoice'], isA<List>());
        expect(args['allocated_amount'], 50);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'docs': [document], 'message': 0}));
        await request.response.close();
        return;
      } else if (method == 'reconcile') {
        expect(document['allocation'], isA<List>());
      } else {
        fail('Unexpected Payment Reconciliation method: $method');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'docs': [document],
        if (method == 'reconcile') 'message': 'Successfully Reconciled',
      }));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final loaded = await api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Customer',
        party: 'CUS-1',
        receivablePayableAccount: 'Debtors - COMP-1',
        bankCashAccount: 'Cash - COMP-1',
        defaultAdvanceAccount: 'Advances - COMP-1',
        costCenter: 'Main - COMP-1',
        project: 'PRJ-1',
        invoiceName: 'SINV-7',
        paymentName: 'PAY-8',
        minimumInvoiceAmount: 10,
        maximumInvoiceAmount: 900,
        minimumPaymentAmount: 5,
        maximumPaymentAmount: 800,
      );
      expect((loaded['invoices'] as List).length, 1);
      expect((loaded['payments'] as List).length, 1);
      final allocated = await api.allocatePaymentReconciliation(
        loaded,
        selectedInvoiceNumbers: const ['SINV-1'],
        selectedPaymentReferences: const ['PAY-1'],
      );
      expect((allocated['allocation'] as List).length, 1);
      final difference = await api.calculatePaymentReconciliationDifference(
        document: allocated,
        allocation: core.Map<String, dynamic>.from((allocated['allocation'] as List).first as core.Map),
        allocatedAmount: 50,
      );
      expect(difference, 0);
      final reconciled = await api.reconcilePaymentAllocations(allocated);
      expect(reconciled['doctype'], 'Payment Reconciliation');
      expect(calls, [
        'get_unreconciled_entries',
        'allocate_entries',
        'calculate_difference_on_allocation_change',
        'reconcile',
      ]);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('employee payment reconciliation uses the native receivable/payable account filters', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/Account')) {
        final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
        expect(
          filters.any((row) => jsonEncode(row) == jsonEncode(['account_type', 'in', ['Receivable', 'Payable']])),
          isTrue,
        );
        expect(
          filters.any((row) => jsonEncode(row) == jsonEncode(['root_type', 'in', ['Asset', 'Liability']])),
          isTrue,
        );
        request.response.write(jsonEncode({'data': [{
          'name': 'Employee Payable - COMP-1',
          'account_type': 'Payable',
          'root_type': 'Liability',
          'account_currency': 'YER',
          'company': 'COMP-1',
        }]}));
      } else if (request.method == 'POST' &&
          request.uri.pathSegments.join('/') == 'api/method/run_doc_method') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
        final document = jsonDecode(body['docs'] as String) as core.Map<String, dynamic>;
        expect(document['party_type'], 'Employee');
        expect(document['party'], 'HR-EMP-0001');
        document['invoices'] = <core.Map<String, dynamic>>[];
        document['payments'] = <core.Map<String, dynamic>>[];
        request.response.write(jsonEncode({'docs': [document]}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final accounts = await api.fetchReconciliationAccounts(
        company: 'COMP-1',
        partyType: 'Employee',
      );
      expect(accounts.single['account_type'], 'Payable');
      final document = await api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Employee',
        party: 'HR-EMP-0001',
        receivablePayableAccount: 'Employee Payable - COMP-1',
      );
      expect(document['party_type'], 'Employee');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('payment reconciliation discovers and validates configured accounting dimensions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.pathSegments.join('/');
      if (request.method == 'POST' &&
          path.endsWith('/payment_reconciliation.get_queries_for_dimension_filters')) {
        request.response.write(jsonEncode({'message': [{
          'fieldname': 'business_unit',
          'filters': {'company': 'COMP-1'},
        }]}));
      } else if (request.method == 'GET' &&
          path == 'api/method/frappe.desk.form.load.getdoctype') {
        request.response.write(jsonEncode({'message': {'docs': [{
          'doctype': 'DocType',
          'name': 'Payment Reconciliation',
          'fields': [{
            'fieldname': 'business_unit',
            'fieldtype': 'Link',
            'label': 'Business Unit',
            'options': 'Business Unit',
          }],
        }]}}));
      } else if (request.method == 'GET' &&
          path == 'api/resource/Business Unit') {
        final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
        expect(filters, contains(['company', '=', 'COMP-1']));
        expect(filters, contains(['name', '=', 'BU-1']));
        request.response.write(jsonEncode({'data': [{'name': 'BU-1'}]}));
      } else if (request.method == 'POST' &&
          path == 'api/method/run_doc_method') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
        final document = jsonDecode(body['docs'] as String) as core.Map<String, dynamic>;
        expect(document['business_unit'], 'BU-1');
        document['invoices'] = <core.Map<String, dynamic>>[];
        document['payments'] = <core.Map<String, dynamic>>[];
        request.response.write(jsonEncode({'docs': [document]}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request: $path'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final definitions = await api.fetchPaymentReconciliationDimensions('COMP-1');
      expect(definitions.single['fieldname'], 'business_unit');
      expect(definitions.single['options'], 'Business Unit');
      final document = await api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Customer',
        party: 'CUS-1',
        receivablePayableAccount: 'Debtors - COMP-1',
        accountingDimensions: const {'business_unit': 'BU-1'},
      );
      expect(document['business_unit'], 'BU-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('payment reconciliation rejects invalid inputs before network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Customer',
        party: ' ',
        receivablePayableAccount: 'Debtors - COMP-1',
      ),
      throwsFormatException,
    );
    await expectLater(
      api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Customer',
        party: 'CUS-1',
        receivablePayableAccount: 'Debtors - COMP-1',
        fromInvoiceDate: '2026-12-31',
        toInvoiceDate: '2026-01-01',
      ),
      throwsFormatException,
    );
    await expectLater(
      api.fetchUnreconciledPaymentEntries(
        company: 'COMP-1',
        partyType: 'Customer',
        party: 'CUS-1',
        receivablePayableAccount: 'Debtors - COMP-1',
        minimumInvoiceAmount: 500,
        maximumInvoiceAmount: 100,
      ),
      throwsFormatException,
    );
    api.dispose();
  });
}
