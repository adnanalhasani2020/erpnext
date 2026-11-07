import 'package:erpnext_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  companyModelTests();
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
