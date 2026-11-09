import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:erpnext_mobile/api/frappe_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('creates item-specific sales promotion with minimum quantity in ERPNext', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/resource/Pricing%20Rule');
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
      expect(payload['doctype'], 'Pricing Rule');
      expect(payload['apply_on'], 'Item Code');
      expect(payload['selling'], 1);
      expect(payload['buying'], 0);
      expect(payload['rate_or_discount'], 'Discount Percentage');
      expect(payload['discount_percentage'], 10);
      expect(payload['items'], [
        {'item_code': 'ITEM-1', 'min_qty': 5},
      ]);
      final saved = Map<String, dynamic>.from(payload)
        ..['name'] = 'PR-ITEM-1'
        ..['doctype'] = 'Pricing Rule';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': saved}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final saved = await api.saveSellingPricingRule(
        title: 'Buy five save ten percent',
        priceList: 'Standard Selling',
        currency: 'YER',
        discountType: 'Discount Percentage',
        discountValue: 10,
        validFrom: '2026-11-01',
        applyOn: 'Item Code',
        itemCode: 'ITEM-1',
        minQty: 5,
      );
      expect(saved['name'], 'PR-ITEM-1');
      expect(saved['apply_on'], 'Item Code');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('rejects item promotions without a positive item quantity', () async {
    final api = FrappeApi();
    await expectLater(
      api.saveSellingPricingRule(
        title: 'Invalid promotion',
        priceList: 'Standard Selling',
        currency: 'YER',
        discountType: 'Discount Percentage',
        discountValue: 10,
        validFrom: '2026-11-01',
        applyOn: 'Item Code',
        itemCode: 'ITEM-1',
        minQty: 0,
      ),
      throwsFormatException,
    );
    api.dispose();
  });

  test('fetches sales pricing rules using the requested page offset', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'GET');
      expect(request.uri.pathSegments.last, 'Pricing Rule');
      expect(request.uri.queryParameters['limit_start'], '40');
      expect(request.uri.queryParameters['limit_page_length'], FrappeApi.pageSize.toString());
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'data': [
          {'name': 'PR-0041', 'title': 'Rule 41', 'selling': 1, 'buying': 0},
        ],
      }));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final rows = await api.fetchSellingPricingRules(start: 40);
      expect(rows, hasLength(1));
      expect(rows.single['name'], 'PR-0041');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });
}
