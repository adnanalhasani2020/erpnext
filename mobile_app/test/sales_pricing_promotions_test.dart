import 'dart:core';
import 'dart:core' as core;
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
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
      expect(payload['doctype'], 'Pricing Rule');
      expect(payload['apply_on'], 'Item Code');
      expect(payload['selling'], 1);
      expect(payload['buying'], 0);
      expect(payload['rate_or_discount'], 'Discount Percentage');
      expect(payload['discount_percentage'], 10);
      expect(payload['items'], [{'item_code': 'ITEM-1'}]);
      expect(payload['min_qty'], 5);
      final saved = core.Map<String, dynamic>.from(payload)
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
  test('creates item-group pricing rules with amount thresholds and priority controls', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.method, 'POST');
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
      expect(payload['apply_on'], 'Item Group');
      expect(payload['item_groups'], [{'item_group': 'Beverages'}]);
      expect(payload['min_qty'], 3);
      expect(payload['min_amt'], 500);
      expect(payload['max_amt'], 2500);
      expect(payload['priority'], '4');
      expect(payload['apply_multiple_pricing_rules'], 1);
      expect(payload['is_cumulative'], 1);
      final saved = core.Map<String, dynamic>.from(payload)
        ..['name'] = 'PR-GROUP-1'
        ..['doctype'] = 'Pricing Rule';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': saved}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final saved = await api.saveSellingPricingRule(
        title: 'Beverages bulk discount',
        priceList: 'Standard Selling',
        currency: 'YER',
        discountType: 'Discount Percentage',
        discountValue: 8,
        validFrom: '2026-11-01',
        applyOn: 'Item Group',
        itemCode: 'Beverages',
        minQty: 3,
        minAmount: 500,
        maxAmount: 2500,
        priority: 4,
        applyMultipleRules: true,
        cumulative: true,
      );
      expect(saved['name'], 'PR-GROUP-1');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('rejects inverted pricing amount thresholds', () async {
    final api = FrappeApi();
    await expectLater(
      api.saveSellingPricingRule(
        title: 'Invalid thresholds',
        priceList: 'Standard Selling',
        currency: 'YER',
        discountType: 'Discount Percentage',
        discountValue: 5,
        validFrom: '2026-11-01',
        minAmount: 1000,
        maxAmount: 500,
      ),
      throwsFormatException,
    );
    api.dispose();
  });

  test('creates a buy-two-get-one-free product promotion', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
      expect(payload['price_or_product_discount'], 'Product');
      expect(payload['apply_on'], 'Item Code');
      expect(payload['items'], [{'item_code': 'ITEM-1'}]);
      expect(payload['min_qty'], 2);
      expect(payload['free_item'], 'GIFT-1');
      expect(payload['free_qty'], 1);
      expect(payload['same_item'], 0);
      expect(payload['dont_enforce_free_item_qty'], 1);
      final saved = core.Map<String, dynamic>.from(payload)..['name'] = 'PR-BOGO'..['doctype'] = 'Pricing Rule';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': saved}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final saved = await api.saveSellingPricingRule(
        title: 'Buy two get one gift',
        priceList: 'Standard Selling',
        currency: 'YER',
        priceOrProductDiscount: 'Product',
        discountValue: 0,
        validFrom: '2026-11-01',
        applyOn: 'Item Code',
        itemCode: 'ITEM-1',
        minQty: 2,
        freeItem: 'GIFT-1',
        freeQty: 1,
        dontEnforceFreeItemQty: true,
      );
      expect(saved['name'], 'PR-BOGO');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

  test('creates a percentage-margin pricing rule using ERPNext margin fields', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = jsonDecode(await utf8.decoder.bind(request).join()) as core.Map<String, dynamic>;
      expect(payload['price_or_product_discount'], 'Price');
      expect(payload.containsKey('rate_or_discount'), isFalse);
      expect(payload['margin_type'], 'Percentage');
      expect(payload['margin_rate_or_amount'], 12.5);
      final saved = core.Map<String, dynamic>.from(payload)..['name'] = 'PR-MARGIN'..['doctype'] = 'Pricing Rule';
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'data': saved}));
      await request.response.close();
    });
    final api = FrappeApi()..configure('http://127.0.0.1:${server.port}');
    try {
      final saved = await api.saveSellingPricingRule(
        title: 'Standard margin',
        priceList: 'Standard Selling',
        currency: 'YER',
        discountType: 'Margin',
        discountValue: 12.5,
        marginType: 'Percentage',
        validFrom: '2026-11-01',
      );
      expect(saved['name'], 'PR-MARGIN');
    } finally {
      api.dispose();
      await server.close(force: true);
    }
  });

}
