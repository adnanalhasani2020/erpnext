import 'package:flutter_test/flutter_test.dart';

import '../lib/api/frappe_api.dart';

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
  });
}
