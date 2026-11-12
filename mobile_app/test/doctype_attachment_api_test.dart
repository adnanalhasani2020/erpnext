import 'dart:convert';
import 'dart:io';

import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('downloads an attachment only after verifying its parent document', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPaths = <String>[];
    final expectedBytes = <int>[37, 80, 68, 70, 45, 49, 46, 55, 10, 37, 226, 227];
    final serverTask = () async {
      await for (final request in server) {
        requestedPaths.add(request.uri.path);
        if (request.uri.path == '/api/resource/File/FILE-1') {
          request.response.write(jsonEncode({
            'data': {
              'doctype': 'File',
              'name': 'FILE-1',
              'attached_to_doctype': 'Sales Invoice',
              'attached_to_name': 'SINV-1',
              'file_url': '/private/files/invoice.pdf',
            },
          }));
        } else if (request.uri.path == '/private/files/invoice.pdf') {
          request.response.headers.contentType = ContentType('application', 'pdf');
          request.response.add(expectedBytes);
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
      final bytes = await api.downloadDocTypeAttachment(
        doctype: 'Sales Invoice',
        name: 'SINV-1',
        fileId: 'FILE-1',
      );
      expect(bytes, expectedBytes);
      expect(requestedPaths, [
        '/api/resource/File/FILE-1',
        '/private/files/invoice.pdf',
      ]);
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });

  test('rejects a File record attached to a different document', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var fileDownloadRequested = false;
    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/api/resource/File/FILE-2') {
          request.response.write(jsonEncode({
            'data': {
              'doctype': 'File',
              'name': 'FILE-2',
              'attached_to_doctype': 'Purchase Invoice',
              'attached_to_name': 'PINV-1',
              'file_url': '/private/files/other.pdf',
            },
          }));
        } else {
          fileDownloadRequested = true;
          request.response.add([1, 2, 3]);
        }
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.downloadDocTypeAttachment(
          doctype: 'Sales Invoice',
          name: 'SINV-1',
          fileId: 'FILE-2',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(fileDownloadRequested, isFalse);
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });

  test('never sends a file request to an external host', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestedPaths = <String>[];
    final serverTask = () async {
      await for (final request in server) {
        requestedPaths.add(request.uri.path);
        request.response.write(jsonEncode({
          'data': {
            'doctype': 'File',
            'name': 'FILE-3',
            'attached_to_doctype': 'Sales Invoice',
            'attached_to_name': 'SINV-1',
            'file_url': 'https://files.example.invalid/private/invoice.pdf',
          },
        }));
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      await expectLater(
        api.downloadDocTypeAttachment(
          doctype: 'Sales Invoice',
          name: 'SINV-1',
          fileId: 'FILE-3',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(requestedPaths, ['/api/resource/File/FILE-3']);
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
}
