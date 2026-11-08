import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  group('FrappeApi sales document type guards', () {
    late FrappeApi api;

    setUp(() => api = FrappeApi());
    tearDown(() => api.dispose());

    test('rejects Purchase Invoice payloads in sales creation', () async {
      await expectLater(
        api.createSalesInvoice({
          'doctype': 'Purchase Invoice',
          'customer': 'CUST-1',
          'company': 'COMP-1',
          'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 10}],
        }),
        throwsFormatException,
      );
    });

    test('rejects non-sales documents before submit or cancel requests', () async {
      await expectLater(
        api.submitSalesInvoice({
          'doctype': 'Purchase Invoice',
          'name': 'PINV-1',
          'docstatus': 0,
        }),
        throwsFormatException,
      );
      await expectLater(
        api.cancelSalesInvoice({
          'doctype': 'Purchase Invoice',
          'name': 'PINV-1',
          'docstatus': 1,
        }),
        throwsFormatException,
      );
    });

    test('rejects finite quantities and rates whose multiplication overflows', () async {
      await expectLater(
        api.createSalesInvoice({
          'doctype': 'Sales Invoice',
          'customer': 'CUST-1',
          'company': 'COMP-1',
          'items': [{'item_code': 'ITEM-1', 'qty': 1e308, 'rate': 1e308}],
        }),
        throwsFormatException,
      );
      await expectLater(
        api.updateDraftSalesInvoice(
          invoiceName: 'SINV-1',
          changes: {
            'doctype': 'Sales Invoice',
            'customer': 'CUST-1',
            'company': 'COMP-1',
            'items': [{'item_code': 'ITEM-1', 'qty': 1e308, 'rate': 1e308}],
          },
        ),
        throwsFormatException,
      );
    });

    test('rejects non-sales documents before draft update requests', () async {
      await expectLater(
        api.updateDraftSalesInvoice(
          invoiceName: 'PINV-1',
          changes: {
            'doctype': 'Purchase Invoice',
            'customer': 'CUST-1',
            'company': 'COMP-1',
            'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 10}],
          },
        ),
        throwsFormatException,
      );
    });
  });
}
