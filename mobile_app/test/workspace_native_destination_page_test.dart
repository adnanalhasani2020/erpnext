import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/doctype_workspace_model.dart';
import 'package:erpnext_mobile/workspace_native_destination_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('native Workspace destination renders and routes only server-returned links', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPaths = <String>[];
    final subscription = server.listen((request) async {
      requestedPaths.add(request.uri.path);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/api/method/frappe.desk.desktop.get_workspace_sidebar_items') {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not found'}));
      } else if (request.uri.path == '/api/method/frappe.sessions.get') {
        request.response.write(jsonEncode({
          'message': {
            'workspace_pages': [
              {'name': 'Selling', 'title': 'Selling'},
            ],
          },
        }));
      } else if (request.uri.path == '/api/resource/Workspace/Selling') {
        request.response.write(jsonEncode({
          'data': {
            'doctype': 'Workspace',
            'name': 'Selling',
            'title': 'المبيعات',
            'links': [
              {'type': 'Card Break', 'label': 'الطلبات'},
              {
                'type': 'Link',
                'link_type': 'DocType',
                'link_to': 'Sales Order',
                'label': 'Sales Order',
                'route_options': {'company': 'Test Company'},
              },
            ],
            'shortcuts': [],
            'charts': [],
            'quick_lists': [],
            'number_cards': [],
          },
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write(jsonEncode({'message': 'Not found'}));
      }
      await request.response.close();
    });

    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    ErpDocTypeDefinition? openedDefinition;
    try {
      await tester.pumpWidget(MaterialApp(
        home: WorkspaceNativeDestinationPage(
          api: api,
          title: 'المبيعات',
          linkType: 'Workspace',
          target: 'Selling',
          onOpenDefinition: (definition) => openedDefinition = definition,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('المبيعات'), findsNWidgets(2));
      expect(find.text('الطلبات'), findsOneWidget);
      expect(find.text('Sales Order'), findsOneWidget);

      await tester.tap(find.text('Sales Order'));
      await tester.pump();

      expect(openedDefinition?.doctype, 'Sales Order');
      expect(openedDefinition?.routeOptions['company'], 'Test Company');
      expect(requestedPaths, contains('/api/resource/Workspace/Selling'));
      expect(requestedPaths, isNot(contains('/api/resource/Workspace')));
    } finally {
      api.dispose();
      await server.close(force: true);
      await subscription.cancel();
    }
  });
}
