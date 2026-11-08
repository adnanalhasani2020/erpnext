import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';

void main() {
  test('purchase invoice model preserves return linkage', () {
    final invoice = ErpPurchaseInvoice.fromJson({
      'name': 'PINV-RET-1', 'supplier': 'SUP-1', 'supplier_name': 'Supplier',
      'is_return': 1, 'return_against': 'PINV-1', 'grand_total': -25,
      'outstanding_amount': 0,
    });
    expect(invoice.isReturn, isTrue);
    expect(invoice.returnAgainst, 'PINV-1');
  });

  test('stock draft retrieval rejects unsupported document types before network access', () async {
    final api = FrappeApi();
    await expectLater(api.fetchDraftStockDocuments('Sales Invoice'), throwsArgumentError);
    await expectLater(api.fetchStockDocument('Sales Invoice', 'SINV-1'), throwsArgumentError);
    api.dispose();
  });

  test('purchase invoice rejects missing supplier, company, or lines before network access', () async {
    final api = FrappeApi();
    await expectLater(api.createPurchaseInvoice({'doctype': 'Purchase Invoice', 'items': []}), throwsFormatException);
    await expectLater(api.createPurchaseInvoice({
      'doctype': 'Purchase Invoice', 'supplier': 'SUP-1', 'company': 'COMP-1',
      'items': [{'item_code': 'ITEM-1', 'qty': 0, 'rate': 2}],
    }), throwsFormatException);
    await expectLater(api.updateDraftPurchaseInvoice(invoiceName: '', changes: {}), throwsFormatException);
    api.dispose();
  });

  test('purchase receipt requires supplier, item, positive quantity and warehouse', () async {
    final api = FrappeApi();
    await expectLater(api.createPurchaseReceipt({'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1', 'items': []}), throwsFormatException);
    await expectLater(api.createPurchaseReceipt({
      'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
      'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 10}],
    }), throwsFormatException);
    api.dispose();
  });

  test('stock entries reject invalid purpose, missing warehouses and non-positive quantities', () async {
    final api = FrappeApi();
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Unknown', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Receipt', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Receipt', toWarehouse: 'WH-1', items: [{'item_code': 'I', 'qty': 1, 'valuation_rate': 0}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Issue', fromWarehouse: 'WH-1', items: [{'item_code': 'I', 'qty': 0}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Transfer', fromWarehouse: 'WH-1', toWarehouse: 'WH-1', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    api.dispose();
  });

  test('stock reconciliation rejects duplicate item rows and negative counted quantities', () async {
    final api = FrappeApi();
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: []), throwsFormatException);
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: [
      {'item_code': 'ITEM-1', 'qty': 3},
      {'item_code': 'ITEM-1', 'qty': 4},
    ]), throwsFormatException);
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: [
      {'item_code': 'ITEM-1', 'qty': -1},
    ]), throwsFormatException);
    api.dispose();
  });

  test('stock submission requires an explicit submitted document response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': {
        'doctype': 'Stock Entry', 'name': 'STE-1', 'docstatus': 1,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.submitStockEntry({
        'doctype': 'Stock Entry', 'name': 'STE-1', 'docstatus': 0,
      });
      expect(result['docstatus'], 1);
      expect(result['name'], 'STE-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('stock submission rejects a response that does not confirm docstatus 1', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'message': {
        'doctype': 'Stock Entry', 'name': 'STE-2', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.submitStockEntry({
          'doctype': 'Stock Entry', 'name': 'STE-2', 'docstatus': 0,
        }),
        throwsException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase invoice API accepts multiple validated item rows', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      expect((payload['items'] as List).length, 2);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Purchase Invoice', 'name': 'PINV-MULTI-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createPurchaseInvoice({
        'doctype': 'Purchase Invoice', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [
          {'item_code': 'ITEM-1', 'qty': 2, 'rate': 5},
          {'item_code': 'ITEM-2', 'qty': 3, 'rate': 7},
        ],
      });
      expect(result['name'], 'PINV-MULTI-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase receipt API accepts multiple item rows with warehouse per row', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final rows = payload['items'] as List;
      expect(rows.length, 2);
      expect(rows.every((row) => row['warehouse'] == 'WH-1'), isTrue);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Purchase Receipt', 'name': 'PREC-MULTI-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [
          {'item_code': 'ITEM-1', 'qty': 2, 'rate': 5, 'warehouse': 'WH-1'},
          {'item_code': 'ITEM-2', 'qty': 3, 'rate': 7, 'warehouse': 'WH-1'},
        ],
      });
      expect(result['name'], 'PREC-MULTI-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('material receipt maps entered valuation rate to ERPNext basic_rate', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final row = (payload['items'] as List).single as Map<String, dynamic>;
      expect(row['basic_rate'], 12.5);
      expect(row.containsKey('valuation_rate'), isFalse);
      expect(row['t_warehouse'], 'WH-RECEIVE');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Stock Entry', 'name': 'STE-RECEIPT-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createStockEntry(
        company: 'COMP-1',
        purpose: 'Material Receipt',
        toWarehouse: 'WH-RECEIVE',
        items: [{'item_code': 'ITEM-1', 'qty': 2, 'valuation_rate': 12.5}],
      );
      expect(result['name'], 'STE-RECEIPT-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase return creates a partial debit note with the original row link', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
          'supplier': 'SUP-1', 'items': [{'name': 'PINV-ITEM-1', 'item_code': 'ITEM-1', 'qty': 5}],
        }}));
      } else if (request.method == 'GET' && request.uri.pathSegments.contains('Purchase Invoice') && request.uri.pathSegments.length == 3) {
        request.response.write(jsonEncode({'data': []}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('make_debit_note')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'is_return': 1, 'return_against': 'PINV-1',
          'items': [{'item_code': 'ITEM-1', 'qty': -5, 'purchase_invoice_item': 'PINV-ITEM-1'}],
        }}));
      } else if (request.method == 'POST' && request.uri.pathSegments.contains('Purchase Invoice') && request.uri.pathSegments.length == 3) {
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final row = (payload['items'] as List).single as Map<String, dynamic>;
        expect(row['qty'], -2.0);
        expect(row['purchase_invoice_item'], 'PINV-ITEM-1');
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-RET-1', 'return_against': 'PINV-1',
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createPurchaseReturn(
        'PINV-1', quantitiesBySourceItem: {'PINV-ITEM-1': 2},
      );
      expect(result['name'], 'PINV-RET-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase return rejects a quantity above the mapped remaining quantity', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
          'supplier': 'SUP-1', 'items': [{'name': 'PINV-ITEM-1', 'item_code': 'ITEM-1', 'qty': 5}],
        }}));
      } else if (request.method == 'GET' && request.uri.pathSegments.contains('Purchase Invoice') && request.uri.pathSegments.length == 3) {
        request.response.write(jsonEncode({'data': []}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('make_debit_note')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'is_return': 1, 'return_against': 'PINV-1',
          'items': [{'item_code': 'ITEM-1', 'qty': -1, 'purchase_invoice_item': 'PINV-ITEM-1'}],
        }}));
      } else {
        fail('The return should be rejected before insertion.');
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.createPurchaseReturn('PINV-1', quantitiesBySourceItem: {'PINV-ITEM-1': 2}),
        throwsFormatException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('stock entry API accepts multiple transfer rows with source and target warehouses', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final rows = payload['items'] as List;
      expect(rows.length, 2);
      expect(rows.every((row) => row['s_warehouse'] == 'WH-FROM'), isTrue);
      expect(rows.every((row) => row['t_warehouse'] == 'WH-TO'), isTrue);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Stock Entry', 'name': 'STE-MULTI-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createStockEntry(
        company: 'COMP-1',
        purpose: 'Material Transfer',
        fromWarehouse: 'WH-FROM',
        toWarehouse: 'WH-TO',
        items: [
          {'item_code': 'ITEM-1', 'qty': 2},
          {'item_code': 'ITEM-2', 'qty': 4},
        ],
      );
      expect(result['name'], 'STE-MULTI-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('stock reconciliation API accepts multiple distinct items including zero count', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final rows = payload['items'] as List;
      expect(rows.length, 2);
      expect(rows.any((row) => row['item_code'] == 'ITEM-1' && row['qty'] == 0), isTrue);
      expect(rows.every((row) => row['warehouse'] == 'WH-1'), isTrue);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Stock Reconciliation', 'name': 'RECON-MULTI-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createStockReconciliation(
        company: 'COMP-1',
        warehouse: 'WH-1',
        items: [
          {'item_code': 'ITEM-1', 'qty': 0, 'valuation_rate': 0},
          {'item_code': 'ITEM-2', 'qty': 5, 'valuation_rate': 8},
        ],
      );
      expect(result['name'], 'RECON-MULTI-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('stock submission refuses canceled documents before network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.submitStockEntry({'doctype': 'Stock Entry', 'name': 'STE-CANCELLED', 'docstatus': 2}),
      throwsFormatException,
    );
    api.dispose();
  });

  test('item model exposes serial and batch tracking requirements', () {
    final item = ErpItem.fromJson({
      'item_code': 'TRACKED-1',
      'item_name': 'Tracked item',
      'has_serial_no': 1,
      'has_batch_no': 0,
    });
    expect(item.hasSerialNo, isTrue);
    expect(item.hasBatchNo, isFalse);
  });

  test('purchase order list and document APIs expose submitted order lines', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.pathSegments.contains('Purchase Order') &&
          request.uri.pathSegments.length == 3) {
        request.response.write(jsonEncode({'data': [
          {'name': 'PO-1', 'supplier': 'SUP-1', 'company': 'COMP-1', 'docstatus': 1},
        ]}));
      } else if (request.method == 'GET' &&
          request.uri.pathSegments.contains('Purchase Order') &&
          request.uri.pathSegments.length == 4) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Order', 'name': 'PO-1', 'supplier': 'SUP-1',
          'company': 'COMP-1', 'docstatus': 1,
          'items': [{'name': 'PO-ITEM-1', 'item_code': 'ITEM-1', 'qty': 10, 'received_qty': 4}],
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final orders = await api.fetchPurchaseOrders();
      expect(orders.single['name'], 'PO-1');
      final order = await api.fetchPurchaseOrderDocument('PO-1');
      expect(order['docstatus'], 1);
      expect((order['items'] as List).single['received_qty'], 4);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase receipt preserves purchase order and source item references', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      final row = (payload['items'] as List).single as Map<String, dynamic>;
      expect(row['purchase_order'], 'PO-1');
      expect(row['purchase_order_item'], 'PO-ITEM-1');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Purchase Receipt', 'name': 'PREC-PO-1', 'docstatus': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{
          'item_code': 'ITEM-1', 'qty': 2, 'rate': 5, 'warehouse': 'WH-1',
          'purchase_order': 'PO-1', 'purchase_order_item': 'PO-ITEM-1',
        }],
      });
      expect(result['name'], 'PREC-PO-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase return rejects selected source rows omitted by ERPNext mapper', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
          'supplier': 'SUP-1', 'items': [
            {'name': 'PINV-ITEM-1', 'item_code': 'ITEM-1', 'qty': 5},
            {'name': 'PINV-ITEM-2', 'item_code': 'ITEM-2', 'qty': 2},
          ],
        }}));
      } else if (request.method == 'GET' && request.uri.pathSegments.contains('Purchase Invoice') && request.uri.pathSegments.length == 3) {
        request.response.write(jsonEncode({'data': []}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('make_debit_note')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'is_return': 1, 'return_against': 'PINV-1',
          'items': [{'item_code': 'ITEM-1', 'qty': -1, 'purchase_invoice_item': 'PINV-ITEM-1'}],
        }}));
      } else {
        fail('A selected source row missing from the mapper must be rejected before insertion.');
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.createPurchaseReturn('PINV-1', quantitiesBySourceItem: {
          'PINV-ITEM-1': 1, 'PINV-ITEM-2': 1,
        }),
        throwsFormatException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase returnable quantities come from ERPNext debit note mapper', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
          'is_return': 0,
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('make_debit_note')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'is_return': 1, 'return_against': 'PINV-1',
          'items': [
            {'purchase_invoice_item': 'PINV-ITEM-1', 'qty': -2},
            {'purchase_invoice_item': 'PINV-ITEM-2', 'qty': -0.5},
          ],
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final quantities = await api.fetchPurchaseReturnableQuantities('PINV-1');
      expect(quantities, {'PINV-ITEM-1': 2.0, 'PINV-ITEM-2': 0.5});
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment creates and submits a correctly allocated Payment Entry', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
          'is_return': 0, 'supplier': 'SUP-1', 'outstanding_amount': 100,
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('get_payment_entry')) {
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        expect(payload['dt'], 'Purchase Invoice');
        expect(payload['dn'], 'PINV-1');
        expect(payload['party_amount'], 40.0);
        expect(payload['bank_account'], 'CASH - C');
        request.response.write(jsonEncode({'message': {
          'doctype': 'Payment Entry', 'payment_type': 'Pay',
          'party_type': 'Supplier', 'party': 'SUP-1', 'paid_from': 'CASH - C',
          'references': [{
            'reference_doctype': 'Purchase Invoice',
            'reference_name': 'PINV-1', 'allocated_amount': 40,
          }],
        }}));
      } else if (request.method == 'POST' && request.uri.pathSegments.contains('Payment Entry')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Payment Entry', 'name': 'PAY-1', 'docstatus': 0,
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('frappe.client.submit')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Payment Entry', 'name': 'PAY-1', 'docstatus': 1,
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.payPurchaseInvoice(
        invoiceName: 'PINV-1', amount: 40, bankAccount: 'CASH - C',
      );
      expect(result['name'], 'PAY-1');
      expect(result['docstatus'], 1);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment rejects amounts greater than the outstanding balance', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
        'is_return': 0, 'supplier': 'SUP-1', 'outstanding_amount': 25,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.payPurchaseInvoice(invoiceName: 'PINV-1', amount: 30),
        throwsFormatException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
