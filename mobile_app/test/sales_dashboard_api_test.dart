import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sales dashboard requests submitted non-return invoices for selected company and dates', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, ['api', 'resource', 'Sales Invoice']);
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


  test('sales dashboard aggregates currencies and top customers on the ERPNext server', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/method/frappe.client.get_list');
      expect(request.uri.queryParameters['doctype'], 'Sales Invoice');
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      final isReturnQuery = filters.any((filter) =>
          filter is List && filter.length >= 3 && filter[0] == 'is_return' && filter[2] == 1);
      expect(filters, [
        ['docstatus', '=', 1],
        ['is_return', '=', isReturnQuery ? 1 : 0],
        ['company', '=', 'COMP-1'],
        ['posting_date', 'between', ['2026-11-01', '2026-11-09']],
      ]);
      final groupBy = request.uri.queryParameters['group_by'];
      final fields = jsonDecode(request.uri.queryParameters['fields']!) as List;
      expect(fields.any((field) => field is Map && field['SUM'] == 'grand_total' && field['as'] == 'total'), isTrue);
      request.response.headers.contentType = ContentType.json;
      if (groupBy == 'currency' && isReturnQuery) {
        expect(fields.any((field) => field is Map && field['COUNT'] == 'name' && field['as'] == 'invoice_count'), isTrue);
        request.response.write(jsonEncode({'message': [{
          'currency': 'YER', 'total': -500, 'invoice_count': 1,
        }]}));
      } else if (groupBy == 'currency') {
        expect(fields.any((field) => field is Map && field['COUNT'] == 'name' && field['as'] == 'invoice_count'), isTrue);
        request.response.write(jsonEncode({'message': [{
          'currency': 'YER', 'total': 3000, 'outstanding': 500, 'invoice_count': 2,
        }]}));
      } else if (groupBy == 'posting_date, currency') {
        expect(fields, contains('posting_date'));
        expect(fields, contains('currency'));
        expect(request.uri.queryParameters['limit_page_length'], '500');
        request.response.write(jsonEncode({'message': isReturnQuery ? [{
          'posting_date': '2026-11-09',
          'currency': 'YER',
          'total': -500,
          'invoice_count': 1,
        }] : [{
          'posting_date': '2026-11-08',
          'currency': 'YER',
          'total': 3000,
          'invoice_count': 2,
        }]}));
      } else {
        expect(groupBy, 'currency, customer, customer_name');
        request.response.write(jsonEncode({'message': [
          {'currency': 'YER', 'customer': 'CUS-1', 'customer_name': 'Customer One', 'total': 2000},
          {'currency': 'YER', 'customer': 'CUS-2', 'customer_name': 'Customer Two', 'total': 1000},
        ]}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final summary = await api.fetchSalesDashboardSummary(
        company: 'COMP-1',
        fromDate: '2026-11-01',
        toDate: '2026-11-09',
      );
      expect(summary['total_invoices'], 2);
      final totals = summary['currency_totals'] as List;
      expect(totals.single['currency'], 'YER');
      expect(totals.single['total'], 3000.0);
      expect(totals.single['return_total'], 500.0);
      expect(totals.single['net_total'], 2500.0);
      expect(totals.single['return_invoice_count'], 1);
      final monthly = summary['monthly_totals_by_currency'] as Map;
      final november = (monthly['YER'] as List).single;
      expect(november['month'], '2026-11');
      expect(november['total'], 3000.0);
      expect(november['return_total'], 500.0);
      expect(november['net_total'], 2500.0);
      final top = summary['top_customers_by_currency'] as Map;
      expect((top['YER'] as List).first['customer'], 'CUS-1');
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
