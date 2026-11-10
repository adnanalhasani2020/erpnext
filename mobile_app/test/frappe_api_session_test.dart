import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('ignores an in-flight response after logout without restoring its cookies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final companyRequestStarted = Completer<void>();
    final releaseCompanyResponse = Completer<void>();
    final companyCookies = <String?>[];
    var companyRequests = 0;

    final serverTask = () async {
      await for (final request in server) {
        unawaited(() async {
          if (request.uri.path == '/api/method/login') {
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'sid=active-session; Path=/; HttpOnly',
            );
            request.response.write(jsonEncode({'message': 'Logged In'}));
          } else if (request.uri.path == '/api/method/frappe.auth.get_logged_user') {
            request.response.write(jsonEncode({'message': 'mobile@example.com'}));
          } else if (request.uri.path == '/api/method/logout') {
            request.response.write(jsonEncode({'message': 'Logged Out'}));
          } else if (request.uri.path == '/api/resource/Company') {
            companyRequests++;
            companyCookies.add(request.headers.value(HttpHeaders.cookieHeader));
            if (companyRequests == 1) {
              if (!companyRequestStarted.isCompleted) companyRequestStarted.complete();
              await releaseCompanyResponse.future;
              request.response.headers.add(
                HttpHeaders.setCookieHeader,
                'sid=stale-session; Path=/; HttpOnly',
              );
              request.response.write(jsonEncode({
                'data': [{'name': 'Stale Company', 'abbr': 'SC'}],
              }));
            } else {
              request.response.statusCode = HttpStatus.forbidden;
              request.response.write(jsonEncode({'message': 'Not logged in'}));
            }
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        }());
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      await api.login('mobile@example.com', 'test-password');
      final pendingCompanies = api.fetchCompanies();
      await companyRequestStarted.future;

      await api.logout();
      releaseCompanyResponse.complete();

      await expectLater(pendingCompanies, throwsA(isA<Exception>()));
      await expectLater(api.fetchCompanies(), throwsA(isA<Exception>()));

      expect(companyCookies, hasLength(2));
      expect(companyCookies.first, contains('sid=active-session'));
      expect(companyCookies.last, isNull);
    } finally {
      if (!releaseCompanyResponse.isCompleted) releaseCompanyResponse.complete();
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
  test('guest mode blocks all network and write-style API calls', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    final serverTask = () async {
      await for (final request in server) {
        requestCount++;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'data': []}));
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    api.enableGuestMode();
    try {
      await expectLater(api.fetchCompanies(), throwsA(isA<Exception>()));
      expect(requestCount, 0);

      await expectLater(
        api.fetchAvailableSerialNumbers(
          itemCode: 'ITEM-001',
          warehouse: 'Main - CO',
          quantity: 1,
        ),
        throwsA(isA<Exception>()),
      );
      expect(requestCount, 0);
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
}
