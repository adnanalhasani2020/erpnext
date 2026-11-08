import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('does not follow API redirects or forward session cookies to the target', () async {
    final targetServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var targetHits = 0;
    String? targetCookie;
    final targetTask = () async {
      await for (final request in targetServer) {
        targetHits++;
        targetCookie = request.headers.value(HttpHeaders.cookieHeader);
        request.response.write(jsonEncode({'data': []}));
        await request.response.close();
      }
    }();

    final sourceServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sourceTask = () async {
      await for (final request in sourceServer) {
        if (request.uri.path == '/api/method/login') {
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'sid=private-session; Path=/; HttpOnly',
          );
          request.response.write(jsonEncode({'message': 'Logged In'}));
        } else if (request.uri.path == '/api/method/frappe.auth.get_logged_user') {
          request.response.write(jsonEncode({'message': 'mobile@example.com'}));
        } else if (request.uri.path == '/api/resource/Company') {
          request.response.statusCode = HttpStatus.found;
          request.response.headers.set(
            HttpHeaders.locationHeader,
            'http://127.0.0.1:${targetServer.port}/capture',
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${sourceServer.port}');
    try {
      expect(await api.login('mobile@example.com', 'test-password'), 'mobile@example.com');
      await expectLater(api.fetchCompanies(), throwsA(isA<Exception>()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(targetHits, 0);
      expect(targetCookie, isNull);
    } finally {
      api.dispose();
      await sourceServer.close(force: true);
      await targetServer.close(force: true);
      await sourceTask;
      await targetTask;
    }
  });
}
