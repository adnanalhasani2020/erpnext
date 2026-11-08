import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  group('FrappeApi request construction', () {
    test('builds a paginated resource URI with encoded filters and fields', () {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: 'https://erp.example.com/',
        resource: 'Sales Invoice',
        fields: const ['name', 'customer', 'grand_total'],
        filters: const [
          ['docstatus', '=', 1],
          ['company', '=', 'Example Company'],
        ],
        orderBy: 'posting_date desc, name desc',
        start: 100,
        pageLength: 50,
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'erp.example.com');
      expect(uri.path, '/api/resource/Sales%20Invoice');
      expect(jsonDecode(uri.queryParameters['fields']!), [
        'name',
        'customer',
        'grand_total',
      ]);
      expect(jsonDecode(uri.queryParameters['filters']!), [
        ['docstatus', '=', 1],
        ['company', '=', 'Example Company'],
      ]);
      expect(uri.queryParameters['limit_start'], '100');
      expect(uri.queryParameters['limit_page_length'], '50');
      expect(uri.queryParameters['order_by'], 'posting_date desc, name desc');
    });

    test('normalizes invalid pagination values to safe minimums', () {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: 'https://erp.example.com',
        resource: 'Item',
        fields: const ['name'],
        orderBy: 'name asc',
        start: -10,
        pageLength: 0,
      );

      expect(uri.queryParameters['limit_start'], '0');
      expect(uri.queryParameters['limit_page_length'], '1');
    });
  });

  group('FrappeApi server URL validation', () {
    test('accepts HTTPS and local development HTTP only', () {
      for (final url in [
        'https://erp.example.com',
        'http://localhost:8000',
        'http://127.0.0.1:8000',
        'http://10.0.2.2:8000',
      ]) {
        final api = FrappeApi();
        expect(() => api.configure(url), returnsNormally, reason: url);
        api.dispose();
      }
    });

    test('rejects insecure remote HTTP and URLs containing credentials or query data', () {
      for (final url in [
        'http://erp.example.com',
        'https://user:password@erp.example.com',
        'https://erp.example.com?token=secret',
        'https://erp.example.com/path#fragment',
      ]) {
        final api = FrappeApi();
        expect(() => api.configure(url), throwsFormatException, reason: url);
        api.dispose();
      }
    });
  });
}
