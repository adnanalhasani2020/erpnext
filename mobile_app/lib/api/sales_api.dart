// ignore_for_file: annotate_overrides, library_private_types_in_public_api, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

mixin SalesApiMixin on _FrappeApiCore {
  Future<List<core.Map<String, dynamic>>> fetchSellingPriceLists() async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Price List',
        fields: const ['name', 'selling', 'enabled', 'currency'],
        filters: const [
          ['selling', '=', 1],
          ['enabled', '=', 1],
        ],
        orderBy: 'name asc',
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل قوائم أسعار البيع.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة قوائم الأسعار غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchItemCatalogRows({
      int start = 0, String? search, String? itemGroup, String? brand, String? status,
    }) async {
      final query = search?.trim() ?? '';
      final filters = <List<dynamic>>[
        if (itemGroup?.trim().isNotEmpty == true) ['item_group', '=', itemGroup!.trim()],
        if (brand?.trim().isNotEmpty == true) ['brand', '=', brand!.trim()],
        if (status == 'active') ['disabled', '=', 0],
        if (status == 'disabled') ['disabled', '=', 1],
      ];
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Item',
        fields: const ['name', 'item_code', 'item_name', 'item_group', 'stock_uom', 'brand',
          'image', 'description', 'disabled', 'is_stock_item', 'has_serial_no', 'has_batch_no'],
        filters: filters,
        orFilters: query.isEmpty ? null : [
          ['name', 'like', '%$query%'], ['item_name', 'like', '%$query%'],
          ['item_group', 'like', '%$query%'], ['brand', 'like', '%$query%'],
        ],
        orderBy: 'modified desc, item_code asc', start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل دليل الأصناف. تحقق من صلاحية قراءة Item.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة دليل الأصناف غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchItemCatalogDocument(String itemCode) async {
      final id = itemCode.trim();
      if (id.isEmpty) throw const FormatException('رمز الصنف مطلوب.');
      final response = await _send('GET', '/api/resource/Item/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل الصنف.'));
      }
      final doc = data['data'];
      if (doc is! core.Map<String, dynamic> || doc['name'] != id ||
          (doc['doctype'] != null && doc['doctype'] != 'Item')) {
        throw const FormatException('لم يؤكد ERPNext هوية الصنف المطلوب.');
      }
      return core.Map<String, dynamic>.from(doc);
    }

  Future<List<core.Map<String, dynamic>>> fetchItemCatalogPrices(String itemCode) async {
      final id = itemCode.trim();
      if (id.isEmpty) throw const FormatException('رمز الصنف مطلوب لتحميل الأسعار.');
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Item Price',
        fields: const ['name', 'item_code', 'price_list', 'price_list_rate', 'currency',
          'uom', 'valid_from', 'valid_upto', 'min_qty', 'selling', 'buying'],
        filters: [['item_code', '=', id]],
        orderBy: 'price_list asc, valid_from desc, name asc',
        pageLength: 200,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أسعار البيع والشراء للصنف.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة أسعار الصنف غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>?> fetchItemByBarcode(String barcode) async {
      final code = barcode.trim();
      if (code.isEmpty) return null;
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Item Barcode',
        fields: const ['name', 'parent', 'barcode', 'barcode_type'],
        filters: [['barcode', '=', code], ['parenttype', '=', 'Item']],
        orderBy: 'modified desc, name asc', pageLength: 5,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر البحث عن الباركود. تحقق من صلاحية قراءة Item Barcode.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة البحث بالباركود غير صحيحة.');
      for (final row in rows.whereType<core.Map<String, dynamic>>()) {
        final parent = row['parent']?.toString() ?? '';
        if (parent.isNotEmpty) return fetchItemCatalogDocument(parent);
      }
      return null;
    }

  Future<List<String>> fetchItemBrands() async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: 'Brand',
        fields: const ['name'], filters: const [],
        orderBy: 'name asc', pageLength: 500,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل العلامات التجارية.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة العلامات التجارية غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => row['name']?.toString() ?? '')
          .where((value) => value.isNotEmpty).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchItemPrices({
      required String priceList,
      String? search,
      int start = 0,
    }) async {
      if (priceList.trim().isEmpty) {
        throw const FormatException('حدد قائمة الأسعار أولاً.');
      }
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Item Price',
        fields: const [
          'name', 'item_code', 'price_list', 'price_list_rate', 'currency',
          'uom', 'valid_from', 'valid_upto', 'min_qty', 'selling',
        ],
        filters: [
          ['price_list', '=', priceList.trim()],
          ['selling', '=', 1],
        ],
        orFilters: search == null || search.trim().isEmpty
            ? null
            : [
                ['item_code', 'like', '%' + search.trim() + '%'],
              ],
        orderBy: 'item_code asc, valid_from desc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أسعار الأصناف.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة أسعار الأصناف غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

  Future<core.Map<String, dynamic>> saveItemSellingPrice({
      String? priceId,
      required String itemCode,
      required String priceList,
      required double rate,
      String? currency,
      String? uom,
      String? validFrom,
      String? validUpto,
      double minQty = 0,
    }) async {
      final item = itemCode.trim();
      final list = priceList.trim();
      if (item.isEmpty || list.isEmpty || !rate.isFinite || rate <= 0 ||
          !minQty.isFinite || minQty < 0) {
        throw const FormatException('أدخل الصنف وقائمة الأسعار وسعراً وكمية دنيا صحيحة.');
      }
      String? validDate(String? raw, String label) {
        final value = raw?.trim() ?? '';
        if (value.isEmpty) return null;
        final parsed = DateTime.tryParse(value);
        final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        if (parsed == null || !pattern.hasMatch(value) ||
            parsed.toIso8601String().substring(0, 10) != value) {
          throw FormatException('$label يجب أن يكون بصيغة YYYY-MM-DD.');
        }
        return value;
      }
      final from = validDate(validFrom, 'تاريخ بداية السعر');
      final until = validDate(validUpto, 'تاريخ نهاية السعر');
      if (from != null && until != null && from.compareTo(until) > 0) {
        throw const FormatException('تاريخ نهاية السعر يجب ألا يسبق تاريخ بدايته.');
      }
  
      final payload = <String, dynamic>{
        'doctype': 'Item Price',
        'item_code': item,
        'price_list': list,
        'selling': 1,
        'price_list_rate': rate,
        'min_qty': minQty,
        if (currency != null && currency.trim().isNotEmpty) 'currency': currency.trim(),
        if (uom != null && uom.trim().isNotEmpty) 'uom': uom.trim(),
        if (from != null) 'valid_from': from,
        if (until != null) 'valid_upto': until,
      };
      final id = priceId?.trim() ?? '';
      final response = id.isEmpty
          ? await _sendJson('POST', '/api/resource/Item%20Price', payload)
          : await _updateExistingItemPrice(id, item, list, payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ سعر الصنف.'));
      }
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> ||
          saved['doctype'] != 'Item Price' ||
          saved['item_code'] != item ||
          saved['price_list'] != list ||
          saved['selling'] != 1) {
        throw Exception('لم يؤكد ERPNext حفظ سعر الصنف؛ أعد تحميل قائمة الأسعار.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<List<core.Map<String, dynamic>>> fetchSellingPromotionalSchemes({
      int start = 0,
      String? company,
      bool activeOnly = false,
    }) async {
      final filters = <List<dynamic>>[
        ['selling', '=', 1],
        ['buying', '=', 0],
        if (company != null && company.trim().isNotEmpty) ['company', '=', company.trim()],
        if (activeOnly) ['disable', '=', 0],
      ];
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Promotional Scheme',
        fields: const ['name', 'apply_on', 'disable', 'selling', 'buying', 'company', 'currency', 'valid_from', 'valid_upto'],
        filters: filters,
        orderBy: 'modified desc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل المخططات الترويجية.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة المخططات الترويجية غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchSellingPromotionalSchemeDocument(String schemeId) async {
      final id = schemeId.trim();
      if (id.isEmpty) throw const FormatException('حدد المخطط الترويجي أولاً.');
      final response = await _send('GET', '/api/resource/Promotional%20Scheme/' + Uri.encodeComponent(id));
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل المخطط الترويجي.'));
      }
      final doc = data['data'];
      if (doc is! core.Map<String, dynamic> || doc['doctype'] != 'Promotional Scheme' ||
          doc['name'] != id || doc['selling'] != 1 || doc['buying'] == 1) {
        throw const FormatException('المخطط المطلوب ليس مخطط بيع صالحاً.');
      }
      return core.Map<String, dynamic>.from(doc);
    }

  Future<core.Map<String, dynamic>> saveSellingPromotionalScheme({
      String? schemeId,
      required String name,
      required String company,
      required String currency,
      required String applyOn,
      String? target,
      required String validFrom,
      String? validUpto,
      required List<core.Map<String, dynamic>> priceSlabs,
      required List<core.Map<String, dynamic>> productSlabs,
      bool mixedConditions = false,
      bool cumulative = false,
    }) async {
      final id = name.trim();
      final companyName = company.trim();
      final currencyCode = currency.trim();
      final targetValue = target?.trim() ?? '';
      if (id.isEmpty || companyName.isEmpty || currencyCode.isEmpty ||
          !{'Transaction', 'Item Code', 'Item Group', 'Brand'}.contains(applyOn) ||
          (applyOn != 'Transaction' && targetValue.isEmpty) ||
          (applyOn == 'Transaction' && targetValue.isNotEmpty) ||
          (priceSlabs.isEmpty && productSlabs.isEmpty)) {
        throw const FormatException('اسم المخطط والشركة والعملة ونطاق التطبيق وشريحة واحدة على الأقل حقول مطلوبة.');
      }
      String date(String raw, String label) {
        final parsed = DateTime.tryParse(raw);
        if (parsed == null || raw.length != 10 ||
            parsed.toIso8601String().substring(0, 10) != raw) {
          throw FormatException('$label يجب أن يكون بصيغة YYYY-MM-DD.');
        }
        return raw;
      }
      final from = date(validFrom.trim(), 'تاريخ البداية');
      final untilRaw = validUpto?.trim() ?? '';
      final until = untilRaw.isEmpty ? null : date(untilRaw, 'تاريخ النهاية');
      if (until != null && until.compareTo(from) < 0) {
        throw const FormatException('تاريخ نهاية المخطط يجب ألا يسبق تاريخ بدايته.');
      }
      final priceRows = <core.Map<String, dynamic>>[];
      for (final raw in priceSlabs) {
        final minQty = _asDouble(raw['min_qty']);
        final maxQty = _asDouble(raw['max_qty']);
        final minAmount = _asDouble(raw['min_amount']);
        final maxAmount = _asDouble(raw['max_amount']);
        final type = raw['rate_or_discount']?.toString() ?? '';
        final value = _asDouble(raw['value']);
        final list = raw['for_price_list']?.toString().trim() ?? '';
        final priority = int.tryParse(raw['priority']?.toString() ?? '') ?? 1;
        if (!{'Rate', 'Discount Percentage', 'Discount Amount'}.contains(type) ||
            !minQty.isFinite || minQty < 0 || !maxQty.isFinite || maxQty < 0 ||
            (maxQty > 0 && minQty > maxQty) ||
            !minAmount.isFinite || minAmount < 0 || !maxAmount.isFinite || maxAmount < 0 ||
            (maxAmount > 0 && minAmount > maxAmount) ||
            !value.isFinite || value <= 0 || (type == 'Discount Percentage' && value > 100) ||
            list.isEmpty || priority < 1 || priority > 20) {
          throw const FormatException('يوجد صف خصم سعري غير صحيح في المخطط.');
        }
        priceRows.add({
          'doctype': 'Promotional Scheme Price Discount',
          'min_qty': minQty,
          'max_qty': maxQty,
          'min_amount': minAmount,
          'max_amount': maxAmount,
          'rate_or_discount': type,
          if (type == 'Rate') 'rate': value,
          if (type == 'Discount Percentage') 'discount_percentage': value,
          if (type == 'Discount Amount') 'discount_amount': value,
          'for_price_list': list,
          if ((raw['warehouse']?.toString().trim() ?? '').isNotEmpty) 'warehouse': raw['warehouse'].toString().trim(),
          'priority': priority.toString(),
          'apply_multiple_pricing_rules': raw['apply_multiple_pricing_rules'] == true ? 1 : 0,
          'rule_description': (raw['rule_description']?.toString() ?? '').trim().isEmpty
              ? 'شريحة ترويجية'
              : raw['rule_description'].toString().trim(),
        });
      }
      final productRows = <core.Map<String, dynamic>>[];
      for (final raw in productSlabs) {
        final minQty = _asDouble(raw['min_qty']);
        final maxQty = _asDouble(raw['max_qty']);
        final minAmount = _asDouble(raw['min_amount']);
        final maxAmount = _asDouble(raw['max_amount']);
        final freeQty = _asDouble(raw['free_qty']);
        final sameItem = raw['same_item'] == true;
        final freeItem = raw['free_item']?.toString().trim() ?? '';
        final priority = int.tryParse(raw['priority']?.toString() ?? '') ?? 1;
        if (!minQty.isFinite || minQty < 0 || !maxQty.isFinite || maxQty < 0 ||
            (maxQty > 0 && minQty > maxQty) ||
            !minAmount.isFinite || minAmount < 0 || !maxAmount.isFinite || maxAmount < 0 ||
            (maxAmount > 0 && minAmount > maxAmount) ||
            !freeQty.isFinite || freeQty <= 0 || (!sameItem && freeItem.isEmpty) ||
            priority < 1 || priority > 20) {
          throw const FormatException('يوجد صف منتج مجاني غير صحيح في المخطط.');
        }
        productRows.add({
          'doctype': 'Promotional Scheme Product Discount',
          'min_qty': minQty,
          'max_qty': maxQty,
          'min_amount': minAmount,
          'max_amount': maxAmount,
          'same_item': sameItem ? 1 : 0,
          if (!sameItem) 'free_item': freeItem,
          'free_qty': freeQty,
          if ((raw['warehouse']?.toString().trim() ?? '').isNotEmpty) 'warehouse': raw['warehouse'].toString().trim(),
          'priority': priority.toString(),
          'apply_multiple_pricing_rules': raw['apply_multiple_pricing_rules'] == true ? 1 : 0,
          'rule_description': (raw['rule_description']?.toString() ?? '').trim().isEmpty
              ? 'شريحة منتج مجاني'
              : raw['rule_description'].toString().trim(),
        });
      }
      final payload = <String, dynamic>{
        'doctype': 'Promotional Scheme',
        'name': id,
        'apply_on': applyOn,
        'selling': 1,
        'buying': 0,
        'company': companyName,
        'currency': currencyCode,
        'valid_from': from,
        if (until != null) 'valid_upto': until,
        'items': applyOn == 'Item Code' ? [{'item_code': targetValue}] : <core.Map<String, dynamic>>[],
        'item_groups': applyOn == 'Item Group' ? [{'item_group': targetValue}] : <core.Map<String, dynamic>>[],
        'brands': applyOn == 'Brand' ? [{'brand': targetValue}] : <core.Map<String, dynamic>>[],
        'mixed_conditions': mixedConditions ? 1 : 0,
        'is_cumulative': cumulative ? 1 : 0,
        'price_discount_slabs': priceRows,
        'product_discount_slabs': productRows,
      };
      final existingId = schemeId?.trim() ?? '';
      late final _ApiResponse response;
      if (existingId.isEmpty) {
        response = await _sendJson('POST', '/api/resource/Promotional%20Scheme', payload);
      } else {
        final currentUri = Uri.parse('$_baseUrl/api/resource/Promotional%20Scheme/' + Uri.encodeComponent(existingId));
        final currentResponse = await _sendUri('GET', currentUri);
        final currentData = _decode(currentResponse.body);
        final current = currentData['data'];
        if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
            current is! core.Map<String, dynamic> || current['name'] != existingId ||
            current['selling'] != 1 || current['buying'] == 1) {
          throw const FormatException('المخطط الترويجي تغير أو لا ينتمي إلى مخططات البيع.');
        }
        final update = core.Map<String, dynamic>.from(payload)..remove('doctype')..remove('name');
        response = await _sendJson('PUT', '/api/resource/Promotional%20Scheme/' + Uri.encodeComponent(existingId), update);
      }
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ المخطط الترويجي.'));
      }
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Promotional Scheme' ||
          saved['selling'] != 1 || saved['company'] != companyName) {
        throw Exception('لم يؤكد ERPNext حفظ المخطط الترويجي؛ أعد تحميل القائمة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  double _asDouble(dynamic value) {
      final parsed = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
      return parsed != null && parsed.isFinite ? parsed : double.nan;
    }

  Future<void> setSellingPromotionalSchemeDisabled(String schemeId, {required bool disabled}) async {
      final id = schemeId.trim();
      if (id.isEmpty) throw const FormatException('حدد المخطط الترويجي أولاً.');
      final uri = Uri.parse('$_baseUrl/api/resource/Promotional%20Scheme/' + Uri.encodeComponent(id));
      final currentResponse = await _sendUri('GET', uri);
      final currentData = _decode(currentResponse.body);
      final current = currentData['data'];
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
          current is! core.Map<String, dynamic> || current['name'] != id ||
          current['selling'] != 1 || current['buying'] == 1) {
        throw const FormatException('تعذر التحقق من المخطط الترويجي قبل تغيير حالته.');
      }
      final response = await _sendJson(
        'PUT',
        '/api/resource/Promotional%20Scheme/' + Uri.encodeComponent(id),
        {'disable': disabled ? 1 : 0},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, disabled ? 'تعذر إيقاف المخطط الترويجي.' : 'تعذر تفعيل المخطط الترويجي.'));
      }
      final updated = data['data'];
      if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
          updated['disable'] != (disabled ? 1 : 0)) {
        throw Exception('لم يؤكد ERPNext تغيير حالة المخطط الترويجي.');
      }
    }

  Future<void> disableSellingPromotionalScheme(String schemeId) =>
        setSellingPromotionalSchemeDisabled(schemeId, disabled: true);

  Future<void> enableSellingPromotionalScheme(String schemeId) =>
        setSellingPromotionalSchemeDisabled(schemeId, disabled: false);

  Future<List<core.Map<String, dynamic>>> fetchSellingPricingRules({
      int start = 0,
    }) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Pricing Rule',
        fields: const [
          'name', 'title', 'apply_on', 'price_or_product_discount',
          'selling', 'buying', 'disable', 'rate_or_discount',
          'discount_percentage', 'discount_amount', 'for_price_list',
          'currency', 'valid_from', 'valid_upto', 'company',
          'apply_discount_on', 'applicable_for', 'customer', 'items', 'item_groups', 'brands', 'min_qty', 'max_qty', 'min_amt', 'max_amt', 'priority', 'has_priority', 'apply_multiple_pricing_rules', 'is_cumulative', 'mixed_conditions', 'rate', 'margin_type', 'margin_rate_or_amount', 'free_item', 'free_qty', 'same_item', 'dont_enforce_free_item_qty',
          'customer_group', 'territory', 'sales_partner', 'campaign', 'warehouse',
        ],
        filters: const [
          ['selling', '=', 1],
          ['buying', '=', 0],
        ],
        orderBy: 'modified desc, name desc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل قواعد خصومات البيع.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة قواعد الخصم غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

  Future<core.Map<String, dynamic>> saveSellingPricingRule({
      String? ruleId,
      required String title,
      required String priceList,
      required String currency,
      String priceOrProductDiscount = 'Price',
      String discountType = 'Discount Percentage',
      required double discountValue,
      required String validFrom,
      String? validUpto,
      String? company,
      String? warehouse,
      String? applicableFor,
      String? applicableValue,
      String applyDiscountOn = 'Grand Total',
      String applyOn = 'Transaction',
      String? itemCode,
      double minQty = 0,
      double maxQty = 0,
      double minAmount = 0,
      double maxAmount = 0,
      int priority = 0,
      bool applyMultipleRules = false,
      bool cumulative = false,
      bool mixedConditions = false,
      String marginType = 'Percentage',
      String? freeItem,
      double freeQty = 1,
      bool sameItem = false,
      bool dontEnforceFreeItemQty = false,
    }) async {
      final cleanTitle = title.trim();
      final cleanList = priceList.trim();
      final cleanCurrency = currency.trim();
      final target = itemCode?.trim() ?? '';
      final freeItemCode = freeItem?.trim() ?? '';
      final isProduct = priceOrProductDiscount == 'Product';
      final validOutcome = priceOrProductDiscount == 'Price'
          ? {'Rate', 'Discount Percentage', 'Discount Amount', 'Margin'}.contains(discountType)
          : isProduct;
      if (cleanTitle.isEmpty || cleanCurrency.isEmpty ||
          !{'Price', 'Product'}.contains(priceOrProductDiscount) || !validOutcome ||
          !{'Grand Total', 'Net Total'}.contains(applyDiscountOn) ||
          !{'Transaction', 'Item Code', 'Item Group', 'Brand'}.contains(applyOn) ||
          !minQty.isFinite || minQty < 0 || !maxQty.isFinite || maxQty < 0 ||
          (maxQty > 0 && minQty > maxQty) ||
          !minAmount.isFinite || minAmount < 0 || !maxAmount.isFinite || maxAmount < 0 ||
          (maxAmount > 0 && minAmount > maxAmount) || priority < 0 || priority > 20 ||
          !freeQty.isFinite || freeQty <= 0 ||
          (applyOn != 'Transaction' && (target.isEmpty || minQty <= 0)) ||
          (applyOn == 'Transaction' && target.isNotEmpty) ||
          (isProduct && !sameItem && freeItemCode.isEmpty) ||
          (!isProduct && (!discountValue.isFinite || discountValue <= 0 ||
            (discountType == 'Discount Percentage' && discountValue > 100) ||
            (discountType == 'Margin' && !{'Percentage', 'Amount'}.contains(marginType))) ) ||
          (cumulative && minAmount <= 0)) {
        throw const FormatException('بيانات قاعدة التسعير أو شروط الكمية والقيمة غير صحيحة.');
      }
      String validateDate(String raw, String label) {
        final parsed = DateTime.tryParse(raw);
        final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        if (parsed == null || !pattern.hasMatch(raw) ||
            parsed.toIso8601String().substring(0, 10) != raw) {
          throw FormatException('$label يجب أن يكون بصيغة YYYY-MM-DD.');
        }
        return raw;
      }
      final from = validateDate(validFrom.trim(), 'تاريخ البداية');
      final untilRaw = validUpto?.trim() ?? '';
      final until = untilRaw.isEmpty ? null : validateDate(untilRaw, 'تاريخ النهاية');
      if (until != null && from.compareTo(until) > 0) {
        throw const FormatException('تاريخ نهاية القاعدة يجب ألا يسبق تاريخ بدايتها.');
      }
      const applicableFields = {
        'Customer': 'customer',
        'Customer Group': 'customer_group',
        'Territory': 'territory',
        'Sales Partner': 'sales_partner',
        'Campaign': 'campaign',
      };
      final applicableField = applicableFields[applicableFor];
      final partyValue = applicableValue?.trim() ?? '';
      if (applicableFor != null && (applicableField == null || partyValue.isEmpty)) {
        throw const FormatException('حدد قيمة صالحة لنطاق تطبيق القاعدة.');
      }
      if (applicableFor == null && partyValue.isNotEmpty) {
        throw const FormatException('حدد نوع نطاق القاعدة قبل إدخال قيمته.');
      }
  
      final itemRows = applyOn == 'Item Code' ? [{'item_code': target}] : <core.Map<String, dynamic>>[];
      final groupRows = applyOn == 'Item Group' ? [{'item_group': target}] : <core.Map<String, dynamic>>[];
      final brandRows = applyOn == 'Brand' ? [{'brand': target}] : <core.Map<String, dynamic>>[];
      final payload = <String, dynamic>{
        'doctype': 'Pricing Rule',
        'title': cleanTitle,
        'apply_on': applyOn,
        'price_or_product_discount': priceOrProductDiscount,
        'selling': 1,
        'buying': 0,
        'apply_discount_on': applyDiscountOn,
        if (cleanList.isNotEmpty) 'for_price_list': cleanList,
        'items': itemRows,
        'item_groups': groupRows,
        'brands': brandRows,
        'min_qty': minQty,
        'max_qty': maxQty,
        'min_amt': minAmount,
        'max_amt': maxAmount,
        'priority': priority == 0 ? '' : priority.toString(),
        'has_priority': priority > 0 ? 1 : 0,
        'apply_multiple_pricing_rules': applyMultipleRules ? 1 : 0,
        'is_cumulative': cumulative ? 1 : 0,
        'mixed_conditions': mixedConditions ? 1 : 0,
        'currency': cleanCurrency,
        'valid_from': from,
        if (until != null) 'valid_upto': until,
        if (company != null && company.trim().isNotEmpty) 'company': company.trim(),
        if (warehouse != null && warehouse.trim().isNotEmpty) 'warehouse': warehouse.trim(),
        if (applicableFor != null) 'applicable_for': applicableFor,
        if (applicableField != null) applicableField: partyValue,
        if (isProduct) ...{
          'free_item': sameItem ? null : freeItemCode,
          'free_qty': freeQty,
          'same_item': sameItem ? 1 : 0,
          'dont_enforce_free_item_qty': dontEnforceFreeItemQty ? 1 : 0,
        } else ...{
          if (discountType != 'Margin') 'rate_or_discount': discountType,
          if (discountType == 'Rate') 'rate': discountValue,
          if (discountType == 'Discount Percentage') 'discount_percentage': discountValue,
          if (discountType == 'Discount Amount') 'discount_amount': discountValue,
          if (discountType == 'Margin') ...{
            'margin_type': marginType,
            'margin_rate_or_amount': discountValue,
          },
        },
      };
  
      final id = ruleId?.trim() ?? '';
      late final _ApiResponse response;
      if (id.isEmpty) {
        response = await _sendJson('POST', '/api/resource/Pricing%20Rule', payload);
      } else {
        final uri = Uri.parse('$_baseUrl/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id));
        final currentResponse = await _sendUri('GET', uri);
        final currentData = _decode(currentResponse.body);
        final current = currentData['data'];
        if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
            current is! core.Map<String, dynamic> || current['name'] != id ||
            !{'Transaction', 'Item Code', 'Item Group', 'Brand'}.contains(current['apply_on']) ||
            current['selling'] != 1 || current['buying'] == 1) {
          throw const FormatException('قاعدة التسعير تغيرت أو لا تنتمي إلى قواعد البيع المدعومة.');
        }
        final updatePayload = core.Map<String, dynamic>.from(payload)..remove('doctype');
        response = await _sendJson('PUT', '/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id), updatePayload);
      }
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ قاعدة التسعير في ERPNext.'));
      }
      final saved = data['data'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Pricing Rule' ||
          saved['apply_on'] != applyOn || saved['selling'] != 1 ||
          saved['title'] != cleanTitle || saved['price_or_product_discount'] != priceOrProductDiscount) {
        throw Exception('لم يؤكد ERPNext حفظ قاعدة التسعير؛ أعد تحميل القائمة.');
      }
      return core.Map<String, dynamic>.from(saved);
    }

  Future<void> disableSellingPricingRule(String ruleId) async {
      final id = ruleId.trim();
      if (id.isEmpty) throw const FormatException('حدد قاعدة الخصم أولاً.');
      final uri = Uri.parse(
        '$_baseUrl/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id),
      );
      final currentResponse = await _sendUri('GET', uri);
      final currentData = _decode(currentResponse.body);
      final current = currentData['data'];
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
          current is! core.Map<String, dynamic> || current['name'] != id ||
          !{'Transaction', 'Item Code', 'Item Group', 'Brand'}.contains(current['apply_on']) ||
          current['selling'] != 1 || current['buying'] == 1) {
        throw const FormatException('تعذر التحقق من قاعدة الخصم قبل إيقافها.');
      }
      final response = await _sendJson(
        'PUT',
        '/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id),
        {'disable': 1},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إيقاف قاعدة الخصم.'));
      }
      final updated = data['data'];
      if (updated is! core.Map<String, dynamic> ||
          updated['name'] != id ||
          updated['disable'] != 1) {
        throw Exception('لم يؤكد ERPNext إيقاف قاعدة الخصم.');
      }
    }

  Future<_ApiResponse> _updateExistingItemPrice(
      String id,
      String itemCode,
      String priceList,
      core.Map<String, dynamic> payload,
    ) async {
      final uri = Uri.parse(
        '$_baseUrl/api/resource/Item%20Price/' + Uri.encodeComponent(id),
      );
      final currentResponse = await _sendUri('GET', uri);
      final currentData = _decode(currentResponse.body);
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300) {
        throw Exception(_message(currentData, 'تعذر التحقق من سعر الصنف قبل تعديله.'));
      }
      final current = currentData['data'];
      if (current is! core.Map<String, dynamic> ||
          current['name'] != id ||
          current['item_code'] != itemCode ||
          current['price_list'] != priceList ||
          current['selling'] != 1) {
        throw const FormatException('سجل السعر تغير أو لا يطابق الصنف وقائمة الأسعار المحددين.');
      }
      return _sendJson(
        'PUT',
        '/api/resource/Item%20Price/' + Uri.encodeComponent(id),
        core.Map<String, dynamic>.from(payload)..remove('doctype'),
      );
    }

  Future<List<ErpSalesInvoice>> fetchSalesInvoices({int start = 0, String? search}) async {
      final uri = Uri.parse('$_baseUrl/api/resource/Sales%20Invoice').replace(queryParameters: {
        'fields': jsonEncode(['name', 'customer', 'customer_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status', 'is_return', 'return_against']),
        'limit_page_length': FrappeApi.pageSize.toString(),
        if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
        'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc, name desc',
      });
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة فواتير المبيعات من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().map(ErpSalesInvoice.fromJson).toList(growable: false);
    }

  Future<List<core.Map<String, dynamic>>> fetchSalesPersons({
      int start = 0,
      String? search,
    }) async {
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Sales Person',
        fields: const [
          'name', 'sales_person_name', 'parent_sales_person',
          'commission_rate', 'is_group', 'enabled', 'employee',
        ],
        filters: const [
          ['is_group', '=', 0],
          ['enabled', '=', 1],
        ],
        orFilters: search == null || search.trim().isEmpty
            ? null
            : [
                ['name', 'like', '%' + search.trim() + '%'],
                ['sales_person_name', 'like', '%' + search.trim() + '%'],
              ],
        orderBy: 'sales_person_name asc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل مندوبي المبيعات. تحقق من صلاحية قراءة Sales Person.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة مندوبي المبيعات غير صحيحة.');
      return rows.whereType<core.Map<String, dynamic>>()
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: false);
    }

  Future<core.Map<String, dynamic>> updateSalesPersonCommission({
      required String salesPersonId,
      required double commissionRate,
    }) async {
      final id = salesPersonId.trim();
      if (id.isEmpty || !commissionRate.isFinite ||
          commissionRate < 0 || commissionRate > 100) {
        throw const FormatException('حدد مندوباً وأدخل نسبة عمولة من 0 إلى 100.');
      }
      final uri = Uri.parse(
        '$_baseUrl/api/resource/Sales%20Person/' + Uri.encodeComponent(id),
      );
      final currentResponse = await _sendUri('GET', uri);
      final currentData = _decode(currentResponse.body);
      final current = currentData['data'];
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
          current is! core.Map<String, dynamic> || current['name'] != id ||
          current['is_group'] == 1 || current['is_group'] == true ||
          current['enabled'] == 0 || current['enabled'] == false) {
        throw const FormatException('مندوب المبيعات تغير أو غير مفعل ولا يمكن تعديل عمولته.');
      }
      final response = await _sendJson(
        'PUT',
        '/api/resource/Sales%20Person/' + Uri.encodeComponent(id),
        {'commission_rate': commissionRate},
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحديث نسبة عمولة مندوب المبيعات.'));
      }
      final updated = data['data'];
      final savedRate = updated is core.Map ? double.tryParse(updated['commission_rate']?.toString() ?? '') : null;
      if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
          savedRate == null || (savedRate - commissionRate).abs() > 0.000001) {
        throw Exception('لم يؤكد ERPNext حفظ نسبة العمولة؛ أعد تحميل سجل المندوب.');
      }
      return core.Map<String, dynamic>.from(updated);
    }

  String _salesWorkflowResource(String doctype) {
      if (!FrappeApi.salesWorkflowDoctypes.contains(doctype)) {
        throw FormatException('نوع مستند المبيعات غير مدعوم: $doctype');
      }
      return Uri.encodeComponent(doctype);
    }

  Future<List<core.Map<String, dynamic>>> fetchSalesWorkflowDocuments(
      String doctype, {int start = 0, String? search}
    ) async {
      _salesWorkflowResource(doctype);
      final uri = FrappeApi.buildResourcePageUri(
        baseUrl: _baseUrl, resource: doctype,
        fields: const ['name', 'customer', 'customer_name', 'company', 'status', 'docstatus', 'grand_total', 'currency', 'modified'],
        orFilters: search == null || search.trim().isEmpty ? null : [
          ['name', 'like', '%${search.trim()}%'],
          ['customer', 'like', '%${search.trim()}%'],
          ['customer_name', 'like', '%${search.trim()}%'],
        ],
        orderBy: 'modified desc, name desc', start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل $doctype.'));
      }
      final rows = data['data'];
      if (rows is! List) throw Exception('استجابة $doctype من ERPNext غير متوقعة.');
      return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
    }

  Future<core.Map<String, dynamic>> fetchSalesWorkflowDocument(String doctype, String name) async {
      final resource = _salesWorkflowResource(doctype);
      if (name.trim().isEmpty) throw const FormatException('رقم مستند المبيعات غير موجود.');
      final response = await _send('GET', '/api/resource/$resource/${Uri.encodeComponent(name.trim())}');
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل تفاصيل $doctype.'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> || document['doctype'] != doctype || document['name'] != name.trim()) {
        throw FormatException('لم يؤكد ERPNext هوية مستند $doctype المطلوب.');
      }
      return document;
    }

  void _validateSalesWorkflowDraft(String doctype, core.Map<String, dynamic> doc) {
      _salesWorkflowResource(doctype);
      if (doctype != 'Quotation' && doctype != 'Sales Order') {
        throw const FormatException('يُنشأ إذن التسليم والفاتورة من مستندات المبيعات الأصلية لضمان صحة الربط والكميات.');
      }
      if (doctype == 'Delivery Note') {
        throw const FormatException('يتم إنشاء إذن التسليم من أمر البيع المرحّل لضمان ربط البنود والكميات.');
      }
      final customer = doc['customer'], company = doc['company'], items = doc['items'];
      if (doc['doctype'] != doctype || customer is! String || customer.trim().isEmpty ||
          company is! String || company.trim().isEmpty || items is! List || items.isEmpty) {
        throw const FormatException('حدد الشركة والعميل وأضف بنداً واحداً على الأقل.');
      }
      for (final raw in items) {
        if (raw is! core.Map<String, dynamic> || raw['item_code'] is! String || (raw['item_code'] as String).trim().isEmpty) {
          throw const FormatException('يوجد بند دون رمز صنف صحيح.');
        }
        final qty = raw['qty'], rate = raw['rate'];
        if (qty is! num || !qty.isFinite || qty <= 0 || rate is! num || !rate.isFinite || rate < 0 || !(qty * rate).isFinite) {
          throw const FormatException('تحقق من كمية وسعر كل بند.');
        }
      }
    }

  Future<core.Map<String, dynamic>> createSalesWorkflowDraft(String doctype, core.Map<String, dynamic> document) async {
      _validateSalesWorkflowDraft(doctype, document);
      await _validateDocumentWarehouses(document);
      final response = await _sendJson('POST', '/api/resource/${_salesWorkflowResource(doctype)}', document);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة $doctype.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != doctype || created['name'] is! String || created['docstatus'] != 0) {
        throw Exception('استجابة حفظ $doctype غير مؤكدة؛ تحقق من المستند قبل إعادة المحاولة.');
      }
      return created;
    }

  Future<core.Map<String, dynamic>> updateSalesWorkflowDraft(String doctype, String name, core.Map<String, dynamic> changes) async {
      _validateSalesWorkflowDraft(doctype, changes);
      await _validateDocumentWarehouses(changes);
      final current = await fetchSalesWorkflowDocument(doctype, name);
      if (current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل مستند مبيعات مرحّل أو ملغى.');
      final payload = core.Map<String, dynamic>.from(current)
        ..['customer'] = changes['customer'] ..['company'] = changes['company'] ..['items'] = changes['items'];
      for (final field in ['transaction_date', 'valid_till', 'delivery_date', 'order_type']) {
        if (changes.containsKey(field)) payload[field] = changes[field];
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة $doctype.'));
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['doctype'] != doctype || saved['name'] != name || saved['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext حفظ مسودة $doctype.');
      }
      return saved;
    }

  Future<core.Map<String, dynamic>> updateDeliveryNoteTracking({
      required String name,
      required List<core.Map<String, dynamic>> trackingRows,
    }) async {
      final actionKey = 'delivery-note-tracking:$name';
      if (!_inFlightDocumentActions.add(actionKey)) {
        throw const FormatException('تحديث أرقام إذن التسليم قيد التنفيذ بالفعل.');
      }
      try {
        if (name.trim().isEmpty || trackingRows.isEmpty) {
          throw const FormatException('حدد بنوداً متتبعة لإضافة أرقامها.');
        }
        final current = await fetchSalesWorkflowDocument('Delivery Note', name);
        if (current['docstatus'] != 0) {
          throw const FormatException('لا يمكن تعديل تتبع إذن تسليم مرحّل أو ملغى.');
        }
        final sourceItems = current['items'];
        if (sourceItems is! List) throw const FormatException('بنود إذن التسليم غير متاحة.');
        final byName = <String, core.Map<String, dynamic>>{
          for (final row in sourceItems.whereType<core.Map<String, dynamic>>())
            if (row['name'] is String) row['name'].toString(): core.Map<String, dynamic>.from(row),
        };
        final seenRows = <String>{};
        for (final tracking in trackingRows) {
          final rowName = tracking['name'];
          if (rowName is! String || !seenRows.add(rowName) || !byName.containsKey(rowName)) {
            throw const FormatException('بند إذن التسليم غير صحيح أو مكرر.');
          }
          final source = byName[rowName]!;
          if (tracking['item_code'] != source['item_code']) {
            throw const FormatException('لا يمكن تغيير الصنف أثناء تخصيص أرقامه التسلسلية أو دفعاته.');
          }
          final updatedRow = <String, dynamic>{...source, ...tracking}
            ..remove('serial_and_batch_bundle')
            ..remove('rejected_serial_and_batch_bundle');
          byName[rowName] = updatedRow;
        }
        final rowsToValidate = trackingRows.map((tracking) {
          final source = byName[tracking['name']]!;
          return core.Map<String, dynamic>.from(source)..remove('name');
        }).toList(growable: false);
        _validateSerialBatchRows(rowsToValidate);
        final payload = core.Map<String, dynamic>.from(current)
          ..['items'] = sourceItems.whereType<core.Map<String, dynamic>>().map((row) {
            final rowName = row['name']?.toString();
            return rowName != null && byName.containsKey(rowName)
                ? byName[rowName]!
                : core.Map<String, dynamic>.from(row);
          }).toList(growable: false);
        final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(data, 'تعذر حفظ أرقام الدفعات والأرقام التسلسلية لإذن التسليم.'));
        }
        final saved = data['message'];
        if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Delivery Note' ||
            saved['name'] != name || saved['docstatus'] != 0) {
          throw Exception('لم يؤكد ERPNext حفظ تخصيص أرقام إذن التسليم.');
        }
        return saved;
      } finally {
        _inFlightDocumentActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> submitSalesWorkflowDocument(String doctype, String name) async {
      final actionKey = 'submit-sales-doc:$name';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('ترحيل مستند المبيعات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      _salesWorkflowResource(doctype);
      final current = await fetchSalesWorkflowDocument(doctype, name);
      if (current['docstatus'] != 0) throw const FormatException('لا يمكن ترحيل هذا المستند لأنه ليس مسودة.');
      final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر ترحيل $doctype.'));
      final submitted = data['message'];
      if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != doctype || submitted['name'] != name || submitted['docstatus'] != 1) {
        throw Exception('لم يؤكد ERPNext ترحيل $doctype؛ تحقق من حالة المستند قبل إعادة المحاولة.');
      }
      return submitted;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> cancelSalesWorkflowDocument(String doctype, String name) async {
      final actionKey = 'cancel-sales-doc:$name';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('إلغاء مستند المبيعات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      _salesWorkflowResource(doctype);
      final current = await fetchSalesWorkflowDocument(doctype, name);
      if (current['docstatus'] != 1) throw const FormatException('يمكن إلغاء مستند مبيعات مرحّل فقط.');
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إلغاء $doctype.'));
      final cancelled = data['message'];
      if (cancelled is! core.Map<String, dynamic> || cancelled['doctype'] != doctype || cancelled['name'] != name || cancelled['docstatus'] != 2) {
        throw Exception('لم يؤكد ERPNext إلغاء $doctype.');
      }
      return cancelled;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> makeSalesWorkflowDocument({
      required String sourceDoctype, required String sourceName, required String targetDoctype,
    }) async {
      final actionKey = 'map-sales:$sourceDoctype:$sourceName:$targetDoctype';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('تحويل مستند المبيعات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      final allowed = <String, Set<String>>{
        'Quotation': {'Sales Order'}, 'Sales Order': {'Delivery Note', 'Sales Invoice'},
        'Delivery Note': {'Sales Invoice'},
      };
      if (!(allowed[sourceDoctype]?.contains(targetDoctype) ?? false)) throw const FormatException('مسار تحويل مستندات المبيعات غير مسموح.');
      final source = await fetchSalesWorkflowDocument(sourceDoctype, sourceName);
      if (source['docstatus'] != 1) throw const FormatException('يجب ترحيل المستند الأصلي قبل إنشاء المستند التالي.');
      final method = switch ('$sourceDoctype>$targetDoctype') {
        'Quotation>Sales Order' => 'erpnext.selling.doctype.quotation.mapper.make_sales_order',
        'Sales Order>Delivery Note' => 'erpnext.selling.doctype.sales_order.mapper.make_delivery_note',
        'Sales Order>Sales Invoice' => 'erpnext.selling.doctype.sales_order.mapper.make_sales_invoice',
        'Delivery Note>Sales Invoice' => 'erpnext.stock.doctype.delivery_note.mapper.make_sales_invoice',
        _ => throw const FormatException('مسار التحويل غير مدعوم.'),
      };
      final mapped = await _sendJson('POST', '/api/method/$method', {'source_name': sourceName});
      final mappedData = _decode(mapped.body);
      if (mapped.statusCode < 200 || mapped.statusCode >= 300) throw Exception(_message(mappedData, 'تعذر تجهيز $targetDoctype من $sourceDoctype.'));
      final raw = mappedData['message'];
      if (raw is! core.Map<String, dynamic> || raw['doctype'] != targetDoctype ||
          raw['company'] is! String || (raw['company'] as String).trim().isEmpty ||
          raw['customer'] is! String || (raw['customer'] as String).trim().isEmpty ||
          raw['items'] is! List || (raw['items'] as List).isEmpty) {
        throw Exception('لم يُرجع ERPNext مستند $targetDoctype صالحاً من أداة التحويل.');
      }
      // Mapped rows inherit warehouses from their source document. Validate
      // those references against the live company/warehouse records before insert.
      await _validateDocumentWarehouses(raw);
      final inserted = await _sendJson('POST', '/api/resource/${_salesWorkflowResource(targetDoctype)}', core.Map<String, dynamic>.from(raw));
      final insertedData = _decode(inserted.body);
      if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ مسودة $targetDoctype.'));
      final created = insertedData['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != targetDoctype || created['name'] is! String || created['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة $targetDoctype؛ تحقق من المستندات قبل إعادة المحاولة.');
      }
      return created;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  void _validateSalesTeamAllocation(dynamic raw) {
      if (raw == null) return;
      if (raw is! List) {
        throw const FormatException('توزيع مندوبي المبيعات يجب أن يكون قائمة صحيحة.');
      }
      if (raw.isEmpty) return;
      final seen = <String>{};
      var total = 0.0;
      for (final entry in raw) {
        if (entry is! core.Map) {
          throw const FormatException('يوجد مندوب مبيعات في توزيع الفاتورة ببيانات غير صحيحة.');
        }
        final person = entry['sales_person']?.toString().trim() ?? '';
        final allocation = double.tryParse(entry['allocated_percentage']?.toString() ?? '');
        if (person.isEmpty || !seen.add(person) || allocation == null ||
            !allocation.isFinite || allocation <= 0 || allocation > 100) {
          throw const FormatException('تحقق من أسماء مندوبي المبيعات ونسب توزيعهم وتجنب تكرار المندوب.');
        }
        total += allocation;
      }
      if ((total - 100).abs() > 0.000001) {
        throw FormatException('مجموع نسب توزيع مندوبي المبيعات يجب أن يساوي 100%. النسبة الحالية: ${total.toStringAsFixed(2)}%.');
      }
    }

  Future<core.Map<String, dynamic>> createSalesInvoice(core.Map<String, dynamic> invoice) async {
      final customer = invoice['customer'];
      final company = invoice['company'];
      final rawItems = invoice['items'];
      if (invoice['doctype'] != 'Sales Invoice' || customer is! String || customer.trim().isEmpty || company is! String || company.trim().isEmpty || rawItems is! List || rawItems.isEmpty) {
        throw const FormatException('حدد الشركة والعميل وأضف صنفاً واحداً على الأقل.');
      }
      invoice['items'] = _cleanSerialBatchRows(rawItems);
      _validateSalesTeamAllocation(invoice['sales_team']);
      for (final rawItem in rawItems) {
        if (rawItem is! core.Map<String, dynamic> || rawItem['item_code'] is! String || (rawItem['item_code'] as String).trim().isEmpty) {
          throw const FormatException('يوجد بند فاتورة دون رمز صنف صحيح.');
        }
        final qty = rawItem['qty'];
        final rate = rawItem['rate'];
        if (qty is! num || !qty.isFinite || qty <= 0 || rate is! num || !rate.isFinite || rate <= 0 || !(qty * rate).isFinite) {
          throw const FormatException('تحقق من كمية وسعر كل بند في الفاتورة.');
        }
      }
      await _validateDocumentWarehouses(invoice);
      final response = await _sendJson('POST', '/api/resource/Sales%20Invoice', invoice);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ فاتورة المبيعات (${response.statusCode}).'));
      }
      final document = data['data'];
      if (document is! core.Map<String, dynamic> ||
          document['doctype'] != 'Sales Invoice' ||
          document['name'] is! String ||
          document['name'].toString().isEmpty ||
          document['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المبيعات؛ تحقق من قائمة الفواتير قبل إعادة المحاولة.');
      }
      return document;
    }

  Future<core.Map<String, dynamic>> submitSalesInvoice(core.Map<String, dynamic> document) async {
      final actionKey = 'submit-invoice:${document['name']}';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('ترحيل هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      if (document['doctype'] != 'Sales Invoice' ||
          document['name'] is! String ||
          document['name'].toString().trim().isEmpty) {
        throw const FormatException('لا يمكن ترحيل هذا المستند؛ يجب أن يكون فاتورة مبيعات صحيحة.');
      }
      final name = document['name'].toString();
      final current = await fetchInvoiceDocument('Sales Invoice', name);
      if (current['docstatus'] != 0) {
        throw const FormatException('لا يمكن ترحيل الفاتورة لأنها ليست مسودة حالياً.');
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تم حفظ المسودة، لكن تعذر ترحيل الفاتورة (${response.statusCode}).'));
      }
      final submitted = data['message'];
      if (submitted is! core.Map<String, dynamic> ||
          submitted['doctype'] != 'Sales Invoice' ||
          submitted['name'] != name ||
          submitted['docstatus'] != 1) {
        throw Exception('لم يؤكد ERPNext ترحيل الفاتورة؛ افتح المستند وتحقق من حالته قبل إعادة المحاولة.');
      }
      return submitted;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> updateDraftSalesInvoice({
      required String invoiceName,
      required core.Map<String, dynamic> changes,
    }) async {
      final normalizedName = invoiceName.trim();
      if (normalizedName.isEmpty || changes['doctype'] != 'Sales Invoice' || changes['items'] is! List || (changes['items'] as List).isEmpty) {
        throw const FormatException('رقم المسودة والبنود المطلوبة للتعديل غير مكتملة.');
      }
      changes['items'] = _cleanSerialBatchRows(changes['items'] as List);
      _validateSalesTeamAllocation(changes['sales_team']);
      final customer = changes['customer'];
      final company = changes['company'];
      if (customer is! String || customer.trim().isEmpty ||
          company is! String || company.trim().isEmpty) {
        throw const FormatException('حدد الشركة والعميل قبل حفظ التعديلات.');
      }
      for (final rawItem in changes['items'] as List) {
        if (rawItem is! core.Map<String, dynamic> ||
            rawItem['item_code'] is! String ||
            (rawItem['item_code'] as String).trim().isEmpty) {
          throw const FormatException('يوجد بند فاتورة دون رمز صنف صحيح.');
        }
        final qty = rawItem['qty'];
        final rate = rawItem['rate'];
        if (qty is! num || !qty.isFinite || qty <= 0 ||
            rate is! num || !rate.isFinite || rate <= 0 || !(qty * rate).isFinite) {
          throw const FormatException('تحقق من كمية وسعر كل بند في الفاتورة.');
        }
      }
  
      await _validateDocumentWarehouses(changes);
      final current = await fetchInvoiceDocument('Sales Invoice', normalizedName);
      if (current['docstatus'] != 0) {
        throw const FormatException('لا يمكن تعديل فاتورة إلا إذا كانت مسودة غير مرحلة.');
      }
      if (current['is_return'] == 1 || current['is_return'] == true) {
        throw const FormatException('مسودة المرتجع لا تُعدّل من محرر الفاتورة العادية؛ راجعها في ERPNext لتجنب إفساد الكميات السالبة وروابط الفاتورة الأصلية.');
      }
      final payload = core.Map<String, dynamic>.from(current);
      payload['customer'] = customer;
      payload['company'] = company;
      payload['posting_date'] = changes['posting_date'] ?? current['posting_date'];
      payload['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0;
      payload['items'] = changes['items'];
      payload['sales_team'] = changes['sales_team'] ?? const <core.Map<String, dynamic>>[];
  
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ تعديلات مسودة فاتورة المبيعات.'));
      }
      final saved = data['message'];
      if (saved is! core.Map<String, dynamic> || saved['name'] != normalizedName || saved['docstatus'] != 0) {
        throw Exception('استجابة تحديث المسودة غير مؤكدة؛ افتح الفاتورة وتحقق من حالتها قبل إعادة المحاولة.');
      }
      return saved;
    }

  Future<core.Map<String, dynamic>> createSalesReturn(String invoiceName) async {
      final actionKey = 'return:$invoiceName';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('إنشاء مرتجع هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      final normalizedName = invoiceName.trim();
      if (normalizedName.isEmpty) {
        throw const FormatException('رقم فاتورة البيع الأصلية غير موجود.');
      }
  
      final pendingUri = Uri.parse('$_baseUrl/api/resource/Sales%20Invoice').replace(
        queryParameters: {
          'fields': jsonEncode(['name', 'return_against', 'docstatus']),
          'filters': jsonEncode([
            ['return_against', '=', normalizedName],
            ['is_return', '=', 1],
            ['docstatus', '=', 0],
          ]),
          'limit_page_length': '5',
          'order_by': 'modified desc',
        },
      );
      final pendingResponse = await _sendUri('GET', pendingUri);
      final pendingData = _decode(pendingResponse.body);
      if (pendingResponse.statusCode < 200 || pendingResponse.statusCode >= 300) {
        throw Exception(_message(pendingData, 'تعذر التحقق من وجود مسودات مرتجع سابقة؛ أوقف الإنشاء لتجنب التكرار.'));
      }
      final pendingRows = pendingData['data'];
      if (pendingRows is List && pendingRows.isNotEmpty) {
        final pendingName = pendingRows.first is core.Map<String, dynamic>
            ? (pendingRows.first as core.Map<String, dynamic>)['name']?.toString()
            : null;
        throw FormatException(
          'يوجد مرتجع غير مرحّل لهذه الفاتورة ${pendingName ?? ''}. افتح المسودة الحالية وراجعها أو رحّلها قبل إنشاء مرتجع آخر.',
        );
      }
  
      final source = await fetchInvoiceDocument('Sales Invoice', normalizedName);
      if (source['docstatus'] != 1 || source['is_return'] == 1 || source['is_return'] == true) {
        throw const FormatException('يمكن إنشاء مرتجع من فاتورة مبيعات أصلية مرحّلة فقط.');
      }
  
      // Let ERPNext map the return so it carries original taxes, item references,
      // negative quantities, and already-returned quantity limits.
      final mapped = await _sendJson(
        'POST',
        '/api/method/erpnext.accounts.doctype.sales_invoice.mapper.make_sales_return',
        {'source_name': normalizedName},
      );
      final mappedData = _decode(mapped.body);
      if (mapped.statusCode < 200 || mapped.statusCode >= 300) {
        throw Exception(_message(mappedData, 'تعذر تجهيز مرتجع المبيعات من ERPNext.'));
      }
      final rawReturn = mappedData['message'];
      if (rawReturn is! core.Map<String, dynamic>) {
        throw Exception('استجابة تجهيز المرتجع غير متوقعة.');
      }
      final returnDraft = core.Map<String, dynamic>.from(rawReturn);
      if (returnDraft['doctype'] != 'Sales Invoice' ||
          (returnDraft['is_return'] != 1 && returnDraft['is_return'] != true) ||
          returnDraft['return_against'] != normalizedName) {
        throw Exception('لم يؤكد ERPNext أن المستند الناتج مرتجع مرتبط بالفاتورة الأصلية.');
      }
      final returnItems = returnDraft['items'];
      if (returnItems is! List || returnItems.isEmpty) {
        throw const FormatException('لا توجد كميات متاحة للإرجاع في هذه الفاتورة.');
      }
  
      final inserted = await _sendJson('POST', '/api/resource/Sales%20Invoice', returnDraft);
      final insertedData = _decode(inserted.body);
      if (inserted.statusCode < 200 || inserted.statusCode >= 300) {
        throw Exception(_message(insertedData, 'تعذر حفظ مسودة مرتجع المبيعات.'));
      }
      final created = insertedData['data'];
      if (created is! core.Map<String, dynamic> ||
          created['doctype'] != 'Sales Invoice' ||
          created['name'] is! String ||
          created['docstatus'] != 0 ||
          (created['is_return'] != 1 && created['is_return'] != true) ||
          created['return_against'] != normalizedName) {
        throw Exception('لم يؤكد ERPNext إنشاء مسودة مرتجع مرتبطة بالفاتورة الأصلية؛ تحقق من فواتير المبيعات قبل إعادة المحاولة.');
      }
      return created;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }

  Future<core.Map<String, dynamic>> cancelSalesInvoice(core.Map<String, dynamic> document) async {
      final actionKey = 'cancel-invoice:${document['name']}';
      if (!_inFlightSalesActions.add(actionKey)) {
        throw const FormatException('إلغاء هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
      }
      try {
      if (document['doctype'] != 'Sales Invoice' ||
          document['name'] is! String ||
          document['name'].toString().trim().isEmpty ||
          document['docstatus'] != 1) {
        throw const FormatException('لا يمكن إلغاء هذا المستند؛ يجب أن يكون فاتورة مبيعات مرحّلة.');
      }
      final name = document['name'].toString();
      final current = await fetchInvoiceDocument('Sales Invoice', name);
      if (current['docstatus'] != 1) {
        throw const FormatException('يمكن إلغاء فاتورة مبيعات مرحّلة فقط.');
      }
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر إلغاء فاتورة المبيعات (${response.statusCode}).'));
      }
      final cancelled = data['message'];
      if (cancelled is! core.Map<String, dynamic> ||
          cancelled['doctype'] != 'Sales Invoice' ||
          cancelled['name'] != name ||
          cancelled['docstatus'] != 2) {
        throw Exception('لم يؤكد ERPNext إلغاء الفاتورة؛ تحقق من حالتها قبل إعادة المحاولة.');
      }
      return cancelled;
      } finally {
        _inFlightSalesActions.remove(actionKey);
      }
    }
}
