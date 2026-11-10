import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;
  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());


  test('creates a balanced multi-currency Journal Entry using base-currency totals', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    core.Map<String, dynamic>? submittedPayload;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final segments = request.uri.pathSegments;
      if (segments.contains('Company')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Company', 'name': 'Company A', 'default_currency': 'USD',
        }}));
      } else if (segments.contains('Account')) {
        final account = segments.last;
        request.response.write(jsonEncode({'data': {
          'doctype': 'Account',
          'name': account,
          'company': 'Company A',
          'is_group': 0,
          'disabled': 0,
          'account_currency': account == 'Foreign Bank - AC' ? 'EUR' : 'USD',
        }}));
      } else if (request.method == 'POST' && segments.contains('Journal Entry')) {
        submittedPayload = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
        request.response.write(jsonEncode({'data': {
          'doctype': 'Journal Entry',
          'name': 'JV-MULTI-0001',
          'company': 'Company A',
          'docstatus': 0,
        }}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not found'}));
      }
      await request.response.close();
    });
    final client = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await client.saveJournalEntryDraft(
        company: 'Company A',
        postingDate: '2026-11-09',
        remark: 'Foreign currency test',
        accounts: const [
          {'account': 'Foreign Bank - AC', 'debit': 10, 'credit': 0, 'exchange_rate': 2.5},
          {'account': 'Local Income - AC', 'debit': 0, 'credit': 25, 'exchange_rate': 1},
        ],
      );
      expect(result['name'], 'JV-MULTI-0001');
      expect(submittedPayload?['multi_currency'], 1);
      final rows = submittedPayload?['accounts'] as List;
      expect(rows[0]['account_currency'], 'EUR');
      expect(rows[0]['exchange_rate'], 2.5);
      expect(rows[0]['debit_in_account_currency'], 10);
      expect(rows[0]['debit'], 25);
      expect(rows[1]['account_currency'], 'USD');
      expect(rows[1]['credit'], 25);
    } finally {
      client.dispose();
      await server.close(force: true);
    }
  });

  group('Journal Entry draft guards', () {
    test('requires a valid ISO posting date before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '09/11/2026',
          remark: '',
          accounts: const [
            {'account': 'Cash', 'debit': 10, 'credit': 0},
            {'account': 'Sales', 'debit': 0, 'credit': 10},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires at least two account rows before network access', () async {
      await expectLater(
        api.saveJournalEntryDraft(
          company: 'Company A',
          postingDate: '2026-11-09',
          remark: '',
          accounts: const [
            {'account': 'Cash', 'debit': 10, 'credit': 0},
          ],
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
