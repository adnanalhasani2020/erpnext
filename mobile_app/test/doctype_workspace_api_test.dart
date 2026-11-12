import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('fetchWorkspaceDirectory uses the permission-filtered v16 Desk workspace list', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPaths = <String>[];
    final serverTask = () async {
      await for (final request in server) {
        requestedPaths.add(request.uri.path);
        if (request.uri.path == '/api/method/frappe.sessions.get') {
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
              'title': 'Selling',
              'links': [
                {'type': 'Card Break', 'label': 'Orders'},
                {'type': 'Link', 'link_type': 'DocType', 'link_to': 'Sales Order'},
              ],
              'shortcuts': [
                {'type': 'DocType', 'link_to': 'Sales Invoice', 'label': 'Invoices'},
              ],
            },
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Not found'}));
        }
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      final workspaces = await api.fetchWorkspaceDirectory();
      expect(workspaces, hasLength(1));
      expect(workspaces.single['name'], 'Selling');
      expect(workspaces.single['links'], isA<List>());
      expect(workspaces.single['shortcuts'], isA<List>());
      expect(requestedPaths, [
        '/api/method/frappe.sessions.get',
        '/api/resource/Workspace/Selling',
      ]);
      expect(requestedPaths, isNot(contains('/api/resource/Workspace')));
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });

  test('fetchWorkspaceDirectory falls back to the v15 Desk workspace method', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPaths = <String>[];
    final serverTask = () async {
      await for (final request in server) {
        requestedPaths.add(request.uri.path);
        if (request.uri.path == '/api/method/frappe.desk.desktop.get_workspace_sidebar_items') {
          request.response.write(jsonEncode({
            'message': {
              'workspace_pages': [
                {'name': 'Stock', 'title': 'Stock'},
              ],
            },
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(jsonEncode({'message': 'Not found'}));
        }
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      final workspaces = await api.fetchWorkspaceDirectory();
      expect(workspaces, hasLength(1));
      expect(workspaces.single['name'], 'Stock');
      expect(requestedPaths, [
        '/api/method/frappe.desk.desktop.get_workspace_sidebar_items',
        '/api/method/frappe.sessions.get',
        '/api/resource/Workspace/Stock',
      ]);
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
}
