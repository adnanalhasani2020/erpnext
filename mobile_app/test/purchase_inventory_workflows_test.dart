import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('purchase invoice rejects missing supplier, company, or lines before network access', () async {
    final api = FrappeApi();
    await expectLater(api.createPurchaseInvoice({'doctype': 'Purchase Invoice', 'items': []}), throwsFormatException);
    await expectLater(api.createPurchaseInvoice({
      'doctype': 'Purchase Invoice', 'supplier': 'SUP-1', 'company': 'COMP-1',
      'items': [{'item_code': 'ITEM-1', 'qty': 0, 'rate': 2}],
    }), throwsFormatException);
    await expectLater(api.updateDraftPurchaseInvoice(invoiceName: '', changes: {}), throwsFormatException);
    api.dispose();
  });

  test('purchase receipt requires supplier, item, positive quantity and warehouse', () async {
    final api = FrappeApi();
    await expectLater(api.createPurchaseReceipt({'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1', 'items': []}), throwsFormatException);
    await expectLater(api.createPurchaseReceipt({
      'doctype': 'Purchase Receipt', 'company': 'COMP-1', 'supplier': 'SUP-1',
      'items': [{'item_code': 'ITEM-1', 'qty': 1, 'rate': 10}],
    }), throwsFormatException);
    api.dispose();
  });

  test('stock entries reject invalid purpose, missing warehouses and non-positive quantities', () async {
    final api = FrappeApi();
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Unknown', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Receipt', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Issue', fromWarehouse: 'WH-1', items: [{'item_code': 'I', 'qty': 0}]), throwsFormatException);
    await expectLater(api.createStockEntry(company: 'COMP-1', purpose: 'Material Transfer', fromWarehouse: 'WH-1', toWarehouse: 'WH-1', items: [{'item_code': 'I', 'qty': 1}]), throwsFormatException);
    api.dispose();
  });

  test('stock reconciliation rejects duplicate item rows and negative counted quantities', () async {
    final api = FrappeApi();
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: []), throwsFormatException);
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: [
      {'item_code': 'ITEM-1', 'qty': 3},
      {'item_code': 'ITEM-1', 'qty': 4},
    ]), throwsFormatException);
    await expectLater(api.createStockReconciliation(company: 'COMP-1', warehouse: 'WH-1', items: [
      {'item_code': 'ITEM-1', 'qty': -1},
    ]), throwsFormatException);
    api.dispose();
  });
}
