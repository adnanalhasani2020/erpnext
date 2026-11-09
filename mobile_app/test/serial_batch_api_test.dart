import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  group('ERPNext serial and batch endpoints', () {
    test('fetches positive batches for the exact item and warehouse', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? itemCode;
      String? warehouse;
      String? includeExpired;
      server.listen((request) async {
        itemCode = request.uri.queryParameters['item_code'];
        warehouse = request.uri.queryParameters['warehouse'];
        includeExpired = request.uri.queryParameters['for_stock_levels'];
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'message': [
            {'batch_no': 'LOT-A', 'qty': 4, 'expiry_date': '2027-01-01'},
            {'batch_no': 'LOT-ZERO', 'qty': 0},
            {'batch_no': 'LOT-NEG', 'qty': -1},
          ],
        }));
        await request.response.close();
      });
      final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      try {
        final rows = await api.fetchAvailableBatches(
          itemCode: 'ITEM-1', warehouse: 'WH-1', includeExpired: true,
        );
        expect(itemCode, 'ITEM-1');
        expect(warehouse, 'WH-1');
        expect(includeExpired, '1');
        expect(rows, hasLength(1));
        expect(rows.single['batch_no'], 'LOT-A');
        expect(rows.single['qty'], 4);
      } finally {
        api.dispose();
        await server.close(force: true);
      }
    });

    test('fetches serials with batch restriction and deduplicates the response', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? body;
      server.listen((request) async {
        body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'message': ['SN-1', 'SN-2', 'SN-1', '  ']}));
        await request.response.close();
      });
      final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      try {
        final serials = await api.fetchAvailableSerialNumbers(
          itemCode: 'ITEM-2', warehouse: 'WH-2', quantity: 10,
          batchNumbers: const ['LOT-2'],
        );
        expect(body?['item_code'], 'ITEM-2');
        expect(body?['warehouse'], 'WH-2');
        expect(body?['qty'], 10);
        expect(jsonDecode(body?['batch_nos'] as String), ['LOT-2']);
        expect(serials, ['SN-1', 'SN-2']);
      } finally {
        api.dispose();
        await server.close(force: true);
      }
    });

    test('rejects invalid lookup arguments without a request', () async {
      final api = FrappeApi();
      await expectLater(api.fetchAvailableSerialNumbers(
        itemCode: 'ITEM-1', warehouse: 'WH-1', quantity: 0,
      ), throwsFormatException);
      await expectLater(api.fetchAvailableSerialNumbers(
        itemCode: 'ITEM-1', warehouse: 'WH-1', quantity: 201,
      ), throwsFormatException);
      await expectLater(api.fetchAvailableBatches(
        itemCode: '', warehouse: 'WH-1',
      ), throwsFormatException);
      api.dispose();
    });
  });

  group('tracked stock document validation', () {
    test('stock issue rejects serial count mismatch before network access', () async {
      final api = FrappeApi();
      await expectLater(api.createStockEntry(
        company: 'COMP-1', purpose: 'Material Issue', fromWarehouse: 'WH-1',
        items: [{
          'item_code': 'SER-1', 'qty': 2,
          'use_serial_batch_fields': 1, 'serial_no': 'SN-1',
        }],
      ), throwsFormatException);
      api.dispose();
    });

    test('stock issue rejects duplicate serials across different item rows', () async {
      final api = FrappeApi();
      await expectLater(api.createStockEntry(
        company: 'COMP-1', purpose: 'Material Issue', fromWarehouse: 'WH-1',
        items: [
          {'item_code': 'SER-1', 'qty': 1, 'use_serial_batch_fields': 1, 'serial_no': 'SN-1'},
          {'item_code': 'SER-2', 'qty': 1, 'use_serial_batch_fields': 1, 'serial_no': 'SN-1'},
        ],
      ), throwsFormatException);
      api.dispose();
    });

    test('stock issue requires a batch identifier when batch tracking is enabled', () async {
      final api = FrappeApi();
      await expectLater(api.createStockEntry(
        company: 'COMP-1', purpose: 'Material Issue', fromWarehouse: 'WH-1',
        items: [{
          'item_code': 'BAT-1', 'qty': 4, 'use_serial_batch_fields': 1,
        }],
      ), throwsFormatException);
      api.dispose();
    });

    test('purchase invoice rejects incomplete serial allocation before network access', () async {
      final api = FrappeApi();
      await expectLater(api.createPurchaseInvoice({
        'doctype': 'Purchase Invoice', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'update_stock': 1,
        'items': [{
          'item_code': 'SER-1', 'qty': 2, 'rate': 5,
          'use_serial_batch_fields': 1, 'serial_no': 'SN-1',
        }],
      }), throwsFormatException);
      api.dispose();
    });

    test('purchase receipt rejects incomplete serial allocation before network access', () async {
      final api = FrappeApi();
      await expectLater(api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{
          'item_code': 'SER-1', 'qty': 2, 'rate': 5, 'warehouse': 'WH-1',
          'use_serial_batch_fields': 1, 'serial_no': 'SN-1',
        }],
      }), throwsFormatException);
      api.dispose();
    });
  });
}
