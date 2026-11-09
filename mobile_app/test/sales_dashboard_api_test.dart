import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/api/frappe_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sales dashboard requests submitted non-return invoices for selected company and dates', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/resource/Sales%20Invoice');
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['docstatus', '=', 1],
        ['is_return', '=', 0],
        ['company', '=', 'COMP-1'],
        ['posting_date', 'between', ['2026-11-01', '2026-11-09']],
      ]);
      expect(request.uri.queryParameters['order_by'], 'posting_date desc, name desc');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'SINV-1',
        'customer': 'CUS-1',
        'customer_name': 'Customer One',
        'posting_date': '2026-11-08',
        'currency': 'YER',
        'grand_total': 2500,
        'outstanding_amount': 500,
        'status': 'Partly Paid',
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchSalesDashboardInvoices(
        company: 'COMP-1',
        fromDate: '2026-11-01',
        toDate: '2026-11-09',
      );
      expect(rows.single['name'], 'SINV-1');
      expect(rows.single['currency'], 'YER');
      expect(rows.single['grand_total'], 2500);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('sales dashboard rejects invalid company and date range before network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.fetchSalesDashboardInvoices(
        company: ' ',
        fromDate: '2026-11-01',
        toDate: '2026-11-09',
      ),
      throwsFormatException,
    );
    await expectLater(
      api.fetchSalesDashboardInvoices(
        company: 'COMP-1',
        fromDate: '2026-11-10',
        toDate: '2026-11-09',
      ),
      throwsFormatException,
    );
    api.dispose();
  });
}
