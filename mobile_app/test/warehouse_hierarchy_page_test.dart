import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/warehouse_hierarchy_page.dart';

void main() {
  testWidgets('warehouse hierarchy renders parent and child warehouses', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': [
          {
            'name': 'Main - AC',
            'warehouse_name': 'Main',
            'company': 'Company A',
            'parent_warehouse': null,
            'is_group': 1,
            'disabled': 0,
          },
          {
            'name': 'Stores - AC',
            'warehouse_name': 'Stores',
            'company': 'Company A',
            'parent_warehouse': 'Main - AC',
            'is_group': 0,
            'disabled': 0,
          },
        ],
      }));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      await tester.pumpWidget(MaterialApp(home: WarehouseHierarchyPage(api: api)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Stores'), findsOneWidget);
      expect(find.textContaining('Main - AC'), findsOneWidget);
      expect(find.textContaining('Stores - AC'), findsOneWidget);
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
