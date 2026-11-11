import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background payment reconciliation uses native draft, submit, job and log APIs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var document = <String, dynamic>{
      'doctype': 'Process Payment Reconciliation',
      'name': 'ACC-PPR-00001',
      'company': 'COMP-1',
      'party_type': 'Customer',
      'party': 'CUS-1',
      'receivable_payable_account': 'Debtors - COMP-1',
      'docstatus': 0,
      'status': '',
    };
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.pathSegments.join('/');
      if (request.method == 'GET' && path.contains('api/resource/Account/')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Account',
          'name': 'Debtors - COMP-1',
          'company': 'COMP-1',
          'account_type': 'Receivable',
          'root_type': 'Asset',
          'is_group': 0,
          'disabled': 0,
        }}));
      } else if (request.method == 'POST' &&
          path == 'api/resource/Process Payment Reconciliation') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
        document = {...body, 'name': 'ACC-PPR-00001', 'docstatus': 0, 'status': ''};
        request.response.write(jsonEncode({'data': document}));
      } else if (request.method == 'GET' &&
          path == 'api/resource/Process Payment Reconciliation/ACC-PPR-00001') {
        request.response.write(jsonEncode({'data': document}));
      } else if (request.method == 'POST' && path == 'api/method/frappe.client.submit') {
        document = {...document, 'docstatus': 1, 'status': 'Queued'};
        request.response.write(jsonEncode({'message': document}));
      } else if (request.method == 'POST' &&
          path.endsWith('/process_payment_reconciliation.trigger_job_for_doc')) {
        document = {...document, 'status': 'Running'};
        request.response.write(jsonEncode({'message': null}));
      } else if (request.method == 'POST' &&
          path.endsWith('/process_payment_reconciliation.pause_job_for_doc')) {
        document = {...document, 'status': 'Paused'};
        request.response.write(jsonEncode({'message': null}));
      } else if (request.method == 'POST' &&
          path.endsWith('/process_payment_reconciliation.get_reconciled_count')) {
        request.response.write(jsonEncode({'message': {'processed': 3, 'total': 5}}));
      } else if (request.method == 'GET' &&
          path == 'api/resource/Process Payment Reconciliation Log') {
        request.response.write(jsonEncode({'data': [{
          'name': 'PPR-LOG-00001',
          'process_pr': 'ACC-PPR-00001',
          'status': 'Running',
          'total_allocations': 5,
          'reconciled_entries': 3,
        }]}));
      } else if (request.method == 'GET' &&
          path == 'api/resource/Process Payment Reconciliation Log/PPR-LOG-00001') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Process Payment Reconciliation Log',
          'name': 'PPR-LOG-00001',
          'process_pr': 'ACC-PPR-00001',
          'status': 'Running',
          'total_allocations': 5,
          'reconciled_entries': 3,
          'allocations': [{
            'reference_type': 'Payment Entry',
            'reference_name': 'PAY-1',
            'invoice_type': 'Sales Invoice',
            'invoice_number': 'SINV-1',
            'allocated_amount': 50,
            'reconciled': 1,
          }],
        }}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request: ${request.method} $path'}));
      }
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final draft = await api.saveProcessPaymentReconciliationDraft(
        company: 'COMP-1',
        partyType: 'Customer',
        party: 'CUS-1',
        receivablePayableAccount: 'Debtors - COMP-1',
        fromInvoiceDate: '2026-01-01',
        toInvoiceDate: '2026-01-31',
      );
      expect(draft['name'], 'ACC-PPR-00001');
      expect(draft['docstatus'], 0);

      final submitted = await api.submitProcessPaymentReconciliation('ACC-PPR-00001');
      expect(submitted['docstatus'], 1);
      expect(submitted['status'], 'Queued');

      final running = await api.startProcessPaymentReconciliation('ACC-PPR-00001');
      expect(running['status'], 'Running');

      final progress = await api.fetchProcessPaymentReconciliationProgress('ACC-PPR-00001');
      expect(progress['processed'], 3);
      expect(progress['total'], 5);

      final log = await api.fetchProcessPaymentReconciliationLog('ACC-PPR-00001');
      expect(log?['name'], 'PPR-LOG-00001');
      expect((log?['allocations'] as List).length, 1);

      final paused = await api.pauseProcessPaymentReconciliation('ACC-PPR-00001');
      expect(paused['status'], 'Paused');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('background payment reconciliation rejects invalid date ranges before network access', () async {
    final api = FrappeApi()..configure('http://127.0.0.1:1');
    try {
      await expectLater(
        api.saveProcessPaymentReconciliationDraft(
          company: 'COMP-1',
          partyType: 'Customer',
          party: 'CUS-1',
          receivablePayableAccount: 'Debtors - COMP-1',
          fromInvoiceDate: '2026-02-01',
          toInvoiceDate: '2026-01-01',
        ),
        throwsFormatException,
      );
    } finally {
      api.dispose();
    }
  });
}
