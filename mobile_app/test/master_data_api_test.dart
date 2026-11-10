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
