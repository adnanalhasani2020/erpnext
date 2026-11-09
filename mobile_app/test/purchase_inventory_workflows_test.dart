import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/purchase_inventory_workflows.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';

void main() {
  testWidgets('stock workflow loads movement history filtered to the selected item', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    List<dynamic>? observedFilters;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.pathSegments.contains('Stock Ledger Entry')) {
        final rawFilters = request.uri.queryParameters['filters'];
        if (rawFilters != null) observedFilters = jsonDecode(rawFilters) as List<dynamic>;
      }
      request.response.write(jsonEncode({'data': []}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: StockWorkflowPage(
          api: api,
          companies: const [],
          suppliers: const [],
          items: const [ErpItem(code: 'ITEM-42', name: 'صنف تجريبي')],
          warehouses: const [],
          initialItemCode: 'ITEM-42',
        ),
      ));
      await tester.pumpAndSettle();
      expect(observedFilters, isNotNull);
      expect(
        observedFilters,
        contains(['item_code', '=', 'ITEM-42']),
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  testWidgets('purchase workflow opens the selected invoice detail on entry', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final segments = request.uri.pathSegments;
      if (request.method == 'GET' &&
          segments.length >= 4 &&
          segments[segments.length - 2] == 'Purchase Invoice' &&
          segments.last == 'PINV-OPEN-1') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice',
          'name': 'PINV-OPEN-1',
          'docstatus': 1,
          'supplier': 'SUP-1',
          'supplier_name': 'مورد تجريبي',
          'company': 'COMP-1',
          'grand_total': 125,
          'outstanding_amount': 125,
          'items': [],
        }}));
      } else {
        request.response.write(jsonEncode({'data': []}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: PurchaseWorkflowPage(
          api: api,
          companies: const [],
          suppliers: const [],
          items: const [],
          warehouses: const [],
          initialInvoiceName: 'PINV-OPEN-1',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('فاتورة مشتريات • PINV-OPEN-1'), findsOneWidget);
      expect(find.text('مورد تجريبي'), findsOneWidget);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase invoice model preserves return linkage', () {
    final invoice = ErpPurchaseInvoice.fromJson({
      'name': 'PINV-RET-1', 'supplier': 'SUP-1', 'supplier_name': 'Supplier',
      'is_return': 1, 'return_against': 'PINV-1', 'grand_total': -25,
      'outstanding_amount': 0,
    });
    expect(invoice.isReturn, isTrue);
    expect(invoice.returnAgainst, 'PINV-1');
  });

  test('stock draft retrieval forwards pagination and document filters', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      expect(request.uri.pathSegments, ['api', 'resource', 'Purchase Receipt']);
      expect(request.uri.queryParameters['limit_start'], '40');
      expect(
        jsonDecode(request.uri.queryParameters['filters']!),
        [['docstatus', '=', 0]],
      );
      request.response.write(jsonEncode({'data': [
        {'name': 'PREC-DRAFT-41', 'docstatus': 0, 'company': 'COMP-1'},
      ]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchDraftStockDocuments('Purchase Receipt', start: 40);
      expect(rows.single['name'], 'PREC-DRAFT-41');
      expect(rows.single['doctype'], 'Purchase Receipt');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
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
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Stock Entry', 'name': 'STE-1', 'docstatus': 0,
        }}));
      } else {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        expect(body['doc']['name'], 'STE-1');
        request.response.write(jsonEncode({'message': {
          'doctype': 'Stock Entry', 'name': 'STE-1', 'docstatus': 1,
        }}));
      }
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

  test('stock submission re-fetches the document and refuses a stale submitted draft', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var submitCalled = false;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Stock Entry', 'name': 'STE-STALE', 'docstatus': 1,
        }}));
      } else {
        submitCalled = true;
        await request.drain<void>();
        request.response.write(jsonEncode({'message': 'unexpected submit'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.submitStockEntry({
          'doctype': 'Stock Entry', 'name': 'STE-STALE', 'docstatus': 0,
        }),
        throwsFormatException,
      );
      expect(submitCalled, isFalse);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('stock submission rejects a response that does not confirm docstatus 1', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Stock Entry', 'name': 'STE-2', 'docstatus': 0,
        }}));
      } else {
        await request.drain<void>();
        request.response.write(jsonEncode({'message': {
          'doctype': 'Stock Entry', 'name': 'STE-2', 'docstatus': 0,
        }}));
      }
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
          'doctype': 'Purchase Invoice', 'name': 'PINV-RET-1', 'docstatus': 0, 'is_return': 1, 'return_against': 'PINV-1',
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
          'is_return': 0, 'supplier': 'SUP-1', 'company': 'COMP-1', 'outstanding_amount': 100,
        }}));
      } else if (request.method == 'GET' && request.uri.path.endsWith('/PAY-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Payment Entry', 'name': 'PAY-1', 'docstatus': 0,
          'payment_type': 'Pay', 'party_type': 'Supplier',
          'party': 'SUP-1', 'references': [],
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
          'payment_type': 'Pay', 'party_type': 'Supplier',
          'party': 'SUP-1', 'company': 'COMP-1', 'paid_from': 'CASH - C',
          'references': [{
            'reference_doctype': 'Purchase Invoice',
            'reference_name': 'PINV-1', 'allocated_amount': 40,
          }],
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('frappe.client.submit')) {
        request.response.write(jsonEncode({'message': {
          'doctype': 'Payment Entry', 'name': 'PAY-1', 'docstatus': 1,
          'payment_type': 'Pay', 'party_type': 'Supplier', 'party': 'SUP-1',
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

  test('purchase returnable quantity preview rejects an unsubmitted source invoice', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT', 'docstatus': 0,
        'is_return': 0,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.fetchPurchaseReturnableQuantities('PINV-DRAFT'),
        throwsFormatException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase draft update preserves server fields while replacing edited lines', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-DRAFT')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT', 'docstatus': 0,
          'company': 'COMP-1', 'supplier': 'SUP-1', 'taxes_and_charges': 'VAT-15',
          'items': [{'name': 'OLD-ROW', 'item_code': 'OLD', 'qty': 1, 'rate': 1}],
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('frappe.client.save')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final doc = body['doc'] as Map<String, dynamic>;
        expect(doc['name'], 'PINV-DRAFT');
        expect(doc['docstatus'], 0);
        expect(doc['taxes_and_charges'], 'VAT-15');
        expect(doc['supplier'], 'SUP-2');
        expect((doc['items'] as List).single['item_code'], 'NEW-ITEM');
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT', 'docstatus': 0,
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.updateDraftPurchaseInvoice(
        invoiceName: 'PINV-DRAFT',
        changes: {
          'doctype': 'Purchase Invoice', 'company': 'COMP-1', 'supplier': 'SUP-2',
          'items': [{'item_code': 'NEW-ITEM', 'qty': 3, 'rate': 7}],
        },
      );
      expect(result['name'], 'PINV-DRAFT');
      expect(result['docstatus'], 0);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
  test('purchase invoice cancellation re-fetches and confirms ERPNext canceled status', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var cancelRequests = 0;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 1,
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('frappe.client.cancel')) {
        cancelRequests++;
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        expect(payload['doctype'], 'Purchase Invoice');
        expect(payload['name'], 'PINV-1');
        request.response.write(jsonEncode({'message': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-1', 'docstatus': 2,
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final result = await api.cancelPurchaseInvoice('PINV-1');
      expect(result['docstatus'], 2);
      expect(cancelRequests, 1);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase invoice cancellation refuses drafts before calling cancel endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var cancelRequests = 0;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT', 'docstatus': 0,
        }}));
      } else {
        cancelRequests++;
        request.response.write(jsonEncode({'message': 'unexpected'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(api.cancelPurchaseInvoice('PINV-DRAFT'), throwsFormatException);
      expect(cancelRequests, 0);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier ledger filters to one supplier and excludes canceled entries', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'GL Entry']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['party_type', '=', 'Supplier'],
        ['party', '=', 'SUP-1'],
        ['is_cancelled', '=', 0],
      ]);
      expect(request.uri.queryParameters['order_by'], 'posting_date desc, creation desc, name desc');
      expect(request.uri.queryParameters['limit_start'], requests == 1 ? '0' : '100');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'GLE-1', 'posting_date': '2026-11-08', 'party': 'SUP-1',
        'voucher_type': 'Payment Entry', 'voucher_no': 'PAY-1',
        'debit': 0, 'credit': 75, 'account': 'Creditors - C',
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final first = await api.fetchSupplierLedger(supplier: 'SUP-1');
      final next = await api.fetchSupplierLedger(supplier: 'SUP-1', start: 100);
      expect(first.single['voucher_no'], 'PAY-1');
      expect(first.single['credit'], 75);
      expect(next.single['party'], 'SUP-1');
      expect(requests, 2);
      await expectLater(api.fetchSupplierLedger(supplier: ' '), throwsFormatException);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('customer ledger filters to one customer and optionally one company', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'GL Entry']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['party_type', '=', 'Customer'],
        ['party', '=', 'CUS-1'],
        ['is_cancelled', '=', 0],
        ['company', '=', 'COMP-1'],
      ]);
      expect(request.uri.queryParameters['limit_start'], '100');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'GLE-CUS-1', 'posting_date': '2026-11-09', 'party': 'CUS-1',
        'voucher_type': 'Sales Invoice', 'voucher_no': 'SINV-1',
        'debit': 125, 'credit': 0, 'company': 'COMP-1',
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchCustomerLedger(customer: 'CUS-1', company: 'COMP-1', start: 100);
      expect(rows.single['voucher_no'], 'SINV-1');
      expect(rows.single['debit'], 125);
      await expectLater(api.fetchCustomerLedger(customer: ' '), throwsFormatException);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment history requests only submitted supplier payments and paginates', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'Payment Entry']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['payment_type', '=', 'Pay'],
        ['party_type', '=', 'Supplier'],
        ['docstatus', '=', 1],
      ]);
      expect(request.uri.queryParameters['order_by'], 'posting_date desc, name desc');
      expect(request.uri.queryParameters['limit_start'], requests == 1 ? '0' : '100');
      expect(request.uri.queryParameters['or_filters'], contains('SUP-1'));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'PAY-SUP-1', 'posting_date': '2026-11-08',
        'party': 'SUP-1', 'party_name': 'Supplier One',
        'paid_amount': 125.5, 'paid_from': 'Cash - COMP',
        'docstatus': 1, 'status': 'Submitted',
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final first = await api.fetchSupplierPayments(search: 'SUP-1');
      final next = await api.fetchSupplierPayments(start: 100, search: 'SUP-1');
      expect(first.single['name'], 'PAY-SUP-1');
      expect(first.single['paid_amount'], 125.5);
      expect(first.single['paid_from'], 'Cash - COMP');
      expect(next.single['party'], 'SUP-1');
      expect(requests, 2);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment history rejects an unexpected response shape', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {'name': 'NOT-A-LIST'}}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(api.fetchSupplierPayments(), throwsException);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment details verify submitted supplier payment and preserve invoice allocations', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'Payment Entry', 'PAY-SUP-1']));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Payment Entry',
        'name': 'PAY-SUP-1',
        'payment_type': 'Pay',
        'party_type': 'Supplier',
        'party': 'SUP-1',
        'party_name': 'Supplier One',
        'docstatus': 1,
        'paid_amount': 125.5,
        'references': [{
          'reference_doctype': 'Purchase Invoice',
          'reference_name': 'PINV-1',
          'allocated_amount': 125.5,
        }],
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final payment = await api.fetchSupplierPaymentDocument('PAY-SUP-1');
      expect(payment['party'], 'SUP-1');
      expect((payment['references'] as List).single['reference_name'], 'PINV-1');
      expect((payment['references'] as List).single['allocated_amount'], 125.5);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('supplier payment details reject drafts and non-supplier payment entries', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Payment Entry',
        'name': 'PAY-DRAFT',
        'payment_type': 'Receive',
        'party_type': 'Customer',
        'docstatus': 0,
        'references': [],
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.fetchSupplierPaymentDocument('PAY-DRAFT'),
        throwsFormatException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });


  test('draft deletion verifies document status and uses Frappe delete endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var deleted = false;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PINV-DRAFT')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT', 'docstatus': 0,
        }}));
      } else if (request.method == 'POST' && request.uri.path.endsWith('frappe.client.delete')) {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        expect(body, {'doctype': 'Purchase Invoice', 'name': 'PINV-DRAFT'});
        deleted = true;
        request.response.write(jsonEncode({'message': 'Successfully deleted'}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await api.deleteDraftDocument(doctype: 'Purchase Invoice', name: 'PINV-DRAFT');
      expect(deleted, isTrue);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('draft deletion refuses submitted documents before calling delete', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var deleteCalled = false;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Stock Entry', 'name': 'STE-1', 'docstatus': 1,
        }}));
      } else {
        deleteCalled = true;
        request.response.statusCode = 500;
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.deleteDraftDocument(doctype: 'Stock Entry', name: 'STE-1'),
        throwsFormatException,
      );
      expect(deleteCalled, isFalse);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('draft deletion rejects unsupported doctypes without network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.deleteDraftDocument(doctype: 'Sales Invoice', name: 'SINV-1'),
      throwsFormatException,
    );
    api.dispose();
  });

  test('stock movement history filters by company, item and warehouse', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments, containsAll(['api', 'resource', 'Stock Ledger Entry']));
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['item_code', '=', 'ITEM-1'],
        ['warehouse', '=', 'WH-1'],
        ['company', '=', 'COMP-1'],
      ]);
      expect(request.uri.queryParameters['limit_start'], '0');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'SLE-1', 'item_code': 'ITEM-1', 'warehouse': 'WH-1',
        'company': 'COMP-1', 'actual_qty': -2, 'qty_after_transaction': 8,
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchStockMovements(
        itemCode: 'ITEM-1', warehouse: 'WH-1', company: 'COMP-1',
      );
      expect(rows.single['name'], 'SLE-1');
      expect(rows.single['company'], 'COMP-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });


  test('supplier ledger can be scoped to a single company', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final filters = jsonDecode(request.uri.queryParameters['filters']!) as List;
      expect(filters, [
        ['party_type', '=', 'Supplier'],
        ['party', '=', 'SUP-1'],
        ['is_cancelled', '=', 0],
        ['company', '=', 'COMP-1'],
      ]);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': [{
        'name': 'GLE-COMP-1', 'party': 'SUP-1', 'company': 'COMP-1',
        'debit': 10, 'credit': 0,
      }]}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchSupplierLedger(
        supplier: 'SUP-1', company: 'COMP-1',
      );
      expect(rows.single['company'], 'COMP-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });


  test('purchase invoice and receipt reject finite line values whose totals overflow', () async {
    final api = FrappeApi();
    await expectLater(
      api.createPurchaseInvoice({
        'doctype': 'Purchase Invoice', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': 1e308, 'rate': 1e308}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createPurchaseReceipt({
        'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{
          'item_code': 'ITEM-1', 'qty': 1e308, 'rate': 1e308,
          'warehouse': 'WH-1',
        }],
      }),
      throwsFormatException,
    );
    api.dispose();
  });

  test('purchase receipt and stock creation require confirmed draft document identity', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': {
        'doctype': 'Wrong Doctype', 'name': 'DRAFT-1', 'docstatus': 1,
      }}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.createPurchaseReceipt({
          'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
          'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 2, 'warehouse': 'WH-1'}],
        }),
        throwsException,
      );
      await expectLater(
        api.createStockEntry(
          company: 'COMP-1',
          purpose: 'Material Transfer',
          fromWarehouse: 'WH-1',
          toWarehouse: 'WH-2',
          items: [{'item_code': 'ITEM-1', 'qty': 1}],
        ),
        throwsException,
      );
      await expectLater(
        api.createStockReconciliation(
          company: 'COMP-1',
          warehouse: 'WH-1',
          items: [{'item_code': 'ITEM-1', 'qty': 1}],
        ),
        throwsException,
      );
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });


  test('stock entry and reconciliation reject valuation totals that overflow', () async {
    final api = FrappeApi();
    await expectLater(
      api.createStockEntry(
        company: 'COMP-1',
        purpose: 'Material Receipt',
        toWarehouse: 'WH-1',
        items: [{
          'item_code': 'ITEM-1',
          'qty': 1e308,
          'valuation_rate': 1e308,
        }],
      ),
      throwsFormatException,
    );
    await expectLater(
      api.createStockReconciliation(
        company: 'COMP-1',
        warehouse: 'WH-1',
        items: [{
          'item_code': 'ITEM-1',
          'qty': 1e308,
          'valuation_rate': 1e308,
        }],
      ),
      throwsFormatException,
    );
    api.dispose();
  });


  test('purchase order search includes supplier display name and supports later pages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final starts = <String>[];
    server.listen((request) async {
      starts.add(request.uri.queryParameters['limit_start'] ?? '');
      final orFilters = jsonDecode(request.uri.queryParameters['or_filters']!) as List;
      expect(orFilters, [
        ['name', 'like', '%Supplier Name%'],
        ['supplier', 'like', '%Supplier Name%'],
        ['supplier_name', 'like', '%Supplier Name%'],
      ]);
      request.response.headers.contentType = ContentType.json;
      final start = int.parse(request.uri.queryParameters['limit_start'] ?? '0');
      final rows = start == 0
          ? List.generate(100, (index) => {
              'name': 'PO-${index + 1}',
              'supplier': 'SUP-1',
              'supplier_name': 'Supplier Name',
              'company': 'COMP-1',
            })
          : [{
              'name': 'PO-101',
              'supplier': 'SUP-1',
              'supplier_name': 'Supplier Name',
              'company': 'COMP-1',
            }];
      request.response.write(jsonEncode({'data': rows}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final first = await api.fetchPurchaseOrders(start: 0, search: 'Supplier Name');
      final second = await api.fetchPurchaseOrders(start: 100, search: 'Supplier Name');
      expect(first, hasLength(100));
      expect(second.single['name'], 'PO-101');
      expect(starts, ['0', '100']);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  testWidgets('purchase workflow displays draft and submitted purchase orders', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' && request.uri.path.endsWith('/PO-DRAFT-1')) {
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Order', 'name': 'PO-DRAFT-1', 'docstatus': 0,
          'supplier': 'SUP-1', 'supplier_name': 'مورد تجريبي',
          'company': 'COMP-1', 'status': 'Draft', 'grand_total': 50,
          'currency': 'YER', 'items': [],
        }}));
      } else if (request.method == 'GET' && request.uri.pathSegments.contains('Purchase Order')) {
        request.response.write(jsonEncode({'data': [{
          'name': 'PO-DRAFT-1', 'docstatus': 0, 'supplier': 'SUP-1',
          'supplier_name': 'مورد تجريبي', 'company': 'COMP-1',
          'status': 'Draft', 'grand_total': 50, 'currency': 'YER',
        }]}));
      } else {
        request.response.write(jsonEncode({'data': []}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(
        home: PurchaseWorkflowPage(
          api: api,
          companies: const [ErpCompany(name: 'COMP-1')],
          suppliers: const [ErpSupplier(id: 'SUP-1', name: 'مورد تجريبي')],
          items: const [ErpItem(code: 'ITEM-1', name: 'صنف تجريبي')],
          warehouses: const [],
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('أوامر الشراء (1)'), findsOneWidget);
      expect(find.text('PO-DRAFT-1'), findsOneWidget);
      await tester.tap(find.text('PO-DRAFT-1'));
      await tester.pumpAndSettle();
      expect(find.text('تعديل المسودة'), findsOneWidget);
      expect(find.text('ترحيل أمر الشراء'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase order creation permits deferred warehouse selection until receipt', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'POST' && request.uri.pathSegments.contains('Purchase Order')) {
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        expect(payload['doctype'], 'Purchase Order');
        expect(payload['supplier'], 'SUP-1');
        expect(payload['company'], 'COMP-1');
        expect(payload['items'], hasLength(1));
        expect(payload['items'][0].containsKey('warehouse'), isFalse);
        request.response.write(jsonEncode({'data': {
          'doctype': 'Purchase Order', 'name': 'PO-NEW-1', 'docstatus': 0,
        }}));
      } else {
        request.response.statusCode = 404;
        request.response.write(jsonEncode({'message': 'unexpected path: ${request.uri.path}'}));
      }
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final created = await api.createPurchaseOrder({
        'doctype': 'Purchase Order',
        'company': 'COMP-1',
        'supplier': 'SUP-1',
        'schedule_date': '2026-11-10',
        'items': [{'item_code': 'ITEM-1', 'qty': 3, 'rate': 12}],
      });
      expect(created['name'], 'PO-NEW-1');
      expect(created['docstatus'], 0);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('purchase order creation rejects missing parties, empty rows and invalid values before network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.createPurchaseOrder({
        'doctype': 'Purchase Order', 'company': 'COMP-1', 'supplier': '',
        'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 10}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createPurchaseOrder({
        'doctype': 'Purchase Order', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createPurchaseOrder({
        'doctype': 'Purchase Order', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': -1, 'rate': 10}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createPurchaseOrder({
        'doctype': 'Purchase Order', 'company': 'COMP-1', 'supplier': 'SUP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': 1e308, 'rate': 1e308}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.submitPurchaseOrder({
        'doctype': 'Purchase Order', 'name': 'PO-1', 'docstatus': 1,
      }),
      throwsFormatException,
    );
    api.dispose();
  });


}
