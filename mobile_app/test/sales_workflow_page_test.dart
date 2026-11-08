import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/sales_workflow_page.dart';

void main() {
  test('sales workflow drafts reject missing customer, company and items before network access', () async {
    final api = FrappeApi();
    await expectLater(
      api.createSalesWorkflowDraft('Quotation', {
        'doctype': 'Quotation', 'customer': 'CUST-1', 'company': 'COMP-1', 'items': [],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createSalesWorkflowDraft('Sales Order', {
        'doctype': 'Sales Order', 'customer': '', 'company': 'COMP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 2}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createSalesWorkflowDraft('Delivery Note', {
        'doctype': 'Delivery Note', 'customer': 'CUST-1', 'company': 'COMP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 2}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createSalesWorkflowDraft('Purchase Invoice', {
        'doctype': 'Purchase Invoice', 'supplier': 'SUP-1', 'company': 'COMP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 2}],
      }),
      throwsFormatException,
    );
    await expectLater(
      api.createSalesWorkflowDraft('Quotation', {
        'doctype': 'Quotation', 'customer': 'CUST-1', 'company': 'COMP-1',
        'items': [{'item_code': 'ITEM-1', 'qty': -1, 'rate': 2}],
      }),
      throwsFormatException,
    );
    api.dispose();
  });

  testWidgets('renders quotation, sales order and delivery note tabs', (tester) async {
    final api = FrappeApi();
    await tester.pumpWidget(MaterialApp(
      home: SalesWorkflowPage(
        api: api,
        companies: const [ErpCompany(name: 'شركة تجريبية')],
        customers: const [ErpCustomer(id: 'CUST-1', name: 'عميل تجريبي')],
        items: const [ErpItem(code: 'ITEM-1', name: 'صنف تجريبي')],
        warehouses: const [],
        onChanged: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('عروض الأسعار'), findsOneWidget);
    expect(find.text('أوامر البيع'), findsOneWidget);
    expect(find.text('أذون التسليم'), findsOneWidget);
    await tester.tap(find.text('أوامر البيع'));
    await tester.pumpAndSettle();
    expect(find.text('إنشاء أمر بيع'), findsOneWidget);
    await tester.tap(find.text('أذون التسليم'));
    await tester.pumpAndSettle();
    expect(find.text('أذون التسليم'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
