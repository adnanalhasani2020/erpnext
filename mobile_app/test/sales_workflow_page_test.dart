import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/sales_workflow_page.dart';

void main() {
  test('preserves quotation and order row links while editing a mapped sales draft', () {
    final row = buildSalesWorkflowLinePayload(
      sourceRow: {
        'item_code': 'ITEM-1',
        'prevdoc_doctype': 'Quotation',
        'prevdoc_docname': 'QTN-0001',
        'quotation': 'QTN-0001',
        'quotation_item': 'QTN-ROW-1',
      },
      itemCode: 'ITEM-1',
      quantity: 3,
      rate: 8,
      warehouse: 'WH-1',
      deliveryDate: '2026-11-08',
    );
    expect(row['prevdoc_docname'], 'QTN-0001');
    expect(row['quotation_item'], 'QTN-ROW-1');
    expect(row['qty'], 3);
    expect(row['warehouse'], 'WH-1');
    expect(row['delivery_date'], '2026-11-08');
  });

  test('clears stale quotation and order links when replacing a sales draft item', () {
    final row = buildSalesWorkflowLinePayload(
      sourceRow: {
        'item_code': 'ITEM-OLD',
        'prevdoc_doctype': 'Quotation',
        'prevdoc_docname': 'QTN-0001',
        'quotation_item': 'QTN-ROW-1',
      },
      itemCode: 'ITEM-NEW',
      quantity: 1,
      rate: 10,
    );
    expect(row['item_code'], 'ITEM-NEW');
    expect(row.containsKey('prevdoc_doctype'), isFalse);
    expect(row.containsKey('prevdoc_docname'), isFalse);
    expect(row.containsKey('quotation_item'), isFalse);
  });

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
      api.createSalesWorkflowDraft('Sales Invoice', {
        'doctype': 'Sales Invoice', 'customer': 'CUST-1', 'company': 'COMP-1',
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
        onSalesInvoiceDraftCreated: (_) {},
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
