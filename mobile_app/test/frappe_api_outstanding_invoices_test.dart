import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('outstanding receivables are fetched across pages with company isolation', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final starts = <String>[];
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'Sales Invoice']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['docstatus', '=', 1],
        ['outstanding_amount', '>', 0],
        ['is_return', '=', 0],
        ['company', '=', 'Company A'],
      ]);
      expect(jsonDecode(request.uri.queryParameters['fields']!), containsAll([
        'customer', 'customer_name', 'company', 'due_date', 'currency', 'outstanding_amount',
      ]));
      expect(request.uri.queryParameters['order_by'], 'due_date asc, posting_date asc, name asc');
      final start = request.uri.queryParameters['limit_start']!;
      starts.add(start);
      request.response.headers.contentType = ContentType.json;
      final rows = start == '0'
          ? List.generate(100, (index) => {
              'name': 'SINV-${index + 1}',
              'customer': 'CUST-1',
              'company': 'Company A',
              'currency': 'YER',
              'outstanding_amount': 10,
            })
          : [{
              'name': 'SINV-101',
              'customer': 'CUST-2',
              'company': 'Company A',
              'currency': 'USD',
              'outstanding_amount': 20,
            }];
      request.response.write(jsonEncode({'data': rows}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchOutstandingInvoices(
        receivable: true,
        company: 'Company A',
      );
      expect(rows, hasLength(101));
      expect(rows.last['name'], 'SINV-101');
      expect(rows.last['currency'], 'USD');
      expect(starts, ['0', '100']);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('outstanding payables query Purchase Invoice and reject oversized company scope', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'Purchase Invoice']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['docstatus', '=', 1],
        ['outstanding_amount', '>', 0],
        ['is_return', '=', 0],
      ]);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': List.generate(100, (index) => {
        'name': 'PINV-${index + 1}',
        'supplier': 'SUP-1',
        'outstanding_amount': 1,
      })}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.fetchOutstandingInvoices(receivable: false),
        throwsFormatException,
      );
      expect(requests, 101);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
