import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/sales_invoice_composer.dart';

void main() {
  test('rejects an empty Sales Invoice before making a network request', () async {
    final api = FrappeApi();
    await expectLater(
      api.createSalesInvoice({'doctype': 'Sales Invoice', 'customer': 'CUST-1', 'items': []}),
      throwsFormatException,
    );
    await expectLater(
      api.submitSalesInvoice({'doctype': 'Sales Invoice'}),
      throwsFormatException,
    );
    await expectLater(
      api.cancelSalesInvoice({'doctype': 'Sales Invoice', 'name': 'SINV-1', 'docstatus': 0}),
      throwsFormatException,
    );
    await expectLater(
      api.receiveSalesInvoicePayment(invoiceName: 'SINV-1', amount: 0),
      throwsFormatException,
    );
    await expectLater(api.createSalesReturn('  '), throwsFormatException);
    await expectLater(
      api.updateDraftSalesInvoice(invoiceName: '  ', changes: {'customer': 'CUST-1', 'company': 'COMP-1', 'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 1}]}),
      throwsFormatException,
    );
    api.dispose();
  });

  testWidgets('renders the Arabic sales invoice composer and its safe actions', (tester) async {
    final api = FrappeApi();
    await tester.pumpWidget(MaterialApp(
      home: SalesInvoiceComposer(
        api: api,
        customers: const [ErpCustomer(id: 'CUST-1', name: 'عميل تجريبي')],
        items: const [ErpItem(code: 'ITEM-1', name: 'صنف تجريبي', isStockItem: true)],
        warehouses: const [ErpWarehouse(id: 'WH-1', name: 'المستودع الرئيسي')],
        companies: const [ErpCompany(name: 'شركة تجريبية', abbr: 'EX')],
        onCompleted: (_) {},
      ),
    ));

    expect(find.text('فاتورة مبيعات جديدة'), findsOneWidget);
    expect(find.text('الشركة'), findsOneWidget);
    expect(find.text('العميل'), findsOneWidget);
    expect(find.text('حفظ كمسودة'), findsOneWidget);
    expect(find.text('حفظ وترحيل الفاتورة'), findsOneWidget);
    expect(find.text('تحديث المخزون عند الترحيل'), findsOneWidget);

    api.dispose();
  });

  testWidgets('loads an existing draft into the editable composer', (tester) async {
    final api = FrappeApi();
    await tester.pumpWidget(MaterialApp(
      home: SalesInvoiceComposer(
        api: api,
        customers: const [ErpCustomer(id: 'CUST-1', name: 'عميل تجريبي')],
        items: const [ErpItem(code: 'ITEM-1', name: 'صنف تجريبي')],
        warehouses: const [],
        companies: const [ErpCompany(name: 'شركة تجريبية', abbr: 'EX')],
        initialDraft: {
          'doctype': 'Sales Invoice',
          'name': 'SINV-DRAFT-1',
          'docstatus': 0,
          'customer': 'CUST-1',
          'customer_name': 'عميل تجريبي',
          'company': 'شركة تجريبية',
          'posting_date': '2026-11-08',
          'update_stock': 0,
          'items': [
            {'item_code': 'ITEM-1', 'item_name': 'صنف تجريبي', 'qty': 2, 'rate': 15},
          ],
        },
        onCompleted: (_) {},
      ),
    ));

    expect(find.text('تعديل مسودة فاتورة'), findsOneWidget);
    expect(find.text('حفظ تعديلات المسودة'), findsOneWidget);
    expect(find.text('رقم المسودة: SINV-DRAFT-1'), findsOneWidget);
    expect(find.text('الإجمالي: 30.00'), findsOneWidget);
    api.dispose();
  });

  testWidgets('recalculates the line total when quantity and rate change', (tester) async {
    final api = FrappeApi();
    await tester.pumpWidget(MaterialApp(
      home: SalesInvoiceComposer(
        api: api,
        customers: const [ErpCustomer(id: 'CUST-1', name: 'عميل تجريبي')],
        items: const [ErpItem(code: 'ITEM-1', name: 'صنف تجريبي', isStockItem: false)],
        warehouses: const [],
        companies: const [ErpCompany(name: 'شركة تجريبية', abbr: 'EX')],
        onCompleted: (_) {},
      ),
    ));

    await tester.enterText(find.byType(TextFormField).at(0), '3');
    await tester.enterText(find.byType(TextFormField).at(1), '12.5');
    await tester.pump();

    expect(find.text('الإجمالي: 37.50'), findsOneWidget);
    api.dispose();
  });
}
