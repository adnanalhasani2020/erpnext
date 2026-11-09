import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('fetchStockMovements applies inclusive date filters with other filters', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    List<dynamic>? observedFilters;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      observedFilters = jsonDecode(request.uri.queryParameters['filters']!) as List<dynamic>;
      expect(request.uri.queryParameters['limit_start'], '100');
      request.response.write(jsonEncode({'data': []}));
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await api.fetchStockMovements(
        start: 100,
        itemCode: 'ITEM-1',
        warehouse: 'Main - AC',
        company: 'ACME',
        fromDate: DateTime(2026, 1, 2, 23, 59),
        toDate: DateTime(2026, 1, 31, 1),
      );

      expect(observedFilters, [
        ['item_code', '=', 'ITEM-1'],
        ['warehouse', '=', 'Main - AC'],
        ['company', '=', 'ACME'],
        ['posting_date', '>=', '2026-01-02'],
        ['posting_date', '<=', '2026-01-31'],
      ]);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('fetchStockMovements rejects a reversed date range before making a request', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    server.listen((request) async {
      requestCount++;
      request.response.write(jsonEncode({'data': []}));
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.fetchStockMovements(
          fromDate: DateTime(2026, 2, 1),
          toDate: DateTime(2026, 1, 31),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(requestCount, 0);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
