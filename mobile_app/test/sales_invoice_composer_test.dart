import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';
import 'package:erpnext_mobile/models/erp_models.dart';
import 'package:erpnext_mobile/sales_invoice_composer.dart';

List<DropdownMenuItem<T>> dropdownItems<T>(WidgetTester tester) {
  final dropdown = tester.widget<DropdownButton<T>>(
    find.descendant(
      of: find.byType(DropdownButtonFormField<T>),
      matching: find.byType(DropdownButton<T>),
    ),
  );
  return dropdown.items ?? const <DropdownMenuItem<T>>[];
}

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
    await expectLater(api.fetchPaymentAccounts('  '), throwsFormatException);
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

  test('marks credit notes as sales returns in the invoice list model', () {
    final invoice = ErpSalesInvoice.fromJson({
      'name': 'SINV-RET-1',
      'customer': 'CUST-1',
      'customer_name': 'عميل تجريبي',
      'grand_total': -50,
      'outstanding_amount': 0,
      'is_return': 1,
      'return_against': 'SINV-1',
    });
    expect(invoice.isReturn, isTrue);
    expect(invoice.returnAgainst, 'SINV-1');
  });

  test('parses eligible ERPNext cash and bank payment accounts', () {
    final account = ErpPaymentAccount.fromJson({
      'name': 'Cash - EX',
      'account_name': 'الصندوق الرئيسي',
      'account_type': 'Cash',
      'account_currency': 'YER',
    });
    expect(account.name, 'Cash - EX');
    expect(account.accountName, 'الصندوق الرئيسي');
    expect(account.accountType, 'Cash');
    expect(account.currency, 'YER');
    expect(
      () => ErpPaymentAccount.fromJson({'name': 'Group - EX', 'account_type': 'Receivable'}),
      throwsFormatException,
    );
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
    await tester.scrollUntilVisible(find.text('حفظ كمسودة'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('حفظ كمسودة'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('حفظ وترحيل الفاتورة'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('حفظ وترحيل الفاتورة'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('تحديث المخزون عند الترحيل'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
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
        initialDraft: const {
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
    await tester.scrollUntilVisible(find.text('حفظ تعديلات المسودة'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('حفظ تعديلات المسودة'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('رقم المسودة: SINV-DRAFT-1'), 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('رقم المسودة: SINV-DRAFT-1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('الإجمالي: 30.00'), 250, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
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

  testWidgets('limits invoice warehouses to the selected company', (tester) async {
    final api = FrappeApi();
    await tester.pumpWidget(MaterialApp(
      home: SalesInvoiceComposer(
        api: api,
        customers: const [ErpCustomer(id: 'CUST-1', name: 'عميل تجريبي')],
        items: const [
          ErpItem(code: 'ITEM-1', name: 'صنف مخزني', isStockItem: true),
        ],
        warehouses: const [
          ErpWarehouse(id: 'WH-A', name: 'مستودع الشركة أ', company: 'Company A'),
          ErpWarehouse(id: 'WH-B', name: 'مستودع الشركة ب', company: 'Company B'),
          ErpWarehouse(id: 'WH-UNKNOWN', name: 'مستودع دون شركة'),
        ],
        companies: const [
          ErpCompany(name: 'Company A'),
          ErpCompany(name: 'Company B'),
        ],
        onCompleted: (_) {},
      ),
    ));

    var companyField = tester.widget<DropdownButtonFormField<ErpCompany>>(
      find.byType(DropdownButtonFormField<ErpCompany>),
    );
    final companyA = dropdownItems<ErpCompany>(tester)
        .singleWhere((item) => item.value?.name == 'Company A')
        .value!;
    companyField.onChanged!(companyA);
    await tester.pump();

    var itemField = tester.widget<DropdownButtonFormField<ErpItem>>(
      find.byType(DropdownButtonFormField<ErpItem>),
    );
    final stockItem = dropdownItems<ErpItem>(tester)
        .singleWhere((item) => item.value?.code == 'ITEM-1')
        .value!;
    itemField.onChanged!(stockItem);
    await tester.pump();

    final warehouseField = tester.widget<DropdownButtonFormField<ErpWarehouse>>(
      find.byType(DropdownButtonFormField<ErpWarehouse>),
    );
    final availableWarehouseIds = dropdownItems<ErpWarehouse>(tester)
        .where((item) => item.value != null)
        .map((item) => item.value!.id)
        .toList();

    expect(availableWarehouseIds, ['WH-A']);

    final companyWarehouse = dropdownItems<ErpWarehouse>(tester)
        .singleWhere((item) => item.value?.id == 'WH-A')
        .value!;
    warehouseField.onChanged!(companyWarehouse);
    await tester.pump();

    companyField = tester.widget<DropdownButtonFormField<ErpCompany>>(
      find.byType(DropdownButtonFormField<ErpCompany>),
    );
    final companyB = dropdownItems<ErpCompany>(tester)
        .singleWhere((item) => item.value?.name == 'Company B')
        .value!;
    companyField.onChanged!(companyB);
    await tester.pump();

    final switchedWarehouseField =
        tester.widget<DropdownButtonFormField<ErpWarehouse>>(
      find.byType(DropdownButtonFormField<ErpWarehouse>),
    );
    expect(switchedWarehouseField.initialValue, isNull);
    expect(
      dropdownItems<ErpWarehouse>(tester)
          .where((item) => item.value != null)
          .map((item) => item.value!.id),
      ['WH-B'],
    );
    api.dispose();
  });

}
