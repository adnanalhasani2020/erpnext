import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fetches supplier payment drafts and submits only the canonical draft', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    final draft = <String, dynamic>{
      'doctype': 'Payment Entry',
      'name': 'PAY-DRAFT-1',
      'docstatus': 0,
      'payment_type': 'Pay',
      'party_type': 'Supplier',
      'party': 'SUP-1',
      'company': 'COMP-1',
      'paid_amount': 250,
      'references': [{
        'reference_doctype': 'Purchase Invoice',
        'reference_name': 'PINV-1',
        'allocated_amount': 250,
      }],
    };
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path == '/api/resource/Payment%20Entry') {
        final fields = jsonDecode(request.uri.queryParameters['fields']!) as List;
        expect(fields, contains('payment_type'));
        expect(fields, contains('party_type'));
        final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
        expect(filters, contains(['payment_type', '=', 'Pay']));
        expect(filters, contains(['party_type', '=', 'Supplier']));
        expect(filters, contains(['docstatus', '=', 0]));
        request.response.write(jsonEncode({'data': [{
          'name': 'PAY-DRAFT-1',
          'party': 'SUP-1',
          'party_name': 'Supplier One',
          'posting_date': '2026-11-09',
          'paid_amount': 250,
          'payment_type': 'Pay',
          'party_type': 'Supplier',
          'docstatus': 0,
        }]}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/resource/Payment%20Entry/PAY-DRAFT-1') {
        request.response.write(jsonEncode({'data': draft}));
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/method/frappe.client.submit') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final submittedDoc = body['doc'] as Map<String, dynamic>;
        expect(submittedDoc['name'], 'PAY-DRAFT-1');
        expect(submittedDoc['docstatus'], 0);
        request.response.write(jsonEncode({'message': {
          ...draft,
          'docstatus': 1,
          'status': 'Submitted',
        }}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Unexpected request'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final drafts = await api.fetchDraftSupplierPayments(search: 'SUP-1');
      expect(drafts.single['name'], 'PAY-DRAFT-1');
      final loaded = await api.fetchSupplierPaymentDraftDocument('PAY-DRAFT-1');
      expect(loaded['docstatus'], 0);
      final submitted = await api.submitSupplierPaymentDraft(loaded);
      expect(submitted['docstatus'], 1);
      expect(calls, [
        'GET /api/resource/Payment%20Entry',
        'GET /api/resource/Payment%20Entry/PAY-DRAFT-1',
        'GET /api/resource/Payment%20Entry/PAY-DRAFT-1',
        'POST /api/method/frappe.client.submit',
      ]);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('rejects a non-supplier or non-payment draft before submission', () async {
    final api = FrappeApi();
    await expectLater(
      api.submitSupplierPaymentDraft({
        'doctype': 'Payment Entry',
        'name': 'PAY-1',
        'docstatus': 0,
        'payment_type': 'Receive',
        'party_type': 'Customer',
      }),
      throwsFormatException,
    );
    api.dispose();
  });
}
