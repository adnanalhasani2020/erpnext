import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('fetchCompanies loads every page and removes expired session cookies', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final companyPageStarts = <int>[];
    final companyCookieHeaders = <String?>[];

    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/api/method/login') {
          request.response.headers.add(HttpHeaders.setCookieHeader, 'sid=session-value; Path=/; HttpOnly');
          request.response.headers.add(HttpHeaders.setCookieHeader, 'csrf_token=csrf-value; Path=/');
          request.response.write(jsonEncode({'message': 'Logged In'}));
        } else if (request.uri.path == '/api/method/frappe.auth.get_logged_user') {
          request.response.write(jsonEncode({'message': 'mobile@example.com'}));
        } else if (request.uri.path == '/api/resource/Company') {
          final start = int.parse(request.uri.queryParameters['limit_start'] ?? '0');
          final pageLength = int.parse(request.uri.queryParameters['limit_page_length'] ?? '0');
          companyPageStarts.add(start);
          companyCookieHeaders.add(request.headers.value(HttpHeaders.cookieHeader));
          final count = start == 0 ? pageLength : (101 - start).clamp(0, pageLength).toInt();
          final rows = List.generate(
            count,
            (index) {
              final number = start + index + 1;
              return {'name': 'Company $number', 'abbr': 'C$number'};
            },
          );
          if (start == 100) {
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'sid=; Max-Age=0; Path=/; HttpOnly',
            );
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'csrf_token=; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/',
            );
            request.response.headers.add(
              HttpHeaders.setCookieHeader,
              'theme=; Max-Age=3600; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/',
            );
          }
          request.response.write(jsonEncode({'data': rows}));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      }
    }();

    final api = FrappeApi();
    api.configure('http://127.0.0.1:${server.port}');
    try {
      expect(await api.login('mobile@example.com', 'test-password'), 'mobile@example.com');

      final companies = await api.fetchCompanies();
      expect(companies, hasLength(101));
      expect(companies.first.name, 'Company 1');
      expect(companies.last.name, 'Company 101');
      expect(companyPageStarts, [0, 100]);

      await api.fetchCompanies();
      expect(companyPageStarts, [0, 100, 0, 100]);
      expect(companyCookieHeaders[0], contains('sid=session-value'));
      expect(companyCookieHeaders[2], isNot(contains('sid=session-value')));
      expect(companyCookieHeaders[2], isNot(contains('csrf_token=csrf-value')));
      expect(companyCookieHeaders[2], contains('theme='));
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
}
