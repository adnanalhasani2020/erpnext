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
  });
}
