import 'package:erpnext_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/widgets/load_more_button.dart';
import 'package:erpnext_mobile/widgets/server_search_field.dart';

void main() {
  test('advances the session generation when the server changes', () {
    final api = FrappeApi();
    api.configure('https://first.example.com');
    final firstGeneration = api.sessionGeneration;
    api.configure('https://first.example.com/');
    expect(api.sessionGeneration, firstGeneration);
    api.configure('https://second.example.com');
    expect(api.sessionGeneration, greaterThan(firstGeneration));
    api.dispose();
  });

  test('invalidates the current session immediately on logout', () async {
    final api = FrappeApi();
    api.configure('https://erp.example.com');
    final generation = api.sessionGeneration;
    final logout = api.logout();
    expect(api.sessionGeneration, generation + 1);
    await logout;
    api.dispose();
  });

  test('rejects server URLs containing credentials, query, or fragment', () {
    final api = FrappeApi();
    expect(() => api.configure('https://user:pass@example.com'), throwsFormatException);
    expect(() => api.configure('https://erp.example.com?token=secret'), throwsFormatException);
    expect(() => api.configure('https://erp.example.com#fragment'), throwsFormatException);
    api.dispose();
  });

  test('builds ERPNext resource page URLs with a safe offset', () {
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: 'https://erp.example.com/',
      resource: 'Item',
      fields: ['item_code', 'item_name'],
      filters: [['disabled', '=', 0]],
      orderBy: 'modified desc',
      start: 200,
    );
    expect(uri.path, '/api/resource/Item');
    expect(uri.queryParameters['limit_page_length'], '100');
    expect(uri.queryParameters['limit_start'], '200');
    expect(uri.queryParameters['order_by'], 'modified desc');
    expect(uri.queryParameters['filters'], '[["disabled","=",0]]');
  });

  test('builds server-side OR search filters with pagination', () {
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: 'https://erp.example.com',
      resource: 'Item',
      fields: ['item_code', 'item_name'],
      filters: [['disabled', '=', 0]],
      orFilters: [
        ['item_code', 'like', '%coffee%'],
        ['item_name', 'like', '%coffee%'],
      ],
      orderBy: 'modified desc',
      start: 100,
    );
    expect(
      uri.queryParameters['or_filters'],
      '[["item_code","like","%coffee%"],["item_name","like","%coffee%"]]',
    );
    expect(uri.queryParameters['limit_start'], '100');
    expect(uri.queryParameters['filters'], '[["disabled","=",0]]');
  });

  test('includes bins with reserved or projected quantity even when actual quantity is zero', () {
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: 'https://erp.example.com',
      resource: 'Bin',
      fields: ['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty'],
      orFilters: [
        ['actual_qty', '!=', 0],
        ['reserved_qty', '!=', 0],
        ['projected_qty', '!=', 0],
      ],
      orderBy: 'item_code asc, warehouse asc',
      start: 100,
    );
    expect(
      uri.queryParameters['or_filters'],
      '[["actual_qty","!=",0],["reserved_qty","!=",0],["projected_qty","!=",0]]',
    );
    expect(uri.queryParameters['filters'], isNull);
    expect(uri.queryParameters['limit_start'], '100');
    expect(uri.queryParameters['order_by'], 'item_code asc, warehouse asc');
  });

  test('clamps invalid pagination offsets and page lengths', () {
    final uri = FrappeApi.buildResourcePageUri(
      baseUrl: 'https://erp.example.com',
      resource: 'Item',
      fields: ['item_code'],
      orderBy: 'name asc',
      start: -5,
      pageLength: 0,
    );
    expect(uri.queryParameters['limit_start'], '0');
    expect(uri.queryParameters['limit_page_length'], '1');
  });

  test('parses ERPNext Item fields', () {
    final item = ErpItem.fromJson({
      'item_code': 'ITEM-001',
      'item_name': 'Test Item',
      'item_group': 'Products',
      'stock_uom': 'Nos',
      'is_stock_item': 1,
    });
    expect(item.code, 'ITEM-001');
    expect(item.name, 'Test Item');
    expect(item.isStockItem, isTrue);
  });

  test('rejects Item without item_code', () {
    expect(() => ErpItem.fromJson({'item_name': 'Missing code'}), throwsFormatException);
  });


  test('parses ERPNext Bin stock balance fields', () {
    final balance = ErpStockBalance.fromJson({
      'item_code': 'ITEM-001',
      'warehouse': 'Main Store - EX',
      'actual_qty': 12.5,
      'reserved_qty': 2,
      'projected_qty': 15,
      'stock_uom': 'Nos',
    });
    expect(balance.itemCode, 'ITEM-001');
    expect(balance.warehouse, 'Main Store - EX');
    expect(balance.actualQty, 12.5);
    expect(balance.reservedQty, 2);
    expect(balance.projectedQty, 15);
    expect(balance.stockUom, 'Nos');
  });


  test('calculates available stock after reserved quantity', () {
    final balance = ErpStockBalance.fromJson({'item_code': 'ITEM-002', 'warehouse': 'Main Store', 'actual_qty': 10, 'reserved_qty': 3});
    expect(balance.availableQty, 7);
  });

  test('preserves negative available stock instead of hiding shortage', () {
    final balance = ErpStockBalance.fromJson({'item_code': 'ITEM-003', 'warehouse': 'Main Store', 'actual_qty': 2, 'reserved_qty': 5});
    expect(balance.availableQty, -3);
  });

  test('rejects Bin row without item or warehouse', () {
    expect(() => ErpStockBalance.fromJson({'actual_qty': 2}), throwsFormatException);
  });

  test('parses ERPNext Warehouse fields', () {
    final warehouse = ErpWarehouse.fromJson({
      'name': 'Main Store - EX',
      'warehouse_name': 'Main Store',
      'company': 'Example Ltd',
    });
    expect(warehouse.id, 'Main Store - EX');
    expect(warehouse.name, 'Main Store');
    expect(warehouse.company, 'Example Ltd');
  });

  test('rejects Warehouse without its ERPNext name', () {
    expect(() => ErpWarehouse.fromJson({'warehouse_name': 'Main Store'}), throwsFormatException);
  });

  test('parses ERPNext Customer fields', () {
    final customer = ErpCustomer.fromJson({'name': 'CUST-001', 'customer_name': 'Test Customer', 'customer_type': 'Company', 'customer_group': 'Commercial', 'territory': 'Yemen'});
    expect(customer.id, 'CUST-001');
    expect(customer.name, 'Test Customer');
    expect(customer.group, 'Commercial');
  });

  test('rejects Customer without its document name', () {
    expect(() => ErpCustomer.fromJson({'customer_name': 'Missing ID'}), throwsFormatException);
  });

  test('parses ERPNext Sales Invoice fields and monetary values', () {
    final invoice = ErpSalesInvoice.fromJson({'name': 'SINV-0001', 'customer': 'CUST-001', 'customer_name': 'Test Customer', 'posting_date': '2026-11-07', 'due_date': '2026-11-14', 'currency': 'YER', 'grand_total': '1250.50', 'outstanding_amount': 500, 'status': 'Partly Paid'});
    expect(invoice.id, 'SINV-0001');
    expect(invoice.customerName, 'Test Customer');
    expect(invoice.grandTotal, 1250.5);
    expect(invoice.outstandingAmount, 500);
    expect(invoice.status, 'Partly Paid');
  });

  test('rejects Sales Invoice without required customer data', () {
    expect(() => ErpSalesInvoice.fromJson({'name': 'SINV-0002'}), throwsFormatException);
  });
  test('parses ERPNext Supplier fields', () {
    final supplier = ErpSupplier.fromJson({'name': 'SUP-001', 'supplier_name': 'Test Supplier', 'supplier_group': 'Local', 'supplier_type': 'Company'});
    expect(supplier.id, 'SUP-001');
    expect(supplier.name, 'Test Supplier');
    expect(supplier.group, 'Local');
  });

  test('rejects Supplier without its name', () {
    expect(() => ErpSupplier.fromJson({'name': 'SUP-001'}), throwsFormatException);
  });

  test('parses ERPNext Purchase Invoice fields', () {
    final invoice = ErpPurchaseInvoice.fromJson({'name': 'PINV-0001', 'supplier': 'SUP-001', 'supplier_name': 'Test Supplier', 'posting_date': '2026-11-07', 'due_date': '2026-11-14', 'currency': 'YER', 'grand_total': 2400, 'outstanding_amount': '1200.50', 'status': 'Partly Paid'});
    expect(invoice.id, 'PINV-0001');
    expect(invoice.supplierName, 'Test Supplier');
    expect(invoice.grandTotal, 2400);
    expect(invoice.outstandingAmount, 1200.5);
    expect(invoice.status, 'Partly Paid');
  });

  test('rejects Purchase Invoice without supplier data', () {
    expect(() => ErpPurchaseInvoice.fromJson({'name': 'PINV-0002'}), throwsFormatException);
  });
  test('parses invoice line item values', () {
    final line = ErpInvoiceLine.fromJson({'item_code': 'ITEM-1', 'item_name': 'Sample item', 'qty': '2.5', 'uom': 'Nos', 'rate': 10, 'amount': '25', 'warehouse': 'Main - EX'});
    expect(line.itemCode, 'ITEM-1');
    expect(line.itemName, 'Sample item');
    expect(line.qty, 2.5);
    expect(line.rate, 10);
    expect(line.amount, 25);
    expect(line.warehouse, 'Main - EX');
  });

  test('rejects invoice line without item identity', () {
    expect(() => ErpInvoiceLine.fromJson({'qty': 2, 'amount': 10}), throwsFormatException);
  });
  companyModelTests();
  testWidgets('server search field disables editing and shows progress while loading', (tester) async {
    final controller = TextEditingController(text: 'Acme');
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerSearchField(
          controller: controller,
          label: 'بحث في العملاء',
          loading: true,
          onSearch: (value) => submitted = value,
        ),
      ),
    ));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('جارٍ البحث...'), findsOneWidget);
    await tester.tap(find.text('جارٍ البحث...'));
    expect(submitted, isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('server search field submits the entered query', (tester) async {
    final controller = TextEditingController();
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerSearchField(
          controller: controller,
          label: 'بحث في العملاء',
          onSearch: (value) => submitted = value,
        ),
      ),
    ));
    await tester.enterText(find.byType(TextField), 'Acme');
    await tester.tap(find.text('بحث في الخادم'));
    expect(submitted, 'Acme');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('server search field clears the query through its clear action', (tester) async {
    final controller = TextEditingController(text: 'Acme');
    String? submitted;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServerSearchField(
          controller: controller,
          label: 'بحث في العملاء',
          onSearch: (value) => submitted = value,
        ),
      ),
    ));
    await tester.tap(find.byTooltip('مسح البحث'));
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(submitted, isEmpty);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('load-more button invokes its callback', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoadMoreButton(false, 'تحميل المزيد', () => tapped = true),
      ),
    ));
    await tester.tap(find.text('تحميل المزيد'));
    expect(tapped, isTrue);
  });

  testWidgets('load-more button disables itself while loading', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LoadMoreButton(true, 'تحميل المزيد', () => tapped = true),
      ),
    ));
    expect(find.text('جارٍ التحميل...'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(tapped, isFalse);
  });

  testWidgets('renders the Arabic ERPNext login screen', (tester) async {
    await tester.pumpWidget(const ErpNextMobileApp());

    expect(find.text('ERPNext للجوال'), findsOneWidget);
    expect(find.text('رابط الخادم'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsOneWidget);
  });

  testWidgets('rejects insecure non-local server URLs', (tester) async {
    await tester.pumpWidget(const ErpNextMobileApp());

    await tester.enterText(find.byType(TextField).at(0), 'http://erp.example.com');
    await tester.enterText(find.byType(TextField).at(1), 'test-user');
    await tester.enterText(find.byType(TextField).at(2), 'test-password');
    await tester.tap(find.text('تسجيل الدخول'));
    await tester.pumpAndSettle();

    expect(find.textContaining('أدخل رابطاً صحيحاً'), findsOneWidget);
  });
}


void companyModelTests() {
  test('parses a Company returned by the Frappe resource API', () {
    final company = ErpCompany.fromJson({'name': 'Example Ltd', 'abbr': 'EX'});
    expect(company.name, 'Example Ltd');
    expect(company.abbr, 'EX');
  });

  test('rejects a Company response without a name', () {
    expect(() => ErpCompany.fromJson({'abbr': 'EX'}), throwsFormatException);
  });
}
