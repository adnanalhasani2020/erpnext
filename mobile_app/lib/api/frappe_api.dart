// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_const_constructors
import 'dart:convert';
import 'dart:io';

import '../models/erp_models.dart';

class FrappeApi {
  static const int pageSize = 100;

  final HttpClient _client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  static Uri buildResourcePageUri({
    required String baseUrl,
    required String resource,
    required List<String> fields,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
    required String orderBy,
    int start = 0,
    int pageLength = pageSize,
  }) {
    final parameters = <String, String>{
      'fields': jsonEncode(fields),
      'limit_page_length': (pageLength < 1 ? 1 : pageLength).toString(),
      'limit_start': (start < 0 ? 0 : start).toString(),
      'order_by': orderBy,
    };
    if (filters != null && filters.isNotEmpty) {
      parameters['filters'] = jsonEncode(filters);
    }
    if (orFilters != null && orFilters.isNotEmpty) {
      parameters['or_filters'] = jsonEncode(orFilters);
    }
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final baseUri = Uri.parse(normalizedBase);
    // Build the resource path from decoded segments so names containing spaces
    // are encoded exactly once. Parsing an already-escaped path and then
    // replacing query parameters can otherwise double-escape "%20" as "%2520".
    final pathSegments = <String>[
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      'resource',
      resource,
    ];
    return baseUri.replace(
      pathSegments: pathSegments,
      queryParameters: parameters,
    );
  }

  final Map<String, String> _cookies = {};
  final Set<String> _inFlightSalesActions = <String>{};
  final Set<String> _inFlightPaymentActions = <String>{};
  final Set<String> _inFlightPurchaseActions = <String>{};
  final Set<String> _inFlightDocumentActions = <String>{};
  String _baseUrl = '';
  int _sessionGeneration = 0;

  int get sessionGeneration => _sessionGeneration;

  void configure(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty ||
        uri.hasQuery || uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '10.0.2.2')))) {
      throw const FormatException('أدخل رابطاً صحيحاً يبدأ بـ https://');
    }
    if (_baseUrl != normalized) {
      _cookies.clear();
      _sessionGeneration++;
    }
    _baseUrl = normalized;
  }

  Future<String> login(String username, String password) async {
    _sessionGeneration++;
    _cookies.clear();
    final generation = _sessionGeneration;
    if (username.trim().isEmpty || password.isEmpty) {
      throw const FormatException('أدخل اسم المستخدم وكلمة المرور.');
    }
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/login'));
    request.followRedirects = false;
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    request.write(Uri(queryParameters: {'usr': username.trim(), 'pwd': password}).query);
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
    if (generation != _sessionGeneration) {
      throw const HttpException('انتهت صلاحية محاولة تسجيل الدخول.');
    }
    _captureCookies(response);
    final data = _decode(body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تسجيل الدخول (${response.statusCode})'));
    }
    if (_cookies.isEmpty) {
      throw Exception(_message(data, 'لم يستلم التطبيق جلسة دخول من الخادم. تحقق من إعدادات ERPNext.'));
    }
    return currentUser();
  }


  void _validateSerialBatchRows(List<dynamic> items) {
    final seenSerials = <String>{};
    final seenCurrentSerials = <String>{};
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) throw const FormatException('بيانات بند الصنف المتتبع غير صحيحة.');
      final serialText = raw['serial_no']?.toString() ?? '';
      final batch = raw['batch_no']?.toString().trim() ?? '';
      final useFields = raw['use_serial_batch_fields'] == 1 || raw['use_serial_batch_fields'] == true;
      if (!useFields && serialText.trim().isEmpty && batch.isEmpty) continue;
      final qty = raw['qty'];
      final currentQty = raw['current_qty'];
      final currentSerialText = raw['current_serial_no']?.toString() ?? '';
      final currentSerials = currentSerialText.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      if (qty is! num || !qty.isFinite || qty < 0) throw const FormatException('كمية الصنف المتتبع غير صحيحة.');
      if (currentQty != null && (currentQty is! num || !currentQty.isFinite || currentQty < 0)) {
        throw const FormatException('الكمية الحالية للصنف المتتبع غير صحيحة.');
      }
      if (currentSerials.isNotEmpty &&
          (currentQty is! num || (currentQty - currentQty.round()).abs() > 0.000001 ||
              currentSerials.length != currentQty.round())) {
        throw const FormatException('عدد الأرقام التسلسلية الحالية لا يطابق الرصيد الحالي.');
      }
      for (final serial in currentSerials) {
        if (!seenCurrentSerials.add(serial)) {
          throw FormatException('الرقم التسلسلي الحالي مكرر داخل تسوية الجرد: ' + serial);
        }
      }
      if (qty == 0) {
        if (currentQty is! num || currentQty <= 0 ||
            (currentSerials.isEmpty && batch.isEmpty) || serialText.trim().isNotEmpty) {
          throw const FormatException('تسوية الصنف المتتبع إلى صفر تتطلب لقطة صحيحة للأرقام أو الدفعة الحالية.');
        }
        continue;
      }
      final serials = serialText.split(RegExp(r'[\r\n,;]+')).map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
      if (serials.isNotEmpty) {
        final rounded = qty.round();
        if ((qty - rounded).abs() > 0.000001 || serials.length != rounded) throw const FormatException('عدد الأرقام التسلسلية يجب أن يساوي كمية الصنف الصحيحة.');
        for (final serial in serials) {
          if (!seenSerials.add(serial)) throw FormatException('الرقم التسلسلي مكرر داخل المستند: ' + serial);
        }
      }
      if (serials.isEmpty && batch.isEmpty) throw const FormatException('أدخل رقماً تسلسلياً أو رقم دفعة للصنف المتتبع.');
    }
  }
  List<Map<String, dynamic>> _cleanSerialBatchRows(List<dynamic> items) {
    _validateSerialBatchRows(items);
    return items.whereType<Map<String, dynamic>>().map((row) => Map<String, dynamic>.from(row)
      ..remove('expiry_date')
      ..remove('manufacturing_date')).toList(growable: false);
  }

  Future<List<ErpCompany>> fetchCompanies() async {
    const companyPageSize = pageSize;
    const maxCompanyCount = 10000;
    final companies = <ErpCompany>[];
    var start = 0;

    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Company',
        fields: const ['name', 'abbr', 'default_currency'],
        orderBy: 'name asc',
        start: start,
        pageLength: companyPageSize,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب الشركات. تحقق من صلاحية قراءة Company.'));
      }
      final rows = data['data'];
      if (rows is! List) {
        throw Exception('استجابة الشركات من ERPNext غير متوقعة.');
      }

      final page = rows
          .whereType<Map<String, dynamic>>()
          .map(ErpCompany.fromJson)
          .toList(growable: false);
      companies.addAll(page);
      if (rows.length < companyPageSize) {
        return companies;
      }
      if (companies.length > maxCompanyCount) {
        throw const FormatException(
          'تجاوز عدد الشركات الحد الآمن للتحميل دفعة واحدة؛ استخدم البحث أو راجع إعدادات ERPNext.',
        );
      }
      start += rows.length;
    }
  }


  /// Reads the complete standard ERPNext Item document. The server returns
  /// only fields the authenticated user is permitted to read.
  Future<Map<String, dynamic>> fetchItemDocument(String itemCode) async {
    final code = itemCode.trim();
    if (code.isEmpty) throw const FormatException('رمز الصنف مطلوب.');
    final uri = Uri.parse(
      '$_baseUrl/api/resource/Item/' + Uri.encodeComponent(code),
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل الصنف من ERPNext. تحقق من صلاحية قراءة Item.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic>) {
      throw Exception('استجابة تفاصيل الصنف من ERPNext غير صحيحة.');
    }
    return Map<String, dynamic>.from(document);
  }

  /// Reads standard Item Price rows for one item, including selling and
  /// buying entries. No price is calculated or invented on the client.
  Future<List<Map<String, dynamic>>> fetchItemPriceEntries({
    required String itemCode,
    int start = 0,
  }) async {
    final code = itemCode.trim();
    if (code.isEmpty) throw const FormatException('رمز الصنف مطلوب.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Item Price',
      fields: const [
        'name', 'item_code', 'price_list', 'price_list_rate', 'currency',
        'uom', 'valid_from', 'valid_upto', 'min_qty', 'selling', 'buying',
      ],
      filters: [['item_code', '=', code]],
      orderBy: 'price_list asc, selling desc, buying desc, valid_from desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أسعار البيع والشراء للصنف. تحقق من صلاحية قراءة Item Price.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة أسعار الصنف من ERPNext غير صحيحة.');
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  /// Resolves ERPNext file paths without changing already absolute URLs.
  String resolveFileUrl(String path) {
    final value = path.trim();
    if (value.isEmpty) return '';
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) return value;
    return Uri.parse(_baseUrl).resolve(value).toString();
  }

  Future<List<ErpItem>> fetchItems({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Item',
      fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date'],
      filters: [['disabled', '=', 0]],
      orFilters: search == null || search.trim().isEmpty
          ? null
          : [
              ['item_code', 'like', '%${search.trim()}%'],
              ['item_name', 'like', '%${search.trim()}%'],
            ],
      orderBy: 'modified desc, item_code asc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب الأصناف. تحقق من صلاحية قراءة Item.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة الأصناف من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpItem.fromJson).toList(growable: false);
  }



  Future<void> _ensureIncomingBatchNumbers(List<dynamic> items) async {
    final seen = <String>{};
    final seenExpiry = <String, String>{};
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final batchNo = raw['batch_no']?.toString().trim() ?? '';
      if (batchNo.isEmpty) continue;
      final itemCode = raw['item_code']?.toString().trim() ?? '';
      if (itemCode.isEmpty) {
        throw const FormatException('رمز الصنف مطلوب لإنشاء الدفعة.');
      }
      final key = '$itemCode|$batchNo';
      final expiryDate = raw['expiry_date']?.toString().trim() ?? '';
      if (expiryDate.isNotEmpty) {
        final parsed = DateTime.tryParse(expiryDate);
        final canonical = RegExp(r'^\d{4}-\d{2}-\d{2}$');
        if (parsed == null || !canonical.hasMatch(expiryDate) ||
            parsed.toIso8601String().substring(0, 10) != expiryDate) {
          throw FormatException('تاريخ انتهاء الدفعة $batchNo غير صحيح. استخدم YYYY-MM-DD.');
        }
      }
      if (!seen.add(key)) {
        final previousExpiry = seenExpiry[key] ?? '';
        if (previousExpiry != expiryDate) {
          throw FormatException('توجد بيانات انتهاء متعارضة للدفعة $batchNo.');
        }
        continue;
      }
      seenExpiry[key] = expiryDate;

      Future<Map<String, dynamic>?> readBatch() async {
        final uri = Uri.parse(
          '$_baseUrl/api/resource/Batch/' + Uri.encodeComponent(batchNo),
        );
        final response = await _sendUri('GET', uri);
        if (response.statusCode == 404) return null;
        final data = _decode(response.body);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(_message(
            data,
            'تعذر التحقق من سجل الدفعة $batchNo. تحقق من صلاحية قراءة Batch.',
          ));
        }
        final batch = data['data'];
        if (batch is! Map<String, dynamic>) {
          throw Exception('استجابة سجل الدفعة غير صحيحة: $batchNo');
        }
        return batch;
      }

      void validateExisting(Map<String, dynamic> batch) {
        if (batch['item'] != itemCode) {
          throw FormatException('رقم الدفعة $batchNo مسجل لصنف آخر.');
        }
        if (batch['disabled'] == 1 || batch['disabled'] == true) {
          throw FormatException('الدفعة $batchNo معطلة ولا يمكن استخدامها.');
        }
        if (expiryDate.isNotEmpty) {
          final existingExpiry = batch['expiry_date']?.toString().trim() ?? '';
          final normalizedExisting = existingExpiry.length >= 10
              ? existingExpiry.substring(0, 10)
              : existingExpiry;
          if (normalizedExisting != expiryDate) {
            final shownExpiry = existingExpiry.isEmpty ? 'غير محدد' : existingExpiry;
            throw FormatException(
              'تاريخ انتهاء الدفعة $batchNo لا يطابق التاريخ المسجل في ERPNext ($shownExpiry).',
            );
          }
        }
      }

      final existing = await readBatch();
      if (existing != null) {
        validateExisting(existing);
        continue;
      }

      final itemUri = Uri.parse(
        '$_baseUrl/api/resource/Item/' + Uri.encodeComponent(itemCode),
      ).replace(queryParameters: {
        'fields': jsonEncode(['item_code', 'has_batch_no', 'has_expiry_date']),
      });
      final itemResponse = await _sendUri('GET', itemUri);
      final itemData = _decode(itemResponse.body);
      if (itemResponse.statusCode < 200 || itemResponse.statusCode >= 300 ||
          itemData['data'] is! Map<String, dynamic>) {
        throw Exception(_message(
          itemData,
          'تعذر قراءة إعدادات الصنف قبل إنشاء الدفعة.',
        ));
      }
      final item = itemData['data'] as Map<String, dynamic>;
      if (item['has_batch_no'] != 1 && item['has_batch_no'] != true) {
        throw FormatException('الصنف $itemCode غير مفعّل لتتبع الدفعات.');
      }
      final requiresExpiry =
          item['has_expiry_date'] == 1 || item['has_expiry_date'] == true;
      if (requiresExpiry && expiryDate.isEmpty) {
        throw FormatException(
          'أدخل تاريخ انتهاء صحيحاً للدفعة $batchNo بصيغة YYYY-MM-DD.',
        );
      }

      final payload = <String, dynamic>{
        'doctype': 'Batch',
        'batch_id': batchNo,
        'item': itemCode,
        if (expiryDate.isNotEmpty) 'expiry_date': expiryDate,
      };
      final createdResponse = await _sendJson(
        'POST',
        '/api/resource/Batch',
        payload,
      );
      final createdData = _decode(createdResponse.body);
      if (createdResponse.statusCode >= 200 &&
          createdResponse.statusCode < 300) {
        final created = createdData['data'];
        if (created is! Map<String, dynamic> ||
            created['name'] != batchNo ||
            created['item'] != itemCode) {
          throw Exception('لم يؤكد ERPNext إنشاء الدفعة $batchNo.');
        }
        continue;
      }

      // A concurrent request may have created the same batch after our read.
      final raced = await readBatch();
      if (raced != null) {
        validateExisting(raced);
        continue;
      }
      throw Exception(_message(
        createdData,
        'تعذر إنشاء الدفعة $batchNo. يحتاج المستخدم إلى صلاحية إنشاء Batch.',
      ));
    }
  }

  Future<List<Map<String, dynamic>>> fetchAvailableBatches({
    required String itemCode,
    required String warehouse,
    bool ignoreReservedStock = false,
    bool includeExpired = false,
  }) async {
    if (itemCode.trim().isEmpty || warehouse.trim().isEmpty) {
      throw const FormatException('حدد الصنف والمستودع لعرض الدفعات المتاحة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.stock.doctype.batch.batch.get_batch_qty')
        .replace(queryParameters: {
      'item_code': itemCode.trim(),
      'warehouse': warehouse.trim(),
      if (ignoreReservedStock) 'ignore_reserved_stock': '1',
      if (includeExpired) 'for_stock_levels': '1',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب الدفعات المتاحة من ERPNext.'));
    }
    final message = data['message'];
    if (message is! List) throw Exception('استجابة الدفعات المتاحة من ERPNext غير متوقعة.');
    return message.whereType<Map<String, dynamic>>().map((row) => Map<String, dynamic>.from(row))
        .where((row) => row['batch_no'] is String &&
            (double.tryParse(row['qty']?.toString() ?? '') ?? 0) > 0)
        .toList(growable: false);
  }

  Future<List<String>> fetchAvailableSerialNumbers({
    required String itemCode,
    required String warehouse,
    required int quantity,
    List<String> batchNumbers = const [],
  }) async {
    if (itemCode.trim().isEmpty || warehouse.trim().isEmpty || quantity < 1 || quantity > 200) {
      throw const FormatException('بيانات طلب الأرقام التسلسلية غير صحيحة؛ الكمية القصوى للبحث 200 وحدة.');
    }
    final response = await _sendJson('POST',
        '/api/method/erpnext.stock.doctype.serial_no.serial_no.auto_fetch_serial_number', {
      'item_code': itemCode.trim(),
      'warehouse': warehouse.trim(),
      'qty': quantity,
      if (batchNumbers.isNotEmpty) 'batch_nos': jsonEncode(batchNumbers),
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب الأرقام التسلسلية المتاحة من ERPNext.'));
    }
    final message = data['message'];
    if (message is! List) throw Exception('استجابة الأرقام التسلسلية من ERPNext غير متوقعة.');
    return message.whereType<String>().map((value) => value.trim()).where((value) => value.isNotEmpty)
        .toSet().toList(growable: false);
  }

  Future<List<ErpWarehouse>> fetchWarehouses({int start = 0, String? search}) async {
    final query = search?.trim();
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Warehouse',
      fields: ['name', 'warehouse_name', 'company', 'is_group'],
      filters: [['disabled', '=', 0], ['is_group', '=', 0]],
      orFilters: query == null || query.isEmpty
          ? null
          : [
              ['name', 'like', '%$query%'],
              ['warehouse_name', 'like', '%$query%'],
              ['company', 'like', '%$query%'],
            ],
      orderBy: 'warehouse_name asc, name asc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب المستودعات. تحقق من صلاحية قراءة Warehouse.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة المستودعات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpWarehouse.fromJson).toList(growable: false);
  }


  Future<List<ErpStockBalance>> fetchStockBalances({int start = 0, String? search, String? warehouse}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Bin',
      fields: ['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty', 'stock_uom', 'valuation_rate', 'stock_value'],
      filters: [
        if (warehouse != null && warehouse.trim().isNotEmpty) ['warehouse', '=', warehouse.trim()],
        if (search != null && search.trim().isNotEmpty) ['item_code', 'like', '%${search.trim()}%'],
      ],
      orFilters: [
        ['actual_qty', '!=', 0],
        ['reserved_qty', '!=', 0],
        ['projected_qty', '!=', 0],
      ],
      orderBy: 'item_code asc, warehouse asc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب أرصدة المخزون. تحقق من صلاحية قراءة Bin.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة أرصدة المخزون من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpStockBalance.fromJson).toList(growable: false);
  }

  /// Finds Item warehouse reorder rules whose projected quantity is at or
  /// below the configured threshold. Group-based rules are omitted because
  /// they require aggregating projected stock across a warehouse tree.
  Future<List<ErpStockReorderAlert>> fetchStockReorderAlerts() async {
    const maxRules = 10000;
    final rules = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Item Reorder',
        fields: const [
          'name', 'parent', 'parenttype', 'parentfield', 'warehouse_group',
          'warehouse', 'warehouse_reorder_level', 'warehouse_reorder_qty',
        ],
        filters: const [
          ['parenttype', '=', 'Item'],
          ['parentfield', '=', 'reorder_levels'],
        ],
        orderBy: 'parent asc, warehouse asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل حدود إعادة الطلب. تحقق من صلاحية قراءة Item Reorder.'));
      }
      final page = data['data'];
      if (page is! List) throw Exception('استجابة حدود إعادة الطلب غير متوقعة.');
      rules.addAll(page.whereType<Map<String, dynamic>>());
      if (rules.length > maxRules) {
        throw const FormatException('عدد قواعد إعادة الطلب تجاوز 10000؛ راجع نطاق البيانات أو صلاحيات المستخدم.');
      }
      if (page.length < pageSize) break;
      start += page.length;
    }
    final supportedRules = rules.where((rule) {
      final group = rule['warehouse_group'];
      return rule['parent'] is String &&
          (rule['parent'] as String).isNotEmpty &&
          rule['warehouse'] is String &&
          (rule['warehouse'] as String).isNotEmpty &&
          (group == null || group.toString().trim().isEmpty);
    }).toList(growable: false);
    if (supportedRules.isEmpty) return const [];

    final itemCodes = supportedRules.map((rule) => rule['parent'] as String).toSet().toList();
    final warehouses = supportedRules.map((rule) => rule['warehouse'] as String).toSet().toList();
    final bins = <Map<String, dynamic>>[];
    var binStart = 0;
    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Bin',
        fields: const ['item_code', 'warehouse', 'actual_qty', 'projected_qty', 'stock_uom', 'company'],
        filters: [
          ['item_code', 'in', itemCodes],
          ['warehouse', 'in', warehouses],
        ],
        orderBy: 'item_code asc, warehouse asc',
        start: binStart,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل أرصدة الأصناف لفحص إعادة الطلب.'));
      }
      final page = data['data'];
      if (page is! List) throw Exception('استجابة أرصدة إعادة الطلب غير متوقعة.');
      bins.addAll(page.whereType<Map<String, dynamic>>());
      if (page.length < pageSize) break;
      binStart += page.length;
    }
    final binByKey = <String, Map<String, dynamic>>{
      for (final bin in bins)
        if (bin['item_code'] is String && bin['warehouse'] is String)
          '${bin['item_code']}::${bin['warehouse']}': bin,
    };
    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }
    final alerts = <ErpStockReorderAlert>[];
    for (final rule in supportedRules) {
      final itemCode = rule['parent'] as String;
      final warehouse = rule['warehouse'] as String;
      final bin = binByKey['$itemCode::$warehouse'];
      final projected = number(bin?['projected_qty']);
      final level = number(rule['warehouse_reorder_level']);
      if (projected <= level) {
        alerts.add(ErpStockReorderAlert(
          itemCode: itemCode,
          warehouse: warehouse,
          actualQty: number(bin?['actual_qty']),
          projectedQty: projected,
          stockUom: bin?['stock_uom'] is String ? bin!['stock_uom'] as String : null,
          company: bin?['company'] is String ? bin!['company'] as String : null,
          reorderLevel: level,
          reorderQty: number(rule['warehouse_reorder_qty']),
        ));
      }
    }
    alerts.sort((a, b) => a.projectedQty.compareTo(b.projectedQty));
    return alerts;
  }

  Future<List<ErpCustomer>> fetchCustomers({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Customer').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer_name', 'customer_type', 'customer_group', 'territory']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'customer_name asc, name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب العملاء. تحقق من صلاحية قراءة Customer.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة العملاء من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpCustomer.fromJson).toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchCustomerDocument(String customerId) async {
    final id = customerId.trim();
    if (id.isEmpty) throw const FormatException('حدد العميل أولاً.');
    final uri = Uri.parse(
      '$_baseUrl/api/resource/Customer/' + Uri.encodeComponent(id),
    ).replace(queryParameters: {
      'fields': jsonEncode([
        'name', 'customer_name', 'customer_type', 'customer_group',
        'territory', 'mobile_no', 'email_id', 'website', 'tax_id',
        'default_currency', 'default_price_list', 'disabled',
      ]),
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل ملف العميل.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> || document['name'] != id) {
      throw Exception('استجابة ملف العميل غير صحيحة.');
    }
    return Map<String, dynamic>.from(document);
  }

  Future<Map<String, dynamic>> updateCustomerProfile({
    required String customerId,
    required Map<String, dynamic> values,
  }) async {
    final id = customerId.trim();
    final customerName = values['customer_name']?.toString().trim() ?? '';
    final customerType = values['customer_type']?.toString().trim() ?? '';
    final customerGroup = values['customer_group']?.toString().trim() ?? '';
    final territory = values['territory']?.toString().trim() ?? '';
    if (id.isEmpty || customerName.isEmpty ||
        !{'Company', 'Individual'}.contains(customerType) ||
        customerGroup.isEmpty || territory.isEmpty) {
      throw const FormatException('اسم العميل ونوعه ومجموعة العميل والمنطقة حقول مطلوبة.');
    }
    final allowedFields = <String>{
      'customer_name', 'customer_type', 'customer_group', 'territory',
      'mobile_no', 'email_id', 'website', 'tax_id',
      'default_currency', 'default_price_list',
    };
    final payload = <String, dynamic>{};
    for (final entry in values.entries) {
      if (allowedFields.contains(entry.key)) {
        payload[entry.key] = entry.value is String
            ? (entry.value as String).trim()
            : entry.value;
      }
    }
    payload['customer_name'] = customerName;
    payload['customer_type'] = customerType;
    payload['customer_group'] = customerGroup;
    payload['territory'] = territory;

    // Re-read the document before updating so a stale or mismatched identity
    // cannot be used to change a different Customer record.
    final current = await fetchCustomerDocument(id);
    if (current['name'] != id) {
      throw const FormatException('تغير سجل العميل؛ حدّث القائمة ثم أعد المحاولة.');
    }
    final response = await _sendJson(
      'PUT',
      '/api/resource/Customer/' + Uri.encodeComponent(id),
      payload,
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حفظ تعديلات العميل.'));
    }
    final updated = data['data'];
    if (updated is! Map<String, dynamic> || updated['name'] != id ||
        updated['customer_name'] != customerName) {
      throw Exception('لم يؤكد ERPNext حفظ ملف العميل؛ أعد تحميل الملف قبل أي تعديل آخر.');
    }
    return Map<String, dynamic>.from(updated);
  }

  Future<List<Map<String, dynamic>>> fetchSellingPriceLists() async {
    final uri = buildResourcePageUri(
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
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchItemPrices({
    required String priceList,
    String? search,
    int start = 0,
  }) async {
    if (priceList.trim().isEmpty) {
      throw const FormatException('حدد قائمة الأسعار أولاً.');
    }
    final uri = buildResourcePageUri(
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
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> saveItemSellingPrice({
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
    if (saved is! Map<String, dynamic> ||
        saved['doctype'] != 'Item Price' ||
        saved['item_code'] != item ||
        saved['price_list'] != list ||
        saved['selling'] != 1) {
      throw Exception('لم يؤكد ERPNext حفظ سعر الصنف؛ أعد تحميل قائمة الأسعار.');
    }
    return Map<String, dynamic>.from(saved);
  }

  Future<List<Map<String, dynamic>>> fetchSellingPricingRules({
    int start = 0,
  }) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Pricing Rule',
      fields: const [
        'name', 'title', 'apply_on', 'price_or_product_discount',
        'selling', 'buying', 'disable', 'rate_or_discount',
        'discount_percentage', 'discount_amount', 'for_price_list',
        'currency', 'valid_from', 'valid_upto', 'company',
        'apply_discount_on', 'applicable_for', 'customer', 'items',
        'customer_group', 'territory',
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
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> saveSellingPricingRule({
    String? ruleId,
    required String title,
    required String priceList,
    required String currency,
    required String discountType,
    required double discountValue,
    required String validFrom,
    String? validUpto,
    String? company,
    String? applicableFor,
    String? applicableValue,
    String applyDiscountOn = 'Grand Total',
    String applyOn = 'Transaction',
    String? itemCode,
    double minQty = 0,
  }) async {
    final cleanTitle = title.trim();
    final cleanList = priceList.trim();
    final cleanCurrency = currency.trim();
    if (cleanTitle.isEmpty || cleanList.isEmpty || cleanCurrency.isEmpty ||
        !discountValue.isFinite || discountValue <= 0 ||
        !{'Discount Percentage', 'Discount Amount'}.contains(discountType) ||
        (discountType == 'Discount Percentage' && discountValue > 100) ||
        !{'Grand Total', 'Net Total'}.contains(applyDiscountOn) ||
        !{'Transaction', 'Item Code'}.contains(applyOn) ||
        !minQty.isFinite || minQty < 0 ||
        (applyOn == 'Item Code' &&
            ((itemCode ?? '').trim().isEmpty || minQty <= 0)) ||
        (applyOn == 'Transaction' &&
            ((itemCode ?? '').trim().isNotEmpty || minQty > 0))) {
      throw const FormatException('بيانات قاعدة الخصم غير صحيحة.');
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
    final from = validateDate(validFrom.trim(), 'تاريخ بداية الخصم');
    final untilRaw = validUpto?.trim() ?? '';
    final until = untilRaw.isEmpty ? null : validateDate(untilRaw, 'تاريخ نهاية الخصم');
    if (until != null && from.compareTo(until) > 0) {
      throw const FormatException('تاريخ نهاية الخصم يجب ألا يسبق تاريخ بدايته.');
    }
    const applicableFields = {
      'Customer': 'customer',
      'Customer Group': 'customer_group',
      'Territory': 'territory',
    };
    final applicableField = applicableFields[applicableFor];
    final target = applicableValue?.trim() ?? '';
    if (applicableFor != null &&
        (applicableField == null || target.isEmpty)) {
      throw const FormatException('حدد قيمة صالحة لنطاق تطبيق الخصم.');
    }
    if (applicableFor == null && target.isNotEmpty) {
      throw const FormatException('حدد نوع نطاق الخصم قبل إدخال قيمته.');
    }

    final payload = <String, dynamic>{
      'doctype': 'Pricing Rule',
      'title': cleanTitle,
      'apply_on': applyOn,
      'price_or_product_discount': 'Price',
      'selling': 1,
      'buying': 0,
      'rate_or_discount': discountType,
      if (discountType == 'Discount Percentage')
        'discount_percentage': discountValue,
      if (discountType == 'Discount Amount') 'discount_amount': discountValue,
      'apply_discount_on': applyDiscountOn,
      'for_price_list': cleanList,
      'items': applyOn == 'Item Code'
          ? [{'item_code': itemCode!.trim(), 'min_qty': minQty}]
          : <Map<String, dynamic>>[],
      'currency': cleanCurrency,
      'valid_from': from,
      if (until != null) 'valid_upto': until,
      if (company != null && company.trim().isNotEmpty) 'company': company.trim(),
      if (applicableFor != null) 'applicable_for': applicableFor,
      if (applicableField != null) applicableField: target,
    };

    final id = ruleId?.trim() ?? '';
    late final _ApiResponse response;
    if (id.isEmpty) {
      response = await _sendJson('POST', '/api/resource/Pricing%20Rule', payload);
    } else {
      final uri = Uri.parse(
        '$_baseUrl/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id),
      );
      final currentResponse = await _sendUri('GET', uri);
      final currentData = _decode(currentResponse.body);
      final current = currentData['data'];
      if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300 ||
          current is! Map<String, dynamic> || current['name'] != id ||
          !{'Transaction', 'Item Code'}.contains(current['apply_on']) ||
          current['selling'] != 1 || current['buying'] == 1) {
        throw const FormatException('قاعدة الخصم تغيرت أو لا تنتمي إلى قواعد خصومات البيع المدعومة.');
      }
      response = await _sendJson(
        'PUT',
        '/api/resource/Pricing%20Rule/' + Uri.encodeComponent(id),
        Map<String, dynamic>.from(payload)..remove('doctype'),
      );
    }
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حفظ قاعدة خصم البيع.'));
    }
    final saved = data['data'];
    if (saved is! Map<String, dynamic> ||
        saved['doctype'] != 'Pricing Rule' ||
        saved['apply_on'] != applyOn ||
        saved['selling'] != 1 ||
        saved['title'] != cleanTitle) {
      throw Exception('لم يؤكد ERPNext حفظ قاعدة الخصم؛ أعد تحميل القائمة.');
    }
    return Map<String, dynamic>.from(saved);
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
        current is! Map<String, dynamic> || current['name'] != id ||
        !{'Transaction', 'Item Code'}.contains(current['apply_on']) ||
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
    if (updated is! Map<String, dynamic> ||
        updated['name'] != id ||
        updated['disable'] != 1) {
      throw Exception('لم يؤكد ERPNext إيقاف قاعدة الخصم.');
    }
  }

  Future<_ApiResponse> _updateExistingItemPrice(
    String id,
    String itemCode,
    String priceList,
    Map<String, dynamic> payload,
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
    if (current is! Map<String, dynamic> ||
        current['name'] != id ||
        current['item_code'] != itemCode ||
        current['price_list'] != priceList ||
        current['selling'] != 1) {
      throw const FormatException('سجل السعر تغير أو لا يطابق الصنف وقائمة الأسعار المحددين.');
    }
    return _sendJson(
      'PUT',
      '/api/resource/Item%20Price/' + Uri.encodeComponent(id),
      Map<String, dynamic>.from(payload)..remove('doctype'),
    );
  }

  Future<List<ErpSalesInvoice>> fetchSalesInvoices({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Sales%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer', 'customer_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status', 'is_return', 'return_against']),
      'limit_page_length': pageSize.toString(),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc, name desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة فواتير المبيعات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSalesInvoice.fromJson).toList(growable: false);
  }
  Future<List<Map<String, dynamic>>> fetchSalesPersons({
    int start = 0,
    String? search,
  }) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Sales Person',
      fields: const [
        'name', 'sales_person_name', 'parent_sales_person',
        'commission_rate', 'is_group', 'enabled', 'employee', 'department',
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
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> updateSalesPersonCommission({
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
        current is! Map<String, dynamic> || current['name'] != id ||
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
    final savedRate = updated is Map ? double.tryParse(updated['commission_rate']?.toString() ?? '') : null;
    if (updated is! Map<String, dynamic> || updated['name'] != id ||
        savedRate == null || (savedRate - commissionRate).abs() > 0.000001) {
      throw Exception('لم يؤكد ERPNext حفظ نسبة العمولة؛ أعد تحميل سجل المندوب.');
    }
    return Map<String, dynamic>.from(updated);
  }

  Future<List<ErpSupplier>> fetchSuppliers({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Supplier').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier_name', 'supplier_group', 'supplier_type']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'supplier_name asc, name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب الموردين. تحقق من صلاحية قراءة Supplier.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة الموردين من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSupplier.fromJson).toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseOrders({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Purchase Order',
      fields: const ['name', 'supplier', 'supplier_name', 'company', 'transaction_date', 'status', 'per_received'],
      filters: const [['docstatus', '=', 1]],
      orFilters: search == null || search.trim().isEmpty ? null : [
        ['name', 'like', '%${search.trim()}%'],
        ['supplier', 'like', '%${search.trim()}%'],
        ['supplier_name', 'like', '%${search.trim()}%'],
      ],
      orderBy: 'transaction_date desc, name desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أوامر الشراء المرحلة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة أوامر الشراء غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchPurchaseOrderDocument(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
    final response = await _send('GET',
        '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> ||
        document['doctype'] != 'Purchase Order' ||
        document['docstatus'] != 1) {
      throw const FormatException('أمر الشراء غير مرحّل أو أن بياناته غير مكتملة.');
    }
    return document;
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseOrderRecords({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Purchase Order',
      fields: const ['name', 'supplier', 'supplier_name', 'company', 'transaction_date', 'status', 'docstatus', 'per_received', 'per_billed', 'grand_total', 'currency'],
      orFilters: search == null || search.trim().isEmpty ? null : [
        ['name', 'like', '%${search.trim()}%'],
        ['supplier', 'like', '%${search.trim()}%'],
        ['supplier_name', 'like', '%${search.trim()}%'],
      ],
      orderBy: 'modified desc, name desc', start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل سجل أوامر الشراء.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة سجل أوامر الشراء غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> _fetchPurchaseOrderAnyStatus(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
    final response = await _send('GET', '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name.trim()));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> || document['doctype'] != 'Purchase Order' || document['name'] != name.trim()) {
      throw const FormatException('لم يؤكد ERPNext هوية أمر الشراء المطلوب.');
    }
    return document;
  }

  Future<Map<String, dynamic>> fetchPurchaseOrderRecordDocument(String name) => _fetchPurchaseOrderAnyStatus(name);

  Future<Map<String, dynamic>> createPurchaseOrder(Map<String, dynamic> document) async {
    _validatePurchaseOrder(document);
    await _validateDocumentWarehouses(document);
    final response = await _sendJson('POST', '/api/resource/Purchase%20Order', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء أمر الشراء.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> || created['doctype'] != 'Purchase Order' || created['name'] is! String || created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة أمر الشراء.');
    }
    return created;
  }

  void _validatePurchaseOrder(Map<String, dynamic> document) {
    final items = document['items'];
    if (document['doctype'] != 'Purchase Order' || document['company'] is! String || (document['company'] as String).trim().isEmpty ||
        document['supplier'] is! String || (document['supplier'] as String).trim().isEmpty || items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل لأمر الشراء.');
    }
    for (final row in items) {
      if (row is! Map<String, dynamic> || row['item_code'] is! String || (row['item_code'] as String).trim().isEmpty ||
          row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
        throw const FormatException('تحقق من صنف وكمية وسعر كل بند في أمر الشراء.');
      }
    }
  }

  Future<Map<String, dynamic>> updateDraftPurchaseOrder({required String name, required Map<String, dynamic> changes}) async {
    _validatePurchaseOrder(changes);
    await _validateDocumentWarehouses(changes);
    final current = await _fetchPurchaseOrderAnyStatus(name);
    if (current['docstatus'] != 0) throw const FormatException('يمكن تعديل أوامر الشراء غير المرحلة فقط.');
    final payload = Map<String, dynamic>.from(current)
      ..['company'] = changes['company']
      ..['supplier'] = changes['supplier']
      ..['transaction_date'] = changes['transaction_date'] ?? current['transaction_date']
      ..['schedule_date'] = changes['schedule_date'] ?? current['schedule_date']
      ..['items'] = changes['items'];
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة أمر الشراء.'));
    final saved = data['message'];
    if (saved is! Map<String, dynamic> || saved['doctype'] != 'Purchase Order' || saved['name'] != name || saved['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext حفظ مسودة أمر الشراء.');
    }
    return saved;
  }

  Future<Map<String, dynamic>> submitPurchaseOrder(Map<String, dynamic> document) => _submitMobileDocument(document, 'Purchase Order');

  Future<Map<String, dynamic>> cancelPurchaseOrder(String name) async {
    final key = 'cancel-purchase-order:$name';
    if (!_inFlightPurchaseActions.add(key)) throw const FormatException('إلغاء أمر الشراء قيد التنفيذ بالفعل.');
    try {
      final current = await _fetchPurchaseOrderAnyStatus(name);
      if (current['docstatus'] != 1) throw const FormatException('يمكن إلغاء أمر الشراء المرحّل فقط.');
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إلغاء أمر الشراء. قد توجد مستندات استلام أو فواتير مرتبطة.'));
      final cancelled = data['message'];
      if (cancelled is! Map<String, dynamic> || cancelled['doctype'] != 'Purchase Order' || cancelled['name'] != name || cancelled['docstatus'] != 2) {
        throw Exception('لم يؤكد ERPNext إلغاء أمر الشراء.');
      }
      return cancelled;
    } finally {
      _inFlightPurchaseActions.remove(key);
    }
  }

  Future<List<Map<String, dynamic>>> fetchSupplierLedger({
    required String supplier, int start = 0, String? company,
  }) async {
    if (supplier.trim().isEmpty) {
      throw const FormatException('حدد المورد لعرض كشف حسابه.');
    }
    final filters = <List<dynamic>>[
      ['party_type', '=', 'Supplier'],
      ['party', '=', supplier.trim()],
      ['is_cancelled', '=', 0],
    ];
    if (company != null && company.trim().isNotEmpty) {
      filters.add(['company', '=', company.trim()]);
    }
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'GL Entry',
      fields: const [
        'name', 'posting_date', 'account', 'against', 'debit', 'credit',
        'voucher_type', 'voucher_no', 'remarks', 'company', 'party',
      ],
      filters: filters,
      orderBy: 'posting_date desc, creation desc, name desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل كشف حساب المورد. تحقق من صلاحية قراءة GL Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة كشف حساب المورد غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchCustomerLedger({
    required String customer, int start = 0, String? company,
  }) async {
    if (customer.trim().isEmpty) {
      throw const FormatException('حدد العميل لعرض كشف حسابه.');
    }
    final filters = <List<dynamic>>[
      ['party_type', '=', 'Customer'],
      ['party', '=', customer.trim()],
      ['is_cancelled', '=', 0],
    ];
    if (company != null && company.trim().isNotEmpty) {
      filters.add(['company', '=', company.trim()]);
    }
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'GL Entry',
      fields: const [
        'name', 'posting_date', 'account', 'against', 'debit', 'credit',
        'voucher_type', 'voucher_no', 'remarks', 'company', 'party',
      ],
      filters: filters,
      orderBy: 'posting_date desc, creation desc, name desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل كشف حساب العميل. تحقق من صلاحية قراءة GL Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة كشف حساب العميل غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchReconciliationAccounts({
    required String company,
    required String partyType,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty ||
        !{'Customer', 'Supplier'}.contains(partyType)) {
      throw const FormatException('حدد الشركة ونوع الطرف الصحيحين.');
    }
    final accountType = partyType == 'Customer' ? 'Receivable' : 'Payable';
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Account',
      fields: const ['name', 'account_type', 'account_currency', 'company'],
      filters: [
        ['company', '=', normalizedCompany],
        ['account_type', '=', accountType],
        ['is_group', '=', 0],
        ['disabled', '=', 0],
      ],
      orderBy: 'name asc',
      pageLength: 500,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل حسابات الذمم للشركة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة حسابات الذمم غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany &&
            row['account_type'] == accountType)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _runPaymentReconciliationMethod({
    required Map<String, dynamic> document,
    required String method,
    Map<String, dynamic>? args,
  }) async {
    if (document['doctype'] != 'Payment Reconciliation') {
      throw const FormatException('مستند تسوية المدفوعات غير صحيح.');
    }
    final response = await _sendJson(
      'POST',
      '/api/method/run_doc_method',
      {
        'docs': jsonEncode(document),
        'method': method,
        if (args != null) 'args': args,
      },
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تنفيذ خطوة تسوية المدفوعات ($method).'));
    }
    final docs = data['docs'];
    if (docs is! List || docs.isEmpty || docs.first is! Map<String, dynamic>) {
      throw Exception('لم يُرجع ERPNext مستند تسوية محدثاً بعد تنفيذ $method.');
    }
    final updated = Map<String, dynamic>.from(docs.first as Map);
    if (updated['doctype'] != 'Payment Reconciliation' ||
        updated['company'] != document['company'] ||
        updated['party_type'] != document['party_type'] ||
        updated['party'] != document['party'] ||
        updated['receivable_payable_account'] != document['receivable_payable_account']) {
      throw const FormatException('تغيرت هوية مستند التسوية في استجابة ERPNext.');
    }
    return updated;
  }

  Future<Map<String, dynamic>> fetchUnreconciledPaymentEntries({
    required String company,
    required String partyType,
    required String party,
    required String receivablePayableAccount,
    String? fromInvoiceDate,
    String? toInvoiceDate,
    String? fromPaymentDate,
    String? toPaymentDate,
    int invoiceLimit = 50,
    int paymentLimit = 50,
  }) async {
    final cleanCompany = company.trim();
    final cleanParty = party.trim();
    final cleanAccount = receivablePayableAccount.trim();
    if (cleanCompany.isEmpty || cleanParty.isEmpty || cleanAccount.isEmpty ||
        !{'Customer', 'Supplier'}.contains(partyType) ||
        invoiceLimit < 0 || invoiceLimit > 500 ||
        paymentLimit < 0 || paymentLimit > 500) {
      throw const FormatException('أكمل الشركة والطرف وحساب الذمم، وحدد حدود تحميل بين 0 و500.');
    }
    String? validateDate(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح.');
      }
      return value;
    }
    final invoiceFrom = validateDate(fromInvoiceDate, 'بداية تاريخ الفواتير');
    final invoiceTo = validateDate(toInvoiceDate, 'نهاية تاريخ الفواتير');
    final paymentFrom = validateDate(fromPaymentDate, 'بداية تاريخ المدفوعات');
    final paymentTo = validateDate(toPaymentDate, 'نهاية تاريخ المدفوعات');
    if ((invoiceFrom != null && invoiceTo != null && invoiceFrom.compareTo(invoiceTo) > 0) ||
        (paymentFrom != null && paymentTo != null && paymentFrom.compareTo(paymentTo) > 0)) {
      throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
    }
    final document = <String, dynamic>{
      'doctype': 'Payment Reconciliation',
      'company': cleanCompany,
      'party_type': partyType,
      'party': cleanParty,
      'receivable_payable_account': cleanAccount,
      'invoice_limit': invoiceLimit,
      'payment_limit': paymentLimit,
      if (invoiceFrom != null) 'from_invoice_date': invoiceFrom,
      if (invoiceTo != null) 'to_invoice_date': invoiceTo,
      if (paymentFrom != null) 'from_payment_date': paymentFrom,
      if (paymentTo != null) 'to_payment_date': paymentTo,
      'invoices': <Map<String, dynamic>>[],
      'payments': <Map<String, dynamic>>[],
      'allocation': <Map<String, dynamic>>[],
    };
    final result = await _runPaymentReconciliationMethod(
      document: document,
      method: 'get_unreconciled_entries',
    );
    if (result['invoices'] is! List || result['payments'] is! List) {
      throw const FormatException('لم يُرجع ERPNext قوائم الفواتير والمدفوعات غير المسواة.');
    }
    return result;
  }

  Future<Map<String, dynamic>> allocatePaymentReconciliation(
    Map<String, dynamic> document,
  ) async {
    final invoices = document['invoices'];
    final payments = document['payments'];
    if (document['doctype'] != 'Payment Reconciliation' ||
        invoices is! List || invoices.isEmpty ||
        payments is! List || payments.isEmpty) {
      throw const FormatException('يجب تحميل فواتير ومدفوعات غير مسواة قبل إنشاء التوزيع.');
    }
    final result = await _runPaymentReconciliationMethod(
      document: document,
      method: 'allocate_entries',
      args: {
        'invoices': invoices,
        'payments': payments,
      },
    );
    final allocation = result['allocation'];
    if (allocation is! List || allocation.isEmpty) {
      throw const FormatException('لم ينتج ERPNext أي تخصيص قابل للتسوية.');
    }
    return result;
  }

  Future<Map<String, dynamic>> reconcilePaymentAllocations(
    Map<String, dynamic> document,
  ) async {
    final allocation = document['allocation'];
    if (document['doctype'] != 'Payment Reconciliation' ||
        allocation is! List || allocation.isEmpty) {
      throw const FormatException('لا توجد تخصيصات مؤكدة لترحيل التسوية.');
    }
    return _runPaymentReconciliationMethod(
      document: document,
      method: 'reconcile',
    );
  }

  Future<List<Map<String, dynamic>>> fetchSupplierPayments({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Payment Entry',
      fields: const [
        'name', 'posting_date', 'party', 'party_name', 'paid_amount',
        'paid_from', 'reference_no', 'reference_date', 'status', 'docstatus',
      ],
      filters: const [
        ['payment_type', '=', 'Pay'],
        ['party_type', '=', 'Supplier'],
        ['docstatus', '=', 1],
      ],
      orFilters: search == null || search.trim().isEmpty ? null : [
        ['name', 'like', '%${search.trim()}%'],
        ['party', 'like', '%${search.trim()}%'],
        ['party_name', 'like', '%${search.trim()}%'],
      ],
      orderBy: 'posting_date desc, name desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل سجل دفعات الموردين. تحقق من صلاحية قراءة Payment Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة سجل دفعات الموردين غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchDraftSupplierPayments({
    int start = 0,
    String? search,
  }) async {
    final query = search?.trim() ?? '';
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Payment Entry',
      fields: const [
        'name', 'posting_date', 'party', 'party_name', 'paid_amount', 'payment_type', 'party_type',
        'paid_from', 'reference_no', 'reference_date', 'status', 'docstatus',
      ],
      filters: const [
        ['payment_type', '=', 'Pay'],
        ['party_type', '=', 'Supplier'],
        ['docstatus', '=', 0],
      ],
      orFilters: query.isEmpty ? null : [
        ['name', 'like', '%$query%'],
        ['party', 'like', '%$query%'],
        ['party_name', 'like', '%$query%'],
      ],
      orderBy: 'modified desc, name desc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مسودات دفعات الموردين.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة مسودات دفعات الموردين غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>()
        .where((row) => row['docstatus'] == 0 &&
            row['payment_type'] == 'Pay' && row['party_type'] == 'Supplier')
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchSupplierPaymentDraftDocument(String name) =>
      _fetchPaymentEntryDraft(
        name,
        paymentType: 'Pay',
        partyType: 'Supplier',
      );

  Future<Map<String, dynamic>> submitSupplierPaymentDraft(
    Map<String, dynamic> draft,
  ) async {
    if (draft['doctype'] != 'Payment Entry' ||
        draft['payment_type'] != 'Pay' ||
        draft['party_type'] != 'Supplier') {
      throw const FormatException('المستند ليس مسودة سند صرف مورد صحيحة.');
    }
    return _submitMobileDocument(draft, 'Payment Entry');
  }

  Future<Map<String, dynamic>> fetchSupplierPaymentDocument(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم سند صرف المورد غير موجود.');
    final response = await _send(
      'GET',
      '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل سند صرف المورد.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['payment_type'] != 'Pay' ||
        document['party_type'] != 'Supplier' ||
        document['docstatus'] != 1 ||
        document['references'] is! List) {
      throw const FormatException('سند الصرف غير مرحّل أو لا يخص دفعات الموردين.');
    }
    return document;
  }

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier', 'supplier_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status', 'is_return', 'return_against']),
      'limit_page_length': pageSize.toString(),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc, name desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المشتريات. تحقق من صلاحية قراءة Purchase Invoice.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة فواتير المشتريات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpPurchaseInvoice.fromJson).toList(growable: false);
  }

  /// Loads bounded, submitted sales invoices for the mobile sales dashboard.
  /// Currency totals are aggregated by the caller; this method never converts
  /// or combines amounts from different currencies.
  Future<List<Map<String, dynamic>>> fetchSalesDashboardInvoices({
    required String company,
    required String fromDate,
    required String toDate,
  }) async {
    final normalizedCompany = company.trim();
    final startDate = DateTime.tryParse(fromDate);
    final endDate = DateTime.tryParse(toDate);
    if (normalizedCompany.isEmpty || startDate == null || endDate == null ||
        startDate.isAfter(endDate)) {
      throw const FormatException('حدد الشركة وفترة زمنية صحيحة للوحة المبيعات.');
    }
    const maxRows = 10000;
    final rows = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Sales Invoice',
        fields: const [
          'name', 'customer', 'customer_name', 'posting_date', 'currency',
          'grand_total', 'outstanding_amount', 'status',
        ],
        filters: [
          ['docstatus', '=', 1],
          ['is_return', '=', 0],
          ['company', '=', normalizedCompany],
          ['posting_date', 'between', [fromDate, toDate]],
        ],
        orderBy: 'posting_date desc, name desc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل بيانات لوحة المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
      }
      final page = data['data'];
      if (page is! List) {
        throw Exception('استجابة لوحة المبيعات من ERPNext غير متوقعة.');
      }
      for (final row in page) {
        if (row is! Map<String, dynamic> ||
            row['name'] is! String ||
            row['customer'] is! String ||
            row['currency'] is! String) {
          throw const FormatException('تحتوي بيانات لوحة المبيعات على فاتورة غير مكتملة.');
        }
        final total = double.tryParse(row['grand_total']?.toString() ?? '');
        final outstanding = double.tryParse(row['outstanding_amount']?.toString() ?? '');
        if (total == null || !total.isFinite ||
            outstanding == null || !outstanding.isFinite ||
            outstanding < -0.01 || outstanding > total.abs() + 0.01) {
          throw const FormatException('تحتوي بيانات لوحة المبيعات على مبالغ غير صالحة.');
        }
        rows.add(row);
      }
      if (rows.length > maxRows) {
        throw const FormatException('تجاوزت لوحة المبيعات 10000 فاتورة؛ قلّص الفترة الزمنية.');
      }
      if (page.length < pageSize) return rows;
      start += page.length;
    }
  }

  /// Loads all submitted, non-return invoices that still have an outstanding
  /// balance. Results are intentionally bounded to avoid unbounded memory use
  /// on very large sites; callers can narrow the report by company.
  Future<List<Map<String, dynamic>>> fetchOutstandingInvoices({
    required bool receivable,
    String? company,
  }) async {
    const maxRows = 10000;
    final doctype = receivable ? 'Sales Invoice' : 'Purchase Invoice';
    final partyField = receivable ? 'customer' : 'supplier';
    final partyNameField = receivable ? 'customer_name' : 'supplier_name';
    final filters = <List<dynamic>>[
      ['docstatus', '=', 1],
      ['outstanding_amount', '>', 0],
      ['is_return', '=', 0],
      if (company != null && company.trim().isNotEmpty)
        ['company', '=', company.trim()],
    ];
    final rows = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: doctype,
        fields: [
          'name', partyField, partyNameField, 'company', 'posting_date',
          'due_date', 'currency', 'grand_total', 'outstanding_amount',
        ],
        filters: filters,
        orderBy: 'due_date asc, posting_date asc, name asc',
        start: start,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(
          data,
          receivable
              ? 'تعذر تحميل الفواتير المستحقة للعملاء.'
              : 'تعذر تحميل الفواتير المستحقة للموردين.',
        ));
      }
      final page = data['data'];
      if (page is! List) {
        throw Exception('استجابة تقرير الفواتير المستحقة غير متوقعة.');
      }
      final validRows = page.whereType<Map<String, dynamic>>().toList();
      rows.addAll(validRows);
      if (rows.length > maxRows) {
        throw const FormatException(
          'تجاوز التقرير 10000 فاتورة مستحقة؛ حدد شركة لتقليل نطاق التقرير.',
        );
      }
      if (page.length < pageSize) return rows;
      start += page.length;
    }
  }

  /// Runs one of ERPNext's standard, permission-checked query reports.
  /// The server remains responsible for report execution and row-level access.
  Future<Map<String, dynamic>> runStandardReport({
    required String reportName,
    required Map<String, dynamic> filters,
  }) async {
    const allowedReports = {
      'Profit and Loss Statement',
      'Balance Sheet',
      'Cash Flow',
      'General Ledger',
      'Trial Balance',
      'Sales Register',
      'Sales Analytics',
      'Sales Person Commission Summary',
      'Sales Person-wise Transaction Summary',
      'Purchase Register',
      'Bank Reconciliation Statement',
      'Payment Ledger',
      'Stock Balance',
      'Stock Ledger',
    };
    if (!allowedReports.contains(reportName)) {
      throw FormatException('التقرير غير مدعوم في التطبيق: $reportName');
    }
    final company = filters['company']?.toString().trim() ?? '';
    if (company.isEmpty) {
      throw const FormatException('حدد الشركة قبل تشغيل التقرير المالي.');
    }
    final response = await _sendJson(
      'POST',
      '/api/method/frappe.desk.query_report.run',
      {
        'report_name': reportName,
        'filters': filters,
        'ignore_prepared_report': true,
      },
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تشغيل تقرير $reportName. تحقق من صلاحيات التقرير.'));
    }
    final message = data['message'];
    if (message is! Map) {
      throw Exception('استجابة تقرير $reportName من ERPNext غير متوقعة.');
    }
    final result = Map<String, dynamic>.from(message);
    if (result['columns'] is! List || result['result'] is! List) {
      throw Exception('لم يُرجع ERPNext أعمدة وبيانات صالحة لتقرير $reportName.');
    }
    return result;
  }

  static const Set<String> salesWorkflowDoctypes = {'Quotation', 'Sales Order', 'Delivery Note', 'Sales Invoice'};

  String _salesWorkflowResource(String doctype) {
    if (!salesWorkflowDoctypes.contains(doctype)) {
      throw FormatException('نوع مستند المبيعات غير مدعوم: $doctype');
    }
    return Uri.encodeComponent(doctype);
  }

  Future<List<Map<String, dynamic>>> fetchSalesWorkflowDocuments(
    String doctype, {int start = 0, String? search}
  ) async {
    _salesWorkflowResource(doctype);
    final uri = buildResourcePageUri(
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
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchSalesWorkflowDocument(String doctype, String name) async {
    final resource = _salesWorkflowResource(doctype);
    if (name.trim().isEmpty) throw const FormatException('رقم مستند المبيعات غير موجود.');
    final response = await _send('GET', '/api/resource/$resource/${Uri.encodeComponent(name.trim())}');
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل $doctype.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> || document['doctype'] != doctype || document['name'] != name.trim()) {
      throw FormatException('لم يؤكد ERPNext هوية مستند $doctype المطلوب.');
    }
    return document;
  }

  void _validateSalesWorkflowDraft(String doctype, Map<String, dynamic> doc) {
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
      if (raw is! Map<String, dynamic> || raw['item_code'] is! String || (raw['item_code'] as String).trim().isEmpty) {
        throw const FormatException('يوجد بند دون رمز صنف صحيح.');
      }
      final qty = raw['qty'], rate = raw['rate'];
      if (qty is! num || !qty.isFinite || qty <= 0 || rate is! num || !rate.isFinite || rate < 0 || !(qty * rate).isFinite) {
        throw const FormatException('تحقق من كمية وسعر كل بند.');
      }
    }
  }

  Future<Map<String, dynamic>> createSalesWorkflowDraft(String doctype, Map<String, dynamic> document) async {
    _validateSalesWorkflowDraft(doctype, document);
    await _validateDocumentWarehouses(document);
    final response = await _sendJson('POST', '/api/resource/${_salesWorkflowResource(doctype)}', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة $doctype.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> || created['doctype'] != doctype || created['name'] is! String || created['docstatus'] != 0) {
      throw Exception('استجابة حفظ $doctype غير مؤكدة؛ تحقق من المستند قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<Map<String, dynamic>> updateSalesWorkflowDraft(String doctype, String name, Map<String, dynamic> changes) async {
    _validateSalesWorkflowDraft(doctype, changes);
    await _validateDocumentWarehouses(changes);
    final current = await fetchSalesWorkflowDocument(doctype, name);
    if (current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل مستند مبيعات مرحّل أو ملغى.');
    final payload = Map<String, dynamic>.from(current)
      ..['customer'] = changes['customer'] ..['company'] = changes['company'] ..['items'] = changes['items'];
    for (final field in ['transaction_date', 'valid_till', 'delivery_date', 'order_type']) {
      if (changes.containsKey(field)) payload[field] = changes[field];
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة $doctype.'));
    final saved = data['message'];
    if (saved is! Map<String, dynamic> || saved['doctype'] != doctype || saved['name'] != name || saved['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext حفظ مسودة $doctype.');
    }
    return saved;
  }


  Future<Map<String, dynamic>> updateDeliveryNoteTracking({
    required String name,
    required List<Map<String, dynamic>> trackingRows,
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
      final byName = <String, Map<String, dynamic>>{
        for (final row in sourceItems.whereType<Map<String, dynamic>>())
          if (row['name'] is String) row['name'].toString(): Map<String, dynamic>.from(row),
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
        return Map<String, dynamic>.from(source)..remove('name');
      }).toList(growable: false);
      _validateSerialBatchRows(rowsToValidate);
      final payload = Map<String, dynamic>.from(current)
        ..['items'] = sourceItems.whereType<Map<String, dynamic>>().map((row) {
          final rowName = row['name']?.toString();
          return rowName != null && byName.containsKey(rowName)
              ? byName[rowName]!
              : Map<String, dynamic>.from(row);
        }).toList(growable: false);
      final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر حفظ أرقام الدفعات والأرقام التسلسلية لإذن التسليم.'));
      }
      final saved = data['message'];
      if (saved is! Map<String, dynamic> || saved['doctype'] != 'Delivery Note' ||
          saved['name'] != name || saved['docstatus'] != 0) {
        throw Exception('لم يؤكد ERPNext حفظ تخصيص أرقام إذن التسليم.');
      }
      return saved;
    } finally {
      _inFlightDocumentActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> submitSalesWorkflowDocument(String doctype, String name) async {
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
    if (submitted is! Map<String, dynamic> || submitted['doctype'] != doctype || submitted['name'] != name || submitted['docstatus'] != 1) {
      throw Exception('لم يؤكد ERPNext ترحيل $doctype؛ تحقق من حالة المستند قبل إعادة المحاولة.');
    }
    return submitted;
    } finally {
      _inFlightSalesActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> cancelSalesWorkflowDocument(String doctype, String name) async {
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
    if (cancelled is! Map<String, dynamic> || cancelled['doctype'] != doctype || cancelled['name'] != name || cancelled['docstatus'] != 2) {
      throw Exception('لم يؤكد ERPNext إلغاء $doctype.');
    }
    return cancelled;
    } finally {
      _inFlightSalesActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> makeSalesWorkflowDocument({
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
    if (raw is! Map<String, dynamic> || raw['doctype'] != targetDoctype ||
        raw['company'] is! String || (raw['company'] as String).trim().isEmpty ||
        raw['customer'] is! String || (raw['customer'] as String).trim().isEmpty ||
        raw['items'] is! List || (raw['items'] as List).isEmpty) {
      throw Exception('لم يُرجع ERPNext مستند $targetDoctype صالحاً من أداة التحويل.');
    }
    // Mapped rows inherit warehouses from their source document. Validate
    // those references against the live company/warehouse records before insert.
    await _validateDocumentWarehouses(raw);
    final inserted = await _sendJson('POST', '/api/resource/${_salesWorkflowResource(targetDoctype)}', Map<String, dynamic>.from(raw));
    final insertedData = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ مسودة $targetDoctype.'));
    final created = insertedData['data'];
    if (created is! Map<String, dynamic> || created['doctype'] != targetDoctype || created['name'] is! String || created['docstatus'] != 0) {
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
      if (entry is! Map) {
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

  Future<Map<String, dynamic>> createSalesInvoice(Map<String, dynamic> invoice) async {
    final customer = invoice['customer'];
    final company = invoice['company'];
    final rawItems = invoice['items'];
    if (invoice['doctype'] != 'Sales Invoice' || customer is! String || customer.trim().isEmpty || company is! String || company.trim().isEmpty || rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('حدد الشركة والعميل وأضف صنفاً واحداً على الأقل.');
    }
    invoice['items'] = _cleanSerialBatchRows(rawItems);
    _validateSalesTeamAllocation(invoice['sales_team']);
    for (final rawItem in rawItems) {
      if (rawItem is! Map<String, dynamic> || rawItem['item_code'] is! String || (rawItem['item_code'] as String).trim().isEmpty) {
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
    if (document is! Map<String, dynamic> ||
        document['doctype'] != 'Sales Invoice' ||
        document['name'] is! String ||
        document['name'].toString().isEmpty ||
        document['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المبيعات؛ تحقق من قائمة الفواتير قبل إعادة المحاولة.');
    }
    return document;
  }

  Future<Map<String, dynamic>> submitSalesInvoice(Map<String, dynamic> document) async {
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
    if (submitted is! Map<String, dynamic> ||
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
  Future<List<ErpPaymentAccount>> fetchPaymentAccounts(String company) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) {
      throw const FormatException('اسم الشركة غير موجود لتحميل حسابات التحصيل.');
    }

    const accountPageSize = pageSize;
    const maxAccountCount = 10000;
    final accounts = <ErpPaymentAccount>[];
    var start = 0;
    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Account',
        fields: const ['name', 'account_name', 'account_type', 'account_currency'],
        filters: [
          ['company', '=', normalizedCompany],
          ['disabled', '=', 0],
          ['is_group', '=', 0],
          ['account_type', 'in', ['Cash', 'Bank']],
        ],
        orderBy: 'account_type asc, account_name asc',
        start: start,
        pageLength: accountPageSize,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل حسابات الصندوق والبنك للشركة.'));
      }
      final rows = data['data'];
      if (rows is! List) {
        throw Exception('استجابة حسابات التحصيل من ERPNext غير متوقعة.');
      }
      accounts.addAll(
        rows
            .whereType<Map<String, dynamic>>()
            .map(ErpPaymentAccount.fromJson),
      );
      if (rows.length < accountPageSize) {
        return accounts;
      }
      if (accounts.length > maxAccountCount) {
        throw const FormatException(
          'تجاوز عدد حسابات التحصيل الحد الآمن للتحميل دفعة واحدة.',
        );
      }
      start += rows.length;
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentEntryDocument(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم سند القبض غير موجود.');
    final response = await _send(
      'GET',
      '/api/resource/Payment%20Entry/${Uri.encodeComponent(name.trim())}',
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر التحقق من حالة سند القبض.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim()) {
      throw const FormatException('بيانات سند القبض غير مؤكدة.');
    }
    return document;
  }

  Future<Map<String, dynamic>> receiveSalesInvoicePayment({
    required String invoiceName,
    required double amount,
    String? bankAccount,
  }) async {
    final actionKey = 'receipt:$invoiceName';
    if (!_inFlightSalesActions.add(actionKey)) {
      throw const FormatException('تسجيل دفعة هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
    }
    try {
    if (invoiceName.trim().isEmpty || !amount.isFinite || amount <= 0) {
      throw const FormatException('أدخل رقم الفاتورة ومبلغ دفعة صحيحاً أكبر من صفر.');
    }
    final invoice = await fetchInvoiceDocument('Sales Invoice', invoiceName);
    if (invoice['docstatus'] != 1) {
      throw const FormatException('لا يمكن تسجيل دفعة إلا على فاتورة مبيعات مرحّلة.');
    }
    final outstanding = double.tryParse(invoice['outstanding_amount']?.toString() ?? '') ?? 0;
    if (outstanding <= 0 || amount > outstanding + 0.000001) {
      throw FormatException('مبلغ الدفعة يتجاوز المبلغ المستحق المتبقي (${outstanding.toStringAsFixed(2)}).');
    }
    final setup = await _sendJson(
      'POST',
      '/api/method/erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry',
      {
        'dt': 'Sales Invoice',
        'dn': invoiceName,
        'party_amount': amount,
        if (bankAccount != null && bankAccount.trim().isNotEmpty) 'bank_account': bankAccount.trim(),
      },
    );
    final setupData = _decode(setup.body);
    if (setup.statusCode < 200 || setup.statusCode >= 300) {
      throw Exception(_message(setupData, 'تعذر تجهيز سند القبض. تحقق من الحسابات الافتراضية وصلاحيات Payment Entry.'));
    }
    final rawDocument = setupData['message'];
    if (rawDocument is! Map<String, dynamic> ||
        rawDocument['doctype'] != 'Payment Entry' ||
        rawDocument['payment_type'] != 'Receive' ||
        rawDocument['party_type'] != 'Customer' ||
        rawDocument['party'] != invoice['customer'] ||
        rawDocument['company'] != invoice['company']) {
      throw const FormatException('بيانات سند القبض التي جهزها ERPNext لا تطابق العميل والشركة والفاتورة المطلوبة.');
    }
    if (bankAccount != null && bankAccount.trim().isNotEmpty &&
        rawDocument['paid_to'] != bankAccount.trim()) {
      throw const FormatException('حساب الصندوق أو البنك الذي جهزه ERPNext لا يطابق الحساب الذي اخترته.');
    }
    final references = rawDocument['references'];
    if (references is! List || references.isEmpty) {
      throw Exception('لم يربط ERPNext سند القبض بفاتورة المبيعات.');
    }
    // ERPNext may split one invoice across several payment-term references.
    // Keep its allocations intact and verify their combined amount instead of
    // overwriting every row with the full payment amount.
    var allocatedTotal = 0.0;
    for (final row in references) {
      if (row is! Map<String, dynamic> ||
          row['reference_doctype'] != 'Sales Invoice' ||
          row['reference_name'] != invoiceName) {
        continue;
      }
      final allocated = row['allocated_amount'];
      if (allocated is num) {
        allocatedTotal += allocated.toDouble();
      } else {
        allocatedTotal += double.tryParse(allocated?.toString() ?? '') ?? 0;
      }
    }
    if ((allocatedTotal - amount).abs() > 0.01) {
      throw FormatException(
        'وزّع ERPNext مبلغ الدفعة على شروط السداد بقيمة ${allocatedTotal.toStringAsFixed(2)} بدلاً من ${amount.toStringAsFixed(2)}؛ لم يتم إنشاء سند القبض.',
      );
    }
    final paymentDraft = Map<String, dynamic>.from(rawDocument);

    final insert = await _sendJson('POST', '/api/resource/Payment%20Entry', paymentDraft);
    final insertData = _decode(insert.body);
    if (insert.statusCode < 200 || insert.statusCode >= 300) {
      throw Exception(_message(insertData, 'تعذر حفظ سند القبض.'));
    }
    final created = insertData['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Payment Entry' ||
        created['name'] is! String ||
        created['docstatus'] != 0 ||
        created['payment_type'] != 'Receive' ||
        created['party_type'] != 'Customer' ||
        created['party'] != invoice['customer']) {
      throw Exception('استجابة حفظ سند القبض غير متوقعة؛ تحقق من سجل Payment Entry قبل إعادة المحاولة.');
    }
    try {
      return await _submitMobileDocument(created, 'Payment Entry');
    } catch (error) {
      // A timeout or lost response must not cause a second receipt to be created.
      // Re-read the same Payment Entry before reporting an uncertain outcome.
      try {
        final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
        if (confirmed['docstatus'] == 1 &&
            confirmed['payment_type'] == 'Receive' &&
            confirmed['party_type'] == 'Customer' &&
            confirmed['party'] == invoice['customer']) {
          return confirmed;
        }
      } catch (_) {
        // Keep the original uncertainty message below; never retry creation here.
      }
      throw Exception('تم إنشاء سند القبض ${created['name']}، لكن لم يتم تأكيد ترحيله. راجع حالة هذا السند في ERPNext قبل محاولة تسجيل دفعة أخرى. التفاصيل: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    } finally {
      _inFlightSalesActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> updateDraftSalesInvoice({
    required String invoiceName,
    required Map<String, dynamic> changes,
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
      if (rawItem is! Map<String, dynamic> ||
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
    final payload = Map<String, dynamic>.from(current);
    payload['customer'] = customer;
    payload['company'] = company;
    payload['posting_date'] = changes['posting_date'] ?? current['posting_date'];
    payload['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0;
    payload['items'] = changes['items'];
    payload['sales_team'] = changes['sales_team'] ?? const <Map<String, dynamic>>[];

    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حفظ تعديلات مسودة فاتورة المبيعات.'));
    }
    final saved = data['message'];
    if (saved is! Map<String, dynamic> || saved['name'] != normalizedName || saved['docstatus'] != 0) {
      throw Exception('استجابة تحديث المسودة غير مؤكدة؛ افتح الفاتورة وتحقق من حالتها قبل إعادة المحاولة.');
    }
    return saved;
  }

  Future<Map<String, dynamic>> createSalesReturn(String invoiceName) async {
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
      final pendingName = pendingRows.first is Map<String, dynamic>
          ? (pendingRows.first as Map<String, dynamic>)['name']?.toString()
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
    if (rawReturn is! Map<String, dynamic>) {
      throw Exception('استجابة تجهيز المرتجع غير متوقعة.');
    }
    final returnDraft = Map<String, dynamic>.from(rawReturn);
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
    if (created is! Map<String, dynamic> ||
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

  Future<Map<String, dynamic>> cancelSalesInvoice(Map<String, dynamic> document) async {
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
    if (cancelled is! Map<String, dynamic> ||
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


  Future<Map<String, dynamic>> createPurchaseInvoice(Map<String, dynamic> invoice) async {
    if (invoice['update_stock'] == 1 || invoice['update_stock'] == true) {
      final items = invoice['items'];
      if (items is List) await _ensureIncomingBatchNumbers(items);
    }
    _validatePurchase(invoice);
    await _validateDocumentWarehouses(invoice);
    final response = await _sendJson('POST', '/api/resource/Purchase%20Invoice', invoice);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ فاتورة المشتريات.'));
    final doc = data['data'];
    if (doc is! Map<String, dynamic> ||
        doc['doctype'] != 'Purchase Invoice' ||
        doc['name'] is! String ||
        doc['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المشتريات.');
    }
    return doc;
  }

  void _validatePurchase(Map<String, dynamic> doc) {
    final items = doc['items'];
    if (doc['doctype'] != 'Purchase Invoice' || doc['supplier'] is! String ||
        (doc['supplier'] as String).trim().isEmpty || doc['company'] is! String ||
        (doc['company'] as String).trim().isEmpty || items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل.');
    }
    doc['items'] = _cleanSerialBatchRows(items);
    for (final row in items) {
      if (row is! Map<String, dynamic> || row['item_code'] is! String ||
          (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
          !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
        throw const FormatException('تحقق من رمز الصنف والكمية والسعر، وتأكد أن إجمالي البند ضمن النطاق الرقمي.');
      }
    }
  }

  Future<Map<String, dynamic>> updateDraftPurchaseInvoice({
    required String invoiceName, required Map<String, dynamic> changes,
  }) async {
    if (changes['update_stock'] == 1 || changes['update_stock'] == true) {
      final items = changes['items'];
      if (items is List) await _ensureIncomingBatchNumbers(items);
    }
    _validatePurchase(changes);
    await _validateDocumentWarehouses(changes);
    if (invoiceName.trim().isEmpty) throw const FormatException('رقم المسودة غير موجود.');
    final current = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
    if (current['docstatus'] != 0) throw const FormatException('يمكن تعديل المسودات غير المرحلة فقط.');
    final payload = Map<String, dynamic>.from(current)
      ..['supplier'] = changes['supplier']
      ..['company'] = changes['company']
      ..['posting_date'] = changes['posting_date'] ?? current['posting_date']
      ..['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0
      ..['items'] = changes['items'];
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة المشتريات.'));
    final saved = data['message'];
    if (saved is! Map<String, dynamic> || saved['name'] != invoiceName || saved['docstatus'] != 0) throw Exception('لم يتم تأكيد حفظ المسودة.');
    return saved;
  }

  Future<Map<String, dynamic>> submitPurchaseInvoice(Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Invoice');

  Future<Map<String, double>> fetchPurchaseReturnableQuantities(String invoiceName) async {
    if (invoiceName.trim().isEmpty) throw const FormatException('رقم فاتورة المشتريات غير موجود.');
    final source = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
    if (source['docstatus'] != 1 || source['is_return'] == 1 || source['is_return'] == true) {
      throw const FormatException('حساب الكميات المتبقية يتطلب فاتورة مشتريات أصلية مرحلة.');
    }
    final mapped = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.purchase_invoice.mapper.make_debit_note',
      {'source_name': invoiceName});
    final data = _decode(mapped.body);
    if (mapped.statusCode < 200 || mapped.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حساب الكميات المتبقية للمرتجع.'));
    }
    final raw = data['message'];
    if (raw is! Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) ||
        raw['return_against'] != invoiceName || raw['items'] is! List) {
      throw Exception('لم يؤكد ERPNext بيانات الكميات القابلة للإرجاع.');
    }
    final result = <String, double>{};
    for (final row in (raw['items'] as List).whereType<Map<String, dynamic>>()) {
      final sourceItem = row['purchase_invoice_item']?.toString();
      final qty = double.tryParse(row['qty']?.toString() ?? '');
      if (sourceItem == null || sourceItem.isEmpty || qty == null || !qty.isFinite || qty == 0) continue;
      if (result.containsKey(sourceItem)) {
        throw const FormatException('تكررت إحالة بند الفاتورة الأصلية في بيانات المرتجع.');
      }
      result[sourceItem] = qty.abs();
    }
    return result;
  }

  Future<Map<String, dynamic>> createPurchaseReturn(String invoiceName, {Map<String, double?>? quantitiesBySourceItem}) async {
    final actionKey = 'purchase-return:$invoiceName';
    if (!_inFlightPurchaseActions.add(actionKey)) {
      throw const FormatException('إنشاء مرتجع المشتريات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
    }
    try {
    final source = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
    if (source['docstatus'] != 1 || source['is_return'] == 1 || source['is_return'] == true) {
      throw const FormatException('المرتجع يتطلب فاتورة مشتريات أصلية مرحلة.');
    }
    final pendingUri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name']),
      'filters': jsonEncode([['return_against', '=', invoiceName], ['is_return', '=', 1], ['docstatus', '=', 0]]),
      'limit_page_length': '1',
    });
    final pending = await _sendUri('GET', pendingUri);
    final pendingData = _decode(pending.body);
    if (pending.statusCode < 200 || pending.statusCode >= 300) throw Exception(_message(pendingData, 'تعذر فحص المرتجعات السابقة.'));
    if (pendingData['data'] is List && (pendingData['data'] as List).isNotEmpty) {
      throw const FormatException('توجد مسودة مرتجع سابقة لهذه الفاتورة؛ راجعها قبل إنشاء أخرى.');
    }
    final mapped = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.purchase_invoice.mapper.make_debit_note',
      {'source_name': invoiceName});
    final mappedData = _decode(mapped.body);
    if (mapped.statusCode < 200 || mapped.statusCode >= 300) throw Exception(_message(mappedData, 'تعذر تجهيز مرتجع المشتريات.'));
    final raw = mappedData['message'];
    if (raw is! Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) || raw['return_against'] != invoiceName ||
        raw['items'] is! List || (raw['items'] as List).isEmpty) {
      throw Exception('لم يؤكد ERPNext بيانات مرتجع المشتريات.');
    }
    final mappedItems = (raw['items'] as List).whereType<Map<String, dynamic>>().toList();
    if (quantitiesBySourceItem != null) {
      final selectedItems = <Map<String, dynamic>>[];
      final matchedSourceRows = <String>{};
      for (var index = 0; index < mappedItems.length; index++) {
        final sourceItemName = mappedItems[index]['purchase_invoice_item']?.toString();
        final requested = sourceItemName == null ? null : quantitiesBySourceItem[sourceItemName];
        if (sourceItemName != null && requested != null && requested > 0) {
          if (!matchedSourceRows.add(sourceItemName)) {
            throw const FormatException('أعاد ERPNext أكثر من بند لنفس سطر الفاتورة الأصلية؛ أوقفنا إنشاء المرتجع لتجنب تكرار الكمية.');
          }
        }
        if (requested == null || requested == 0) continue;
        if (!requested.isFinite || requested < 0) {
          throw const FormatException('أدخل كمية مرتجع صحيحة موجبة أو اترك البند دون إرجاع.');
        }
        final mappedQty = double.tryParse(mappedItems[index]['qty']?.toString() ?? '') ?? 0;
        if (mappedQty == 0 || requested > mappedQty.abs() + 0.000001) {
          throw FormatException('كمية المرتجع للصنف ${mappedItems[index]['item_code'] ?? index + 1} تتجاوز الكمية المتبقية المسموح بها في ERPNext.');
        }
        final line = Map<String, dynamic>.from(mappedItems[index]);
        line['qty'] = mappedQty.isNegative ? -requested : requested;
        selectedItems.add(line);
      }
      final unmatchedSelections = quantitiesBySourceItem.entries
          .where((entry) => entry.value != null && entry.value! > 0 &&
              !matchedSourceRows.contains(entry.key))
          .map((entry) => entry.key).toList();
      if (unmatchedSelections.isNotEmpty) {
        throw FormatException('لم يعد الصنف المرتبط بالسطر ${unmatchedSelections.first} متاحاً للإرجاع وفق بيانات ERPNext الحالية. حدّث الفاتورة وحاول مجدداً.');
      }
      if (selectedItems.isEmpty) {
        throw const FormatException('حدد كمية مرتجع واحدة على الأقل.');
      }
      raw['items'] = selectedItems;
    }
    final inserted = await _sendJson('POST', '/api/resource/Purchase%20Invoice', Map<String, dynamic>.from(raw));
    final data = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة المرتجع.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Purchase Invoice' ||
        created['name'] is! String ||
        created['docstatus'] != 0 ||
        (created['is_return'] != 1 && created['is_return'] != true) ||
        created['return_against'] != invoiceName) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة مرتجع مشتريات مرتبطة بالفاتورة الأصلية؛ تحقق من السجل قبل إعادة المحاولة.');
    }
    return created;
    } finally {
      _inFlightPurchaseActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> payPurchaseInvoice({
    required String invoiceName, required double amount, String? bankAccount,
  }) async {
    final actionKey = 'purchase-payment:$invoiceName';
    if (!_inFlightPaymentActions.add(actionKey)) {
      throw const FormatException('سداد هذه الفاتورة قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
    }
    try {
    if (invoiceName.trim().isEmpty || !amount.isFinite || amount <= 0) throw const FormatException('أدخل فاتورة ومبلغ دفعة صحيحاً.');
    final invoice = await fetchInvoiceDocument('Purchase Invoice', invoiceName);
    if (invoice['docstatus'] != 1 || invoice['is_return'] == 1 || invoice['is_return'] == true) {
      throw const FormatException('سداد المورد يتطلب فاتورة مشتريات أصلية مرحلة.');
    }
    final outstanding = double.tryParse(invoice['outstanding_amount']?.toString() ?? '') ?? 0;
    if (outstanding <= 0 || amount > outstanding + 0.000001) throw const FormatException('مبلغ الدفعة يتجاوز المستحق المتبقي.');
    final setup = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.payment_entry.payment_entry.get_payment_entry',
      {'dt': 'Purchase Invoice', 'dn': invoiceName, 'party_amount': amount,
       if (bankAccount != null && bankAccount.trim().isNotEmpty) 'bank_account': bankAccount.trim()});
    final setupData = _decode(setup.body);
    if (setup.statusCode < 200 || setup.statusCode >= 300) throw Exception(_message(setupData, 'تعذر تجهيز سند صرف المورد.'));
    final raw = setupData['message'];
    if (raw is! Map<String, dynamic> || raw['payment_type'] != 'Pay' ||
        raw['party_type'] != 'Supplier' || raw['party'] != invoice['supplier']) {
      throw Exception('بيانات سند الصرف لا تطابق المورد المطلوب.');
    }
    if (bankAccount != null && bankAccount.trim().isNotEmpty &&
        raw['paid_from'] != bankAccount.trim()) {
      throw Exception('حساب الصندوق أو البنك الذي جهزه ERPNext لا يطابق الحساب الذي اخترته.');
    }
    final refs = raw['references'];
    if (refs is! List || refs.isEmpty) throw Exception('لم يربط ERPNext سند الصرف بالفاتورة.');
    var allocated = 0.0;
    for (final row in refs) {
      if (row is Map<String, dynamic> && row['reference_doctype'] == 'Purchase Invoice' &&
          row['reference_name'] == invoiceName) {
        allocated += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
      }
    }
    if ((allocated - amount).abs() > 0.01) throw const FormatException('توزيع الدفعة من ERPNext لا يطابق المبلغ المطلوب.');
    final inserted = await _sendJson('POST', '/api/resource/Payment%20Entry', Map<String, dynamic>.from(raw));
    final insertedData = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ سند الصرف.'));
    final created = insertedData['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Payment Entry' ||
        created['name'] is! String ||
        created['docstatus'] != 0 ||
        created['payment_type'] != 'Pay' ||
        created['party_type'] != 'Supplier' ||
        created['party'] != invoice['supplier'] ||
        created['company'] != invoice['company'] ||
        (bankAccount != null && bankAccount.trim().isNotEmpty &&
            created['paid_from'] != bankAccount.trim()) ||
        created['references'] is! List) {
      throw Exception('استجابة حفظ سند الصرف لا تطابق المورد أو الشركة أو الحساب أو حالة المسودة؛ تحقق من سجل Payment Entry قبل إعادة المحاولة.');
    }
    var createdAllocation = 0.0;
    for (final row in created['references'] as List) {
      if (row is Map<String, dynamic> &&
          row['reference_doctype'] == 'Purchase Invoice' &&
          row['reference_name'] == invoiceName) {
        createdAllocation += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
      }
    }
    if ((createdAllocation - amount).abs() > 0.01) {
      throw const FormatException('سند الصرف المحفوظ لا يحتوي على توزيع مطابق للفاتورة والمبلغ المطلوب؛ لا تحاول إنشاء دفعة ثانية قبل مراجعة السند.');
    }
    try {
      return await _submitMobileDocument(created, 'Payment Entry');
    } catch (error) {
      // Confirm the same voucher after a lost response; never create a second payment here.
      try {
        final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
        if (confirmed['docstatus'] == 1 &&
            confirmed['payment_type'] == 'Pay' &&
            confirmed['party_type'] == 'Supplier') {
          return confirmed;
        }
      } catch (_) {
        // Keep the original uncertainty message below.
      }
      throw Exception('تم حفظ سند الصرف ' + created['name'].toString() + ' لكن لم يؤكد ERPNext ترحيله. راجع حالة هذا السند قبل تسجيل دفعة أخرى. ' + error.toString().replaceFirst('Exception: ', ''));
    }
    } finally {
      _inFlightPaymentActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> _fetchPaymentEntryDraft(String name, {required String paymentType, required String partyType}) async {
    if (name.trim().isEmpty) throw const FormatException('رقم سند الدفع غير موجود.');
    final response = await _send('GET',
      '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name.trim()),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مسودة سند الدفع.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim() || document['docstatus'] != 0 ||
        document['payment_type'] != paymentType ||
        document['party_type'] != partyType ||
        document['references'] is! List) {
      throw const FormatException('سند الدفع لم يعد مسودة أو أن بياناته غير صحيحة.');
    }
    return document;
  }

  Future<Map<String, dynamic>> _submitMobileDocument(Map<String, dynamic> doc, String doctype) async {
    final name = doc['name']?.toString() ?? '';
    final actionKey = '$doctype:$name';
    if (!_inFlightDocumentActions.add(actionKey)) {
      throw const FormatException('ترحيل هذا المستند قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
    }
    try {
    if (doc['doctype'] != doctype || doc['name'] is! String || (doc['name'] as String).trim().isEmpty || doc['docstatus'] != 0) {
      throw FormatException('لا يمكن ترحيل المستند من النوع أو الحالة الحالية.');
    }
    // Never submit a stale object supplied by the screen. Re-read the canonical
    // server document immediately before submission and verify its identity/state.
    final name = (doc['name'] as String).trim();
    final current = switch (doctype) {
      'Payment Entry' => await _fetchPaymentEntryDraft(
        name,
        paymentType: doc['payment_type']?.toString() ?? '',
        partyType: doc['party_type']?.toString() ?? '',
      ),
      'Purchase Invoice' => await fetchInvoiceDocument('Purchase Invoice', name),
      'Purchase Order' => await _fetchPurchaseOrderAnyStatus(name),
      _ => await fetchStockDocument(doctype, name),
    };
    if (current['doctype'] != doctype || current['name'] != name || current['docstatus'] != 0) {
      throw const FormatException('تغيرت حالة المسودة على الخادم؛ حدّث قائمة المستندات قبل محاولة الترحيل.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر ترحيل المستند.'));
    final submitted = data['message'];
    if (submitted is! Map<String, dynamic> ||
        submitted['doctype'] != doctype ||
        submitted['name'] != doc['name'] ||
        submitted['docstatus'] != 1) {
      throw Exception('أرسل ERPNext استجابة غير مؤكدة للترحيل. أعد تحميل المستند قبل محاولة ترحيله مرة أخرى.');
    }
    return submitted;
    } finally {
      _inFlightDocumentActions.remove(actionKey);
    }
  }

  Future<Map<String, dynamic>> cancelPurchaseInvoice(String name) async {
    final actionKey = 'cancel-purchase:$name';
    if (!_inFlightPurchaseActions.add(actionKey)) {
      throw const FormatException('إلغاء فاتورة المشتريات قيد التنفيذ بالفعل؛ انتظر النتيجة قبل إعادة المحاولة.');
    }
    try {
    if (name.trim().isEmpty) throw const FormatException('رقم فاتورة المشتريات غير موجود.');
    final current = await fetchInvoiceDocument('Purchase Invoice', name);
    if (current['doctype'] != 'Purchase Invoice' || current['name'] != name || current['docstatus'] != 1) {
      throw const FormatException('إلغاء الفاتورة متاح للمستندات المرحلة فقط.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {
      'doctype': 'Purchase Invoice',
      'name': name,
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إلغاء فاتورة المشتريات. قد توجد دفعات أو مرتجعات أو مستندات مرتبطة.'));
    }
    final canceled = data['message'];
    if (canceled is! Map<String, dynamic> ||
        canceled['doctype'] != 'Purchase Invoice' ||
        canceled['name'] != name ||
        canceled['docstatus'] != 2) {
      throw Exception('لم يؤكد ERPNext إلغاء الفاتورة. أعد تحميلها للتحقق قبل أي إجراء آخر.');
    }
    return canceled;
    } finally {
      _inFlightPurchaseActions.remove(actionKey);
    }
  }

  Future<void> _validateWarehouseForCompany(String warehouseName, String company) async {
    final normalizedWarehouse = warehouseName.trim();
    final normalizedCompany = company.trim();
    if (normalizedWarehouse.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('حدد مستودعاً وشركة صالحين.');
    }
    final response = await _send('GET',
      '/api/resource/Warehouse/' + Uri.encodeComponent(normalizedWarehouse),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر التحقق من المستودع ' + normalizedWarehouse + '.'));
    }
    final warehouse = data['data'];
    if (warehouse is! Map<String, dynamic> ||
        warehouse['doctype'] != 'Warehouse' ||
        warehouse['name'] != normalizedWarehouse ||
        warehouse['company'] != normalizedCompany ||
        warehouse['is_group'] == 1 || warehouse['is_group'] == true ||
        warehouse['disabled'] == 1 || warehouse['disabled'] == true) {
      throw FormatException('المستودع ' + normalizedWarehouse + ' غير صالح أو لا يتبع الشركة ' + normalizedCompany + '. اختر مستودعاً فعّالاً تابعاً للشركة.');
    }
  }

  Future<void> _validateDocumentWarehouses(Map<String, dynamic> document) async {
    final company = document['company'];
    final items = document['items'];
    if (company is! String || company.trim().isEmpty || items is! List) return;
    final warehouses = <String>{};
    for (final row in items.whereType<Map<String, dynamic>>()) {
      final warehouse = row['warehouse'];
      if (warehouse is String && warehouse.trim().isNotEmpty) {
        warehouses.add(warehouse.trim());
      }
    }
    for (final warehouse in warehouses) {
      await _validateWarehouseForCompany(warehouse, company);
    }
  }

  Future<Map<String, dynamic>> createStockEntry({
    required String company, required String purpose, required List<Map<String, dynamic>> items,
    String? fromWarehouse, String? toWarehouse, String? remarks,
  }) async {
    const validPurposes = {'Material Receipt', 'Material Issue', 'Material Transfer'};
    if (company.trim().isEmpty || !validPurposes.contains(purpose) || items.isEmpty) {
      throw const FormatException('حدد الشركة ونوع الحركة وأضف صنفاً.');
    }
    if (purpose == 'Material Receipt' && (toWarehouse == null || toWarehouse.trim().isEmpty)) throw const FormatException('حدد مستودع الاستلام.');
    if (purpose == 'Material Issue' && (fromWarehouse == null || fromWarehouse.trim().isEmpty)) throw const FormatException('حدد مستودع الصرف.');
    if (purpose == 'Material Transfer' && ((fromWarehouse ?? '').isEmpty || (toWarehouse ?? '').isEmpty || fromWarehouse == toWarehouse)) {
      throw const FormatException('حدد مستودعَي تحويل مختلفين.');
    }
    _validateSerialBatchRows(items);
    if (purpose == 'Material Receipt') await _ensureIncomingBatchNumbers(items);
    for (final row in items) {
      if (row['item_code'] is! String || (row['item_code'] as String).trim().isEmpty ||
          row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0) {
        throw const FormatException('كل بند يحتاج صنفاً وكمية موجبة.');
      }
      if (purpose == 'Material Receipt' &&
          (row['valuation_rate'] is! num ||
              !(row['valuation_rate'] as num).isFinite ||
              (row['valuation_rate'] as num) <= 0)) {
        throw const FormatException('استلام المخزون يتطلب سعر تقييم أكبر من صفر لكل صنف.');
      }
      if (row.containsKey('valuation_rate') &&
          (row['valuation_rate'] is! num ||
              !(row['valuation_rate'] as num).isFinite ||
              (row['valuation_rate'] as num) < 0 ||
              !((row['qty'] as num) * (row['valuation_rate'] as num)).isFinite)) {
        throw const FormatException('سعر التقييم أو إجمالي قيمة البند غير صحيح.');
      }
    }
    for (final warehouse in {if (fromWarehouse != null) fromWarehouse, if (toWarehouse != null) toWarehouse}) {
      await _validateWarehouseForCompany(warehouse, company);
    }
    final cleanItems = _cleanSerialBatchRows(items);
    final payload = <String, dynamic>{
      'doctype': 'Stock Entry', 'company': company, 'purpose': purpose, 'stock_entry_type': purpose,
      if (fromWarehouse != null) 'from_warehouse': fromWarehouse,
      if (toWarehouse != null) 'to_warehouse': toWarehouse,
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
      'items': cleanItems.map((row) {
        final item = Map<String, dynamic>.from(row);
        final valuationRate = item.remove('valuation_rate');
        if (valuationRate != null && purpose == 'Material Receipt') {
          item['basic_rate'] = valuationRate;
        }
        if (purpose == 'Material Receipt' || purpose == 'Material Transfer') {
          item['t_warehouse'] = toWarehouse;
        }
        if (purpose == 'Material Issue' || purpose == 'Material Transfer') {
          item['s_warehouse'] = fromWarehouse;
        }
        return item;
      }).toList(),
    };
    final response = await _sendJson('POST', '/api/resource/Stock%20Entry', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء حركة المخزون.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Stock Entry' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة حركة المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<Map<String, dynamic>> createPurchaseReceipt(Map<String, dynamic> document) async {
    final items = document['items'];
    if (document['doctype'] != 'Purchase Receipt' ||
        document['company'] is! String || (document['company'] as String).trim().isEmpty ||
        document['supplier'] is! String || (document['supplier'] as String).trim().isEmpty ||
        items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً لاستلام البضائع.');
    }
    await _ensureIncomingBatchNumbers(items);
    document['items'] = _cleanSerialBatchRows(items);
    for (final row in items) {
      if (row is! Map<String, dynamic> || row['item_code'] is! String ||
          (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
          !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite ||
          row['warehouse'] is! String || (row['warehouse'] as String).trim().isEmpty) {
        throw const FormatException('بيانات استلام البضائع غير مكتملة: الصنف والكمية والسعر والمستودع مطلوبة.');
      }
    }
    // Revalidate purchase-order references against the latest server document
    // immediately before creating the receipt; UI-side quantities may be stale.
    final orderNames = <String>{};
    final sourceRowsByOrder = <String, Map<String, Map<String, dynamic>>>{};
    for (final row in items) {
      final orderName = row is Map<String, dynamic> ? row['purchase_order'] : null;
      final orderItemName = row is Map<String, dynamic> ? row['purchase_order_item'] : null;
      if ((orderName == null) != (orderItemName == null)) {
        throw const FormatException('مرجع أمر الشراء وبند الأمر يجب أن يظهرا معاً في بند الاستلام.');
      }
      if (orderName == null) continue;
      if (orderName is! String || orderName.trim().isEmpty ||
          orderItemName is! String || orderItemName.trim().isEmpty) {
        throw const FormatException('مرجع أمر الشراء أو بند الأمر غير صحيح.');
      }
      final normalizedOrder = orderName.trim();
      final normalizedOrderItem = orderItemName.trim();
      orderNames.add(normalizedOrder);
      final byItem = sourceRowsByOrder.putIfAbsent(normalizedOrder, () => <String, Map<String, dynamic>>{});
      if (byItem.containsKey(normalizedOrderItem)) {
        throw const FormatException('لا تكرر بند أمر الشراء في سند الاستلام؛ اجمع الكمية في سطر واحد.');
      }
      byItem[normalizedOrderItem] = row;
    }
    for (final orderName in orderNames) {
      final order = await fetchPurchaseOrderDocument(orderName);
      if (order['company'] != document['company'] || order['supplier'] != document['supplier']) {
        throw FormatException('أمر الشراء ' + orderName + ' لا يطابق شركة أو مورد سند الاستلام.');
      }
      final sourceItems = order['items'];
      if (sourceItems is! List) throw FormatException('تعذر قراءة بنود أمر الشراء ' + orderName + '.');
      final sourceByName = <String, Map<String, dynamic>>{
        for (final source in sourceItems.whereType<Map<String, dynamic>>())
          if (source['name'] is String) source['name'].toString(): source,
      };
      for (final entry in sourceRowsByOrder[orderName]!.entries) {
        final source = sourceByName[entry.key];
        final receiptLine = entry.value;
        if (source == null || source['item_code'] != receiptLine['item_code']) {
          throw FormatException('بند الاستلام ' + entry.key + ' لا يطابق بنداً في أمر الشراء ' + orderName + '.');
        }
        final ordered = double.tryParse(source['qty']?.toString() ?? '') ?? 0;
        final received = double.tryParse(source['received_qty']?.toString() ?? '') ?? 0;
        final remaining = ordered - received;
        final requested = (receiptLine['qty'] as num).toDouble();
        if (!remaining.isFinite || remaining <= 0.000001 || requested > remaining + 0.000001) {
          throw FormatException('كمية الصنف ' + receiptLine['item_code'].toString() + ' تجاوزت المتبقي في أمر الشراء ' + orderName + ' (' + remaining.toStringAsFixed(3) + '). حدّث الأمر قبل إنشاء سند الاستلام.');
        }
      }
    }
    final receiptWarehouses = items.map((row) => (row as Map<String, dynamic>)['warehouse'].toString()).toSet();
    for (final warehouse in receiptWarehouses) {
      await _validateWarehouseForCompany(warehouse, document['company'] as String);
    }
    final response = await _sendJson('POST', '/api/resource/Purchase%20Receipt', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء سند استلام المشتريات.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Purchase Receipt' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة سند استلام المشتريات؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<Map<String, dynamic>> submitPurchaseReceipt(Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Receipt');

  Future<Map<String, dynamic>> submitStockEntry(Map<String, dynamic> doc) => _submitMobileDocument(doc, 'Stock Entry');

  Future<Map<String, dynamic>> createStockReconciliation({
    required String company, required String warehouse, required List<Map<String, dynamic>> items, String? remarks,
  }) async {
    if (company.trim().isEmpty || warehouse.trim().isEmpty || items.isEmpty) throw const FormatException('حدد الشركة والمستودع وأصناف الجرد.');
    _validateSerialBatchRows(items);
    await _ensureIncomingBatchNumbers(items);
    final seen = <String>{};
    for (final row in items) {
      final code = row['item_code'];
      final qty = row['qty'];
      final batchNo = row['batch_no']?.toString().trim() ?? '';
      final usesTracking = row['use_serial_batch_fields'] == 1 ||
          row['use_serial_batch_fields'] == true || batchNo.isNotEmpty ||
          (row['serial_no']?.toString().trim().isNotEmpty ?? false);
      if (usesTracking && (row['current_qty'] is! num ||
          !(row['current_qty'] as num).isFinite || (row['current_qty'] as num) < 0)) {
        throw const FormatException('يجب تحميل الكمية الحالية للصنف المتتبع قبل تسوية الجرد.');
      }
      final uniqueKey = code is String ? code + '|' + batchNo : '';
      if (code is! String || code.trim().isEmpty || !seen.add(uniqueKey) || qty is! num || !qty.isFinite || qty < 0) {
        throw const FormatException('أصناف الجرد يجب أن تكون غير مكررة وكمياتها صفر أو أكثر.');
      }
      if (row.containsKey('valuation_rate') &&
          (row['valuation_rate'] is! num ||
              !(row['valuation_rate'] as num).isFinite ||
              (row['valuation_rate'] as num) < 0 ||
              !(qty * (row['valuation_rate'] as num)).isFinite)) {
        throw const FormatException('سعر تقييم بند الجرد أو إجمالي قيمته غير صحيح.');
      }
    }
    await _validateWarehouseForCompany(warehouse, company);
    final payload = <String, dynamic>{
      'doctype': 'Stock Reconciliation', 'company': company, 'purpose': 'Stock Reconciliation',
      'items': _cleanSerialBatchRows(items).map((row) => <String, dynamic>{...row, 'warehouse': warehouse}).toList(),
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Stock%20Reconciliation', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء تسوية المخزون.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> ||
        created['doctype'] != 'Stock Reconciliation' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة تسوية المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<Map<String, dynamic>> submitStockReconciliation(Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Stock Reconciliation');

  Future<void> deleteDraftDocument({required String doctype, required String name}) async {
    const allowed = {'Purchase Invoice', 'Purchase Order', 'Purchase Receipt', 'Stock Entry', 'Stock Reconciliation'};
    if (!allowed.contains(doctype) || name.trim().isEmpty) {
      throw const FormatException('نوع أو رقم المسودة غير صحيح.');
    }
    final path = '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name);
    final current = await _send('GET', path);
    final currentData = _decode(current.body);
    if (current.statusCode < 200 || current.statusCode >= 300) {
      throw Exception(_message(currentData, 'تعذر التحقق من المسودة قبل حذفها.'));
    }
    final document = currentData['data'];
    if (document is! Map<String, dynamic> ||
        document['doctype'] != doctype ||
        document['name'] != name ||
        document['docstatus'] != 0) {
      throw const FormatException('الحذف مسموح للمسودات غير المرحلة فقط. حدّث المستند قبل المتابعة.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.delete', {
      'doctype': doctype,
      'name': name,
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حذف المسودة.'));
    }
    final message = data['message'];
    if (message is! String || !message.toLowerCase().contains('deleted')) {
      throw Exception('لم يؤكد ERPNext حذف المسودة؛ أعد تحميل المستند للتحقق.');
    }
  }

  Future<List<Map<String, dynamic>>> fetchDraftStockDocuments(String doctype, {int start = 0}) async {
    const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation'};
    if (!allowed.contains(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع مستند المخزون غير مدعوم.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: doctype,
      fields: const ['name', 'docstatus', 'posting_date', 'company'],
      filters: const [['docstatus', '=', 0]],
      orderBy: 'modified desc, name desc', start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مسودات ' + doctype + '.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة مسودات ' + doctype + ' غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map((row) => <String, dynamic>{...row, 'doctype': doctype}).toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchStockDocument(String doctype, String name) async {
    const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation'};
    if (!allowed.contains(doctype) || name.trim().isEmpty) throw ArgumentError('نوع أو رقم مستند المخزون غير صحيح.');
    final response = await _send('GET', '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل مستند المخزون.'));
    final doc = data['data'];
    if (doc is! Map<String, dynamic>) throw Exception('تفاصيل مستند المخزون غير متوقعة.');
    return doc;
  }

  Future<List<Map<String, dynamic>>> fetchStockMovements({
    int start = 0,
    String? itemCode,
    String? warehouse,
    String? company,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    DateTime? dateOnly(DateTime? value) =>
        value == null ? null : DateTime(value.year, value.month, value.day);
    String dateString(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

    final from = dateOnly(fromDate);
    final to = dateOnly(toDate);
    if (from != null && to != null && from.isAfter(to)) {
      throw const FormatException('تاريخ بداية التقرير يجب ألا يتجاوز تاريخ نهايته.');
    }

    final filters = <List<dynamic>>[];
    if (itemCode != null && itemCode.trim().isNotEmpty) filters.add(['item_code', '=', itemCode.trim()]);
    if (warehouse != null && warehouse.trim().isNotEmpty) filters.add(['warehouse', '=', warehouse.trim()]);
    if (company != null && company.trim().isNotEmpty) filters.add(['company', '=', company.trim()]);
    if (from != null) filters.add(['posting_date', '>=', dateString(from)]);
    if (to != null) filters.add(['posting_date', '<=', dateString(to)]);
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Stock Ledger Entry',
      fields: const ['name', 'posting_date', 'posting_time', 'item_code', 'warehouse', 'actual_qty', 'qty_after_transaction', 'voucher_type', 'voucher_no', 'company'],
      filters: filters, orderBy: 'posting_date desc, posting_time desc, creation desc', start: start);
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل حركات المخزون.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة سجل الحركات غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchInvoiceDocument(String documentType, String name) async {
    if (documentType != 'Sales Invoice' && documentType != 'Purchase Invoice') {
      throw ArgumentError.value(documentType, 'documentType', 'نوع المستند غير مدعوم.');
    }
    final path = '/api/resource/${Uri.encodeComponent(documentType)}/${Uri.encodeComponent(name)}';
    final response = await _send('GET', path);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل الفاتورة. تحقق من صلاحية قراءة المستند.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic>) throw Exception('تفاصيل الفاتورة من ERPNext غير متوقعة.');
    return document;
  }
  Future<List<Map<String, dynamic>>> fetchAccountingAccounts({
    required String company,
    int start = 0,
    String? search,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض دليل الحسابات.');
    final query = search?.trim();
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Account',
      fields: const ['name', 'account_name', 'parent_account', 'account_type',
        'root_type', 'account_currency', 'company', 'is_group', 'disabled'],
      filters: [
        ['company', '=', normalizedCompany],
        ['disabled', '=', 0],
      ],
      orFilters: query == null || query.isEmpty ? null : [
        ['name', 'like', '%$query%'],
        ['account_name', 'like', '%$query%'],
        ['account_type', 'like', '%$query%'],
      ],
      orderBy: 'lft asc, name asc',
      start: start,
      pageLength: 200,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل دليل الحسابات للشركة المحددة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة دليل الحسابات غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany)
        .map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  // Allow-listed mobile master-data access; ERPNext remains authoritative.
  static const Map<String, List<String>> _masterDataFields = {
    'Item': ['name', 'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'],
    'Supplier': ['name', 'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'],
    'Warehouse': ['name', 'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'],
    'Item Group': ['name', 'item_group_name', 'parent_item_group', 'is_group', 'disabled'],
    'UOM': ['name', 'uom_name', 'must_be_whole_number', 'enabled'],
    'Supplier Group': ['name', 'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'],
    'Price List': ['name', 'price_list_name', 'currency', 'buying', 'selling', 'enabled'],
  };

  static const Map<String, Set<String>> _masterDataWritableFields = {
    'Item': {'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'},
    'Supplier': {'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'},
    'Warehouse': {'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'},
    'Item Group': {'item_group_name', 'parent_item_group', 'is_group', 'disabled'},
    'UOM': {'uom_name', 'must_be_whole_number', 'enabled'},
    'Supplier Group': {'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'},
    'Price List': {'price_list_name', 'currency', 'buying', 'selling', 'enabled'},
  };


  Future<List<Map<String, dynamic>>> fetchMasterDataOptions(String doctype) async {
    if (!_masterDataFields.containsKey(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    const maxRows = 2000;
    final result = <Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await fetchMasterDataRows(doctype: doctype, start: start);
      result.addAll(page);
      if (page.length < pageSize) return result;
      start += page.length;
      if (result.length >= maxRows) return result;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMasterDataRows({
    required String doctype,
    int start = 0,
    String? search,
  }) async {
    final fields = _masterDataFields[doctype];
    if (fields == null) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    final query = search?.trim();
    final searchable = switch (doctype) {
      'Item' => const ['name', 'item_name', 'item_group'],
      'Supplier' => const ['name', 'supplier_name', 'supplier_group'],
      'Warehouse' => const ['name', 'warehouse_name', 'company'],
      'Item Group' => const ['name', 'item_group_name', 'parent_item_group'],
      'UOM' => const ['name', 'uom_name'],
      'Supplier Group' => const ['name', 'supplier_group_name', 'parent_supplier_group'],
      'Price List' => const ['name', 'price_list_name', 'currency'],
      _ => const <String>[],
    };
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: doctype,
      fields: fields,
      filters: const [],
      orFilters: query == null || query.isEmpty
          ? null
          : searchable.map((field) => [field, 'like', '%$query%']).toList(),
      orderBy: 'modified desc, name asc',
      start: start,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل بيانات $doctype. تحقق من صلاحية القراءة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة بيانات $doctype غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>()
        .map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchMasterDataDocument({
    required String doctype,
    required String name,
  }) async {
    if (!_masterDataFields.containsKey(doctype)) {
      throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    }
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('حدد السجل أولاً.');
    final uri = Uri.parse('$_baseUrl/api/resource/${Uri.encodeComponent(doctype)}/${Uri.encodeComponent(id)}')
        .replace(queryParameters: {'fields': jsonEncode(_masterDataFields[doctype])});
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل السجل.'));
    }
    final document = data['data'];
    if (document is! Map<String, dynamic> || document['name'] != id) {
      throw Exception('لم تتطابق هوية السجل المسترجع مع المطلوب.');
    }
    return Map<String, dynamic>.from(document);
  }

  Future<Map<String, dynamic>> saveMasterDataDocument({
    required String doctype,
    String? name,
    required Map<String, dynamic> values,
  }) async {
    final allowed = _masterDataWritableFields[doctype];
    if (allowed == null) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    final payload = <String, dynamic>{};
    for (final entry in values.entries) {
      if (allowed.contains(entry.key)) {
        payload[entry.key] = entry.value is String
            ? (entry.value as String).trim()
            : entry.value;
      }
    }
    String requiredValue(String key) => payload[key]?.toString().trim() ?? '';
    switch (doctype) {
      case 'Item':
        if (requiredValue('item_code').isEmpty || requiredValue('item_name').isEmpty ||
            requiredValue('item_group').isEmpty || requiredValue('stock_uom').isEmpty) {
          throw const FormatException('رمز الصنف واسمه ومجموعته ووحدة القياس حقول مطلوبة.');
        }
        if (payload['has_serial_no'] == true && payload['has_batch_no'] == true) {
          throw const FormatException('لا يمكن تفعيل التتبع بالرقم التسلسلي والدفعة معاً.');
        }
        final rawUoms = payload['uoms'];
        if (rawUoms != null) {
          if (rawUoms is! List) throw const FormatException('جدول تحويل وحدات الصنف غير صالح.');
          final seenUoms = <String>{};
          for (final raw in rawUoms) {
            if (raw is! Map) throw const FormatException('يوجد صف غير صالح في تحويل وحدات الصنف.');
            final uom = raw['uom']?.toString().trim() ?? '';
            final factorValue = raw['conversion_factor'];
            final factor = factorValue is num ? factorValue.toDouble() : double.tryParse(factorValue?.toString() ?? '');
            if (uom.isEmpty || uom == requiredValue('stock_uom') || !seenUoms.add(uom) ||
                factor == null || !factor.isFinite || factor <= 0) {
              throw const FormatException('كل وحدة بديلة يجب أن تكون مختلفة عن وحدة المخزون، وغير مكررة، ومعامل تحويلها أكبر من صفر.');
            }
          }
          payload['uoms'] = rawUoms.map((raw) => {
            'doctype': 'UOM Conversion Detail',
            'uom': raw['uom'].toString().trim(),
            'conversion_factor': raw['conversion_factor'] is num
                ? raw['conversion_factor']
                : double.parse(raw['conversion_factor'].toString()),
          }).toList();
        }
        break;
      case 'Supplier':
        if (requiredValue('supplier_name').isEmpty ||
            !{'Company', 'Individual'}.contains(requiredValue('supplier_type')) ||
            requiredValue('supplier_group').isEmpty) {
          throw const FormatException('اسم المورد ونوعه ومجموعته حقول مطلوبة.');
        }
        break;
      case 'Warehouse':
        if (requiredValue('warehouse_name').isEmpty || requiredValue('company').isEmpty) {
          throw const FormatException('اسم المستودع والشركة حقول مطلوبة.');
        }
        break;
      case 'Item Group':
        if (requiredValue('item_group_name').isEmpty) throw const FormatException('اسم مجموعة الأصناف مطلوب.');
        break;
      case 'UOM':
        if (requiredValue('uom_name').isEmpty) throw const FormatException('اسم وحدة القياس مطلوب.');
        break;
      case 'Supplier Group':
        if (requiredValue('supplier_group_name').isEmpty) throw const FormatException('اسم مجموعة الموردين مطلوب.');
        break;
      case 'Price List':
        if (requiredValue('price_list_name').isEmpty || requiredValue('currency').isEmpty) {
          throw const FormatException('اسم قائمة الأسعار والعملة حقول مطلوبة.');
        }
        if (payload['selling'] != true && payload['buying'] != true) {
          throw const FormatException('حدد استخدام القائمة للمبيعات أو المشتريات على الأقل.');
        }
        break;
    }
    final id = name?.trim();
    if (id != null && id.isNotEmpty) {
      // Preserve autoname/identity fields across all supported master doctypes.
      const identityFields = {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'price_list_name'};
      payload.removeWhere((key, value) => identityFields.contains(key));
      final current = await fetchMasterDataDocument(doctype: doctype, name: id);
      if (current['name'] != id) throw const FormatException('تغير السجل؛ أعد تحميله قبل التعديل.');
    }
    final path = '/api/resource/${Uri.encodeComponent(doctype)}'
        '${id == null || id.isEmpty ? '' : '/${Uri.encodeComponent(id)}'}';
    final response = await _sendJson(id == null || id.isEmpty ? 'POST' : 'PUT', path, payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حفظ السجل. راجع الحقول المطلوبة وصلاحيات ERPNext.'));
    }
    final saved = data['data'];
    if (saved is! Map<String, dynamic> || (saved['name']?.toString().isNotEmpty != true)) {
      throw Exception('لم يؤكد ERPNext حفظ السجل؛ أعد تحميل القائمة قبل المتابعة.');
    }
    if (id != null && id.isNotEmpty && saved['name'] != id) {
      throw Exception('تغيرت هوية السجل بعد الحفظ؛ أوقف العملية وراجع ERPNext.');
    }
    return Map<String, dynamic>.from(saved);
  }

  Future<String> currentUser() async {
    final response = await _send('GET', '/api/method/frappe.auth.get_logged_user');
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'انتهت جلسة الدخول أو تعذر التحقق منها.'));
    }
    final message = data['message'];
    if (message is! String || message.isEmpty || message == 'Guest') {
      throw Exception('لم يتم التحقق من المستخدم المسجل.');
    }
    return message;
  }

  Future<void> logout() async {
    _sessionGeneration++;
    if (_cookies.isNotEmpty) {
      try {
        await _send('POST', '/api/method/logout');
      } catch (_) {}
    }
    _cookies.clear();
  }

  Future<_ApiResponse> _send(String method, String path) =>
      _sendUri(method, Uri.parse('$_baseUrl$path'));

  Future<_ApiResponse> _sendUri(String method, Uri uri) async {
    final generation = _sessionGeneration;
    final request = await _client.openUrl(method, uri);
    // Session cookies must never be forwarded automatically to a redirect target.
    // Frappe API endpoints should return their response directly; surface redirects
    // to the caller as non-success HTTP statuses instead.
    request.followRedirects = false;
    if (_cookies.isNotEmpty) {
      request.headers.set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '),
      );
      final csrfToken = _cookies['csrf_token'];
      if (csrfToken != null && csrfToken.isNotEmpty) {
        request.headers.set('X-Frappe-CSRF-Token', csrfToken);
      }
    }
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
    if (generation != _sessionGeneration) {
      return _ApiResponse(401, jsonEncode({'message': 'تم تجاهل استجابة من جلسة سابقة.'}));
    }
    _captureCookies(response);
    return _ApiResponse(response.statusCode, body);
  }

  Future<_ApiResponse> _sendJson(String method, String path, Map<String, dynamic> payload) async {
    final generation = _sessionGeneration;
    final request = await _client.openUrl(method, Uri.parse('$_baseUrl$path'));
    request.followRedirects = false;
    request.headers.contentType = ContentType.json;
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader, _cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; '));
      final csrfToken = _cookies['csrf_token'];
      if (csrfToken != null && csrfToken.isNotEmpty) request.headers.set('X-Frappe-CSRF-Token', csrfToken);
    }
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(const Duration(seconds: 45));
    final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 45));
    if (generation != _sessionGeneration) return _ApiResponse(401, jsonEncode({'message': 'تم تجاهل استجابة من جلسة سابقة.'}));
    _captureCookies(response);
    return _ApiResponse(response.statusCode, body);
  }
  void _captureCookies(HttpClientResponse response) {
    for (final header in response.headers[HttpHeaders.setCookieHeader] ?? []) {
      final parts = header.split(';');
      final pair = parts.first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;

      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      int? maxAge;
      DateTime? expires;
      for (final attribute in parts.skip(1)) {
        final attributePair = attribute.trim().split('=');
        final attributeName = attributePair.first.trim().toLowerCase();
        final attributeValue = attributePair.length > 1
            ? attributePair.sublist(1).join('=').trim()
            : '';
        if (attributeName == 'max-age') {
          maxAge = int.tryParse(attributeValue);
        } else if (attributeName == 'expires' && attributeValue.isNotEmpty) {
          try {
            expires = HttpDate.parse(attributeValue);
          } on FormatException {
            // Ignore malformed Expires attributes.
          }
        }
      }

      // RFC 6265 gives Max-Age precedence over Expires. Empty cookie values
      // are valid and must not be treated as deletion on their own.
      final shouldDelete = maxAge != null
          ? maxAge <= 0
          : expires != null && expires.isBefore(DateTime.now());
      if (shouldDelete) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  String _message(Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }


  Future<List<Map<String, dynamic>>> fetchJournalEntryDrafts({required String company, int start = 0, String? search}) async {
    final normalized = company.trim();
    if (normalized.isEmpty) throw const FormatException('حدد الشركة أولاً.');
    final query = search?.trim() ?? '';
    final uri = buildResourcePageUri(baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'posting_date', 'company', 'total_debit', 'total_credit', 'user_remark', 'docstatus'],
      filters: [['company', '=', normalized], ['docstatus', '=', 0]],
      orFilters: query.isEmpty ? null : [['name', 'like', '%$query%'], ['user_remark', 'like', '%$query%']],
      orderBy: 'modified desc, name desc', start: start, pageLength: 50);
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل مسودات القيود اليومية.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة القيود اليومية غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().where((row) => row['company'] == normalized && row['docstatus'] == 0)
      .map((row) => Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<Map<String, dynamic>> fetchJournalEntryDocument(String name) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
    final response = await _send('GET', '/api/resource/Journal%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل القيد اليومي.'));
    final doc = data['data'];
    if (doc is! Map<String, dynamic> || doc['name'] != id || doc['doctype'] != 'Journal Entry') throw const FormatException('هوية القيد المسترجع غير مطابقة.');
    return Map<String, dynamic>.from(doc);
  }

  Future<Map<String, dynamic>> saveJournalEntryDraft({String? name, required String company, required String postingDate, required String remark, required List<Map<String, dynamic>> accounts}) async {
    final normalizedCompany = company.trim();
    final date = DateTime.tryParse(postingDate.trim());
    if (normalizedCompany.isEmpty || date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) throw const FormatException('الشركة وتاريخ القيد بصيغة YYYY-MM-DD حقول مطلوبة.');
    if (accounts.length < 2) throw const FormatException('القيد يتطلب حسابين على الأقل.');
    final companyResponse = await _send('GET', '/api/resource/Company/' + Uri.encodeComponent(normalizedCompany));
    final companyData = _decode(companyResponse.body);
    final companyDoc = companyData['data'];
    if (companyResponse.statusCode < 200 || companyResponse.statusCode >= 300 || companyDoc is! Map<String, dynamic>) throw Exception(_message(companyData, 'تعذر التحقق من الشركة.'));
    final currency = companyDoc['default_currency']?.toString() ?? '';
    if (currency.isEmpty) throw const FormatException('عملة الشركة غير محددة في ERPNext.');
    final clean = <Map<String, dynamic>>[];
    var debitTotal = 0.0, creditTotal = 0.0;
    final seen = <String>{};
    for (final row in accounts) {
      final account = row['account']?.toString().trim() ?? '';
      final debit = row['debit'] is num ? (row['debit'] as num).toDouble() : double.tryParse(row['debit']?.toString() ?? '') ?? 0;
      final credit = row['credit'] is num ? (row['credit'] as num).toDouble() : double.tryParse(row['credit']?.toString() ?? '') ?? 0;
      if (account.isEmpty || !debit.isFinite || !credit.isFinite || debit < 0 || credit < 0 || (debit > 0 && credit > 0) || (debit == 0 && credit == 0)) throw const FormatException('كل سطر يجب أن يحتوي حساباً ومبلغاً مديناً أو دائناً واحداً فقط.');
      if (!seen.add(account)) throw FormatException('الحساب مكرر في القيد: ' + account);
      final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(account));
      final accountData = _decode(accountResponse.body);
      final accountDoc = accountData['data'];
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 || accountDoc is! Map<String, dynamic> || accountDoc['company'] != normalizedCompany || accountDoc['is_group'] == 1 || accountDoc['is_group'] == true || accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) throw FormatException('الحساب ' + account + ' غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
      if ((accountDoc['account_currency']?.toString().isNotEmpty ?? false) && accountDoc['account_currency'] != currency) throw FormatException('الحساب ' + account + ' بعملة مختلفة. هذه الشاشة تدعم حالياً حسابات عملة الشركة فقط (' + currency + ').');
      final costCenter = row['cost_center']?.toString().trim() ?? '';
      if (costCenter.isNotEmpty) {
        final costResponse = await _send('GET',
          '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
        final costData = _decode(costResponse.body);
        final costDoc = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            costDoc is! Map<String, dynamic> || costDoc['company'] != normalizedCompany ||
            costDoc['is_group'] == 1 || costDoc['is_group'] == true ||
            costDoc['disabled'] == 1 || costDoc['disabled'] == true) {
          throw FormatException('مركز التكلفة $costCenter غير صالح أو لا يتبع الشركة المحددة أو ليس مركز حركة.');
        }
      }
      final project = row['project']?.toString().trim() ?? '';
      if (project.isNotEmpty) {
        final projectResponse = await _send('GET',
          '/api/resource/Project/' + Uri.encodeComponent(project));
        final projectData = _decode(projectResponse.body);
        final projectDoc = projectData['data'];
        if (projectResponse.statusCode < 200 || projectResponse.statusCode >= 300 ||
            projectDoc is! Map<String, dynamic> || projectDoc['company'] != normalizedCompany) {
          throw FormatException('المشروع $project غير صالح أو لا يتبع الشركة المحددة.');
        }
      }
      debitTotal += debit; creditTotal += credit;
      clean.add({
        'doctype': 'Journal Entry Account',
        'account': account,
        'debit_in_account_currency': debit,
        'credit_in_account_currency': credit,
        if (costCenter.isNotEmpty) 'cost_center': costCenter,
        if (project.isNotEmpty) 'project': project,
      });
    }
    if (debitTotal <= 0 || (debitTotal - creditTotal).abs() > 0.005) throw FormatException('القيد غير متوازن. المدين ' + debitTotal.toStringAsFixed(2) + ' والدائن ' + creditTotal.toStringAsFixed(2) + '.');
    final id = name?.trim() ?? '';
    final payload = <String, dynamic>{'doctype': 'Journal Entry', 'voucher_type': 'Journal Entry', 'company': normalizedCompany, 'posting_date': postingDate.trim(), 'user_remark': remark.trim(), 'multi_currency': 0, 'accounts': clean};
    if (id.isEmpty) {
      final response = await _sendJson('POST', '/api/resource/Journal%20Entry', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء مسودة القيد.'));
      final created = data['data'];
      if (created is! Map<String, dynamic> || created['doctype'] != 'Journal Entry' || created['name'] is! String || created['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext إنشاء مسودة القيد.');
      return Map<String, dynamic>.from(created);
    }
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != normalizedCompany || current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': {...current, ...payload, 'name': id}});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة القيد.'));
    final saved = data['message'];
    if (saved is! Map<String, dynamic> || saved['doctype'] != 'Journal Entry' || saved['name'] != id || saved['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext تحديث مسودة القيد.');
    return Map<String, dynamic>.from(saved);
  }

  Future<Map<String, dynamic>> submitJournalEntry(String name, {required String company}) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != company || current['docstatus'] != 0) throw const FormatException('لا يمكن ترحيل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
    final accounts = current['accounts'];
    if (accounts is! List || accounts.length < 2) throw const FormatException('القيد لا يحتوي سطرين صالحين على الأقل.');
    final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر ترحيل القيد اليومي.'));
    final submitted = data['message'];
    if (submitted is! Map<String, dynamic> || submitted['doctype'] != 'Journal Entry' || submitted['name'] != id || submitted['docstatus'] != 1) throw const FormatException('لم يؤكد ERPNext ترحيل القيد اليومي.');
    return Map<String, dynamic>.from(submitted);
  }


  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
