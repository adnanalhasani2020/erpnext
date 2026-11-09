import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';

void main() {
  test('fetchStockReorderAlerts joins ERPNext reorder rules to matching Bin rows', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <String>[];
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      requests.add(request.uri.path);
      if (request.uri.path.endsWith('/Item%20Reorder') ||
          request.uri.path.endsWith('/Item Reorder')) {
        request.response.write(jsonEncode({'data': [
          {
            'name': 'RULE-1', 'parent': 'ITEM-LOW', 'parenttype': 'Item',
            'parentfield': 'reorder_levels', 'warehouse': 'MAIN - AC',
            'warehouse_reorder_level': 10, 'warehouse_reorder_qty': 25,
          },
          {
            'name': 'RULE-2', 'parent': 'ITEM-OK', 'parenttype': 'Item',
            'parentfield': 'reorder_levels', 'warehouse': 'MAIN - AC',
            'warehouse_reorder_level': 5, 'warehouse_reorder_qty': 10,
          },
          {
            'name': 'RULE-3', 'parent': 'ITEM-GROUP', 'parenttype': 'Item',
            'parentfield': 'reorder_levels', 'warehouse_group': 'ALL - AC',
            'warehouse': 'MAIN - AC', 'warehouse_reorder_level': 100,
            'warehouse_reorder_qty': 20,
          },
          {
            'name': 'RULE-4', 'parent': 'ITEM-ZERO', 'parenttype': 'Item',
            'parentfield': 'reorder_levels', 'warehouse': 'EMPTY - AC',
            'warehouse_reorder_level': 2, 'warehouse_reorder_qty': 8,
          },
        ]}));
      } else if (request.uri.path.endsWith('/Bin')) {
        request.response.write(jsonEncode({'data': [
          {'item_code': 'ITEM-LOW', 'warehouse': 'MAIN - AC',
            'actual_qty': 3, 'projected_qty': 7, 'stock_uom': 'Nos',
            'company': 'Example Company'},
          {'item_code': 'ITEM-OK', 'warehouse': 'MAIN - AC',
            'actual_qty': 20, 'projected_qty': 18, 'stock_uom': 'Nos',
            'company': 'Example Company'},
        ]}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not found'}));
      }
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final alerts = await api.fetchStockReorderAlerts();
      expect(alerts, hasLength(2));
      expect(alerts.map((x) => x.itemCode), ['ITEM-LOW', 'ITEM-ZERO']);
      expect(alerts.first.actualQty, 3);
      expect(alerts.first.projectedQty, 7);
      expect(alerts.first.reorderLevel, 10);
      expect(alerts.last.actualQty, 0);
      expect(alerts.last.projectedQty, 0);
      expect(requests, contains('/api/resource/Item%20Reorder'));
      expect(requests, contains('/api/resource/Bin'));
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('reorder alert model validates identity and parses quantities', () {
    final alert = ErpStockReorderAlert.fromJson({
      'item_code': 'ITEM-1',
      'warehouse': 'MAIN - AC',
      'actual_qty': '2',
      'projected_qty': '4.5',
      'warehouse_reorder_level': 5,
      'warehouse_reorder_qty': 12,
      'stock_uom': 'Nos',
      'company': 'Example Company',
    });
    expect(alert.actualQty, 2);
    expect(alert.projectedQty, 4.5);
    expect(alert.reorderLevel, 5);
    expect(alert.reorderQty, 12);
    expect(alert.company, 'Example Company');
    expect(
      () => ErpStockReorderAlert.fromJson({'item_code': '', 'warehouse': 'MAIN'}),
      throwsFormatException,
    );
  });
}
