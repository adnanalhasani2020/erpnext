import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  group('FrappeApi purchase payment submission', () {
    late HttpServer server;
    late FrappeApi api;
    var paymentEntryWasRefetched = false;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
      paymentEntryWasRefetched = false;
      server.listen((request) async {
        final segments = request.uri.pathSegments;
        Map<String, dynamic> response;
        if (request.method == 'GET' &&
            segments.length == 4 &&
            segments[2] == 'Purchase Invoice') {
          response = {
            'data': {
              'doctype': 'Purchase Invoice',
              'name': 'PINV-1',
              'supplier': 'SUP-1',
              'docstatus': 1,
              'is_return': 0,
              'outstanding_amount': 100,
            },
          };
        } else if (request.method == 'POST' &&
            segments.length == 4 &&
            segments[2] == 'method' &&
            segments[3] == 'erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry') {
          response = {
            'message': {
              'doctype': 'Payment Entry',
              'payment_type': 'Pay',
              'party_type': 'Supplier',
              'party': 'SUP-1',
              'paid_amount': 25,
              'references': [
                {
                  'reference_doctype': 'Purchase Invoice',
                  'reference_name': 'PINV-1',
                  'allocated_amount': 25,
                },
              ],
            },
          };
        } else if (request.method == 'POST' &&
            segments.length == 3 &&
            segments[2] == 'Payment Entry') {
          response = {
            'data': {
              'doctype': 'Payment Entry',
              'name': 'PAY-1',
              'payment_type': 'Pay',
              'party_type': 'Supplier',
              'party': 'SUP-1',
              'docstatus': 0,
              'references': [
                {
                  'reference_doctype': 'Purchase Invoice',
                  'reference_name': 'PINV-1',
                  'allocated_amount': 25,
                },
              ],
            },
          };
        } else if (request.method == 'GET' &&
            segments.length == 4 &&
            segments[2] == 'Payment Entry' &&
            segments[3] == 'PAY-1') {
          paymentEntryWasRefetched = true;
          response = {
            'data': {
              'doctype': 'Payment Entry',
              'name': 'PAY-1',
              'payment_type': 'Pay',
              'party_type': 'Supplier',
              'party': 'SUP-1',
              'docstatus': 0,
              'references': [
                {
                  'reference_doctype': 'Purchase Invoice',
                  'reference_name': 'PINV-1',
                  'allocated_amount': 25,
                },
              ],
            },
          };
        } else if (request.method == 'POST' &&
            segments.length == 4 &&
            segments[2] == 'method' &&
            segments[3] == 'frappe.client.submit') {
          response = {
            'message': {
              'doctype': 'Payment Entry',
              'name': 'PAY-1',
              'payment_type': 'Pay',
              'party_type': 'Supplier',
              'party': 'SUP-1',
              'docstatus': 1,
              'references': [
                {
                  'reference_doctype': 'Purchase Invoice',
                  'reference_name': 'PINV-1',
                  'allocated_amount': 25,
                },
              ],
            },
          };
        } else {
          response = {'message': 'Unexpected request: ${request.method} ${request.uri.path}'};
          request.response.statusCode = HttpStatus.notFound;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
    });

    tearDown(() async {
      api.dispose();
      await server.close(force: true);
    });

    test('re-fetches and submits the supplier Payment Entry draft', () async {
      final submitted = await api.payPurchaseInvoice(
        invoiceName: 'PINV-1',
        amount: 25,
      );

      expect(paymentEntryWasRefetched, isTrue);
      expect(submitted['doctype'], 'Payment Entry');
      expect(submitted['name'], 'PAY-1');
      expect(submitted['payment_type'], 'Pay');
      expect(submitted['party_type'], 'Supplier');
      expect(submitted['docstatus'], 1);
    });
  });
}
