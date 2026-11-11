import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  late FrappeApi api;

  setUp(() => api = FrappeApi());
  tearDown(() => api.dispose());

  group('master data validation', () {
    test('rejects an Item without required identity and reference fields', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Item',
          values: const {
            'item_code': '',
            'item_name': 'Test',
            'item_group': 'Products',
            'stock_uom': 'Nos',
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects enabling serial and batch tracking together', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Item',
          values: const {
            'item_code': 'TEST-001',
            'item_name': 'Test item',
            'item_group': 'Products',
            'stock_uom': 'Nos',
            'has_serial_no': true,
            'has_batch_no': true,
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a company before loading the chart of accounts', () async {
      await expectLater(
        api.fetchAccountingAccounts(company: '  '),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an incomplete chart account before network access', () async {
      await expectLater(
        api.saveAccountingAccount(
          accountName: ' ',
          company: 'Company A',
          parentAccount: 'Assets - A',
          isGroup: false,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('creates an account only after validating company and parent group', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET' && request.uri.pathSegments.contains('Company')) {
          request.response.write(jsonEncode({
            'data': {'name': 'Company A', 'default_currency': 'YER'},
          }));
        } else if (request.method == 'GET' && request.uri.pathSegments.contains('Account')) {
          request.response.write(jsonEncode({
            'data': {
              'name': 'Assets - A', 'company': 'Company A',
              'is_group': 1, 'root_type': 'Asset', 'report_type': 'Balance Sheet', 'account_currency': 'YER', 'disabled': 0,
            },
          }));
        } else if (request.method == 'POST' && request.uri.path.endsWith('/api/resource/Account')) {
          final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
          expect(payload['account_name'], 'Cash');
          expect(payload['company'], 'Company A');
          expect(payload['parent_account'], 'Assets - A');
          expect(payload['root_type'], 'Asset');
          expect(payload['report_type'], 'Balance Sheet');
          request.response.write(jsonEncode({
            'data': {
              'doctype': 'Account', 'name': 'Cash - A', 'account_name': 'Cash', 'company': 'Company A',
              'parent_account': 'Assets - A', 'root_type': 'Asset',
            },
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Unexpected request'}));
        }
        await request.response.close();
      });
      api.configure('http://127.0.0.1:${server.port}');
      try {
        final saved = await api.saveAccountingAccount(
          accountName: 'Cash',
          company: 'Company A',
          parentAccount: 'Assets - A',
          accountCurrency: 'YER',
          isGroup: false,
          accountType: 'Cash',
        );
        expect(saved['name'], 'Cash - A');
        expect(saved['company'], 'Company A');
      } finally {
        await server.close(force: true);
      }
    });

    test('rejects unsupported reference option doctypes before sending a request', () async {
      await expectLater(api.fetchMasterDataOptions('Sales Invoice'), throwsA(isA<ArgumentError>()));
    });

    test('rejects unsupported doctypes before sending a request', () async {
      await expectLater(
        api.fetchMasterDataRows(doctype: 'Sales Invoice'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('requires a valid Customer type, group and territory', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Customer',
          values: const {
            'customer_name': 'Test Customer',
            'customer_type': 'Unknown',
            'customer_group': '',
            'territory': '',
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a valid Customer Group name', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Customer Group',
          values: const {'customer_group_name': ''},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a valid Territory name', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Territory',
          values: const {'territory_name': ''},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a valid Sales Person name and commission rate', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Sales Person',
          values: const {
            'sales_person_name': 'Test Sales Person',
            'commission_rate': 101,
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a valid Supplier type and group', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Supplier',
          values: const {
            'supplier_name': 'Test Supplier',
            'supplier_type': 'Unknown',
            'supplier_group': '',
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a currency and a selling or buying scope for Price Lists', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Price List',
          values: const {
            'price_list_name': 'Test Price List',
            'currency': '',
            'selling': false,
            'buying': false,
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('requires a UOM name before saving', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'UOM',
          values: const {'uom_name': ''},
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects non-positive item UOM conversion factors before network access', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Item',
          values: const {
            'item_code': 'TEST-UOM',
            'item_name': 'Test item',
            'item_group': 'Products',
            'stock_uom': 'Nos',
            'uoms': [
              {'uom': 'Box', 'conversion_factor': 0},
            ],
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects duplicate and base-unit conversion rows before network access', () async {
      await expectLater(
        api.saveMasterDataDocument(
          doctype: 'Item',
          values: const {
            'item_code': 'TEST-UOM',
            'item_name': 'Test item',
            'item_group': 'Products',
            'stock_uom': 'Nos',
            'uoms': [
              {'uom': 'Nos', 'conversion_factor': 1},
              {'uom': 'Box', 'conversion_factor': 12},
              {'uom': 'Box', 'conversion_factor': 24},
            ],
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

    test('paginates warehouse master data with server-side search beyond the first page', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.method, 'GET');
        expect(request.uri.pathSegments.last, 'Warehouse');
        expect(request.uri.queryParameters['limit_start'], '100');
        expect(request.uri.queryParameters['limit_page_length'], '100');
        expect(request.uri.queryParameters['or_filters'], contains('Main'));
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"data":[{"name":"Main - AC","warehouse_name":"Main","company":"Company A"}]}');
        await request.response.close();
      });
      api.configure('http://127.0.0.1:${server.port}');
      try {
        final rows = await api.fetchMasterDataRows(doctype: 'Warehouse', start: 100, search: 'Main');
        expect(rows, hasLength(1));
        expect(rows.single['name'], 'Main - AC');
      } finally {
        await server.close(force: true);
      }
    });

}
