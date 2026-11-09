import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/models/erp_models.dart';

void main() {
  group('ErpStockBalance valuation', () {
    test('parses ERPNext Bin valuation rate and stock value', () {
      final balance = ErpStockBalance.fromJson({
        'item_code': 'ITEM-001',
        'warehouse': 'Main - AC',
        'actual_qty': 4,
        'reserved_qty': 1,
        'projected_qty': 6,
        'stock_uom': 'Nos',
        'valuation_rate': 12.5,
        'stock_value': 50,
      });

      expect(balance.actualQty, 4);
      expect(balance.availableQty, 3);
      expect(balance.valuationRate, 12.5);
      expect(balance.stockValue, 50);
    });

    test('keeps valuation optional for sites that do not expose Bin values', () {
      final balance = ErpStockBalance.fromJson({
        'item_code': 'ITEM-002',
        'warehouse': 'Main - AC',
        'actual_qty': '2.5',
      });

      expect(balance.valuationRate, isNull);
      expect(balance.stockValue, isNull);
    });

    test('ignores malformed or non-finite optional valuation values', () {
      final balance = ErpStockBalance.fromJson({
        'item_code': 'ITEM-003',
        'warehouse': 'Main - AC',
        'actual_qty': 0,
        'valuation_rate': 'NaN',
        'stock_value': 'not-a-number',
      });

      expect(balance.valuationRate, isNull);
      expect(balance.stockValue, isNull);
    });
  });
}
