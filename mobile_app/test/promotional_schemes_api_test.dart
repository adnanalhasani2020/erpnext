import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  test('creates a native multi-slab selling promotional scheme', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'POST');
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      expect(payload['doctype'], 'Promotional Scheme');
      expect(payload['name'], 'Beverage Bundle');
      expect(payload['apply_on'], 'Item Group');
      expect(payload['item_groups'], [{'item_group': 'Beverages'}]);
      final priceSlabs = payload['price_discount_slabs'] as List;
      expect(priceSlabs, hasLength(2));
      expect(priceSlabs[0]['rate_or_discount'], 'Discount Percentage');
      expect(priceSlabs[0]['min_qty'], 5);
      expect(priceSlabs[0]['discount_percentage'], 10);
      expect(priceSlabs[1]['rate_or_discount'], 'Rate');
      expect(priceSlabs[1]['rate'], 80);
      final productSlabs = payload['product_discount_slabs'] as List;
      expect(productSlabs, hasLength(1));
      expect(productSlabs[0]['same_item'], 0);
      expect(productSlabs[0]['free_item'], 'GIFT-1');
      expect(productSlabs[0]['free_qty'], 1);
      final saved = Map<String, dynamic>.from(payload)..['doctype'] = 'Promotional Scheme';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': saved}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final saved = await api.saveSellingPromotionalScheme(
        name: 'Beverage Bundle',
        company: 'Company A',
        currency: 'YER',
        applyOn: 'Item Group',
        target: 'Beverages',
        validFrom: '2026-11-01',
        priceSlabs: [
          {'rate_or_discount': 'Discount Percentage', 'value': 10, 'min_qty': 5, 'max_qty': 0, 'min_amount': 0, 'max_amount': 0, 'for_price_list': 'Standard Selling', 'priority': '1', 'rule_description': 'خصم خمسة فأكثر'},
          {'rate_or_discount': 'Rate', 'value': 80, 'min_qty': 20, 'max_qty': 0, 'min_amount': 0, 'max_amount': 0, 'for_price_list': 'Standard Selling', 'priority': '2', 'rule_description': 'سعر الجملة'},
        ],
        productSlabs: [
          {'min_qty': 10, 'max_qty': 0, 'min_amount': 0, 'max_amount': 0, 'same_item': false, 'free_item': 'GIFT-1', 'free_qty': 1, 'priority': '1', 'rule_description': 'هدية عند الشراء'},
        ],
      );
      expect(saved['name'], 'Beverage Bundle');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('rejects promotional schemes with no discount slabs', () async {
    final api = FrappeApi();
    await expectLater(
      api.saveSellingPromotionalScheme(
        name: 'Empty scheme',
        company: 'Company A',
        currency: 'YER',
        applyOn: 'Transaction',
        validFrom: '2026-11-01',
        priceSlabs: const [],
        productSlabs: const [],
      ),
      throwsFormatException,
    );
    api.dispose();
  });
}
