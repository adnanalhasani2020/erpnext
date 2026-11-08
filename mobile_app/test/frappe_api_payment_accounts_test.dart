import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('fetchPaymentAccounts paginates eligible cash and bank accounts by company', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final pageStarts = <int>[];
    final observedFilters = <dynamic>[];

    final serverTask = () async {
      await for (final request in server) {
        if (request.uri.path == '/api/method/login') {
          request.response.headers.add(
            HttpHeaders.setCookieHeader,
            'sid=payment-session; Path=/; HttpOnly',
          );
          request.response.write(jsonEncode({'message': 'Logged In'}));
        } else if (request.uri.path == '/api/method/frappe.auth.get_logged_user') {
          request.response.write(jsonEncode({'message': 'mobile@example.com'}));
        } else if (request.uri.path == '/api/resource/Account') {
          final start = int.parse(request.uri.queryParameters['limit_start'] ?? '0');
          final pageLength = int.parse(request.uri.queryParameters['limit_page_length'] ?? '0');
          pageStarts.add(start);
          observedFilters.add(jsonDecode(request.uri.queryParameters['filters']!));
          final count = (201 - start).clamp(0, pageLength).toInt();
          final rows = List.generate(count, (index) {
            final number = start + index + 1;
            return {
              'name': 'Cash Bank $number - EX',
              'account_name': 'حساب التحصيل $number',
              'account_type': number.isEven ? 'Bank' : 'Cash',
              'account_currency': 'YER',
            };
          });
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
      await api.login('mobile@example.com', 'test-password');
      final accounts = await api.fetchPaymentAccounts(' Example Company ');

      expect(accounts, hasLength(201));
      expect(accounts.first.name, 'Cash Bank 1 - EX');
      expect(accounts.last.name, 'Cash Bank 201 - EX');
      expect(pageStarts, [0, 100, 200]);
      expect(
        observedFilters.first,
        [
          ['company', '=', 'Example Company'],
          ['disabled', '=', 0],
          ['is_group', '=', 0],
          ['account_type', 'in', ['Cash', 'Bank']],
        ],
      );
    } finally {
      api.dispose();
      await server.close(force: true);
      await serverTask;
    }
  });
}
