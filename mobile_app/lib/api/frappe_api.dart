// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_const_constructors
import 'dart:core';
import 'dart:core' as core;
import 'dart:convert';
import 'dart:io';

import '../models/erp_models.dart';

class _DirectHttpOverrides extends HttpOverrides {}

class FrappeApi {
  static const int pageSize = 100;
  static final _directHttpOverrides = _DirectHttpOverrides();

  FrappeApi({HttpClient? httpClient})
      : _client = (httpClient ?? _directHttpOverrides.createHttpClient(null))
          ..connectionTimeout = const Duration(seconds: 20);

  final HttpClient _client;
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

  final core.Map<String, String> _cookies = {};
  final Set<String> _inFlightSalesActions = <String>{};
  final Set<String> _inFlightPaymentActions = <String>{};
  final Set<String> _inFlightPurchaseActions = <String>{};
  final Set<String> _inFlightDocumentActions = <String>{};
  String _baseUrl = '';
  int _sessionGeneration = 0;
  bool _guestMode = false;

  int get sessionGeneration => _sessionGeneration;
  bool get isGuestMode => _guestMode;

  void enableGuestMode() {
    _sessionGeneration++;
    _cookies.clear();
    _guestMode = true;
  }

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
    _guestMode = false;
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
      if (raw is! core.Map<String, dynamic>) throw const FormatException('بيانات بند الصنف المتتبع غير صحيحة.');
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
  List<core.Map<String, dynamic>> _cleanSerialBatchRows(List<dynamic> items) {
    _validateSerialBatchRows(items);
    return items.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row)
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
          .whereType<core.Map<String, dynamic>>()
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


  Future<List<ErpItem>> fetchItems({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Item',
      fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item', 'brand', 'has_serial_no', 'has_batch_no', 'has_expiry_date'],
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpItem.fromJson).toList(growable: false);
  }



  Future<void> _ensureIncomingBatchNumbers(List<dynamic> items) async {
    final seen = <String>{};
    final seenExpiry = <String, String>{};
    for (final raw in items) {
      if (raw is! core.Map<String, dynamic>) continue;
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

      Future<core.Map<String, dynamic>?> readBatch() async {
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
        if (batch is! core.Map<String, dynamic>) {
          throw Exception('استجابة سجل الدفعة غير صحيحة: $batchNo');
        }
        return batch;
      }

      void validateExisting(core.Map<String, dynamic> batch) {
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
          itemData['data'] is! core.Map<String, dynamic>) {
        throw Exception(_message(
          itemData,
          'تعذر قراءة إعدادات الصنف قبل إنشاء الدفعة.',
        ));
      }
      final item = itemData['data'] as core.Map<String, dynamic>;
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
        if (created is! core.Map<String, dynamic> ||
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

  Future<List<core.Map<String, dynamic>>> fetchAvailableBatches({
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
    return message.whereType<core.Map<String, dynamic>>().map((row) => core.Map<String, dynamic>.from(row))
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
    final code = itemCode.trim(), location = warehouse.trim();
    if (code.isEmpty || location.isEmpty || quantity < 1 || quantity > 5000) {
      throw const FormatException('بيانات طلب الأرقام التسلسلية غير صحيحة؛ الحد الأعلى للطلب 5000 رقم.');
    }
    final selected = <String>[];
    final seen = <String>{};
    while (selected.length < quantity) {
      final remaining = quantity - selected.length;
      final chunkSize = remaining > 200 ? 200 : remaining;
      final response = await _sendJson(
        'POST',
        '/api/method/erpnext.stock.doctype.serial_no.serial_no.auto_fetch_serial_number',
        {
          'item_code': code,
          'warehouse': location,
          'qty': chunkSize,
          if (batchNumbers.isNotEmpty) 'batch_nos': jsonEncode(batchNumbers),
          if (selected.isNotEmpty) 'exclude_sr_nos': jsonEncode(selected),
        },
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر جلب الأرقام التسلسلية المتاحة من ERPNext.'));
      }
      final message = data['message'];
      if (message is! List) {
        throw const FormatException('استجابة الأرقام التسلسلية من ERPNext غير متوقعة.');
      }
      final page = message.whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty && seen.add(value))
          .toList(growable: false);
      if (page.isEmpty) break;
      selected.addAll(page);
      if (page.length < chunkSize) break;
    }
    return selected;
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpWarehouse.fromJson).toList(growable: false);
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpStockBalance.fromJson).toList(growable: false);
  }

  /// Finds Item warehouse reorder rules whose projected quantity is at or
  /// below the configured threshold. Group-based rules are omitted because
  /// they require aggregating projected stock across a warehouse tree.
  Future<List<ErpStockReorderAlert>> fetchStockReorderAlerts() async {
    const maxRules = 10000;
    final rules = <core.Map<String, dynamic>>[];
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
      rules.addAll(page.whereType<core.Map<String, dynamic>>());
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
    final bins = <core.Map<String, dynamic>>[];
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
      bins.addAll(page.whereType<core.Map<String, dynamic>>());
      if (page.length < pageSize) break;
      binStart += page.length;
    }
    final binByKey = <String, core.Map<String, dynamic>>{
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpCustomer.fromJson).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchCustomerDocument(String customerId) async {
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
    if (document is! core.Map<String, dynamic> || document['name'] != id) {
      throw Exception('استجابة ملف العميل غير صحيحة.');
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<core.Map<String, dynamic>> updateCustomerProfile({
    required String customerId,
    required core.Map<String, dynamic> values,
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
    if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
        updated['customer_name'] != customerName) {
      throw Exception('لم يؤكد ERPNext حفظ ملف العميل؛ أعد تحميل الملف قبل أي تعديل آخر.');
    }
    return core.Map<String, dynamic>.from(updated);
  }

  Future<List<core.Map<String, dynamic>>> fetchSellingPriceLists() async {
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
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchItemPrices({
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
    final uri = buildResourcePageUri(
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
    final uri = buildResourcePageUri(
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
      'limit_page_length': pageSize.toString(),
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
    final uri = buildResourcePageUri(
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpSupplier.fromJson).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrders({int start = 0, String? search}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchPurchaseOrderDocument(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
    final response = await _send('GET',
        '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Purchase Order' ||
        document['docstatus'] != 1) {
      throw const FormatException('أمر الشراء غير مرحّل أو أن بياناته غير مكتملة.');
    }
    return document;
  }

  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrderRecords({int start = 0, String? search}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<core.Map<String, dynamic>> _fetchPurchaseOrderAnyStatus(String name) async {
    if (name.trim().isEmpty) throw const FormatException('رقم أمر الشراء غير موجود.');
    final response = await _send('GET', '/api/resource/Purchase%20Order/' + Uri.encodeComponent(name.trim()));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل أمر الشراء.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> || document['doctype'] != 'Purchase Order' || document['name'] != name.trim()) {
      throw const FormatException('لم يؤكد ERPNext هوية أمر الشراء المطلوب.');
    }
    return document;
  }

  Future<core.Map<String, dynamic>> fetchPurchaseOrderRecordDocument(String name) => _fetchPurchaseOrderAnyStatus(name);

  Future<core.Map<String, dynamic>> createPurchaseOrder(core.Map<String, dynamic> document) async {
    _validatePurchaseOrder(document);
    await _validateDocumentWarehouses(document);
    final response = await _sendJson('POST', '/api/resource/Purchase%20Order', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء أمر الشراء.'));
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Purchase Order' || created['name'] is! String || created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة أمر الشراء.');
    }
    return created;
  }

  void _validatePurchaseOrder(core.Map<String, dynamic> document) {
    final items = document['items'];
    if (document['doctype'] != 'Purchase Order' || document['company'] is! String || (document['company'] as String).trim().isEmpty ||
        document['supplier'] is! String || (document['supplier'] as String).trim().isEmpty || items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل لأمر الشراء.');
    }
    for (final row in items) {
      if (row is! core.Map<String, dynamic> || row['item_code'] is! String || (row['item_code'] as String).trim().isEmpty ||
          row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
        throw const FormatException('تحقق من صنف وكمية وسعر كل بند في أمر الشراء.');
      }
    }
  }

  Future<core.Map<String, dynamic>> updateDraftPurchaseOrder({required String name, required core.Map<String, dynamic> changes}) async {
    _validatePurchaseOrder(changes);
    await _validateDocumentWarehouses(changes);
    final current = await _fetchPurchaseOrderAnyStatus(name);
    if (current['docstatus'] != 0) throw const FormatException('يمكن تعديل أوامر الشراء غير المرحلة فقط.');
    final payload = core.Map<String, dynamic>.from(current)
      ..['company'] = changes['company']
      ..['supplier'] = changes['supplier']
      ..['transaction_date'] = changes['transaction_date'] ?? current['transaction_date']
      ..['schedule_date'] = changes['schedule_date'] ?? current['schedule_date']
      ..['items'] = changes['items'];
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة أمر الشراء.'));
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Purchase Order' || saved['name'] != name || saved['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext حفظ مسودة أمر الشراء.');
    }
    return saved;
  }

  Future<core.Map<String, dynamic>> submitPurchaseOrder(core.Map<String, dynamic> document) => _submitMobileDocument(document, 'Purchase Order');

  Future<core.Map<String, dynamic>> cancelPurchaseOrder(String name) async {
    final key = 'cancel-purchase-order:$name';
    if (!_inFlightPurchaseActions.add(key)) throw const FormatException('إلغاء أمر الشراء قيد التنفيذ بالفعل.');
    try {
      final current = await _fetchPurchaseOrderAnyStatus(name);
      if (current['docstatus'] != 1) throw const FormatException('يمكن إلغاء أمر الشراء المرحّل فقط.');
      final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إلغاء أمر الشراء. قد توجد مستندات استلام أو فواتير مرتبطة.'));
      final cancelled = data['message'];
      if (cancelled is! core.Map<String, dynamic> || cancelled['doctype'] != 'Purchase Order' || cancelled['name'] != name || cancelled['docstatus'] != 2) {
        throw Exception('لم يؤكد ERPNext إلغاء أمر الشراء.');
      }
      return cancelled;
    } finally {
      _inFlightPurchaseActions.remove(key);
    }
  }

  Future<List<core.Map<String, dynamic>>> fetchSupplierLedger({
    required String supplier, int start = 0, String? company,
    String? fromDate, String? toDate,
  }) => _fetchPartyLedger(
    partyType: 'Supplier', party: supplier, start: start, company: company,
    fromDate: fromDate, toDate: toDate,
  );

  Future<List<core.Map<String, dynamic>>> fetchCustomerLedger({
    required String customer, int start = 0, String? company,
    String? fromDate, String? toDate,
  }) => _fetchPartyLedger(
    partyType: 'Customer', party: customer, start: start, company: company,
    fromDate: fromDate, toDate: toDate,
  );

  String? _validateLedgerDate(String? raw, String label) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
    }
    return value;
  }

  Future<List<core.Map<String, dynamic>>> _fetchPartyLedger({
    required String partyType, required String party, int start = 0,
    String? company, String? fromDate, String? toDate,
  }) async {
    final cleanParty = party.trim();
    final cleanCompany = company?.trim() ?? '';
    final from = _validateLedgerDate(fromDate, 'تاريخ البداية');
    final to = _validateLedgerDate(toDate, 'تاريخ النهاية');
    if (cleanParty.isEmpty || start < 0 ||
        !{'Customer', 'Supplier'}.contains(partyType) ||
        (from != null && to != null && from.compareTo(to) > 0)) {
      throw const FormatException('حدد الطرف ونطاق تاريخ صحيحاً.');
    }
    final filters = <List<dynamic>>[
      ['party_type', '=', partyType], ['party', '=', cleanParty],
      ['is_cancelled', '=', 0],
      if (cleanCompany.isNotEmpty) ['company', '=', cleanCompany],
      if (from != null) ['posting_date', '>=', from],
      if (to != null) ['posting_date', '<=', to],
    ];
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'GL Entry',
      fields: const [
        'name', 'posting_date', 'account', 'against', 'debit', 'credit',
        'voucher_type', 'voucher_no', 'remarks', 'company', 'party',
        'account_currency',
      ],
      filters: filters, orderBy: 'posting_date asc, creation asc, name asc',
      start: start, pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل كشف حساب الطرف من GL Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة كشف الحساب غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchPartyLedgerOpeningBalance({
    required String partyType, required String party, required String beforeDate,
    String? company,
  }) async {
    final cleanParty = party.trim();
    final before = _validateLedgerDate(beforeDate, 'تاريخ بداية الكشف');
    if (cleanParty.isEmpty || before == null ||
        !{'Customer', 'Supplier'}.contains(partyType)) {
      throw const FormatException('بيانات رصيد افتتاح كشف الحساب غير صحيحة.');
    }
    final filters = <List<dynamic>>[
      ['party_type', '=', partyType], ['party', '=', cleanParty],
      ['is_cancelled', '=', 0], ['posting_date', '<', before],
      if (company?.trim().isNotEmpty == true) ['company', '=', company!.trim()],
    ];
    final uri = Uri.parse('$_baseUrl/api/method/frappe.client.get_list').replace(
      queryParameters: {
        'doctype': 'GL Entry',
        'fields': jsonEncode(['sum(debit) as debit', 'sum(credit) as credit']),
        'filters': jsonEncode(filters),
        'limit_page_length': '1',
      },
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر حساب الرصيد الافتتاحي من دفتر الأستاذ.'));
    }
    final rows = data['message'];
    if (rows is! List || rows.isEmpty || rows.first is! core.Map<String, dynamic>) {
      return {'debit': 0.0, 'credit': 0.0, 'balance': 0.0};
    }
    final row = rows.first as core.Map<String, dynamic>;
    final debit = double.tryParse(row['debit']?.toString() ?? '') ?? 0.0;
    final credit = double.tryParse(row['credit']?.toString() ?? '') ?? 0.0;
    if (!debit.isFinite || !credit.isFinite) {
      throw const FormatException('أعاد ERPNext إجماليات غير صالحة للرصيد الافتتاحي.');
    }
    return {'debit': debit, 'credit': credit, 'balance': debit - credit};
  }

  Future<List<core.Map<String, dynamic>>> fetchReconciliationAccounts({
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
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany &&
            row['account_type'] == accountType)
        .map((row) => core.Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchBankAccounts({
    required String company,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض الحسابات البنكية.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Bank Account',
      fields: const [
        'name', 'account', 'account_name', 'company', 'is_default',
        'is_company_account', 'disabled', 'account_type', 'bank',
      ],
      filters: [
        ['company', '=', normalizedCompany],
        ['is_company_account', '=', 1],
        ['disabled', '=', 0],
      ],
      orderBy: 'is_default desc, account_name asc',
      pageLength: 500,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل الحسابات البنكية للشركة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة الحسابات البنكية غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany &&
            (row['is_company_account'] == 1 || row['is_company_account'] == true) &&
            (row['disabled'] != 1 && row['disabled'] != true) &&
            (row['name']?.toString().isNotEmpty ?? false) &&
            (row['account']?.toString().isNotEmpty ?? false))
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> createBankStatementImportPreview({
    required String bankAccount, required String company,
    required String fileName, required List<int> fileBytes,
  }) async {
    final account = bankAccount.trim(), cleanCompany = company.trim();
    final lowerName = fileName.toLowerCase();
    if (account.isEmpty || cleanCompany.isEmpty || fileBytes.isEmpty ||
        !RegExp(r'\.(csv|xlsx|xls|txt)
    required String bankAccount,
    required String company,
    required String date,
  }) async {
    final account = bankAccount.trim(), normalizedCompany = company.trim();
    final parsed = DateTime.tryParse(date.trim());
    if (account.isEmpty || normalizedCompany.isEmpty || parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date.trim()) {
      throw const FormatException('حدد الحساب البنكي والشركة وتاريخ كشف صحيحاً.');
    }
    final accountResponse = await _send(
      'GET', '/api/resource/Bank%20Account/' + Uri.encodeComponent(account),
    );
    final accountData = _decode(accountResponse.body);
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300) {
      throw Exception(_message(accountData, 'تعذر التحقق من الحساب البنكي.'));
    }
    final bank = accountData['data'];
    if (bank is! core.Map<String, dynamic> || bank['name'] != account ||
        bank['company'] != normalizedCompany) {
      throw const FormatException('الحساب البنكي لا يتبع الشركة المحددة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_account_balance')
        .replace(queryParameters: {
      'bank_account': account,
      'company': normalizedCompany,
      'till_date': date.trim(),
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل رصيد الحساب البنكي من ERPNext.'));
    }
    final balance = double.tryParse(data['message']?.toString() ?? '');
    if (balance == null || !balance.isFinite) {
      throw const FormatException('لم يرجع ERPNext رصيداً بنكياً صالحاً.');
    }
    return {
      'bank_account': account,
      'company': normalizedCompany,
      'date': date.trim(),
      'system_balance': balance,
    };
  }


  Future<List<core.Map<String, dynamic>>> fetchBankTransactions({
    required String bankAccount,
    required String company,
    String? fromDate,
    String? toDate,
    int start = 0,
  }) async {
    final account = bankAccount.trim(), normalizedCompany = company.trim();
    if (account.isEmpty || normalizedCompany.isEmpty || start < 0) {
      throw const FormatException('حدد الشركة والحساب البنكي وبداية صفحة صحيحة.');
    }
    String? dateValue(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value;
    }
    final from = dateValue(fromDate, 'تاريخ البداية');
    final to = dateValue(toDate, 'تاريخ النهاية');
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
    }
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Bank Transaction',
      fields: const [
        'name', 'date', 'deposit', 'withdrawal', 'currency', 'description',
        'transaction_type', 'bank_account', 'company', 'allocated_amount',
        'unallocated_amount', 'reference_number', 'party_type', 'party',
        'status', 'docstatus',
      ],
      filters: [
        ['bank_account', '=', account],
        ['company', '=', normalizedCompany],
        ['docstatus', '=', 1],
        ['unallocated_amount', '>', 0],
        if (from != null) ['date', '>=', from],
        if (to != null) ['date', '<=', to],
      ],
      orderBy: 'date asc, name asc',
      start: start,
      pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل حركات الحساب البنكي.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة حركات الحساب البنكي غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['bank_account'] == account &&
            row['company'] == normalizedCompany && row['docstatus'] == 1)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchLinkedBankVouchers({
    required String transactionName,
    required String bankAccount,
    required String company,
    String? fromDate,
    String? toDate,
  }) async {
    final id = transactionName.trim(), account = bankAccount.trim();
    final normalizedCompany = company.trim();
    if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('بيانات حركة البنك والشركة غير مكتملة.');
    }
    String? normalizeDate(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value;
    }
    final from = normalizeDate(fromDate, 'تاريخ البداية');
    final to = normalizeDate(toDate, 'تاريخ النهاية');
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
    }
    final transactionResponse = await _send(
      'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
    );
    final transactionData = _decode(transactionResponse.body);
    if (transactionResponse.statusCode < 200 || transactionResponse.statusCode >= 300) {
      throw Exception(_message(transactionData, 'تعذر إعادة قراءة حركة البنك قبل المطابقة.'));
    }
    final transaction = transactionData['data'];
    if (transaction is! core.Map<String, dynamic> ||
        transaction['name'] != id || transaction['bank_account'] != account ||
        transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
      throw const FormatException('حركة البنك لا تتبع الحساب أو الشركة المحددة أو أنها غير مرحّلة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_linked_payments')
        .replace(queryParameters: {
      'bank_transaction_name': id,
      'document_types': jsonEncode(['payment_entry', 'journal_entry', 'sales_invoice', 'purchase_invoice']),
      if (from != null) 'from_date': from,
      if (to != null) 'to_date': to,
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب المستندات المرشحة لمطابقة حركة البنك.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة المستندات المرشحة غير متوقعة.');
    const allowed = {'Payment Entry', 'Journal Entry', 'Sales Invoice', 'Purchase Invoice'};
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => allowed.contains(row['doctype']) &&
            (row['name']?.toString().trim().isNotEmpty ?? false))
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> reconcileBankTransaction({
    required String transactionName,
    required String bankAccount,
    required String company,
    required List<core.Map<String, dynamic>> vouchers,
    String? fromDate,
    String? toDate,
  }) async {
    final id = transactionName.trim(), account = bankAccount.trim();
    final normalizedCompany = company.trim();
    if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty || vouchers.isEmpty) {
      throw const FormatException('حدد حركة البنك ومستنداً واحداً على الأقل للمطابقة.');
    }
    final freshTransactionResponse = await _send(
      'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
    );
    final freshData = _decode(freshTransactionResponse.body);
    if (freshTransactionResponse.statusCode < 200 || freshTransactionResponse.statusCode >= 300) {
      throw Exception(_message(freshData, 'تعذر التحقق من حركة البنك قبل التسوية.'));
    }
    final transaction = freshData['data'];
    if (transaction is! core.Map<String, dynamic> ||
        transaction['name'] != id || transaction['bank_account'] != account ||
        transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
      throw const FormatException('تم رفض التسوية لأن حركة البنك لا تتبع الشركة والحساب المحددين.');
    }
    final unallocated = double.tryParse(transaction['unallocated_amount']?.toString() ?? '') ?? 0;
    final freshCandidates = await fetchLinkedBankVouchers(
      transactionName: id,
      bankAccount: account,
      company: normalizedCompany,
      fromDate: fromDate,
      toDate: toDate,
    );
    final candidateByKey = <String, core.Map<String, dynamic>>{
      for (final row in freshCandidates)
        '${row['doctype']}|${row['name']}': row,
    };
    final selected = <core.Map<String, dynamic>>[];
    final seen = <String>{};
    var total = 0.0;
    const allowed = {
      'Payment Entry',
      'Journal Entry',
      'Sales Invoice',
      'Purchase Invoice',
    };
    for (final row in vouchers) {
      final doctype = row['payment_doctype']?.toString() ?? '';
      final name = row['payment_name']?.toString().trim() ?? '';
      final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
      final key = '$doctype|$name';
      final candidate = candidateByKey[key];
      final candidateAmount = double.tryParse(candidate?['paid_amount']?.toString() ?? '') ?? 0;
      if (!allowed.contains(doctype) || name.isEmpty || !seen.add(key) ||
          !amount.isFinite || amount <= 0 || candidate == null ||
          amount > candidateAmount + 0.000001) {
        throw const FormatException('توجد بيانات مستند أو مبلغ غير صالح أو لم يعد مرشحاً للمطابقة في ERPNext.');
      }
      total += amount;
      selected.add({'payment_doctype': doctype, 'payment_name': name, 'amount': amount});
    }
    if (total > unallocated + 0.000001) {
      throw const FormatException('إجمالي المطابقة يتجاوز المبلغ غير المخصص في حركة البنك.');
    }
    final response = await _sendJson(
      'POST',
      '/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.reconcile_vouchers',
      {'bank_transaction_name': id, 'vouchers': jsonEncode(selected)},
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext مطابقة حركة البنك.'));
    }
    final updated = data['message'];
    if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
        updated['bank_account'] != account || updated['company'] != normalizedCompany) {
      throw const FormatException('لم يؤكد ERPNext تحديث حركة البنك الصحيحة.');
    }
    return core.Map<String, dynamic>.from(updated);
  }

  Future<core.Map<String, dynamic>> _runPaymentReconciliationMethod({
    required core.Map<String, dynamic> document,
    required String method,
    core.Map<String, dynamic>? args,
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
    if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
      throw Exception('لم يُرجع ERPNext مستند تسوية محدثاً بعد تنفيذ $method.');
    }
    final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
    if (updated['doctype'] != 'Payment Reconciliation' ||
        updated['company'] != document['company'] ||
        updated['party_type'] != document['party_type'] ||
        updated['party'] != document['party'] ||
        updated['receivable_payable_account'] != document['receivable_payable_account']) {
      throw const FormatException('تغيرت هوية مستند التسوية في استجابة ERPNext.');
    }
    return updated;
  }

  Future<core.Map<String, dynamic>> fetchUnreconciledPaymentEntries({
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
      'invoices': <core.Map<String, dynamic>>[],
      'payments': <core.Map<String, dynamic>>[],
      'allocation': <core.Map<String, dynamic>>[],
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

  Future<core.Map<String, dynamic>> allocatePaymentReconciliation(
    core.Map<String, dynamic> document,
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

  Future<core.Map<String, dynamic>> reconcilePaymentAllocations(
    core.Map<String, dynamic> document,
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

  Future<List<core.Map<String, dynamic>>> fetchSupplierPayments({int start = 0, String? search}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchDraftSupplierPayments({
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
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['docstatus'] == 0 &&
            row['payment_type'] == 'Pay' && row['party_type'] == 'Supplier')
        .toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDraftDocument(String name) =>
      _fetchPaymentEntryDraft(
        name,
        paymentType: 'Pay',
        partyType: 'Supplier',
      );

  Future<core.Map<String, dynamic>> submitSupplierPaymentDraft(
    core.Map<String, dynamic> draft,
  ) async {
    if (draft['doctype'] != 'Payment Entry' ||
        draft['payment_type'] != 'Pay' ||
        draft['party_type'] != 'Supplier') {
      throw const FormatException('المستند ليس مسودة سند صرف مورد صحيحة.');
    }
    return _submitMobileDocument(draft, 'Payment Entry');
  }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDocument(String name) async {
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
    if (document is! core.Map<String, dynamic> ||
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpPurchaseInvoice.fromJson).toList(growable: false);
  }

  /// Loads bounded, submitted sales invoices for the mobile sales dashboard.
  /// Currency totals are aggregated by the caller; this method never converts
  /// or combines amounts from different currencies.
  Future<List<core.Map<String, dynamic>>> fetchSalesDashboardInvoices({
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
    final rows = <core.Map<String, dynamic>>[];
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
        if (row is! core.Map<String, dynamic> ||
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
  Future<List<core.Map<String, dynamic>>> fetchOutstandingInvoices({
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
    final rows = <core.Map<String, dynamic>>[];
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
      final validRows = page.whereType<core.Map<String, dynamic>>().toList();
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
  Future<core.Map<String, dynamic>> runStandardReport({
    required String reportName,
    required core.Map<String, dynamic> filters,
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
    if (message is! core.Map) {
      throw Exception('استجابة تقرير $reportName من ERPNext غير متوقعة.');
    }
    final result = core.Map<String, dynamic>.from(message);
    if (result['columns'] is! List || result['result'] is! List) {
      throw Exception('لم يُرجع ERPNext أعمدة وبيانات صالحة لتقرير $reportName.');
    }
    return result;
  }


  // Update only explicitly supported Employee profile fields after re-reading
  // the record and confirming company ownership. ERPNext permissions remain authoritative.
  Future<core.Map<String, dynamic>> createEmployee({
    required String company,
    required String employeeName,
    required String dateOfBirth,
    required String dateOfJoining,
    required String gender,
    String department = '',
    String designation = '',
    String cellNumber = '',
    String email = '',
  }) async {
    final normalizedCompany = company.trim();
    final displayName = employeeName.trim();
    final birthText = dateOfBirth.trim();
    final joiningText = dateOfJoining.trim();
    final birth = DateTime.tryParse(birthText);
    final joining = DateTime.tryParse(joiningText);
    if (normalizedCompany.isEmpty || displayName.isEmpty ||
        birth == null || joining == null ||
        birth.toIso8601String().substring(0, 10) != birthText ||
        joining.toIso8601String().substring(0, 10) != joiningText ||
        !joining.isAfter(birth)) {
      throw const FormatException('الشركة والاسم وتاريخا الميلاد والتعيين الصحيحة مطلوبة، ويجب أن يكون التعيين بعد الميلاد.');
    }
    if (!const {'Male', 'Female', 'Other'}.contains(gender)) {
      throw const FormatException('حدد الجنس من الخيارات المدعومة.');
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isNotEmpty) {
      final parts = normalizedEmail.split('@');
      if (parts.length != 2 || parts.first.isEmpty ||
          !parts.last.contains('.') || parts.last.startsWith('.') ||
          parts.last.endsWith('.')) {
        throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
      }
    }
    final nameParts = displayName.split(' ').where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (nameParts.isEmpty) throw const FormatException('اسم الموظف مطلوب.');
    final payload = <String, dynamic>{
      'doctype': 'Employee',
      'first_name': nameParts.first,
      if (nameParts.length > 1) 'last_name': nameParts.skip(1).join(' '),
      'company': normalizedCompany,
      'date_of_birth': birthText,
      'date_of_joining': joiningText,
      'gender': gender,
      'status': 'Active',
      if (department.trim().isNotEmpty) 'department': department.trim(),
      if (designation.trim().isNotEmpty) 'designation': designation.trim(),
      if (cellNumber.trim().isNotEmpty) 'cell_number': cellNumber.trim(),
      if (normalizedEmail.isNotEmpty) 'prefered_email': normalizedEmail,
    };
    final response = await _sendJson('POST', '/api/resource/Employee', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء الموظف. تحقق من الحقول الإلزامية وصلاحية Employee في ERPNext.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Employee' ||
        created['name'] is! String || created['name'].toString().isEmpty ||
        created['company'] != normalizedCompany ||
        created['employee_name'] != displayName ||
        created['docstatus'] != 0) {
      throw const FormatException('لم يؤكد ERPNext إنشاء سجل الموظف المطابق.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> updateEmployeeProfile({
    required String employee,
    required String company,
    required String employeeName,
    String department = '',
    String designation = '',
    String cellNumber = '',
    String email = '',
    String status = 'Active',
  }) async {
    final id = employee.trim(), normalizedCompany = company.trim();
    final displayName = employeeName.trim();
    if (id.isEmpty || normalizedCompany.isEmpty || displayName.isEmpty) {
      throw const FormatException('رقم الموظف والشركة والاسم حقول مطلوبة.');
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
    }
    if (!const {'Active', 'Inactive', 'Left', 'Suspended'}.contains(status)) {
      throw const FormatException('حالة الموظف المحددة غير مدعومة.');
    }
    final current = await _fetchHrEmployee(id, normalizedCompany);
    final payload = <String, dynamic>{
      ...current,
      'employee_name': displayName,
      'department': department.trim().isEmpty ? null : department.trim(),
      'designation': designation.trim().isEmpty ? null : designation.trim(),
      'cell_number': cellNumber.trim(),
      'prefered_email': normalizedEmail,
      'status': status,
    };
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحديث بيانات الموظف. تحقق من صلاحية Employee.'));
    }
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Employee' ||
        saved['name'] != id || saved['company'] != normalizedCompany ||
        saved['employee_name'] != displayName || saved['status'] != status) {
      throw const FormatException('لم يؤكد ERPNext حفظ بيانات الموظف المطابقة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<core.Map<String, dynamic>> updateAttendanceDraft({
    required String name,
    required String company,
    required String attendanceDate,
    required String status,
    String leaveType = '',
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final date = DateTime.tryParse(attendanceDate.trim());
    if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
        date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
      throw const FormatException('رقم سجل الحضور والشركة والتاريخ الصحيح مطلوبة.');
    }
    if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
      throw const FormatException('حالة الحضور المحددة غير مدعومة.');
    }
    final response = await _send('GET', '/api/resource/Attendance/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة سجل الحضور.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Attendance' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || current['employee'] is! String) {
      throw const FormatException('يمكن تصحيح مسودات الحضور التابعة للشركة المحددة فقط.');
    }
    await _fetchHrEmployee(current['employee'].toString(), normalizedCompany);
    if (status == 'On Leave' && leaveType.trim().isEmpty) {
      throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
    }
    final duplicateUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Attendance',
      fields: const ['name', 'docstatus'],
      filters: [
        ['employee', '=', current['employee']],
        ['attendance_date', '=', attendanceDate.trim()],
      ],
      orderBy: 'attendance_date asc',
      pageLength: 20,
    );
    final duplicateResponse = await _sendUri('GET', duplicateUri);
    final duplicateData = _decode(duplicateResponse.body);
    if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
      throw Exception(_message(duplicateData, 'تعذر التحقق من تكرار الحضور.'));
    }
    final duplicates = duplicateData['data'];
    if (duplicates is! List || duplicates.whereType<core.Map<String, dynamic>>()
        .any((row) => row['name'] != id && row['docstatus'] != 2)) {
      throw const FormatException('يوجد سجل حضور آخر للموظف في التاريخ المحدد.');
    }
    final payload = <String, dynamic>{
      ...current,
      'attendance_date': attendanceDate.trim(),
      'status': status,
      'leave_type': status == 'On Leave' ? leaveType.trim() : null,
    };
    final savedResponse = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final savedData = _decode(savedResponse.body);
    if (savedResponse.statusCode < 200 || savedResponse.statusCode >= 300) {
      throw Exception(_message(savedData, 'تعذر حفظ تصحيح الحضور.'));
    }
    final saved = savedData['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Attendance' ||
        saved['name'] != id || saved['company'] != normalizedCompany ||
        saved['docstatus'] != 0 || saved['attendance_date'] != attendanceDate.trim()) {
      throw const FormatException('لم يؤكد ERPNext حفظ مسودة الحضور المصححة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<List<core.Map<String, dynamic>>> fetchLeaveTypes() async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Leave Type',
      fields: const ['name', 'is_lwp', 'allow_negative', 'max_days_allowed', 'is_carry_forward'],
      orderBy: 'name asc', pageLength: 200,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أنواع الإجازات. تحقق من صلاحية Leave Type.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة أنواع الإجازات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> createLeaveType({
    required String name,
    bool isLeaveWithoutPay = false,
    bool allowNegative = false,
    double? maxDaysAllowed,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
    if (maxDaysAllowed != null &&
        (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
      throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
    }
    final payload = <String, dynamic>{
      'doctype': 'Leave Type',
      'leave_type_name': normalized,
      'is_lwp': isLeaveWithoutPay ? 1 : 0,
      'allow_negative': allowNegative ? 1 : 0,
      if (maxDaysAllowed != null) 'max_days_allowed': maxDaysAllowed,
    };
    final response = await _sendJson('POST', '/api/resource/Leave%20Type', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء نوع الإجازة. تحقق من صلاحية إدارة Leave Type.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Type' ||
        created['name'] is! String || created['name'].toString().isEmpty) {
      throw const FormatException('لم يؤكد ERPNext إنشاء نوع الإجازة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> updateLeaveType({
    required String name,
    required bool isLeaveWithoutPay,
    required bool allowNegative,
    double? maxDaysAllowed,
  }) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
    if (maxDaysAllowed != null &&
        (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
      throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
    }
    final currentResponse = await _send(
      'GET', '/api/resource/Leave%20Type/' + Uri.encodeComponent(id),
    );
    final currentData = _decode(currentResponse.body);
    if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300) {
      throw Exception(_message(currentData, 'تعذر إعادة قراءة نوع الإجازة قبل التعديل.'));
    }
    final current = currentData['data'];
    if (current is! core.Map<String, dynamic> ||
        current['doctype'] != 'Leave Type' || current['name'] != id) {
      throw const FormatException('هوية نوع الإجازة المسترجع غير مطابقة.');
    }
    final payload = <String, dynamic>{
      ...current,
      'is_lwp': isLeaveWithoutPay ? 1 : 0,
      'allow_negative': allowNegative ? 1 : 0,
      'max_days_allowed': maxDaysAllowed,
    };
    final response = await _sendJson(
      'POST', '/api/method/frappe.client.save', {'doc': payload},
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحديث نوع الإجازة. قد توجد قيود أو صلاحيات تمنع التعديل.'));
    }
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> ||
        saved['doctype'] != 'Leave Type' || saved['name'] != id ||
        saved['is_lwp'] != (isLeaveWithoutPay ? 1 : 0) ||
        saved['allow_negative'] != (allowNegative ? 1 : 0)) {
      throw const FormatException('لم يؤكد ERPNext حفظ إعدادات نوع الإجازة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  static const Set<String> salesWorkflowDoctypes = {'Quotation', 'Sales Order', 'Delivery Note', 'Sales Invoice'};

  String _salesWorkflowResource(String doctype) {
    if (!salesWorkflowDoctypes.contains(doctype)) {
      throw FormatException('نوع مستند المبيعات غير مدعوم: $doctype');
    }
    return Uri.encodeComponent(doctype);
  }

  Future<List<core.Map<String, dynamic>>> fetchSalesWorkflowDocuments(
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
            .whereType<core.Map<String, dynamic>>()
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

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDocument(String name) async {
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
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim()) {
      throw const FormatException('بيانات سند القبض غير مؤكدة.');
    }
    return document;
  }

  Future<core.Map<String, dynamic>> receiveSalesInvoicePayment({
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
    if (rawDocument is! core.Map<String, dynamic> ||
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
      if (row is! core.Map<String, dynamic> ||
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
    final paymentDraft = core.Map<String, dynamic>.from(rawDocument);

    final insert = await _sendJson('POST', '/api/resource/Payment%20Entry', paymentDraft);
    final insertData = _decode(insert.body);
    if (insert.statusCode < 200 || insert.statusCode >= 300) {
      throw Exception(_message(insertData, 'تعذر حفظ سند القبض.'));
    }
    final created = insertData['data'];
    if (created is! core.Map<String, dynamic> ||
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


  Future<core.Map<String, dynamic>> createPurchaseInvoice(core.Map<String, dynamic> invoice) async {
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
    if (doc is! core.Map<String, dynamic> ||
        doc['doctype'] != 'Purchase Invoice' ||
        doc['name'] is! String ||
        doc['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المشتريات.');
    }
    return doc;
  }

  void _validatePurchase(core.Map<String, dynamic> doc) {
    final items = doc['items'];
    if (doc['doctype'] != 'Purchase Invoice' || doc['supplier'] is! String ||
        (doc['supplier'] as String).trim().isEmpty || doc['company'] is! String ||
        (doc['company'] as String).trim().isEmpty || items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل.');
    }
    doc['items'] = _cleanSerialBatchRows(items);
    for (final row in items) {
      if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
          (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
          !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
        throw const FormatException('تحقق من رمز الصنف والكمية والسعر، وتأكد أن إجمالي البند ضمن النطاق الرقمي.');
      }
    }
  }

  Future<core.Map<String, dynamic>> updateDraftPurchaseInvoice({
    required String invoiceName, required core.Map<String, dynamic> changes,
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
    final payload = core.Map<String, dynamic>.from(current)
      ..['supplier'] = changes['supplier']
      ..['company'] = changes['company']
      ..['posting_date'] = changes['posting_date'] ?? current['posting_date']
      ..['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0
      ..['items'] = changes['items'];
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة المشتريات.'));
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['name'] != invoiceName || saved['docstatus'] != 0) throw Exception('لم يتم تأكيد حفظ المسودة.');
    return saved;
  }

  Future<core.Map<String, dynamic>> submitPurchaseInvoice(core.Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Invoice');

  Future<core.Map<String, double>> fetchPurchaseReturnableQuantities(String invoiceName) async {
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
    if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) ||
        raw['return_against'] != invoiceName || raw['items'] is! List) {
      throw Exception('لم يؤكد ERPNext بيانات الكميات القابلة للإرجاع.');
    }
    final result = <String, double>{};
    for (final row in (raw['items'] as List).whereType<core.Map<String, dynamic>>()) {
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

  Future<core.Map<String, dynamic>> createPurchaseReturn(String invoiceName, {core.Map<String, double?>? quantitiesBySourceItem}) async {
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
    if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) || raw['return_against'] != invoiceName ||
        raw['items'] is! List || (raw['items'] as List).isEmpty) {
      throw Exception('لم يؤكد ERPNext بيانات مرتجع المشتريات.');
    }
    final mappedItems = (raw['items'] as List).whereType<core.Map<String, dynamic>>().toList();
    if (quantitiesBySourceItem != null) {
      final selectedItems = <core.Map<String, dynamic>>[];
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
        final line = core.Map<String, dynamic>.from(mappedItems[index]);
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
    final inserted = await _sendJson('POST', '/api/resource/Purchase%20Invoice', core.Map<String, dynamic>.from(raw));
    final data = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة المرتجع.'));
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
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

  Future<core.Map<String, dynamic>> payPurchaseInvoice({
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
    if (raw is! core.Map<String, dynamic> || raw['payment_type'] != 'Pay' ||
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
      if (row is core.Map<String, dynamic> && row['reference_doctype'] == 'Purchase Invoice' &&
          row['reference_name'] == invoiceName) {
        allocated += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
      }
    }
    if ((allocated - amount).abs() > 0.01) throw const FormatException('توزيع الدفعة من ERPNext لا يطابق المبلغ المطلوب.');
    final inserted = await _sendJson('POST', '/api/resource/Payment%20Entry', core.Map<String, dynamic>.from(raw));
    final insertedData = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ سند الصرف.'));
    final created = insertedData['data'];
    if (created is! core.Map<String, dynamic> ||
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
      if (row is core.Map<String, dynamic> &&
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

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDraft(String name, {required String paymentType, required String partyType}) async {
    if (name.trim().isEmpty) throw const FormatException('رقم سند الدفع غير موجود.');
    final response = await _send('GET',
      '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name.trim()),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مسودة سند الدفع.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim() || document['docstatus'] != 0 ||
        document['payment_type'] != paymentType ||
        document['party_type'] != partyType ||
        document['references'] is! List) {
      throw const FormatException('سند الدفع لم يعد مسودة أو أن بياناته غير صحيحة.');
    }
    return document;
  }

  Future<core.Map<String, dynamic>> _submitMobileDocument(core.Map<String, dynamic> doc, String doctype) async {
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
    if (submitted is! core.Map<String, dynamic> ||
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

  Future<core.Map<String, dynamic>> cancelPurchaseInvoice(String name) async {
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
    if (canceled is! core.Map<String, dynamic> ||
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
    if (warehouse is! core.Map<String, dynamic> ||
        warehouse['doctype'] != 'Warehouse' ||
        warehouse['name'] != normalizedWarehouse ||
        warehouse['company'] != normalizedCompany ||
        warehouse['is_group'] == 1 || warehouse['is_group'] == true ||
        warehouse['disabled'] == 1 || warehouse['disabled'] == true) {
      throw FormatException('المستودع ' + normalizedWarehouse + ' غير صالح أو لا يتبع الشركة ' + normalizedCompany + '. اختر مستودعاً فعّالاً تابعاً للشركة.');
    }
  }

  Future<void> _validateDocumentWarehouses(core.Map<String, dynamic> document) async {
    final company = document['company'];
    final items = document['items'];
    if (company is! String || company.trim().isEmpty || items is! List) return;
    final warehouses = <String>{};
    for (final row in items.whereType<core.Map<String, dynamic>>()) {
      final warehouse = row['warehouse'];
      if (warehouse is String && warehouse.trim().isNotEmpty) {
        warehouses.add(warehouse.trim());
      }
    }
    for (final warehouse in warehouses) {
      await _validateWarehouseForCompany(warehouse, company);
    }
  }

  Future<core.Map<String, dynamic>> createStockEntry({
    required String company, required String purpose, required List<core.Map<String, dynamic>> items,
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
        final item = core.Map<String, dynamic>.from(row);
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
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Stock Entry' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة حركة المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> createPurchaseReceipt(core.Map<String, dynamic> document) async {
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
      if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
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
    final sourceRowsByOrder = <String, core.Map<String, core.Map<String, dynamic>>>{};
    for (final row in items) {
      final orderName = row is core.Map<String, dynamic> ? row['purchase_order'] : null;
      final orderItemName = row is core.Map<String, dynamic> ? row['purchase_order_item'] : null;
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
      final byItem = sourceRowsByOrder.putIfAbsent(normalizedOrder, () => <String, core.Map<String, dynamic>>{});
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
      final sourceByName = <String, core.Map<String, dynamic>>{
        for (final source in sourceItems.whereType<core.Map<String, dynamic>>())
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
    final receiptWarehouses = items.map((row) => (row as core.Map<String, dynamic>)['warehouse'].toString()).toSet();
    for (final warehouse in receiptWarehouses) {
      await _validateWarehouseForCompany(warehouse, document['company'] as String);
    }
    final response = await _sendJson('POST', '/api/resource/Purchase%20Receipt', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء سند استلام المشتريات.'));
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Purchase Receipt' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة سند استلام المشتريات؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> submitPurchaseReceipt(core.Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Receipt');

  Future<core.Map<String, dynamic>> submitStockEntry(core.Map<String, dynamic> doc) => _submitMobileDocument(doc, 'Stock Entry');

  Future<core.Map<String, dynamic>> createStockReconciliation({
    required String company, required String warehouse, required List<core.Map<String, dynamic>> items, String? remarks,
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
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Stock Reconciliation' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة تسوية المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> submitStockReconciliation(core.Map<String, dynamic> doc) =>
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
    if (document is! core.Map<String, dynamic> ||
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

  Future<List<core.Map<String, dynamic>>> fetchDraftStockDocuments(String doctype, {int start = 0}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().map((row) => <String, dynamic>{...row, 'doctype': doctype}).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchStockDocument(String doctype, String name) async {
    const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation'};
    if (!allowed.contains(doctype) || name.trim().isEmpty) throw ArgumentError('نوع أو رقم مستند المخزون غير صحيح.');
    final response = await _send('GET', '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل مستند المخزون.'));
    final doc = data['data'];
    if (doc is! core.Map<String, dynamic>) throw Exception('تفاصيل مستند المخزون غير متوقعة.');
    return doc;
  }

  Future<List<core.Map<String, dynamic>>> fetchStockMovements({
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchInvoiceDocument(String documentType, String name) async {
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
    if (document is! core.Map<String, dynamic>) throw Exception('تفاصيل الفاتورة من ERPNext غير متوقعة.');
    return document;
  }
  Future<List<core.Map<String, dynamic>>> fetchAccountingAccounts({
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
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  // Allow-listed mobile master-data access; ERPNext remains authoritative.
  static const core.Map<String, List<String>> _masterDataFields = {
    'Item': ['name', 'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'],
    'Supplier': ['name', 'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'],
    'Customer': ['name', 'customer_name', 'customer_type', 'customer_group', 'territory',
      'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'],
    'Customer Group': ['name', 'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'],
    'Territory': ['name', 'territory_name', 'parent_territory', 'is_group', 'disabled'],
    'Sales Person': ['name', 'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'],
    'Warehouse': ['name', 'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'],
    'Item Group': ['name', 'item_group_name', 'parent_item_group', 'is_group', 'disabled'],
    'UOM': ['name', 'uom_name', 'must_be_whole_number', 'enabled'],
    'Supplier Group': ['name', 'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'],
    'Price List': ['name', 'price_list_name', 'currency', 'buying', 'selling', 'enabled'],
  };

  static const core.Map<String, Set<String>> _masterDataWritableFields = {
    'Item': {'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'},
    'Supplier': {'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'},
    'Customer': {'customer_name', 'customer_type', 'customer_group', 'territory',
      'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'},
    'Customer Group': {'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'},
    'Territory': {'territory_name', 'parent_territory', 'is_group', 'disabled'},
    'Sales Person': {'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'},
    'Warehouse': {'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'},
    'Item Group': {'item_group_name', 'parent_item_group', 'is_group', 'disabled'},
    'UOM': {'uom_name', 'must_be_whole_number', 'enabled'},
    'Supplier Group': {'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'},
    'Price List': {'price_list_name', 'currency', 'buying', 'selling', 'enabled'},
  };


  Future<List<core.Map<String, dynamic>>> fetchMasterDataOptions(String doctype) async {
    if (!_masterDataFields.containsKey(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    const maxRows = 2000;
    final result = <core.Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await fetchMasterDataRows(doctype: doctype, start: start);
      result.addAll(page);
      if (page.length < pageSize) return result;
      start += page.length;
      if (result.length >= maxRows) return result;
    }
  }

  Future<List<core.Map<String, dynamic>>> fetchMasterDataRows({
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
      'Customer' => const ['name', 'customer_name', 'customer_group', 'territory'],
      'Customer Group' => const ['name', 'customer_group_name', 'parent_customer_group'],
      'Territory' => const ['name', 'territory_name', 'parent_territory'],
      'Sales Person' => const ['name', 'sales_person_name', 'parent_sales_person', 'employee'],
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
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchMasterDataDocument({
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
    if (document is! core.Map<String, dynamic> || document['name'] != id) {
      throw Exception('لم تتطابق هوية السجل المسترجع مع المطلوب.');
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<core.Map<String, dynamic>> saveMasterDataDocument({
    required String doctype,
    String? name,
    required core.Map<String, dynamic> values,
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
            if (raw is! core.Map) throw const FormatException('يوجد صف غير صالح في تحويل وحدات الصنف.');
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
      case 'Customer':
        if (requiredValue('customer_name').isEmpty ||
            !{'Company', 'Individual'}.contains(requiredValue('customer_type')) ||
            requiredValue('customer_group').isEmpty ||
            requiredValue('territory').isEmpty) {
          throw const FormatException('اسم العميل ونوعه ومجموعته ومنطقته حقول مطلوبة.');
        }
        break;
      case 'Customer Group':
        if (requiredValue('customer_group_name').isEmpty) {
          throw const FormatException('اسم مجموعة العملاء مطلوب.');
        }
        break;
      case 'Territory':
        if (requiredValue('territory_name').isEmpty) {
          throw const FormatException('اسم المنطقة مطلوب.');
        }
        break;
      case 'Sales Person':
        final commissionText = requiredValue('commission_rate');
        final commissionRate = commissionText.isEmpty ? 0.0 : double.tryParse(commissionText);
        if (requiredValue('sales_person_name').isEmpty ||
            commissionRate == null || !commissionRate.isFinite ||
            commissionRate < 0 || commissionRate > 100) {
          throw const FormatException('اسم مندوب المبيعات ونسبة العمولة يجب أن تكون بين 0 و100.');
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
      const identityFields = {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'customer_group_name', 'territory_name', 'sales_person_name', 'price_list_name'};
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
    if (saved is! core.Map<String, dynamic> || (saved['name']?.toString().isNotEmpty != true)) {
      throw Exception('لم يؤكد ERPNext حفظ السجل؛ أعد تحميل القائمة قبل المتابعة.');
    }
    if (id != null && id.isNotEmpty && saved['name'] != id) {
      throw Exception('تغيرت هوية السجل بعد الحفظ؛ أوقف العملية وراجع ERPNext.');
    }
    return core.Map<String, dynamic>.from(saved);
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
    _guestMode = false;
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
    if (_guestMode) {
      return _ApiResponse(403, jsonEncode({
        'message': 'أنت في وضع الضيف المحلي دون خادم. سجّل الدخول إلى ERPNext للوصول إلى بيانات الشركة.'
      }));
    }
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

  Future<_ApiResponse> _sendJson(String method, String path, core.Map<String, dynamic> payload) async {
    if (_guestMode) {
      return _ApiResponse(403, jsonEncode({'message': 'وضع الضيف للقراءة فقط؛ سجّل الدخول لتنفيذ هذه العملية.'}));
    }
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

  core.Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is core.Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  String _message(core.Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }


  Future<List<core.Map<String, dynamic>>> fetchJournalEntryDrafts({required String company, int start = 0, String? search}) async {
    final normalized = company.trim();
    if (normalized.isEmpty) throw const FormatException('حدد الشركة أولاً.');
    final query = search?.trim() ?? '';
    final uri = buildResourcePageUri(baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'posting_date', 'company', 'total_debit', 'total_credit', 'user_remark', 'docstatus'],
      filters: [['company', '=', normalized], ['docstatus', 'in', [0, 1]],],
      orFilters: query.isEmpty ? null : [['name', 'like', '%$query%'], ['user_remark', 'like', '%$query%']],
      orderBy: 'modified desc, name desc', start: start, pageLength: 50);
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل القيود اليومية.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة القيود اليومية غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>().where((row) => row['company'] == normalized && (row['docstatus'] == 0 || row['docstatus'] == 1))
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchJournalEntryDocument(String name) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
    final response = await _send('GET', '/api/resource/Journal%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل القيد اليومي.'));
    final doc = data['data'];
    if (doc is! core.Map<String, dynamic> || doc['name'] != id || doc['doctype'] != 'Journal Entry') throw const FormatException('هوية القيد المسترجع غير مطابقة.');
    return core.Map<String, dynamic>.from(doc);
  }

  Future<core.Map<String, dynamic>> saveJournalEntryDraft({String? name, required String company, required String postingDate, required String remark, required List<core.Map<String, dynamic>> accounts}) async {
    final normalizedCompany = company.trim();
    final date = DateTime.tryParse(postingDate.trim());
    if (normalizedCompany.isEmpty || date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) throw const FormatException('الشركة وتاريخ القيد بصيغة YYYY-MM-DD حقول مطلوبة.');
    if (accounts.length < 2) throw const FormatException('القيد يتطلب حسابين على الأقل.');
    final companyResponse = await _send('GET', '/api/resource/Company/' + Uri.encodeComponent(normalizedCompany));
    final companyData = _decode(companyResponse.body);
    final companyDoc = companyData['data'];
    if (companyResponse.statusCode < 200 || companyResponse.statusCode >= 300 || companyDoc is! core.Map<String, dynamic>) throw Exception(_message(companyData, 'تعذر التحقق من الشركة.'));
    final currency = companyDoc['default_currency']?.toString() ?? '';
    if (currency.isEmpty) throw const FormatException('عملة الشركة غير محددة في ERPNext.');
    final clean = <core.Map<String, dynamic>>[];
    var debitTotal = 0.0, creditTotal = 0.0;
    var hasForeignCurrency = false;
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
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 || accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != normalizedCompany || accountDoc['is_group'] == 1 || accountDoc['is_group'] == true || accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) throw FormatException('الحساب ' + account + ' غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
      final accountCurrency = accountDoc['account_currency']?.toString().trim().isNotEmpty == true
          ? accountDoc['account_currency'].toString().trim()
          : currency;
      final requestedRate = row['exchange_rate'] is num
          ? (row['exchange_rate'] as num).toDouble()
          : double.tryParse(row['exchange_rate']?.toString() ?? '') ?? (accountCurrency == currency ? 1.0 : 0.0);
      if (accountCurrency == currency && requestedRate != 1.0 && requestedRate != 0.0) {
        throw FormatException('سعر تحويل حساب العملة الأساسية يجب أن يساوي 1: $account');
      }
      final exchangeRate = accountCurrency == currency ? 1.0 : requestedRate;
      if (!exchangeRate.isFinite || exchangeRate <= 0) {
        throw FormatException('أدخل سعر تحويل موجباً للحساب $account بعملة $accountCurrency.');
      }
      if (accountCurrency != currency) hasForeignCurrency = true;
      final costCenter = row['cost_center']?.toString().trim() ?? '';
      if (costCenter.isNotEmpty) {
        final costResponse = await _send('GET',
          '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
        final costData = _decode(costResponse.body);
        final costDoc = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            costDoc is! core.Map<String, dynamic> || costDoc['company'] != normalizedCompany ||
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
            projectDoc is! core.Map<String, dynamic> || projectDoc['company'] != normalizedCompany) {
          throw FormatException('المشروع $project غير صالح أو لا يتبع الشركة المحددة.');
        }
      }
      final partyType = row['party_type']?.toString().trim() ?? '';
      final party = row['party']?.toString().trim() ?? '';
      if (partyType.isEmpty != party.isEmpty) {
        throw FormatException('يجب تحديد نوع الطرف والطرف معاً للحساب $account.');
      }
      final referenceType = row['reference_type']?.toString().trim() ?? '';
      final referenceName = row['reference_name']?.toString().trim() ?? '';
      if (referenceType.isEmpty != referenceName.isEmpty) {
        throw FormatException('يجب تحديد نوع المرجع ورقمه معاً للحساب $account.');
      }
      final againstType = row['against_voucher_type']?.toString().trim() ?? '';
      final againstVoucher = row['against_voucher']?.toString().trim() ?? '';
      if (againstType.isEmpty != againstVoucher.isEmpty) {
        throw FormatException('يجب تحديد نوع المستند المقابل ورقمه معاً للحساب $account.');
      }
      final baseDebit = debit * exchangeRate;
      final baseCredit = credit * exchangeRate;
      if (!baseDebit.isFinite || !baseCredit.isFinite) {
        throw FormatException('قيمة التحويل للحساب $account تتجاوز النطاق المسموح.');
      }
      debitTotal += baseDebit;
      creditTotal += baseCredit;
      clean.add({
        'doctype': 'Journal Entry Account',
        'account': account,
        'account_currency': accountCurrency,
        'exchange_rate': exchangeRate,
        'debit_in_account_currency': debit,
        'credit_in_account_currency': credit,
        'debit': baseDebit,
        'credit': baseCredit,
        if (costCenter.isNotEmpty) 'cost_center': costCenter,
        if (project.isNotEmpty) 'project': project,
        if (partyType.isNotEmpty) 'party_type': partyType,
        if (party.isNotEmpty) 'party': party,
        if (referenceType.isNotEmpty) 'reference_type': referenceType,
        if (referenceName.isNotEmpty) 'reference_name': referenceName,
        if (againstType.isNotEmpty) 'against_voucher_type': againstType,
        if (againstVoucher.isNotEmpty) 'against_voucher': againstVoucher,
        if (row['is_advance'] != null) 'is_advance': row['is_advance'],
      });
    }
    if (debitTotal <= 0 || (debitTotal - creditTotal).abs() > 0.005) throw FormatException('القيد غير متوازن. المدين ' + debitTotal.toStringAsFixed(2) + ' والدائن ' + creditTotal.toStringAsFixed(2) + '.');
    final id = name?.trim() ?? '';
    final payload = <String, dynamic>{'doctype': 'Journal Entry', 'voucher_type': 'Journal Entry', 'company': normalizedCompany, 'posting_date': postingDate.trim(), 'user_remark': remark.trim(), 'multi_currency': hasForeignCurrency ? 1 : 0, 'accounts': clean};
    if (id.isEmpty) {
      final response = await _sendJson('POST', '/api/resource/Journal%20Entry', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء مسودة القيد.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Journal Entry' || created['name'] is! String || created['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext إنشاء مسودة القيد.');
      return core.Map<String, dynamic>.from(created);
    }
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != normalizedCompany || current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': {...current, ...payload, 'name': id}});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة القيد.'));
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Journal Entry' || saved['name'] != id || saved['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext تحديث مسودة القيد.');
    return core.Map<String, dynamic>.from(saved);
  }

  Future<core.Map<String, dynamic>> submitJournalEntry(String name, {required String company}) async {
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
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Journal Entry' || submitted['name'] != id || submitted['docstatus'] != 1) throw const FormatException('لم يؤكد ERPNext ترحيل القيد اليومي.');
    return core.Map<String, dynamic>.from(submitted);
  }


  Future<List<core.Map<String, dynamic>>> fetchPayrollCostCenters({
    required String company,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض مراكز التكلفة.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Cost Center',
      fields: const ['name', 'cost_center_name', 'company', 'is_group', 'disabled'],
      filters: [
        ['company', '=', normalizedCompany],
        ['is_group', '=', 0],
        ['disabled', '=', 0],
      ],
      orderBy: 'lft asc, name asc',
      pageLength: 500,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مراكز التكلفة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة مراكز التكلفة غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany &&
            row['is_group'] != 1 && row['is_group'] != true)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchPayrollEntries({
    required String company,
    int start = 0,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض دورات الرواتب.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Payroll Entry',
      fields: const [
        'name', 'company', 'posting_date', 'start_date', 'end_date',
        'payroll_frequency', 'status', 'docstatus', 'number_of_employees',
        'salary_slips_created', 'salary_slips_submitted', 'currency',
      ],
      filters: [['company', '=', normalizedCompany]],
      orderBy: 'modified desc, name desc',
      start: start,
      pageLength: 50,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل دورات الرواتب. تأكد من تثبيت HRMS وصلاحية Payroll Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة دورات الرواتب غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchPayrollEntryDocument({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل دورة الرواتب.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> || document['doctype'] != 'Payroll Entry' ||
        document['name'] != id || document['company'] != normalizedCompany) {
      throw const FormatException('دورة الرواتب لا تتبع الشركة المحددة أو أن هويتها غير مطابقة.');
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<List<core.Map<String, dynamic>>> fetchPayrollSalarySlips({
    required String payrollEntry,
    required String company,
  }) async {
    final entry = payrollEntry.trim(), normalizedCompany = company.trim();
    if (entry.isEmpty || normalizedCompany.isEmpty) throw const FormatException('دورة الرواتب والشركة مطلوبتان.');
    final collected = <core.Map<String, dynamic>>[];
    var start = 0;
    while (collected.length < 10000) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Salary Slip',
        fields: const [
          'name', 'employee', 'employee_name', 'company', 'start_date', 'end_date',
          'gross_pay', 'total_deduction', 'net_pay', 'currency', 'docstatus', 'status',
          'payroll_entry',
        ],
        filters: [
          ['company', '=', normalizedCompany],
          ['payroll_entry', '=', entry],
        ],
        orderBy: 'employee_name asc, name asc',
        start: start,
        pageLength: 500,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل كشوف الرواتب لدورة الرواتب المحددة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة كشوف الرواتب غير متوقعة.');
      final page = rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany && row['payroll_entry'] == entry)
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
      collected.addAll(page);
      if (rows.length < 500) return collected;
      start += rows.length;
    }
    throw const FormatException('تجاوزت كشوف الرواتب حد العرض الآمن 10,000 سجل؛ صفّ الدورة في ERPNext قبل المتابعة.');
  }

  Future<core.Map<String, dynamic>> createPayrollEntryDraft({
    required String company,
    required String postingDate,
    required String startDate,
    required String endDate,
    required String payrollFrequency,
    required String costCenter,
    required String currency,
    required String payrollPayableAccount,
    required double exchangeRate,
    String? paymentAccount,
    String? bankAccount,
  }) async {
    final cleanCompany = company.trim();
    final cleanCostCenter = costCenter.trim();
    final cleanCurrency = currency.trim();
    final payable = payrollPayableAccount.trim();
    final frequency = payrollFrequency.trim();
    String validDate(String value, String label) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value.trim()) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value.trim();
    }
    final posting = validDate(postingDate, 'تاريخ الترحيل');
    final from = validDate(startDate, 'بداية فترة الرواتب');
    final to = validDate(endDate, 'نهاية فترة الرواتب');
    if (cleanCompany.isEmpty || cleanCostCenter.isEmpty || cleanCurrency.isEmpty ||
        payable.isEmpty || !const {'Monthly', 'Fortnightly', 'Bimonthly', 'Weekly', 'Daily'}.contains(frequency) ||
        !exchangeRate.isFinite || exchangeRate <= 0 || from.compareTo(to) > 0) {
      throw const FormatException('أكمل بيانات دورة الرواتب وتأكد من الفترة والتكرار وسعر الصرف.');
    }
    Future<core.Map<String, dynamic>> readSetupDoc(String doctype, String name, String failure) async {
      final response = await _send(
        'GET',
        '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, failure));
      }
      final row = data['data'];
      if (row is! core.Map<String, dynamic> || row['doctype'] != doctype || row['name'] != name) {
        throw FormatException('بيانات $doctype غير مطابقة.');
      }
      return row;
    }
    final setup = await Future.wait([
      readSetupDoc('Cost Center', cleanCostCenter, 'تعذر التحقق من مركز التكلفة.'),
      readSetupDoc('Account', payable, 'تعذر التحقق من حساب الرواتب المستحقة.'),
    ]);
    final costCenterDoc = setup[0], payableDoc = setup[1];
    if (costCenterDoc['company'] != cleanCompany || (costCenterDoc['disabled'] == 1 || costCenterDoc['disabled'] == true) ||
        costCenterDoc['is_group'] == 1 || costCenterDoc['is_group'] == true) {
      throw const FormatException('مركز التكلفة يجب أن يكون مركز ترحيل نشطاً تابعاً للشركة المحددة.');
    }
    if (payableDoc['company'] != cleanCompany || (payableDoc['disabled'] == 1 || payableDoc['disabled'] == true) ||
        payableDoc['is_group'] == 1 || payableDoc['is_group'] == true ||
        payableDoc['account_type'] != 'Payable') {
      throw const FormatException('حساب الرواتب يجب أن يكون حساب Payable نشطاً وقابلاً للترحيل ضمن الشركة.');
    }
    final bankId = bankAccount?.trim() ?? '';
    final paymentId = paymentAccount?.trim() ?? '';
    if (bankId.isNotEmpty || paymentId.isNotEmpty) {
      if (bankId.isEmpty || paymentId.isEmpty) {
        throw const FormatException('يجب تحديد حساب البنك وحساب الأستاذ المرتبط به معاً.');
      }
      final bank = await readSetupDoc('Bank Account', bankId, 'تعذر التحقق من حساب البنك.');
      if (bank['company'] != cleanCompany || bank['disabled'] == 1 || bank['disabled'] == true ||
          (bank['is_company_account'] != 1 && bank['is_company_account'] != true) || bank['account'] != paymentId) {
        throw const FormatException('حساب البنك أو حساب الأستاذ المرتبط به لا يتبع الشركة أو غير صالح للصرف.');
      }
      final paymentDoc = await readSetupDoc('Account', paymentId, 'تعذر التحقق من حساب الدفع.');
      if (paymentDoc['company'] != cleanCompany || paymentDoc['disabled'] == 1 || paymentDoc['disabled'] == true ||
          paymentDoc['is_group'] == 1 || paymentDoc['is_group'] == true ||
          !{'Bank', 'Cash'}.contains(paymentDoc['account_type'])) {
        throw const FormatException('حساب الدفع يجب أن يكون حساب بنك أو نقد نشطاً وقابلاً للترحيل ضمن الشركة.');
      }
    }
    final doc = <String, dynamic>{
      'doctype': 'Payroll Entry',
      'company': cleanCompany,
      'posting_date': posting,
      'start_date': from,
      'end_date': to,
      'payroll_frequency': frequency,
      'salary_slip_based_on_timesheet': 0,
      'cost_center': cleanCostCenter,
      'currency': cleanCurrency,
      'exchange_rate': exchangeRate,
      'payroll_payable_account': payable,
      if (paymentAccount?.trim().isNotEmpty == true) 'payment_account': paymentAccount!.trim(),
      if (bankAccount?.trim().isNotEmpty == true) 'bank_account': bankAccount!.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Payroll%20Entry', doc);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext إنشاء دورة الرواتب. تحقق من إعدادات HRMS والحسابات.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Payroll Entry' ||
        created['company'] != cleanCompany || created['docstatus'] != 0 ||
        (created['name']?.toString().trim().isEmpty ?? true)) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مسودة دورة الرواتب الصحيحة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> _runPayrollEntryMethod({
    required String name,
    required String company,
    required String method,
    bool requireSubmitted = false,
  }) async {
    const allowedMethods = {'fill_employee_details', 'submit_salary_slips', 'make_bank_entry'};
    if (!allowedMethods.contains(method)) throw ArgumentError.value(method, 'method', 'إجراء رواتب غير مدعوم.');
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة دورة الرواتب.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Payroll Entry' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        (requireSubmitted ? current['docstatus'] != 1 : current['docstatus'] != 0)) {
      throw const FormatException('تم رفض الإجراء لأن دورة الرواتب لا تتبع الشركة أو أن حالتها غير مناسبة.');
    }
    final result = await _sendJson('POST', '/api/method/run_doc_method', {
      'docs': jsonEncode(current),
      'method': method,
    });
    final resultData = _decode(result.body);
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw Exception(_message(resultData, 'تعذر تنفيذ إجراء الرواتب $method.'));
    }
    final docs = resultData['docs'];
    if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
      throw const FormatException('لم يُرجع ERPNext دورة رواتب محدثة بعد تنفيذ الإجراء.');
    }
    final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
    if (updated['doctype'] != 'Payroll Entry' || updated['name'] != id ||
        updated['company'] != normalizedCompany) {
      throw const FormatException('استجابة إجراء الرواتب لا تطابق دورة الرواتب المطلوبة.');
    }
    updated['_mobile_method_message'] = resultData['message'];
    return updated;
  }

  Future<core.Map<String, dynamic>> fillPayrollEmployees({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final updated = await _runPayrollEntryMethod(
      name: id, company: normalizedCompany, method: 'fill_employee_details',
    );
    final employees = updated['employees'];
    if (employees is! List || employees.isEmpty) {
      throw const FormatException('لم يعثر HRMS على موظفين لهم تعيين هيكل راتب نشط مطابق للفترة والحسابات.');
    }
    final saveResponse = await _sendJson(
      'PUT',
      '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id),
      {
        'employees': employees,
        'number_of_employees': updated['number_of_employees'] ?? employees.length,
      },
    );
    final saveData = _decode(saveResponse.body);
    if (saveResponse.statusCode < 200 || saveResponse.statusCode >= 300) {
      throw Exception(_message(saveData, 'تعذر حفظ قائمة الموظفين في مسودة دورة الرواتب.'));
    }
    final saved = saveData['data'];
    if (saved is! core.Map<String, dynamic> || saved['name'] != id ||
        saved['company'] != normalizedCompany || saved['employees'] is! List ||
        (saved['employees'] as List).length != employees.length) {
      throw const FormatException('لم يؤكد ERPNext حفظ قائمة الموظفين الصحيحة في دورة الرواتب.');
    }
    final unmarked = updated['_mobile_method_message'];
    if (unmarked is List && unmarked.isNotEmpty) {
      throw FormatException('لا يمكن ترحيل الرواتب قبل استكمال تسجيل الحضور لبعض الموظفين. عدد الحالات غير المكتملة: ${unmarked.length}.');
    }
    return {...core.Map<String, dynamic>.from(saved), 'mobile_unmarked_attendance': unmarked ?? const []};
  }

  Future<core.Map<String, dynamic>> submitPayrollSalarySlips({
    required String name,
    required String company,
  }) async {
    final updated = await _runPayrollEntryMethod(
      name: name, company: company, method: 'submit_salary_slips', requireSubmitted: true,
    );
    final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
    final pending = slips.where((row) => row['docstatus'] == 0).length;
    return {...updated, 'mobile_pending_salary_slips': pending};
  }

  Future<core.Map<String, dynamic>> createPayrollBankEntry({
    required String name,
    required String company,
  }) async {
    final document = await fetchPayrollEntryDocument(name: name, company: company);
    if ((document['payment_account']?.toString().trim().isEmpty ?? true) ||
        (document['bank_account']?.toString().trim().isEmpty ?? true)) {
      throw const FormatException('حدد حساب الدفع وحساب البنك في دورة الرواتب قبل إنشاء قيد الصرف.');
    }
    final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
    if (slips.isEmpty || slips.any((row) => row['docstatus'] != 1)) {
      throw const FormatException('لا يمكن إنشاء قيد الصرف قبل اعتماد جميع كشوف الرواتب المرتبطة بالدورة.');
    }
    return _runPayrollEntryMethod(
      name: name, company: company, method: 'make_bank_entry', requireSubmitted: true,
    );
  }

  Future<core.Map<String, dynamic>> submitPayrollEntry({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    await fillPayrollEmployees(name: id, company: normalizedCompany);
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة دورة الرواتب قبل الترحيل.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Payroll Entry' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || current['employees'] is! List ||
        (current['employees'] as List).isEmpty) {
      throw const FormatException('لا يمكن ترحيل دورة الرواتب قبل تحميل الموظفين والتحقق من الشركة والحالة.');
    }
    final responseSubmit = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final submitData = _decode(responseSubmit.body);
    if (responseSubmit.statusCode < 200 || responseSubmit.statusCode >= 300) {
      throw Exception(_message(submitData, 'رفض ERPNext ترحيل دورة الرواتب وإنشاء كشوف الرواتب.'));
    }
    final submitted = submitData['message'];
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Payroll Entry' ||
        submitted['name'] != id || submitted['company'] != normalizedCompany ||
        submitted['docstatus'] != 1) {
      throw const FormatException('لم يؤكد ERPNext ترحيل دورة الرواتب.');
    }
    return core.Map<String, dynamic>.from(submitted);
  }

  // HR mobile access is intentionally allow-listed. ERPNext permissions,
  // employee/company rules and document validation remain authoritative.
  static const core.Map<String, List<String>> _hrFields = {
    'Employee': ['name', 'employee_name', 'company', 'department', 'designation',
      'status', 'date_of_joining', 'reports_to', 'cell_number', 'prefered_email'],
    'Attendance': ['name', 'employee', 'employee_name', 'company', 'attendance_date',
      'status', 'docstatus', 'leave_type'],
    'Leave Application': ['name', 'employee', 'employee_name', 'company', 'leave_type',
      'from_date', 'to_date', 'total_leave_days', 'status', 'docstatus',
      'posting_date', 'description'],
    'Expense Claim': ['name', 'employee', 'employee_name', 'company', 'posting_date',
      'total_claimed_amount', 'total_sanctioned_amount', 'approval_status',
      'status', 'docstatus'],
    'Salary Slip': ['name', 'employee', 'employee_name', 'company', 'start_date',
      'end_date', 'gross_pay', 'total_deduction', 'net_pay', 'currency', 'status', 'docstatus'],
  };

  Future<core.Map<String, dynamic>> fetchSalarySlipDetails({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('رقم كشف الراتب والشركة مطلوبان.');
    }
    final response = await _send(
      'GET', '/api/resource/Salary%20Slip/' + Uri.encodeComponent(id),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل كشف الراتب.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Salary Slip' || document['name'] != id ||
        document['company'] != normalizedCompany) {
      throw const FormatException('كشف الراتب لا ينتمي إلى الشركة المحددة أو أن هويته غير مطابقة.');
    }
    for (final field in const ['earnings', 'deductions']) {
      final rows = document[field];
      if (rows != null && rows is! List) {
        throw FormatException('تفاصيل $field في كشف الراتب غير متوقعة.');
      }
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<List<core.Map<String, dynamic>>> fetchHrRecords({
    required String doctype,
    String? company,
    int start = 0,
    String? search,
  }) async {
    final fields = _hrFields[doctype];
    if (fields == null) throw ArgumentError.value(doctype, 'doctype', 'نوع سجل موارد بشرية غير مدعوم.');
    final normalizedCompany = company?.trim() ?? '';
    final query = search?.trim() ?? '';
    final searchFields = switch (doctype) {
      'Employee' => const ['name', 'employee_name', 'department', 'designation'],
      'Attendance' => const ['name', 'employee', 'employee_name'],
      'Leave Application' => const ['name', 'employee', 'employee_name', 'leave_type'],
      'Expense Claim' => const ['name', 'employee', 'employee_name'],
      'Salary Slip' => const ['name', 'employee', 'employee_name', 'payroll_frequency'],
      _ => const <String>[],
    };
    final filters = <List<dynamic>>[];
    if (normalizedCompany.isNotEmpty) filters.add(['company', '=', normalizedCompany]);
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: doctype,
      fields: fields,
      filters: filters,
      orFilters: query.isEmpty ? null : searchFields.map((field) => [field, 'like', '%$query%']).toList(),
      orderBy: doctype == 'Employee' ? 'employee_name asc, name asc' : 'modified desc, name desc',
      start: start,
      pageLength: 50,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل سجلات $doctype. تحقق من صلاحية القراءة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة سجلات $doctype غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .where((row) => normalizedCompany.isEmpty || row['company'] == normalizedCompany)
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> _fetchHrEmployee(String employee, String company) async {
    final id = employee.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('حدد الموظف والشركة.');
    final response = await _send('GET', '/api/resource/Employee/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر التحقق من الموظف. تحقق من صلاحية قراءة Employee.'));
    }
    final row = data['data'];
    if (row is! core.Map<String, dynamic> || row['name'] != id ||
        row['company'] != normalizedCompany || row['status'] == 'Left' ||
        row['status'] == 'Inactive') {
      throw const FormatException('الموظف غير موجود أو لا يتبع الشركة المحددة أو غير نشط.');
    }
    return core.Map<String, dynamic>.from(row);
  }

  Future<core.Map<String, dynamic>> createAttendanceDraft({
    required String employee,
    required String company,
    required String attendanceDate,
    required String status,
    String? leaveType,
  }) async {
    final date = DateTime.tryParse(attendanceDate.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
      throw const FormatException('تاريخ الحضور يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
      throw const FormatException('حالة الحضور المحددة غير مدعومة.');
    }
    if (status == 'On Leave' && (leaveType?.trim().isEmpty ?? true)) {
      throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
    }
    await _fetchHrEmployee(employee, company);
    final duplicateUri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Attendance',
      fields: const ['name', 'docstatus'],
      filters: [
        ['employee', '=', employee.trim()],
        ['attendance_date', '=', attendanceDate.trim()],
      ],
      orderBy: 'modified desc',
      pageLength: 10,
    );
    final duplicateResponse = await _sendUri('GET', duplicateUri);
    final duplicateData = _decode(duplicateResponse.body);
    if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
      throw Exception(_message(duplicateData, 'تعذر التحقق من سجلات الحضور السابقة.'));
    }
    final existingAttendance = duplicateData['data'];
    if (existingAttendance is! List) throw const FormatException('استجابة التحقق من تكرار الحضور غير متوقعة.');
    if (existingAttendance.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('يوجد سجل حضور أو مسودة لهذا الموظف في التاريخ المحدد.');
    }
    final payload = <String, dynamic>{
      'doctype': 'Attendance',
      'employee': employee.trim(),
      'company': company.trim(),
      'attendance_date': attendanceDate.trim(),
      'status': status,
      if (leaveType?.trim().isNotEmpty ?? false) 'leave_type': leaveType!.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Attendance', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة الحضور.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Attendance' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مسودة الحضور المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> createLeaveApplicationDraft({
    required String employee,
    required String company,
    required String leaveType,
    required String fromDate,
    required String toDate,
    String description = '',
  }) async {
    final from = DateTime.tryParse(fromDate.trim()), to = DateTime.tryParse(toDate.trim());
    if (from == null || to == null ||
        from.toIso8601String().substring(0, 10) != fromDate.trim() ||
        to.toIso8601String().substring(0, 10) != toDate.trim() ||
        to.isBefore(from)) {
      throw const FormatException('تحقق من تاريخ بداية الإجازة ونهايتها بصيغة YYYY-MM-DD.');
    }
    if (leaveType.trim().isEmpty) throw const FormatException('حدد نوع الإجازة.');
    await _fetchHrEmployee(employee, company);
    final payload = <String, dynamic>{
      'doctype': 'Leave Application',
      'employee': employee.trim(),
      'company': company.trim(),
      'leave_type': leaveType.trim(),
      'from_date': fromDate.trim(),
      'to_date': toDate.trim(),
      'description': description.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Leave%20Application', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء طلب الإجازة.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Application' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء طلب الإجازة المطابق.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<List<core.Map<String, dynamic>>> fetchExpenseClaimTypes() async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Expense Claim Type',
      fields: const ['name', 'default_account', 'disabled'],
      filters: const [['disabled', '=', 0]],
      orderBy: 'name asc',
      pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أنواع المصروفات.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة أنواع المصروفات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .where((row) => row['disabled'] != 1 && row['disabled'] != true)
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> createExpenseClaimDraft({
    required String employee,
    required String company,
    required String postingDate,
    required String expenseType,
    required String amount,
    required String account,
    String description = '',
    String costCenter = '',
  }) async {
    final date = DateTime.tryParse(postingDate.trim());
    final value = double.tryParse(amount.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (value == null || !value.isFinite || value <= 0) {
      throw const FormatException('أدخل مبلغ مصروف أكبر من صفر.');
    }
    if (expenseType.trim().isEmpty) {
      throw const FormatException('نوع المصروف حقل مطلوب.');
    }
    await _fetchHrEmployee(employee, company);
    final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(expenseType.trim()));
    final typeData = _decode(typeResponse.body);
    final type = typeData['data'];
    if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
        type is! core.Map<String, dynamic> || type['name'] != expenseType.trim() ||
        type['disabled'] == 1 || type['disabled'] == true) {
      throw const FormatException('نوع المصروف غير موجود أو معطل في ERPNext.');
    }
    final configuredAccount = type['default_account']?.toString().trim() ?? '';
    final selectedAccount = configuredAccount.isNotEmpty ? configuredAccount : account.trim();
    if (selectedAccount.isEmpty) throw const FormatException('حدد حساب المصروف أو استخدم نوعاً له حساب افتراضي.');
    final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(selectedAccount));
    final accountData = _decode(accountResponse.body);
    final accountDoc = accountData['data'];
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
        accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != company.trim() ||
        accountDoc['is_group'] == 1 || accountDoc['is_group'] == true ||
        accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) {
      throw const FormatException('حساب المصروف غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
    }
    final normalizedCostCenter = costCenter.trim();
    if (normalizedCostCenter.isNotEmpty) {
      final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(normalizedCostCenter));
      final costData = _decode(costResponse.body);
      final costDoc = costData['data'];
      if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
          costDoc is! core.Map<String, dynamic> || costDoc['company'] != company.trim() ||
          costDoc['is_group'] == 1 || costDoc['is_group'] == true ||
          costDoc['disabled'] == 1 || costDoc['disabled'] == true) {
        throw const FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة المحددة.');
      }
    }
    final payload = <String, dynamic>{
      'doctype': 'Expense Claim',
      'employee': employee.trim(),
      'company': company.trim(),
      'posting_date': postingDate.trim(),
      'expenses': [{
        'doctype': 'Expense Claim Detail',
        'expense_type': expenseType.trim(),
        'expense_date': postingDate.trim(),
        'amount': value,
        'default_account': selectedAccount,
        'description': description.trim(),
        if (normalizedCostCenter.isNotEmpty) 'cost_center': normalizedCostCenter,
      }],
    };
    final response = await _sendJson('POST', '/api/resource/Expense%20Claim', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }


  Future<core.Map<String, dynamic>> createExpenseClaimDraftLines({
    required String employee,
    required String company,
    required String postingDate,
    required List<core.Map<String, dynamic>> expenses,
  }) async {
    final date = DateTime.tryParse(postingDate.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (expenses.isEmpty || expenses.length > 50) {
      throw const FormatException('أضف بند مصروف واحداً على الأقل، وبحد أقصى 50 بنداً.');
    }
    await _fetchHrEmployee(employee, company);
    final typeCache = <String, core.Map<String, dynamic>>{};
    final accountCache = <String, core.Map<String, dynamic>>{};
    final costCenterCache = <String, core.Map<String, dynamic>>{};
    final cleanExpenses = <core.Map<String, dynamic>>[];
    for (var index = 0; index < expenses.length; index++) {
      final row = expenses[index];
      final typeName = row['expense_type']?.toString().trim() ?? '';
      final amount = row['amount'] is num
          ? (row['amount'] as num).toDouble()
          : double.tryParse(row['amount']?.toString() ?? '') ?? double.nan;
      if (typeName.isEmpty || !amount.isFinite || amount <= 0) {
        throw FormatException('تحقق من نوع ومبلغ بند المصروف رقم ${index + 1}.');
      }
      var type = typeCache[typeName];
      if (type == null) {
        final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(typeName));
        final typeData = _decode(typeResponse.body);
        final rawType = typeData['data'];
        if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
            rawType is! core.Map<String, dynamic> || rawType['name'] != typeName ||
            rawType['disabled'] == 1 || rawType['disabled'] == true) {
          throw FormatException('نوع المصروف غير موجود أو معطل: $typeName');
        }
        type = core.Map<String, dynamic>.from(rawType);
        typeCache[typeName] = type;
      }
      final configuredAccount = type['default_account']?.toString().trim() ?? '';
      final account = configuredAccount.isNotEmpty
          ? configuredAccount
          : (row['default_account']?.toString().trim() ?? '');
      if (account.isEmpty) throw FormatException('حدد حساباً لبند المصروف: $typeName');
      var accountDoc = accountCache[account];
      if (accountDoc == null) {
        final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(account));
        final accountData = _decode(accountResponse.body);
        final rawAccount = accountData['data'];
        if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
            rawAccount is! core.Map<String, dynamic> || rawAccount['company'] != company.trim() ||
            rawAccount['is_group'] == 1 || rawAccount['is_group'] == true ||
            rawAccount['disabled'] == 1 || rawAccount['disabled'] == true) {
          throw FormatException('حساب المصروف غير صالح أو لا يتبع الشركة: $account');
        }
        accountDoc = core.Map<String, dynamic>.from(rawAccount);
        accountCache[account] = accountDoc;
      }
      final costCenter = row['cost_center']?.toString().trim() ?? '';
      if (costCenter.isNotEmpty && !costCenterCache.containsKey(costCenter)) {
        final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
        final costData = _decode(costResponse.body);
        final rawCostCenter = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            rawCostCenter is! core.Map<String, dynamic> || rawCostCenter['company'] != company.trim() ||
            rawCostCenter['is_group'] == 1 || rawCostCenter['is_group'] == true ||
            rawCostCenter['disabled'] == 1 || rawCostCenter['disabled'] == true) {
          throw FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة: $costCenter');
        }
        costCenterCache[costCenter] = core.Map<String, dynamic>.from(rawCostCenter);
      }
      cleanExpenses.add({
        'doctype': 'Expense Claim Detail',
        'expense_type': typeName,
        'expense_date': postingDate.trim(),
        'amount': amount,
        'default_account': account,
        'description': row['description']?.toString().trim() ?? '',
        if (costCenter.isNotEmpty) 'cost_center': costCenter,
      });
    }
    final response = await _sendJson('POST', '/api/resource/Expense%20Claim', {
      'doctype': 'Expense Claim',
      'employee': employee.trim(),
      'company': company.trim(),
      'posting_date': postingDate.trim(),
      'expenses': cleanExpenses,
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات متعددة البنود.'));
    }
    final created = data['data'];
    final savedExpenses = created is core.Map<String, dynamic> ? created['expenses'] : null;
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim() ||
        savedExpenses is! List || savedExpenses.length != cleanExpenses.length) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات متعددة البنود المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<List<core.Map<String, dynamic>>> fetchWorkflowTransitions({
    required String doctype,
    required String name,
    required String company,
  }) async {
    final type = doctype.trim(), id = name.trim(), normalizedCompany = company.trim();
    if (type.isEmpty || id.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('نوع المستند ورقمه والشركة مطلوبة لجلب إجراءات الموافقة.');
    }
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(type) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر قراءة المستند قبل جلب إجراءات الموافقة.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != type ||
        current['name'] != id || current['company'] != normalizedCompany) {
      throw const FormatException('المستند لا ينتمي إلى الشركة المحددة أو أن هويته غير مطابقة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/frappe.model.workflow.get_transitions')
        .replace(queryParameters: {'doc': jsonEncode(current)});
    final transitionsResponse = await _sendUri('GET', uri);
    final transitionsData = _decode(transitionsResponse.body);
    if (transitionsResponse.statusCode < 200 || transitionsResponse.statusCode >= 300) {
      throw Exception(_message(transitionsData, 'تعذر جلب إجراءات سير العمل من ERPNext.'));
    }
    final rows = transitionsData['message'];
    if (rows is! List) throw const FormatException('استجابة إجراءات سير العمل غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>().where((row) =>
      row['action'] is String && (row['action'] as String).trim().isNotEmpty
    ).map((row) => core.Map<String, dynamic>.from(row)).toList();
  }

  Future<core.Map<String, dynamic>> applyWorkflowAction({
    required String doctype,
    required String name,
    required String company,
    required String action,
  }) async {
    final type = doctype.trim(), id = name.trim();
    final normalizedCompany = company.trim(), selectedAction = action.trim();
    if (type.isEmpty || id.isEmpty || normalizedCompany.isEmpty || selectedAction.isEmpty) {
      throw const FormatException('نوع المستند ورقمه والشركة وإجراء الموافقة مطلوبة.');
    }
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(type) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة المستند قبل تنفيذ إجراء الموافقة.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != type ||
        current['name'] != id || current['company'] != normalizedCompany) {
      throw const FormatException('تم رفض الإجراء لأن هوية المستند أو الشركة غير مطابقة.');
    }
    final transitionsUri = Uri.parse('$_baseUrl/api/method/frappe.model.workflow.get_transitions')
        .replace(queryParameters: {'doc': jsonEncode(current)});
    final transitionsResponse = await _sendUri('GET', transitionsUri);
    final transitionsData = _decode(transitionsResponse.body);
    if (transitionsResponse.statusCode < 200 || transitionsResponse.statusCode >= 300) {
      throw Exception(_message(transitionsData, 'تعذر التحقق من صلاحية إجراء سير العمل.'));
    }
    final transitions = transitionsData['message'];
    if (transitions is! List || !transitions.whereType<core.Map>().any((row) =>
        row['action']?.toString() == selectedAction)) {
      throw const FormatException('الإجراء غير متاح لهذا المستند أو للمستخدم الحالي.');
    }
    final appliedResponse = await _sendJson(
      'POST', '/api/method/frappe.model.workflow.apply_workflow',
      {'doc': current, 'action': selectedAction},
    );
    final appliedData = _decode(appliedResponse.body);
    if (appliedResponse.statusCode < 200 || appliedResponse.statusCode >= 300) {
      throw Exception(_message(appliedData, 'رفض ERPNext تنفيذ إجراء سير العمل.'));
    }
    final updated = appliedData['message'];
    if (updated is! core.Map<String, dynamic> || updated['doctype'] != type ||
        updated['name'] != id || updated['company'] != normalizedCompany) {
      throw const FormatException('لم يؤكد ERPNext تنفيذ الإجراء على المستند الصحيح.');
    }
    return core.Map<String, dynamic>.from(updated);
  }

  Future<core.Map<String, dynamic>> submitHrDraft({
    required String doctype,
    required String name,
    required String company,
  }) async {
    if (doctype != 'Attendance' && doctype != 'Leave Application' && doctype != 'Expense Claim') {
      throw ArgumentError.value(doctype, 'doctype', 'ترحيل هذا النوع من سجلات الموارد البشرية غير مدعوم.');
    }
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم المستند والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة المستند قبل الترحيل.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != doctype ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || (current['employee']?.toString().isEmpty ?? true)) {
      throw const FormatException('تم رفض الترحيل لأن هوية المستند أو الشركة أو حالته تغيرت.');
    }
    final submittedResponse = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final submittedData = _decode(submittedResponse.body);
    if (submittedResponse.statusCode < 200 || submittedResponse.statusCode >= 300) {
      throw Exception(_message(submittedData, 'تعذر ترحيل مستند الموارد البشرية.'));
    }
    final submitted = submittedData['message'];
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != doctype ||
        submitted['name'] != id || submitted['company'] != normalizedCompany ||
        submitted['docstatus'] != 1) {
      throw const FormatException('لم يؤكد ERPNext ترحيل المستند المطلوب.');
    }
    return core.Map<String, dynamic>.from(submitted);
  }



  Future<core.Map<String, dynamic>> cancelJournalEntry(String name, {required String company}) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم القيد والشركة مطلوبان.');
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != normalizedCompany || current['docstatus'] != 1) {
      throw const FormatException('يمكن إلغاء القيد المرحّل التابع للشركة المحددة فقط.');
    }
    final reversalRemark = 'قيد عكسي للقيد $id';
    final reversalUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'docstatus'],
      filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
      orderBy: 'modified desc', pageLength: 20,
    );
    final reversalResponse = await _sendUri('GET', reversalUri);
    final reversalData = _decode(reversalResponse.body);
    if (reversalResponse.statusCode < 200 || reversalResponse.statusCode >= 300) {
      throw Exception(_message(reversalData, 'تعذر التحقق من وجود قيد عكسي قبل الإلغاء.'));
    }
    final reversalRows = reversalData['data'];
    if (reversalRows is! List) throw const FormatException('استجابة التحقق من القيد العكسي غير متوقعة.');
    if (reversalRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('ألغِ أو احسم القيد العكسي أولاً قبل إلغاء القيد الأصلي.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إلغاء القيد. تحقق من صلاحية الإلغاء والقيود المرتبطة.'));
    }
    final canceled = data['message'];
    if (canceled is! core.Map<String, dynamic> || canceled['doctype'] != 'Journal Entry' ||
        canceled['name'] != id || canceled['docstatus'] != 2) {
      throw const FormatException('لم يؤكد ERPNext إلغاء القيد.');
    }
    return core.Map<String, dynamic>.from(canceled);
  }

  Future<core.Map<String, dynamic>> createJournalEntryReversalDraft({
    required String name,
    required String company,
    required String postingDate,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final date = DateTime.tryParse(postingDate.trim());
    if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
        date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('رقم القيد والشركة وتاريخ العكس الصحيح مطلوبة.');
    }
    final original = await fetchJournalEntryDocument(id);
    if (original['doctype'] != 'Journal Entry' || original['company'] != normalizedCompany ||
        original['docstatus'] != 1 || original['accounts'] is! List) {
      throw const FormatException('يمكن إنشاء قيد عكسي من قيد مرحّل تابع للشركة المحددة فقط.');
    }
    final reversalRemark = 'قيد عكسي للقيد $id';
    final existingUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'docstatus', 'user_remark'],
      filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
      orderBy: 'modified desc', pageLength: 20,
    );
    final existingResponse = await _sendUri('GET', existingUri);
    final existingData = _decode(existingResponse.body);
    if (existingResponse.statusCode < 200 || existingResponse.statusCode >= 300) {
      throw Exception(_message(existingData, 'تعذر التحقق من وجود قيد عكسي سابق.'));
    }
    final existingRows = existingData['data'];
    if (existingRows is! List) throw const FormatException('استجابة التحقق من القيود العكسية غير متوقعة.');
    if (existingRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('يوجد بالفعل قيد عكسي غير ملغى لهذا القيد.');
    }
    final reversedLines = <core.Map<String, dynamic>>[];
    for (final raw in (original['accounts'] as List).whereType<core.Map<String, dynamic>>()) {
      reversedLines.add({
        'account': raw['account']?.toString() ?? '',
        'debit': raw['credit_in_account_currency'] ?? raw['credit'] ?? 0,
        'credit': raw['debit_in_account_currency'] ?? raw['debit'] ?? 0,
        'exchange_rate': raw['exchange_rate'] ?? 1,
        'cost_center': raw['cost_center'] ?? '',
        'project': raw['project'] ?? '',
        'party_type': raw['party_type'] ?? '',
        'party': raw['party'] ?? '',
        'reference_type': raw['reference_type'] ?? '',
        'reference_name': raw['reference_name'] ?? '',
        'against_voucher_type': raw['against_voucher_type'] ?? '',
        'against_voucher': raw['against_voucher'] ?? '',
        'is_advance': raw['is_advance'],
      });
    }
    return saveJournalEntryDraft(
      company: normalizedCompany,
      postingDate: postingDate.trim(),
      remark: reversalRemark,
      accounts: reversedLines,
    );
  }

  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
).hasMatch(lowerName) ||
        fileBytes.length > 15 * 1024 * 1024) {
      throw const FormatException('اختر ملف CSV أو Excel أو MT940 صالحاً، بحجم لا يتجاوز 15 ميجابايت.');
    }
    final accountResponse = await _send('GET',
      '/api/resource/Bank%20Account/' + Uri.encodeComponent(account));
    final accountData = _decode(accountResponse.body);
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300) {
      throw Exception(_message(accountData, 'تعذر التحقق من الحساب البنكي.'));
    }
    final bankAccountDoc = accountData['data'];
    if (bankAccountDoc is! core.Map<String, dynamic> ||
        bankAccountDoc['name'] != account || bankAccountDoc['company'] != cleanCompany ||
        (bankAccountDoc['bank']?.toString().trim().isNotEmpty ?? false) == false) {
      throw const FormatException('الحساب البنكي لا يتبع الشركة أو لا يرتبط ببنك مهيأ.');
    }
    final createdResponse = await _sendJson('POST', '/api/resource/Bank%20Statement%20Import', {
      'doctype': 'Bank Statement Import', 'company': cleanCompany,
      'bank_account': account, 'reference_doctype': 'Bank Transaction',
      'import_type': 'Insert New Records', 'submit_after_import': 1, 'mute_emails': 1,
    });
    final createdData = _decode(createdResponse.body);
    if (createdResponse.statusCode < 200 || createdResponse.statusCode >= 300) {
      throw Exception(_message(createdData, 'تعذر إنشاء مستند استيراد كشف البنك. تحقق من صلاحية Bank Statement Import.'));
    }
    final created = createdData['data'];
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Bank Statement Import' ||
        (created['name']?.toString().isEmpty ?? true) ||
        created['company'] != cleanCompany || created['bank_account'] != account) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مستند استيراد كشف البنك.');
    }
    final importId = created['name'].toString();
    final boundary = '----ERPNextMobile' + DateTime.now().microsecondsSinceEpoch.toString();
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/upload_file'));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    if (_cookies.isNotEmpty) {
      request.headers.set(HttpHeaders.cookieHeader,
        _cookies.entries.map((entry) => entry.key + '=' + entry.value).join('; '));
      final csrf = _cookies['csrf_token'];
      if (csrf != null && csrf.isNotEmpty) request.headers.set('X-Frappe-CSRF-Token', csrf);
    }
    void field(String name, String value) {
      request.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="$name"\r\n\r\n$value\r\n'));
    }
    field('is_private', '1');
    field('doctype', 'Bank Statement Import');
    field('docname', importId);
    field('fieldname', 'import_file');
    request.add(utf8.encode('--$boundary\r\nContent-Disposition: form-data; name="file"; filename="$fileName"\r\nContent-Type: application/octet-stream\r\n\r\n'));
    request.add(fileBytes);
    request.add(utf8.encode('\r\n--$boundary--\r\n'));
    final uploadResponse = await request.close().timeout(const Duration(seconds: 90));
    final uploadBody = await utf8.decoder.bind(uploadResponse).join().timeout(const Duration(seconds: 90));
    final uploadData = _decode(uploadBody);
    _captureCookies(uploadResponse);
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw Exception(_message(uploadData, 'فشل رفع ملف كشف البنك إلى ERPNext.'));
    }
    final uploaded = uploadData['message'];
    final fileUrl = uploaded is core.Map<String, dynamic> ? uploaded['file_url']?.toString() : null;
    if (fileUrl == null || fileUrl.isEmpty) {
      throw const FormatException('رفع الملف لم يُرجع رابط ملف صالحاً.');
    }
    final attachResponse = await _sendJson('PUT',
      '/api/resource/Bank%20Statement%20Import/' + Uri.encodeComponent(importId),
      {'import_file': fileUrl});
    final attachData = _decode(attachResponse.body);
    if (attachResponse.statusCode < 200 || attachResponse.statusCode >= 300) {
      throw Exception(_message(attachData, 'تم رفع الملف لكن تعذر ربطه بمستند الاستيراد.'));
    }
    final previewResponse = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.get_preview_from_template',
      {'data_import': importId, 'import_file': fileUrl});
    final previewData = _decode(previewResponse.body);
    if (previewResponse.statusCode < 200 || previewResponse.statusCode >= 300) {
      throw Exception(_message(previewData, 'رفع الملف ناجح، لكن ERPNext لم يتمكن من قراءة المعاينة. راجع إعداد مطابقة أعمدة البنك.'));
    }
    final preview = previewData['message'];
    if (preview is! core.Map<String, dynamic>) {
      throw const FormatException('لم يُرجع ERPNext معاينة صالحة لملف كشف البنك.');
    }
    final columns = preview['columns'];
    final columnNames = columns is List
        ? columns.map((column) => column is core.Map ? column['content']?.toString().toLowerCase().trim() ?? '' : '').toList()
        : <String>[];
    if (!columnNames.contains('bank account') && !columnNames.contains('bank_account')) {
      throw const FormatException('الملف لا يحتوي عمود Bank Account؛ لم يبدأ الاستيراد.');
    }
    return {'name': importId, 'file_url': fileUrl, 'preview': preview,
      'warnings': preview['warnings'] is List ? preview['warnings'] : const [],
      'columns': columnNames};
  }

  Future<core.Map<String, dynamic>> startBankStatementImport(String importName) async {
    final id = importName.trim();
    if (id.isEmpty) throw const FormatException('رقم مستند الاستيراد غير موجود.');
    final response = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.form_start_import',
      {'data_import': id});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext بدء استيراد كشف البنك.'));
    }
    final job = data['message'];
    if (job is! String || job.isEmpty) throw const FormatException('لم يؤكد ERPNext جدولة مهمة استيراد كشف البنك.');
    return {'name': id, 'job_id': job, 'status': 'Queued'};
  }

  Future<core.Map<String, dynamic>> fetchBankStatementImportStatus(String importName) async {
    final id = importName.trim();
    if (id.isEmpty) throw const FormatException('رقم مستند الاستيراد غير موجود.');
    final response = await _sendJson('POST',
      '/api/method/erpnext.accounts.doctype.bank_statement_import.bank_statement_import.get_import_status',
      {'docname': id});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر قراءة حالة استيراد كشف البنك.'));
    final status = data['message'];
    if (status is! core.Map<String, dynamic>) throw const FormatException('استجابة حالة الاستيراد غير صحيحة.');
    return core.Map<String, dynamic>.from(status);
  }

  Future<core.Map<String, dynamic>> saveBankStatementClosingBalance({
    required String bankAccount, required String company,
    required String statementDate, required double closingBalance,
    String? importName,
  }) async {
    final account = bankAccount.trim(), cleanCompany = company.trim();
    final date = _validateLedgerDate(statementDate, 'تاريخ رصيد كشف البنك');
    if (account.isEmpty || cleanCompany.isEmpty || date == null ||
        !closingBalance.isFinite || (importName?.trim().isEmpty ?? false)) {
      throw const FormatException('بيانات رصيد كشف البنك الختامي غير مكتملة أو غير صحيحة.');
    }
    final accountResponse = await _send('GET',
      '/api/resource/Bank%20Account/' + Uri.encodeComponent(account));
    final accountData = _decode(accountResponse.body);
    final bank = accountData['data'];
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
        bank is! core.Map<String, dynamic> || bank['company'] != cleanCompany || bank['name'] != account) {
      throw const FormatException('الحساب البنكي لا يطابق الشركة؛ لم يُحفظ الرصيد.');
    }
    final content = jsonEncode({
      'kind': 'bank_statement_closing_balance_v1', 'bank_account': account,
      'company': cleanCompany, 'statement_date': date,
      'closing_balance': closingBalance,
      'currency': bank['account_currency'] ?? bank['currency'],
      'bank_statement_import': importName?.trim(),
    });
    final response = await _sendJson('POST', '/api/resource/Comment', {
      'doctype': 'Comment', 'comment_type': 'Info',
      'reference_doctype': 'Bank Account', 'reference_name': account, 'content': content,
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ رصيد الكشف كسجل دائم في سجل الحساب البنكي.'));
    final saved = data['data'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Comment' ||
        saved['reference_doctype'] != 'Bank Account' || saved['reference_name'] != account) {
      throw const FormatException('لم يؤكد ERPNext حفظ سجل رصيد كشف البنك.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<core.Map<String, dynamic>?> fetchLatestBankStatementClosingBalance({
    required String bankAccount, required String company,
  }) async {
    final account = bankAccount.trim(), cleanCompany = company.trim();
    if (account.isEmpty || cleanCompany.isEmpty) throw const FormatException('حدد الحساب البنكي والشركة.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Comment',
      fields: const ['name', 'content', 'creation', 'reference_doctype', 'reference_name'],
      filters: [
        ['reference_doctype', '=', 'Bank Account'],
        ['reference_name', '=', account], ['comment_type', '=', 'Info'],
      ],
      orderBy: 'creation desc', pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل أرصدة كشف البنك المحفوظة.'));
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة أرصدة كشف البنك غير صحيحة.');
    for (final raw in rows) {
      if (raw is! core.Map<String, dynamic>) continue;
      try {
        final decoded = jsonDecode(raw['content']?.toString() ?? '');
        if (decoded is core.Map<String, dynamic> &&
            decoded['kind'] == 'bank_statement_closing_balance_v1' &&
            decoded['bank_account'] == account && decoded['company'] == cleanCompany) {
          return {...decoded, 'comment_name': raw['name'], 'creation': raw['creation']};
        }
      } catch (_) {}
    }
    return null;
  }

  Future<core.Map<String, dynamic>> fetchBankReconciliationBalances({
    required String bankAccount,
    required String company,
    required String date,
  }) async {
    final account = bankAccount.trim(), normalizedCompany = company.trim();
    final parsed = DateTime.tryParse(date.trim());
    if (account.isEmpty || normalizedCompany.isEmpty || parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date.trim()) {
      throw const FormatException('حدد الحساب البنكي والشركة وتاريخ كشف صحيحاً.');
    }
    final accountResponse = await _send(
      'GET', '/api/resource/Bank%20Account/' + Uri.encodeComponent(account),
    );
    final accountData = _decode(accountResponse.body);
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300) {
      throw Exception(_message(accountData, 'تعذر التحقق من الحساب البنكي.'));
    }
    final bank = accountData['data'];
    if (bank is! core.Map<String, dynamic> || bank['name'] != account ||
        bank['company'] != normalizedCompany) {
      throw const FormatException('الحساب البنكي لا يتبع الشركة المحددة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_account_balance')
        .replace(queryParameters: {
      'bank_account': account,
      'company': normalizedCompany,
      'till_date': date.trim(),
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل رصيد الحساب البنكي من ERPNext.'));
    }
    final balance = double.tryParse(data['message']?.toString() ?? '');
    if (balance == null || !balance.isFinite) {
      throw const FormatException('لم يرجع ERPNext رصيداً بنكياً صالحاً.');
    }
    return {
      'bank_account': account,
      'company': normalizedCompany,
      'date': date.trim(),
      'system_balance': balance,
    };
  }


  Future<List<core.Map<String, dynamic>>> fetchBankTransactions({
    required String bankAccount,
    required String company,
    String? fromDate,
    String? toDate,
    int start = 0,
  }) async {
    final account = bankAccount.trim(), normalizedCompany = company.trim();
    if (account.isEmpty || normalizedCompany.isEmpty || start < 0) {
      throw const FormatException('حدد الشركة والحساب البنكي وبداية صفحة صحيحة.');
    }
    String? dateValue(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value;
    }
    final from = dateValue(fromDate, 'تاريخ البداية');
    final to = dateValue(toDate, 'تاريخ النهاية');
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
    }
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Bank Transaction',
      fields: const [
        'name', 'date', 'deposit', 'withdrawal', 'currency', 'description',
        'transaction_type', 'bank_account', 'company', 'allocated_amount',
        'unallocated_amount', 'reference_number', 'party_type', 'party',
        'status', 'docstatus',
      ],
      filters: [
        ['bank_account', '=', account],
        ['company', '=', normalizedCompany],
        ['docstatus', '=', 1],
        ['unallocated_amount', '>', 0],
        if (from != null) ['date', '>=', from],
        if (to != null) ['date', '<=', to],
      ],
      orderBy: 'date asc, name asc',
      start: start,
      pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل حركات الحساب البنكي.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة حركات الحساب البنكي غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['bank_account'] == account &&
            row['company'] == normalizedCompany && row['docstatus'] == 1)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchLinkedBankVouchers({
    required String transactionName,
    required String bankAccount,
    required String company,
    String? fromDate,
    String? toDate,
  }) async {
    final id = transactionName.trim(), account = bankAccount.trim();
    final normalizedCompany = company.trim();
    if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('بيانات حركة البنك والشركة غير مكتملة.');
    }
    String? normalizeDate(String? raw, String label) {
      final value = raw?.trim() ?? '';
      if (value.isEmpty) return null;
      final parsed = DateTime.tryParse(value);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value;
    }
    final from = normalizeDate(fromDate, 'تاريخ البداية');
    final to = normalizeDate(toDate, 'تاريخ النهاية');
    if (from != null && to != null && from.compareTo(to) > 0) {
      throw const FormatException('تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
    }
    final transactionResponse = await _send(
      'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
    );
    final transactionData = _decode(transactionResponse.body);
    if (transactionResponse.statusCode < 200 || transactionResponse.statusCode >= 300) {
      throw Exception(_message(transactionData, 'تعذر إعادة قراءة حركة البنك قبل المطابقة.'));
    }
    final transaction = transactionData['data'];
    if (transaction is! core.Map<String, dynamic> ||
        transaction['name'] != id || transaction['bank_account'] != account ||
        transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
      throw const FormatException('حركة البنك لا تتبع الحساب أو الشركة المحددة أو أنها غير مرحّلة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.get_linked_payments')
        .replace(queryParameters: {
      'bank_transaction_name': id,
      'document_types': jsonEncode(['payment_entry', 'journal_entry', 'sales_invoice', 'purchase_invoice']),
      if (from != null) 'from_date': from,
      if (to != null) 'to_date': to,
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب المستندات المرشحة لمطابقة حركة البنك.'));
    }
    final rows = data['message'];
    if (rows is! List) throw const FormatException('استجابة المستندات المرشحة غير متوقعة.');
    const allowed = {'Payment Entry', 'Journal Entry', 'Sales Invoice', 'Purchase Invoice'};
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => allowed.contains(row['doctype']) &&
            (row['name']?.toString().trim().isNotEmpty ?? false))
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> reconcileBankTransaction({
    required String transactionName,
    required String bankAccount,
    required String company,
    required List<core.Map<String, dynamic>> vouchers,
    String? fromDate,
    String? toDate,
  }) async {
    final id = transactionName.trim(), account = bankAccount.trim();
    final normalizedCompany = company.trim();
    if (id.isEmpty || account.isEmpty || normalizedCompany.isEmpty || vouchers.isEmpty) {
      throw const FormatException('حدد حركة البنك ومستنداً واحداً على الأقل للمطابقة.');
    }
    final freshTransactionResponse = await _send(
      'GET', '/api/resource/Bank%20Transaction/' + Uri.encodeComponent(id),
    );
    final freshData = _decode(freshTransactionResponse.body);
    if (freshTransactionResponse.statusCode < 200 || freshTransactionResponse.statusCode >= 300) {
      throw Exception(_message(freshData, 'تعذر التحقق من حركة البنك قبل التسوية.'));
    }
    final transaction = freshData['data'];
    if (transaction is! core.Map<String, dynamic> ||
        transaction['name'] != id || transaction['bank_account'] != account ||
        transaction['company'] != normalizedCompany || transaction['docstatus'] != 1) {
      throw const FormatException('تم رفض التسوية لأن حركة البنك لا تتبع الشركة والحساب المحددين.');
    }
    final unallocated = double.tryParse(transaction['unallocated_amount']?.toString() ?? '') ?? 0;
    final freshCandidates = await fetchLinkedBankVouchers(
      transactionName: id,
      bankAccount: account,
      company: normalizedCompany,
      fromDate: fromDate,
      toDate: toDate,
    );
    final candidateByKey = <String, core.Map<String, dynamic>>{
      for (final row in freshCandidates)
        '${row['doctype']}|${row['name']}': row,
    };
    final selected = <core.Map<String, dynamic>>[];
    final seen = <String>{};
    var total = 0.0;
    const allowed = {
      'Payment Entry',
      'Journal Entry',
      'Sales Invoice',
      'Purchase Invoice',
    };
    for (final row in vouchers) {
      final doctype = row['payment_doctype']?.toString() ?? '';
      final name = row['payment_name']?.toString().trim() ?? '';
      final amount = double.tryParse(row['amount']?.toString() ?? '') ?? 0;
      final key = '$doctype|$name';
      final candidate = candidateByKey[key];
      final candidateAmount = double.tryParse(candidate?['paid_amount']?.toString() ?? '') ?? 0;
      if (!allowed.contains(doctype) || name.isEmpty || !seen.add(key) ||
          !amount.isFinite || amount <= 0 || candidate == null ||
          amount > candidateAmount + 0.000001) {
        throw const FormatException('توجد بيانات مستند أو مبلغ غير صالح أو لم يعد مرشحاً للمطابقة في ERPNext.');
      }
      total += amount;
      selected.add({'payment_doctype': doctype, 'payment_name': name, 'amount': amount});
    }
    if (total > unallocated + 0.000001) {
      throw const FormatException('إجمالي المطابقة يتجاوز المبلغ غير المخصص في حركة البنك.');
    }
    final response = await _sendJson(
      'POST',
      '/api/method/erpnext.accounts.doctype.bank_reconciliation_tool.bank_reconciliation_tool.reconcile_vouchers',
      {'bank_transaction_name': id, 'vouchers': jsonEncode(selected)},
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext مطابقة حركة البنك.'));
    }
    final updated = data['message'];
    if (updated is! core.Map<String, dynamic> || updated['name'] != id ||
        updated['bank_account'] != account || updated['company'] != normalizedCompany) {
      throw const FormatException('لم يؤكد ERPNext تحديث حركة البنك الصحيحة.');
    }
    return core.Map<String, dynamic>.from(updated);
  }

  Future<core.Map<String, dynamic>> _runPaymentReconciliationMethod({
    required core.Map<String, dynamic> document,
    required String method,
    core.Map<String, dynamic>? args,
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
    if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
      throw Exception('لم يُرجع ERPNext مستند تسوية محدثاً بعد تنفيذ $method.');
    }
    final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
    if (updated['doctype'] != 'Payment Reconciliation' ||
        updated['company'] != document['company'] ||
        updated['party_type'] != document['party_type'] ||
        updated['party'] != document['party'] ||
        updated['receivable_payable_account'] != document['receivable_payable_account']) {
      throw const FormatException('تغيرت هوية مستند التسوية في استجابة ERPNext.');
    }
    return updated;
  }

  Future<core.Map<String, dynamic>> fetchUnreconciledPaymentEntries({
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
      'invoices': <core.Map<String, dynamic>>[],
      'payments': <core.Map<String, dynamic>>[],
      'allocation': <core.Map<String, dynamic>>[],
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

  Future<core.Map<String, dynamic>> allocatePaymentReconciliation(
    core.Map<String, dynamic> document,
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

  Future<core.Map<String, dynamic>> reconcilePaymentAllocations(
    core.Map<String, dynamic> document,
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

  Future<List<core.Map<String, dynamic>>> fetchSupplierPayments({int start = 0, String? search}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchDraftSupplierPayments({
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
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['docstatus'] == 0 &&
            row['payment_type'] == 'Pay' && row['party_type'] == 'Supplier')
        .toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDraftDocument(String name) =>
      _fetchPaymentEntryDraft(
        name,
        paymentType: 'Pay',
        partyType: 'Supplier',
      );

  Future<core.Map<String, dynamic>> submitSupplierPaymentDraft(
    core.Map<String, dynamic> draft,
  ) async {
    if (draft['doctype'] != 'Payment Entry' ||
        draft['payment_type'] != 'Pay' ||
        draft['party_type'] != 'Supplier') {
      throw const FormatException('المستند ليس مسودة سند صرف مورد صحيحة.');
    }
    return _submitMobileDocument(draft, 'Payment Entry');
  }

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDocument(String name) async {
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
    if (document is! core.Map<String, dynamic> ||
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
    return rows.whereType<core.Map<String, dynamic>>().map(ErpPurchaseInvoice.fromJson).toList(growable: false);
  }

  /// Loads bounded, submitted sales invoices for the mobile sales dashboard.
  /// Currency totals are aggregated by the caller; this method never converts
  /// or combines amounts from different currencies.
  Future<List<core.Map<String, dynamic>>> fetchSalesDashboardInvoices({
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
    final rows = <core.Map<String, dynamic>>[];
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
        if (row is! core.Map<String, dynamic> ||
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
  Future<List<core.Map<String, dynamic>>> fetchOutstandingInvoices({
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
    final rows = <core.Map<String, dynamic>>[];
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
      final validRows = page.whereType<core.Map<String, dynamic>>().toList();
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
  Future<core.Map<String, dynamic>> runStandardReport({
    required String reportName,
    required core.Map<String, dynamic> filters,
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
    if (message is! core.Map) {
      throw Exception('استجابة تقرير $reportName من ERPNext غير متوقعة.');
    }
    final result = core.Map<String, dynamic>.from(message);
    if (result['columns'] is! List || result['result'] is! List) {
      throw Exception('لم يُرجع ERPNext أعمدة وبيانات صالحة لتقرير $reportName.');
    }
    return result;
  }


  // Update only explicitly supported Employee profile fields after re-reading
  // the record and confirming company ownership. ERPNext permissions remain authoritative.
  Future<core.Map<String, dynamic>> createEmployee({
    required String company,
    required String employeeName,
    required String dateOfBirth,
    required String dateOfJoining,
    required String gender,
    String department = '',
    String designation = '',
    String cellNumber = '',
    String email = '',
  }) async {
    final normalizedCompany = company.trim();
    final displayName = employeeName.trim();
    final birthText = dateOfBirth.trim();
    final joiningText = dateOfJoining.trim();
    final birth = DateTime.tryParse(birthText);
    final joining = DateTime.tryParse(joiningText);
    if (normalizedCompany.isEmpty || displayName.isEmpty ||
        birth == null || joining == null ||
        birth.toIso8601String().substring(0, 10) != birthText ||
        joining.toIso8601String().substring(0, 10) != joiningText ||
        !joining.isAfter(birth)) {
      throw const FormatException('الشركة والاسم وتاريخا الميلاد والتعيين الصحيحة مطلوبة، ويجب أن يكون التعيين بعد الميلاد.');
    }
    if (!const {'Male', 'Female', 'Other'}.contains(gender)) {
      throw const FormatException('حدد الجنس من الخيارات المدعومة.');
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isNotEmpty) {
      final parts = normalizedEmail.split('@');
      if (parts.length != 2 || parts.first.isEmpty ||
          !parts.last.contains('.') || parts.last.startsWith('.') ||
          parts.last.endsWith('.')) {
        throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
      }
    }
    final nameParts = displayName.split(' ').where((part) => part.trim().isNotEmpty).toList(growable: false);
    if (nameParts.isEmpty) throw const FormatException('اسم الموظف مطلوب.');
    final payload = <String, dynamic>{
      'doctype': 'Employee',
      'first_name': nameParts.first,
      if (nameParts.length > 1) 'last_name': nameParts.skip(1).join(' '),
      'company': normalizedCompany,
      'date_of_birth': birthText,
      'date_of_joining': joiningText,
      'gender': gender,
      'status': 'Active',
      if (department.trim().isNotEmpty) 'department': department.trim(),
      if (designation.trim().isNotEmpty) 'designation': designation.trim(),
      if (cellNumber.trim().isNotEmpty) 'cell_number': cellNumber.trim(),
      if (normalizedEmail.isNotEmpty) 'prefered_email': normalizedEmail,
    };
    final response = await _sendJson('POST', '/api/resource/Employee', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء الموظف. تحقق من الحقول الإلزامية وصلاحية Employee في ERPNext.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Employee' ||
        created['name'] is! String || created['name'].toString().isEmpty ||
        created['company'] != normalizedCompany ||
        created['employee_name'] != displayName ||
        created['docstatus'] != 0) {
      throw const FormatException('لم يؤكد ERPNext إنشاء سجل الموظف المطابق.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> updateEmployeeProfile({
    required String employee,
    required String company,
    required String employeeName,
    String department = '',
    String designation = '',
    String cellNumber = '',
    String email = '',
    String status = 'Active',
  }) async {
    final id = employee.trim(), normalizedCompany = company.trim();
    final displayName = employeeName.trim();
    if (id.isEmpty || normalizedCompany.isEmpty || displayName.isEmpty) {
      throw const FormatException('رقم الموظف والشركة والاسم حقول مطلوبة.');
    }
    final normalizedEmail = email.trim();
    if (normalizedEmail.isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      throw const FormatException('عنوان البريد الإلكتروني غير صحيح.');
    }
    if (!const {'Active', 'Inactive', 'Left', 'Suspended'}.contains(status)) {
      throw const FormatException('حالة الموظف المحددة غير مدعومة.');
    }
    final current = await _fetchHrEmployee(id, normalizedCompany);
    final payload = <String, dynamic>{
      ...current,
      'employee_name': displayName,
      'department': department.trim().isEmpty ? null : department.trim(),
      'designation': designation.trim().isEmpty ? null : designation.trim(),
      'cell_number': cellNumber.trim(),
      'prefered_email': normalizedEmail,
      'status': status,
    };
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحديث بيانات الموظف. تحقق من صلاحية Employee.'));
    }
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Employee' ||
        saved['name'] != id || saved['company'] != normalizedCompany ||
        saved['employee_name'] != displayName || saved['status'] != status) {
      throw const FormatException('لم يؤكد ERPNext حفظ بيانات الموظف المطابقة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<core.Map<String, dynamic>> updateAttendanceDraft({
    required String name,
    required String company,
    required String attendanceDate,
    required String status,
    String leaveType = '',
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final date = DateTime.tryParse(attendanceDate.trim());
    if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
        date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
      throw const FormatException('رقم سجل الحضور والشركة والتاريخ الصحيح مطلوبة.');
    }
    if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
      throw const FormatException('حالة الحضور المحددة غير مدعومة.');
    }
    final response = await _send('GET', '/api/resource/Attendance/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة سجل الحضور.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Attendance' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || current['employee'] is! String) {
      throw const FormatException('يمكن تصحيح مسودات الحضور التابعة للشركة المحددة فقط.');
    }
    await _fetchHrEmployee(current['employee'].toString(), normalizedCompany);
    if (status == 'On Leave' && leaveType.trim().isEmpty) {
      throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
    }
    final duplicateUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Attendance',
      fields: const ['name', 'docstatus'],
      filters: [
        ['employee', '=', current['employee']],
        ['attendance_date', '=', attendanceDate.trim()],
      ],
      orderBy: 'attendance_date asc',
      pageLength: 20,
    );
    final duplicateResponse = await _sendUri('GET', duplicateUri);
    final duplicateData = _decode(duplicateResponse.body);
    if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
      throw Exception(_message(duplicateData, 'تعذر التحقق من تكرار الحضور.'));
    }
    final duplicates = duplicateData['data'];
    if (duplicates is! List || duplicates.whereType<core.Map<String, dynamic>>()
        .any((row) => row['name'] != id && row['docstatus'] != 2)) {
      throw const FormatException('يوجد سجل حضور آخر للموظف في التاريخ المحدد.');
    }
    final payload = <String, dynamic>{
      ...current,
      'attendance_date': attendanceDate.trim(),
      'status': status,
      'leave_type': status == 'On Leave' ? leaveType.trim() : null,
    };
    final savedResponse = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final savedData = _decode(savedResponse.body);
    if (savedResponse.statusCode < 200 || savedResponse.statusCode >= 300) {
      throw Exception(_message(savedData, 'تعذر حفظ تصحيح الحضور.'));
    }
    final saved = savedData['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Attendance' ||
        saved['name'] != id || saved['company'] != normalizedCompany ||
        saved['docstatus'] != 0 || saved['attendance_date'] != attendanceDate.trim()) {
      throw const FormatException('لم يؤكد ERPNext حفظ مسودة الحضور المصححة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  Future<List<core.Map<String, dynamic>>> fetchLeaveTypes() async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Leave Type',
      fields: const ['name', 'is_lwp', 'allow_negative', 'max_days_allowed', 'is_carry_forward'],
      orderBy: 'name asc', pageLength: 200,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أنواع الإجازات. تحقق من صلاحية Leave Type.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة أنواع الإجازات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> createLeaveType({
    required String name,
    bool isLeaveWithoutPay = false,
    bool allowNegative = false,
    double? maxDaysAllowed,
  }) async {
    final normalized = name.trim();
    if (normalized.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
    if (maxDaysAllowed != null &&
        (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
      throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
    }
    final payload = <String, dynamic>{
      'doctype': 'Leave Type',
      'leave_type_name': normalized,
      'is_lwp': isLeaveWithoutPay ? 1 : 0,
      'allow_negative': allowNegative ? 1 : 0,
      if (maxDaysAllowed != null) 'max_days_allowed': maxDaysAllowed,
    };
    final response = await _sendJson('POST', '/api/resource/Leave%20Type', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء نوع الإجازة. تحقق من صلاحية إدارة Leave Type.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Type' ||
        created['name'] is! String || created['name'].toString().isEmpty) {
      throw const FormatException('لم يؤكد ERPNext إنشاء نوع الإجازة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> updateLeaveType({
    required String name,
    required bool isLeaveWithoutPay,
    required bool allowNegative,
    double? maxDaysAllowed,
  }) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('اسم نوع الإجازة مطلوب.');
    if (maxDaysAllowed != null &&
        (!maxDaysAllowed.isFinite || maxDaysAllowed <= 0)) {
      throw const FormatException('الحد الأقصى للإجازة يجب أن يكون أكبر من صفر.');
    }
    final currentResponse = await _send(
      'GET', '/api/resource/Leave%20Type/' + Uri.encodeComponent(id),
    );
    final currentData = _decode(currentResponse.body);
    if (currentResponse.statusCode < 200 || currentResponse.statusCode >= 300) {
      throw Exception(_message(currentData, 'تعذر إعادة قراءة نوع الإجازة قبل التعديل.'));
    }
    final current = currentData['data'];
    if (current is! core.Map<String, dynamic> ||
        current['doctype'] != 'Leave Type' || current['name'] != id) {
      throw const FormatException('هوية نوع الإجازة المسترجع غير مطابقة.');
    }
    final payload = <String, dynamic>{
      ...current,
      'is_lwp': isLeaveWithoutPay ? 1 : 0,
      'allow_negative': allowNegative ? 1 : 0,
      'max_days_allowed': maxDaysAllowed,
    };
    final response = await _sendJson(
      'POST', '/api/method/frappe.client.save', {'doc': payload},
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحديث نوع الإجازة. قد توجد قيود أو صلاحيات تمنع التعديل.'));
    }
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> ||
        saved['doctype'] != 'Leave Type' || saved['name'] != id ||
        saved['is_lwp'] != (isLeaveWithoutPay ? 1 : 0) ||
        saved['allow_negative'] != (allowNegative ? 1 : 0)) {
      throw const FormatException('لم يؤكد ERPNext حفظ إعدادات نوع الإجازة.');
    }
    return core.Map<String, dynamic>.from(saved);
  }

  static const Set<String> salesWorkflowDoctypes = {'Quotation', 'Sales Order', 'Delivery Note', 'Sales Invoice'};

  String _salesWorkflowResource(String doctype) {
    if (!salesWorkflowDoctypes.contains(doctype)) {
      throw FormatException('نوع مستند المبيعات غير مدعوم: $doctype');
    }
    return Uri.encodeComponent(doctype);
  }

  Future<List<core.Map<String, dynamic>>> fetchSalesWorkflowDocuments(
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
            .whereType<core.Map<String, dynamic>>()
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

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDocument(String name) async {
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
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim()) {
      throw const FormatException('بيانات سند القبض غير مؤكدة.');
    }
    return document;
  }

  Future<core.Map<String, dynamic>> receiveSalesInvoicePayment({
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
    if (rawDocument is! core.Map<String, dynamic> ||
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
      if (row is! core.Map<String, dynamic> ||
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
    final paymentDraft = core.Map<String, dynamic>.from(rawDocument);

    final insert = await _sendJson('POST', '/api/resource/Payment%20Entry', paymentDraft);
    final insertData = _decode(insert.body);
    if (insert.statusCode < 200 || insert.statusCode >= 300) {
      throw Exception(_message(insertData, 'تعذر حفظ سند القبض.'));
    }
    final created = insertData['data'];
    if (created is! core.Map<String, dynamic> ||
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


  Future<core.Map<String, dynamic>> createPurchaseInvoice(core.Map<String, dynamic> invoice) async {
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
    if (doc is! core.Map<String, dynamic> ||
        doc['doctype'] != 'Purchase Invoice' ||
        doc['name'] is! String ||
        doc['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة فاتورة المشتريات.');
    }
    return doc;
  }

  void _validatePurchase(core.Map<String, dynamic> doc) {
    final items = doc['items'];
    if (doc['doctype'] != 'Purchase Invoice' || doc['supplier'] is! String ||
        (doc['supplier'] as String).trim().isEmpty || doc['company'] is! String ||
        (doc['company'] as String).trim().isEmpty || items is! List || items.isEmpty) {
      throw const FormatException('حدد الشركة والمورد وأضف صنفاً واحداً على الأقل.');
    }
    doc['items'] = _cleanSerialBatchRows(items);
    for (final row in items) {
      if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
          (row['item_code'] as String).trim().isEmpty || row['qty'] is! num ||
          !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0 ||
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0 ||
          !((row['qty'] as num) * (row['rate'] as num)).isFinite) {
        throw const FormatException('تحقق من رمز الصنف والكمية والسعر، وتأكد أن إجمالي البند ضمن النطاق الرقمي.');
      }
    }
  }

  Future<core.Map<String, dynamic>> updateDraftPurchaseInvoice({
    required String invoiceName, required core.Map<String, dynamic> changes,
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
    final payload = core.Map<String, dynamic>.from(current)
      ..['supplier'] = changes['supplier']
      ..['company'] = changes['company']
      ..['posting_date'] = changes['posting_date'] ?? current['posting_date']
      ..['update_stock'] = changes['update_stock'] == true || changes['update_stock'] == 1 ? 1 : 0
      ..['items'] = changes['items'];
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': payload});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تعديل مسودة المشتريات.'));
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['name'] != invoiceName || saved['docstatus'] != 0) throw Exception('لم يتم تأكيد حفظ المسودة.');
    return saved;
  }

  Future<core.Map<String, dynamic>> submitPurchaseInvoice(core.Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Invoice');

  Future<core.Map<String, double>> fetchPurchaseReturnableQuantities(String invoiceName) async {
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
    if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) ||
        raw['return_against'] != invoiceName || raw['items'] is! List) {
      throw Exception('لم يؤكد ERPNext بيانات الكميات القابلة للإرجاع.');
    }
    final result = <String, double>{};
    for (final row in (raw['items'] as List).whereType<core.Map<String, dynamic>>()) {
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

  Future<core.Map<String, dynamic>> createPurchaseReturn(String invoiceName, {core.Map<String, double?>? quantitiesBySourceItem}) async {
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
    if (raw is! core.Map<String, dynamic> || raw['doctype'] != 'Purchase Invoice' ||
        (raw['is_return'] != 1 && raw['is_return'] != true) || raw['return_against'] != invoiceName ||
        raw['items'] is! List || (raw['items'] as List).isEmpty) {
      throw Exception('لم يؤكد ERPNext بيانات مرتجع المشتريات.');
    }
    final mappedItems = (raw['items'] as List).whereType<core.Map<String, dynamic>>().toList();
    if (quantitiesBySourceItem != null) {
      final selectedItems = <core.Map<String, dynamic>>[];
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
        final line = core.Map<String, dynamic>.from(mappedItems[index]);
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
    final inserted = await _sendJson('POST', '/api/resource/Purchase%20Invoice', core.Map<String, dynamic>.from(raw));
    final data = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة المرتجع.'));
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
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

  Future<core.Map<String, dynamic>> payPurchaseInvoice({
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
    if (raw is! core.Map<String, dynamic> || raw['payment_type'] != 'Pay' ||
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
      if (row is core.Map<String, dynamic> && row['reference_doctype'] == 'Purchase Invoice' &&
          row['reference_name'] == invoiceName) {
        allocated += double.tryParse(row['allocated_amount']?.toString() ?? '') ?? 0;
      }
    }
    if ((allocated - amount).abs() > 0.01) throw const FormatException('توزيع الدفعة من ERPNext لا يطابق المبلغ المطلوب.');
    final inserted = await _sendJson('POST', '/api/resource/Payment%20Entry', core.Map<String, dynamic>.from(raw));
    final insertedData = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(insertedData, 'تعذر حفظ سند الصرف.'));
    final created = insertedData['data'];
    if (created is! core.Map<String, dynamic> ||
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
      if (row is core.Map<String, dynamic> &&
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

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDraft(String name, {required String paymentType, required String partyType}) async {
    if (name.trim().isEmpty) throw const FormatException('رقم سند الدفع غير موجود.');
    final response = await _send('GET',
      '/api/resource/Payment%20Entry/' + Uri.encodeComponent(name.trim()),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مسودة سند الدفع.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Payment Entry' ||
        document['name'] != name.trim() || document['docstatus'] != 0 ||
        document['payment_type'] != paymentType ||
        document['party_type'] != partyType ||
        document['references'] is! List) {
      throw const FormatException('سند الدفع لم يعد مسودة أو أن بياناته غير صحيحة.');
    }
    return document;
  }

  Future<core.Map<String, dynamic>> _submitMobileDocument(core.Map<String, dynamic> doc, String doctype) async {
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
    if (submitted is! core.Map<String, dynamic> ||
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

  Future<core.Map<String, dynamic>> cancelPurchaseInvoice(String name) async {
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
    if (canceled is! core.Map<String, dynamic> ||
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
    if (warehouse is! core.Map<String, dynamic> ||
        warehouse['doctype'] != 'Warehouse' ||
        warehouse['name'] != normalizedWarehouse ||
        warehouse['company'] != normalizedCompany ||
        warehouse['is_group'] == 1 || warehouse['is_group'] == true ||
        warehouse['disabled'] == 1 || warehouse['disabled'] == true) {
      throw FormatException('المستودع ' + normalizedWarehouse + ' غير صالح أو لا يتبع الشركة ' + normalizedCompany + '. اختر مستودعاً فعّالاً تابعاً للشركة.');
    }
  }

  Future<void> _validateDocumentWarehouses(core.Map<String, dynamic> document) async {
    final company = document['company'];
    final items = document['items'];
    if (company is! String || company.trim().isEmpty || items is! List) return;
    final warehouses = <String>{};
    for (final row in items.whereType<core.Map<String, dynamic>>()) {
      final warehouse = row['warehouse'];
      if (warehouse is String && warehouse.trim().isNotEmpty) {
        warehouses.add(warehouse.trim());
      }
    }
    for (final warehouse in warehouses) {
      await _validateWarehouseForCompany(warehouse, company);
    }
  }

  Future<core.Map<String, dynamic>> createStockEntry({
    required String company, required String purpose, required List<core.Map<String, dynamic>> items,
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
        final item = core.Map<String, dynamic>.from(row);
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
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Stock Entry' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة حركة المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> createPurchaseReceipt(core.Map<String, dynamic> document) async {
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
      if (row is! core.Map<String, dynamic> || row['item_code'] is! String ||
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
    final sourceRowsByOrder = <String, core.Map<String, core.Map<String, dynamic>>>{};
    for (final row in items) {
      final orderName = row is core.Map<String, dynamic> ? row['purchase_order'] : null;
      final orderItemName = row is core.Map<String, dynamic> ? row['purchase_order_item'] : null;
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
      final byItem = sourceRowsByOrder.putIfAbsent(normalizedOrder, () => <String, core.Map<String, dynamic>>{});
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
      final sourceByName = <String, core.Map<String, dynamic>>{
        for (final source in sourceItems.whereType<core.Map<String, dynamic>>())
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
    final receiptWarehouses = items.map((row) => (row as core.Map<String, dynamic>)['warehouse'].toString()).toSet();
    for (final warehouse in receiptWarehouses) {
      await _validateWarehouseForCompany(warehouse, document['company'] as String);
    }
    final response = await _sendJson('POST', '/api/resource/Purchase%20Receipt', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء سند استلام المشتريات.'));
    final created = data['data'];
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Purchase Receipt' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة سند استلام المشتريات؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> submitPurchaseReceipt(core.Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Purchase Receipt');

  Future<core.Map<String, dynamic>> submitStockEntry(core.Map<String, dynamic> doc) => _submitMobileDocument(doc, 'Stock Entry');

  Future<core.Map<String, dynamic>> createStockReconciliation({
    required String company, required String warehouse, required List<core.Map<String, dynamic>> items, String? remarks,
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
    if (created is! core.Map<String, dynamic> ||
        created['doctype'] != 'Stock Reconciliation' ||
        created['name'] is! String ||
        created['docstatus'] != 0) {
      throw Exception('لم يؤكد ERPNext إنشاء مسودة تسوية المخزون؛ حدّث قائمة المستندات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<core.Map<String, dynamic>> submitStockReconciliation(core.Map<String, dynamic> doc) =>
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
    if (document is! core.Map<String, dynamic> ||
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

  Future<List<core.Map<String, dynamic>>> fetchDraftStockDocuments(String doctype, {int start = 0}) async {
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
    return rows.whereType<core.Map<String, dynamic>>().map((row) => <String, dynamic>{...row, 'doctype': doctype}).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchStockDocument(String doctype, String name) async {
    const allowed = {'Stock Entry', 'Purchase Receipt', 'Stock Reconciliation'};
    if (!allowed.contains(doctype) || name.trim().isEmpty) throw ArgumentError('نوع أو رقم مستند المخزون غير صحيح.');
    final response = await _send('GET', '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل مستند المخزون.'));
    final doc = data['data'];
    if (doc is! core.Map<String, dynamic>) throw Exception('تفاصيل مستند المخزون غير متوقعة.');
    return doc;
  }

  Future<List<core.Map<String, dynamic>>> fetchStockMovements({
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
    return rows.whereType<core.Map<String, dynamic>>().toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchInvoiceDocument(String documentType, String name) async {
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
    if (document is! core.Map<String, dynamic>) throw Exception('تفاصيل الفاتورة من ERPNext غير متوقعة.');
    return document;
  }
  Future<List<core.Map<String, dynamic>>> fetchAccountingAccounts({
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
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  // Allow-listed mobile master-data access; ERPNext remains authoritative.
  static const core.Map<String, List<String>> _masterDataFields = {
    'Item': ['name', 'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'],
    'Supplier': ['name', 'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'],
    'Customer': ['name', 'customer_name', 'customer_type', 'customer_group', 'territory',
      'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'],
    'Customer Group': ['name', 'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'],
    'Territory': ['name', 'territory_name', 'parent_territory', 'is_group', 'disabled'],
    'Sales Person': ['name', 'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'],
    'Warehouse': ['name', 'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'],
    'Item Group': ['name', 'item_group_name', 'parent_item_group', 'is_group', 'disabled'],
    'UOM': ['name', 'uom_name', 'must_be_whole_number', 'enabled'],
    'Supplier Group': ['name', 'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'],
    'Price List': ['name', 'price_list_name', 'currency', 'buying', 'selling', 'enabled'],
  };

  static const core.Map<String, Set<String>> _masterDataWritableFields = {
    'Item': {'item_code', 'item_name', 'item_group', 'stock_uom',
      'is_stock_item', 'has_serial_no', 'has_batch_no', 'has_expiry_date', 'disabled', 'uoms'},
    'Supplier': {'supplier_name', 'supplier_type', 'supplier_group',
      'country', 'tax_id', 'mobile_no', 'email_id', 'website', 'disabled'},
    'Customer': {'customer_name', 'customer_type', 'customer_group', 'territory',
      'tax_id', 'mobile_no', 'email_id', 'website', 'default_currency', 'default_price_list', 'disabled'},
    'Customer Group': {'customer_group_name', 'parent_customer_group', 'is_group', 'disabled'},
    'Territory': {'territory_name', 'parent_territory', 'is_group', 'disabled'},
    'Sales Person': {'sales_person_name', 'parent_sales_person', 'commission_rate', 'is_group', 'enabled', 'employee'},
    'Warehouse': {'warehouse_name', 'company', 'parent_warehouse', 'is_group', 'disabled'},
    'Item Group': {'item_group_name', 'parent_item_group', 'is_group', 'disabled'},
    'UOM': {'uom_name', 'must_be_whole_number', 'enabled'},
    'Supplier Group': {'supplier_group_name', 'parent_supplier_group', 'is_group', 'disabled'},
    'Price List': {'price_list_name', 'currency', 'buying', 'selling', 'enabled'},
  };


  Future<List<core.Map<String, dynamic>>> fetchMasterDataOptions(String doctype) async {
    if (!_masterDataFields.containsKey(doctype)) throw ArgumentError.value(doctype, 'doctype', 'نوع بيانات غير مدعوم.');
    const maxRows = 2000;
    final result = <core.Map<String, dynamic>>[];
    var start = 0;
    while (true) {
      final page = await fetchMasterDataRows(doctype: doctype, start: start);
      result.addAll(page);
      if (page.length < pageSize) return result;
      start += page.length;
      if (result.length >= maxRows) return result;
    }
  }

  Future<List<core.Map<String, dynamic>>> fetchMasterDataRows({
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
      'Customer' => const ['name', 'customer_name', 'customer_group', 'territory'],
      'Customer Group' => const ['name', 'customer_group_name', 'parent_customer_group'],
      'Territory' => const ['name', 'territory_name', 'parent_territory'],
      'Sales Person' => const ['name', 'sales_person_name', 'parent_sales_person', 'employee'],
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
    return rows.whereType<core.Map<String, dynamic>>()
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchMasterDataDocument({
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
    if (document is! core.Map<String, dynamic> || document['name'] != id) {
      throw Exception('لم تتطابق هوية السجل المسترجع مع المطلوب.');
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<core.Map<String, dynamic>> saveMasterDataDocument({
    required String doctype,
    String? name,
    required core.Map<String, dynamic> values,
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
            if (raw is! core.Map) throw const FormatException('يوجد صف غير صالح في تحويل وحدات الصنف.');
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
      case 'Customer':
        if (requiredValue('customer_name').isEmpty ||
            !{'Company', 'Individual'}.contains(requiredValue('customer_type')) ||
            requiredValue('customer_group').isEmpty ||
            requiredValue('territory').isEmpty) {
          throw const FormatException('اسم العميل ونوعه ومجموعته ومنطقته حقول مطلوبة.');
        }
        break;
      case 'Customer Group':
        if (requiredValue('customer_group_name').isEmpty) {
          throw const FormatException('اسم مجموعة العملاء مطلوب.');
        }
        break;
      case 'Territory':
        if (requiredValue('territory_name').isEmpty) {
          throw const FormatException('اسم المنطقة مطلوب.');
        }
        break;
      case 'Sales Person':
        final commissionText = requiredValue('commission_rate');
        final commissionRate = commissionText.isEmpty ? 0.0 : double.tryParse(commissionText);
        if (requiredValue('sales_person_name').isEmpty ||
            commissionRate == null || !commissionRate.isFinite ||
            commissionRate < 0 || commissionRate > 100) {
          throw const FormatException('اسم مندوب المبيعات ونسبة العمولة يجب أن تكون بين 0 و100.');
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
      const identityFields = {'item_code', 'warehouse_name', 'item_group_name', 'uom_name', 'supplier_group_name', 'customer_group_name', 'territory_name', 'sales_person_name', 'price_list_name'};
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
    if (saved is! core.Map<String, dynamic> || (saved['name']?.toString().isNotEmpty != true)) {
      throw Exception('لم يؤكد ERPNext حفظ السجل؛ أعد تحميل القائمة قبل المتابعة.');
    }
    if (id != null && id.isNotEmpty && saved['name'] != id) {
      throw Exception('تغيرت هوية السجل بعد الحفظ؛ أوقف العملية وراجع ERPNext.');
    }
    return core.Map<String, dynamic>.from(saved);
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
    _guestMode = false;
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
    if (_guestMode) {
      return _ApiResponse(403, jsonEncode({
        'message': 'أنت في وضع الضيف المحلي دون خادم. سجّل الدخول إلى ERPNext للوصول إلى بيانات الشركة.'
      }));
    }
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

  Future<_ApiResponse> _sendJson(String method, String path, core.Map<String, dynamic> payload) async {
    if (_guestMode) {
      return _ApiResponse(403, jsonEncode({'message': 'وضع الضيف للقراءة فقط؛ سجّل الدخول لتنفيذ هذه العملية.'}));
    }
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

  core.Map<String, dynamic> _decode(String body) {
    try {
      final value = jsonDecode(body);
      return value is core.Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  String _message(core.Map<String, dynamic> data, String fallback) {
    final message = data['message'];
    return message is String && message.isNotEmpty ? message : fallback;
  }


  Future<List<core.Map<String, dynamic>>> fetchJournalEntryDrafts({required String company, int start = 0, String? search}) async {
    final normalized = company.trim();
    if (normalized.isEmpty) throw const FormatException('حدد الشركة أولاً.');
    final query = search?.trim() ?? '';
    final uri = buildResourcePageUri(baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'posting_date', 'company', 'total_debit', 'total_credit', 'user_remark', 'docstatus'],
      filters: [['company', '=', normalized], ['docstatus', 'in', [0, 1]],],
      orFilters: query.isEmpty ? null : [['name', 'like', '%$query%'], ['user_remark', 'like', '%$query%']],
      orderBy: 'modified desc, name desc', start: start, pageLength: 50);
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل سجل القيود اليومية.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة القيود اليومية غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>().where((row) => row['company'] == normalized && (row['docstatus'] == 0 || row['docstatus'] == 1))
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchJournalEntryDocument(String name) async {
    final id = name.trim();
    if (id.isEmpty) throw const FormatException('رقم القيد غير موجود.');
    final response = await _send('GET', '/api/resource/Journal%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحميل القيد اليومي.'));
    final doc = data['data'];
    if (doc is! core.Map<String, dynamic> || doc['name'] != id || doc['doctype'] != 'Journal Entry') throw const FormatException('هوية القيد المسترجع غير مطابقة.');
    return core.Map<String, dynamic>.from(doc);
  }

  Future<core.Map<String, dynamic>> saveJournalEntryDraft({String? name, required String company, required String postingDate, required String remark, required List<core.Map<String, dynamic>> accounts}) async {
    final normalizedCompany = company.trim();
    final date = DateTime.tryParse(postingDate.trim());
    if (normalizedCompany.isEmpty || date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) throw const FormatException('الشركة وتاريخ القيد بصيغة YYYY-MM-DD حقول مطلوبة.');
    if (accounts.length < 2) throw const FormatException('القيد يتطلب حسابين على الأقل.');
    final companyResponse = await _send('GET', '/api/resource/Company/' + Uri.encodeComponent(normalizedCompany));
    final companyData = _decode(companyResponse.body);
    final companyDoc = companyData['data'];
    if (companyResponse.statusCode < 200 || companyResponse.statusCode >= 300 || companyDoc is! core.Map<String, dynamic>) throw Exception(_message(companyData, 'تعذر التحقق من الشركة.'));
    final currency = companyDoc['default_currency']?.toString() ?? '';
    if (currency.isEmpty) throw const FormatException('عملة الشركة غير محددة في ERPNext.');
    final clean = <core.Map<String, dynamic>>[];
    var debitTotal = 0.0, creditTotal = 0.0;
    var hasForeignCurrency = false;
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
      if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 || accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != normalizedCompany || accountDoc['is_group'] == 1 || accountDoc['is_group'] == true || accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) throw FormatException('الحساب ' + account + ' غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
      final accountCurrency = accountDoc['account_currency']?.toString().trim().isNotEmpty == true
          ? accountDoc['account_currency'].toString().trim()
          : currency;
      final requestedRate = row['exchange_rate'] is num
          ? (row['exchange_rate'] as num).toDouble()
          : double.tryParse(row['exchange_rate']?.toString() ?? '') ?? (accountCurrency == currency ? 1.0 : 0.0);
      if (accountCurrency == currency && requestedRate != 1.0 && requestedRate != 0.0) {
        throw FormatException('سعر تحويل حساب العملة الأساسية يجب أن يساوي 1: $account');
      }
      final exchangeRate = accountCurrency == currency ? 1.0 : requestedRate;
      if (!exchangeRate.isFinite || exchangeRate <= 0) {
        throw FormatException('أدخل سعر تحويل موجباً للحساب $account بعملة $accountCurrency.');
      }
      if (accountCurrency != currency) hasForeignCurrency = true;
      final costCenter = row['cost_center']?.toString().trim() ?? '';
      if (costCenter.isNotEmpty) {
        final costResponse = await _send('GET',
          '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
        final costData = _decode(costResponse.body);
        final costDoc = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            costDoc is! core.Map<String, dynamic> || costDoc['company'] != normalizedCompany ||
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
            projectDoc is! core.Map<String, dynamic> || projectDoc['company'] != normalizedCompany) {
          throw FormatException('المشروع $project غير صالح أو لا يتبع الشركة المحددة.');
        }
      }
      final partyType = row['party_type']?.toString().trim() ?? '';
      final party = row['party']?.toString().trim() ?? '';
      if (partyType.isEmpty != party.isEmpty) {
        throw FormatException('يجب تحديد نوع الطرف والطرف معاً للحساب $account.');
      }
      final referenceType = row['reference_type']?.toString().trim() ?? '';
      final referenceName = row['reference_name']?.toString().trim() ?? '';
      if (referenceType.isEmpty != referenceName.isEmpty) {
        throw FormatException('يجب تحديد نوع المرجع ورقمه معاً للحساب $account.');
      }
      final againstType = row['against_voucher_type']?.toString().trim() ?? '';
      final againstVoucher = row['against_voucher']?.toString().trim() ?? '';
      if (againstType.isEmpty != againstVoucher.isEmpty) {
        throw FormatException('يجب تحديد نوع المستند المقابل ورقمه معاً للحساب $account.');
      }
      final baseDebit = debit * exchangeRate;
      final baseCredit = credit * exchangeRate;
      if (!baseDebit.isFinite || !baseCredit.isFinite) {
        throw FormatException('قيمة التحويل للحساب $account تتجاوز النطاق المسموح.');
      }
      debitTotal += baseDebit;
      creditTotal += baseCredit;
      clean.add({
        'doctype': 'Journal Entry Account',
        'account': account,
        'account_currency': accountCurrency,
        'exchange_rate': exchangeRate,
        'debit_in_account_currency': debit,
        'credit_in_account_currency': credit,
        'debit': baseDebit,
        'credit': baseCredit,
        if (costCenter.isNotEmpty) 'cost_center': costCenter,
        if (project.isNotEmpty) 'project': project,
        if (partyType.isNotEmpty) 'party_type': partyType,
        if (party.isNotEmpty) 'party': party,
        if (referenceType.isNotEmpty) 'reference_type': referenceType,
        if (referenceName.isNotEmpty) 'reference_name': referenceName,
        if (againstType.isNotEmpty) 'against_voucher_type': againstType,
        if (againstVoucher.isNotEmpty) 'against_voucher': againstVoucher,
        if (row['is_advance'] != null) 'is_advance': row['is_advance'],
      });
    }
    if (debitTotal <= 0 || (debitTotal - creditTotal).abs() > 0.005) throw FormatException('القيد غير متوازن. المدين ' + debitTotal.toStringAsFixed(2) + ' والدائن ' + creditTotal.toStringAsFixed(2) + '.');
    final id = name?.trim() ?? '';
    final payload = <String, dynamic>{'doctype': 'Journal Entry', 'voucher_type': 'Journal Entry', 'company': normalizedCompany, 'posting_date': postingDate.trim(), 'user_remark': remark.trim(), 'multi_currency': hasForeignCurrency ? 1 : 0, 'accounts': clean};
    if (id.isEmpty) {
      final response = await _sendJson('POST', '/api/resource/Journal%20Entry', payload);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء مسودة القيد.'));
      final created = data['data'];
      if (created is! core.Map<String, dynamic> || created['doctype'] != 'Journal Entry' || created['name'] is! String || created['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext إنشاء مسودة القيد.');
      return core.Map<String, dynamic>.from(created);
    }
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != normalizedCompany || current['docstatus'] != 0) throw const FormatException('لا يمكن تعديل القيد: تغيرت الشركة أو لم تعد حالته مسودة.');
    final response = await _sendJson('POST', '/api/method/frappe.client.save', {'doc': {...current, ...payload, 'name': id}});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر تحديث مسودة القيد.'));
    final saved = data['message'];
    if (saved is! core.Map<String, dynamic> || saved['doctype'] != 'Journal Entry' || saved['name'] != id || saved['docstatus'] != 0) throw const FormatException('لم يؤكد ERPNext تحديث مسودة القيد.');
    return core.Map<String, dynamic>.from(saved);
  }

  Future<core.Map<String, dynamic>> submitJournalEntry(String name, {required String company}) async {
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
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Journal Entry' || submitted['name'] != id || submitted['docstatus'] != 1) throw const FormatException('لم يؤكد ERPNext ترحيل القيد اليومي.');
    return core.Map<String, dynamic>.from(submitted);
  }


  Future<List<core.Map<String, dynamic>>> fetchPayrollCostCenters({
    required String company,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض مراكز التكلفة.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Cost Center',
      fields: const ['name', 'cost_center_name', 'company', 'is_group', 'disabled'],
      filters: [
        ['company', '=', normalizedCompany],
        ['is_group', '=', 0],
        ['disabled', '=', 0],
      ],
      orderBy: 'lft asc, name asc',
      pageLength: 500,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل مراكز التكلفة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة مراكز التكلفة غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany &&
            row['is_group'] != 1 && row['is_group'] != true)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<List<core.Map<String, dynamic>>> fetchPayrollEntries({
    required String company,
    int start = 0,
  }) async {
    final normalizedCompany = company.trim();
    if (normalizedCompany.isEmpty) throw const FormatException('حدد الشركة لعرض دورات الرواتب.');
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Payroll Entry',
      fields: const [
        'name', 'company', 'posting_date', 'start_date', 'end_date',
        'payroll_frequency', 'status', 'docstatus', 'number_of_employees',
        'salary_slips_created', 'salary_slips_submitted', 'currency',
      ],
      filters: [['company', '=', normalizedCompany]],
      orderBy: 'modified desc, name desc',
      start: start,
      pageLength: 50,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل دورات الرواتب. تأكد من تثبيت HRMS وصلاحية Payroll Entry.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة دورات الرواتب غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
        .where((row) => row['company'] == normalizedCompany)
        .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> fetchPayrollEntryDocument({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل دورة الرواتب.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> || document['doctype'] != 'Payroll Entry' ||
        document['name'] != id || document['company'] != normalizedCompany) {
      throw const FormatException('دورة الرواتب لا تتبع الشركة المحددة أو أن هويتها غير مطابقة.');
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<List<core.Map<String, dynamic>>> fetchPayrollSalarySlips({
    required String payrollEntry,
    required String company,
  }) async {
    final entry = payrollEntry.trim(), normalizedCompany = company.trim();
    if (entry.isEmpty || normalizedCompany.isEmpty) throw const FormatException('دورة الرواتب والشركة مطلوبتان.');
    final collected = <core.Map<String, dynamic>>[];
    var start = 0;
    while (collected.length < 10000) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Salary Slip',
        fields: const [
          'name', 'employee', 'employee_name', 'company', 'start_date', 'end_date',
          'gross_pay', 'total_deduction', 'net_pay', 'currency', 'docstatus', 'status',
          'payroll_entry',
        ],
        filters: [
          ['company', '=', normalizedCompany],
          ['payroll_entry', '=', entry],
        ],
        orderBy: 'employee_name asc, name asc',
        start: start,
        pageLength: 500,
      );
      final response = await _sendUri('GET', uri);
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, 'تعذر تحميل كشوف الرواتب لدورة الرواتب المحددة.'));
      }
      final rows = data['data'];
      if (rows is! List) throw const FormatException('استجابة كشوف الرواتب غير متوقعة.');
      final page = rows.whereType<core.Map<String, dynamic>>()
          .where((row) => row['company'] == normalizedCompany && row['payroll_entry'] == entry)
          .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
      collected.addAll(page);
      if (rows.length < 500) return collected;
      start += rows.length;
    }
    throw const FormatException('تجاوزت كشوف الرواتب حد العرض الآمن 10,000 سجل؛ صفّ الدورة في ERPNext قبل المتابعة.');
  }

  Future<core.Map<String, dynamic>> createPayrollEntryDraft({
    required String company,
    required String postingDate,
    required String startDate,
    required String endDate,
    required String payrollFrequency,
    required String costCenter,
    required String currency,
    required String payrollPayableAccount,
    required double exchangeRate,
    String? paymentAccount,
    String? bankAccount,
  }) async {
    final cleanCompany = company.trim();
    final cleanCostCenter = costCenter.trim();
    final cleanCurrency = currency.trim();
    final payable = payrollPayableAccount.trim();
    final frequency = payrollFrequency.trim();
    String validDate(String value, String label) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != value.trim()) {
        throw FormatException('$label غير صحيح. استخدم YYYY-MM-DD.');
      }
      return value.trim();
    }
    final posting = validDate(postingDate, 'تاريخ الترحيل');
    final from = validDate(startDate, 'بداية فترة الرواتب');
    final to = validDate(endDate, 'نهاية فترة الرواتب');
    if (cleanCompany.isEmpty || cleanCostCenter.isEmpty || cleanCurrency.isEmpty ||
        payable.isEmpty || !const {'Monthly', 'Fortnightly', 'Bimonthly', 'Weekly', 'Daily'}.contains(frequency) ||
        !exchangeRate.isFinite || exchangeRate <= 0 || from.compareTo(to) > 0) {
      throw const FormatException('أكمل بيانات دورة الرواتب وتأكد من الفترة والتكرار وسعر الصرف.');
    }
    Future<core.Map<String, dynamic>> readSetupDoc(String doctype, String name, String failure) async {
      final response = await _send(
        'GET',
        '/api/resource/' + Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(name),
      );
      final data = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_message(data, failure));
      }
      final row = data['data'];
      if (row is! core.Map<String, dynamic> || row['doctype'] != doctype || row['name'] != name) {
        throw FormatException('بيانات $doctype غير مطابقة.');
      }
      return row;
    }
    final setup = await Future.wait([
      readSetupDoc('Cost Center', cleanCostCenter, 'تعذر التحقق من مركز التكلفة.'),
      readSetupDoc('Account', payable, 'تعذر التحقق من حساب الرواتب المستحقة.'),
    ]);
    final costCenterDoc = setup[0], payableDoc = setup[1];
    if (costCenterDoc['company'] != cleanCompany || (costCenterDoc['disabled'] == 1 || costCenterDoc['disabled'] == true) ||
        costCenterDoc['is_group'] == 1 || costCenterDoc['is_group'] == true) {
      throw const FormatException('مركز التكلفة يجب أن يكون مركز ترحيل نشطاً تابعاً للشركة المحددة.');
    }
    if (payableDoc['company'] != cleanCompany || (payableDoc['disabled'] == 1 || payableDoc['disabled'] == true) ||
        payableDoc['is_group'] == 1 || payableDoc['is_group'] == true ||
        payableDoc['account_type'] != 'Payable') {
      throw const FormatException('حساب الرواتب يجب أن يكون حساب Payable نشطاً وقابلاً للترحيل ضمن الشركة.');
    }
    final bankId = bankAccount?.trim() ?? '';
    final paymentId = paymentAccount?.trim() ?? '';
    if (bankId.isNotEmpty || paymentId.isNotEmpty) {
      if (bankId.isEmpty || paymentId.isEmpty) {
        throw const FormatException('يجب تحديد حساب البنك وحساب الأستاذ المرتبط به معاً.');
      }
      final bank = await readSetupDoc('Bank Account', bankId, 'تعذر التحقق من حساب البنك.');
      if (bank['company'] != cleanCompany || bank['disabled'] == 1 || bank['disabled'] == true ||
          (bank['is_company_account'] != 1 && bank['is_company_account'] != true) || bank['account'] != paymentId) {
        throw const FormatException('حساب البنك أو حساب الأستاذ المرتبط به لا يتبع الشركة أو غير صالح للصرف.');
      }
      final paymentDoc = await readSetupDoc('Account', paymentId, 'تعذر التحقق من حساب الدفع.');
      if (paymentDoc['company'] != cleanCompany || paymentDoc['disabled'] == 1 || paymentDoc['disabled'] == true ||
          paymentDoc['is_group'] == 1 || paymentDoc['is_group'] == true ||
          !{'Bank', 'Cash'}.contains(paymentDoc['account_type'])) {
        throw const FormatException('حساب الدفع يجب أن يكون حساب بنك أو نقد نشطاً وقابلاً للترحيل ضمن الشركة.');
      }
    }
    final doc = <String, dynamic>{
      'doctype': 'Payroll Entry',
      'company': cleanCompany,
      'posting_date': posting,
      'start_date': from,
      'end_date': to,
      'payroll_frequency': frequency,
      'salary_slip_based_on_timesheet': 0,
      'cost_center': cleanCostCenter,
      'currency': cleanCurrency,
      'exchange_rate': exchangeRate,
      'payroll_payable_account': payable,
      if (paymentAccount?.trim().isNotEmpty == true) 'payment_account': paymentAccount!.trim(),
      if (bankAccount?.trim().isNotEmpty == true) 'bank_account': bankAccount!.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Payroll%20Entry', doc);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'رفض ERPNext إنشاء دورة الرواتب. تحقق من إعدادات HRMS والحسابات.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Payroll Entry' ||
        created['company'] != cleanCompany || created['docstatus'] != 0 ||
        (created['name']?.toString().trim().isEmpty ?? true)) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مسودة دورة الرواتب الصحيحة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> _runPayrollEntryMethod({
    required String name,
    required String company,
    required String method,
    bool requireSubmitted = false,
  }) async {
    const allowedMethods = {'fill_employee_details', 'submit_salary_slips', 'make_bank_entry'};
    if (!allowedMethods.contains(method)) throw ArgumentError.value(method, 'method', 'إجراء رواتب غير مدعوم.');
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة دورة الرواتب.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Payroll Entry' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        (requireSubmitted ? current['docstatus'] != 1 : current['docstatus'] != 0)) {
      throw const FormatException('تم رفض الإجراء لأن دورة الرواتب لا تتبع الشركة أو أن حالتها غير مناسبة.');
    }
    final result = await _sendJson('POST', '/api/method/run_doc_method', {
      'docs': jsonEncode(current),
      'method': method,
    });
    final resultData = _decode(result.body);
    if (result.statusCode < 200 || result.statusCode >= 300) {
      throw Exception(_message(resultData, 'تعذر تنفيذ إجراء الرواتب $method.'));
    }
    final docs = resultData['docs'];
    if (docs is! List || docs.isEmpty || docs.first is! core.Map<String, dynamic>) {
      throw const FormatException('لم يُرجع ERPNext دورة رواتب محدثة بعد تنفيذ الإجراء.');
    }
    final updated = core.Map<String, dynamic>.from(docs.first as core.Map);
    if (updated['doctype'] != 'Payroll Entry' || updated['name'] != id ||
        updated['company'] != normalizedCompany) {
      throw const FormatException('استجابة إجراء الرواتب لا تطابق دورة الرواتب المطلوبة.');
    }
    updated['_mobile_method_message'] = resultData['message'];
    return updated;
  }

  Future<core.Map<String, dynamic>> fillPayrollEmployees({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final updated = await _runPayrollEntryMethod(
      name: id, company: normalizedCompany, method: 'fill_employee_details',
    );
    final employees = updated['employees'];
    if (employees is! List || employees.isEmpty) {
      throw const FormatException('لم يعثر HRMS على موظفين لهم تعيين هيكل راتب نشط مطابق للفترة والحسابات.');
    }
    final saveResponse = await _sendJson(
      'PUT',
      '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id),
      {
        'employees': employees,
        'number_of_employees': updated['number_of_employees'] ?? employees.length,
      },
    );
    final saveData = _decode(saveResponse.body);
    if (saveResponse.statusCode < 200 || saveResponse.statusCode >= 300) {
      throw Exception(_message(saveData, 'تعذر حفظ قائمة الموظفين في مسودة دورة الرواتب.'));
    }
    final saved = saveData['data'];
    if (saved is! core.Map<String, dynamic> || saved['name'] != id ||
        saved['company'] != normalizedCompany || saved['employees'] is! List ||
        (saved['employees'] as List).length != employees.length) {
      throw const FormatException('لم يؤكد ERPNext حفظ قائمة الموظفين الصحيحة في دورة الرواتب.');
    }
    final unmarked = updated['_mobile_method_message'];
    if (unmarked is List && unmarked.isNotEmpty) {
      throw FormatException('لا يمكن ترحيل الرواتب قبل استكمال تسجيل الحضور لبعض الموظفين. عدد الحالات غير المكتملة: ${unmarked.length}.');
    }
    return {...core.Map<String, dynamic>.from(saved), 'mobile_unmarked_attendance': unmarked ?? const []};
  }

  Future<core.Map<String, dynamic>> submitPayrollSalarySlips({
    required String name,
    required String company,
  }) async {
    final updated = await _runPayrollEntryMethod(
      name: name, company: company, method: 'submit_salary_slips', requireSubmitted: true,
    );
    final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
    final pending = slips.where((row) => row['docstatus'] == 0).length;
    return {...updated, 'mobile_pending_salary_slips': pending};
  }

  Future<core.Map<String, dynamic>> createPayrollBankEntry({
    required String name,
    required String company,
  }) async {
    final document = await fetchPayrollEntryDocument(name: name, company: company);
    if ((document['payment_account']?.toString().trim().isEmpty ?? true) ||
        (document['bank_account']?.toString().trim().isEmpty ?? true)) {
      throw const FormatException('حدد حساب الدفع وحساب البنك في دورة الرواتب قبل إنشاء قيد الصرف.');
    }
    final slips = await fetchPayrollSalarySlips(payrollEntry: name, company: company);
    if (slips.isEmpty || slips.any((row) => row['docstatus'] != 1)) {
      throw const FormatException('لا يمكن إنشاء قيد الصرف قبل اعتماد جميع كشوف الرواتب المرتبطة بالدورة.');
    }
    return _runPayrollEntryMethod(
      name: name, company: company, method: 'make_bank_entry', requireSubmitted: true,
    );
  }

  Future<core.Map<String, dynamic>> submitPayrollEntry({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم دورة الرواتب والشركة مطلوبان.');
    await fillPayrollEmployees(name: id, company: normalizedCompany);
    final response = await _send('GET', '/api/resource/Payroll%20Entry/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة دورة الرواتب قبل الترحيل.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != 'Payroll Entry' ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || current['employees'] is! List ||
        (current['employees'] as List).isEmpty) {
      throw const FormatException('لا يمكن ترحيل دورة الرواتب قبل تحميل الموظفين والتحقق من الشركة والحالة.');
    }
    final responseSubmit = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final submitData = _decode(responseSubmit.body);
    if (responseSubmit.statusCode < 200 || responseSubmit.statusCode >= 300) {
      throw Exception(_message(submitData, 'رفض ERPNext ترحيل دورة الرواتب وإنشاء كشوف الرواتب.'));
    }
    final submitted = submitData['message'];
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != 'Payroll Entry' ||
        submitted['name'] != id || submitted['company'] != normalizedCompany ||
        submitted['docstatus'] != 1) {
      throw const FormatException('لم يؤكد ERPNext ترحيل دورة الرواتب.');
    }
    return core.Map<String, dynamic>.from(submitted);
  }

  // HR mobile access is intentionally allow-listed. ERPNext permissions,
  // employee/company rules and document validation remain authoritative.
  static const core.Map<String, List<String>> _hrFields = {
    'Employee': ['name', 'employee_name', 'company', 'department', 'designation',
      'status', 'date_of_joining', 'reports_to', 'cell_number', 'prefered_email'],
    'Attendance': ['name', 'employee', 'employee_name', 'company', 'attendance_date',
      'status', 'docstatus', 'leave_type'],
    'Leave Application': ['name', 'employee', 'employee_name', 'company', 'leave_type',
      'from_date', 'to_date', 'total_leave_days', 'status', 'docstatus',
      'posting_date', 'description'],
    'Expense Claim': ['name', 'employee', 'employee_name', 'company', 'posting_date',
      'total_claimed_amount', 'total_sanctioned_amount', 'approval_status',
      'status', 'docstatus'],
    'Salary Slip': ['name', 'employee', 'employee_name', 'company', 'start_date',
      'end_date', 'gross_pay', 'total_deduction', 'net_pay', 'currency', 'status', 'docstatus'],
  };

  Future<core.Map<String, dynamic>> fetchSalarySlipDetails({
    required String name,
    required String company,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('رقم كشف الراتب والشركة مطلوبان.');
    }
    final response = await _send(
      'GET', '/api/resource/Salary%20Slip/' + Uri.encodeComponent(id),
    );
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل تفاصيل كشف الراتب.'));
    }
    final document = data['data'];
    if (document is! core.Map<String, dynamic> ||
        document['doctype'] != 'Salary Slip' || document['name'] != id ||
        document['company'] != normalizedCompany) {
      throw const FormatException('كشف الراتب لا ينتمي إلى الشركة المحددة أو أن هويته غير مطابقة.');
    }
    for (final field in const ['earnings', 'deductions']) {
      final rows = document[field];
      if (rows != null && rows is! List) {
        throw FormatException('تفاصيل $field في كشف الراتب غير متوقعة.');
      }
    }
    return core.Map<String, dynamic>.from(document);
  }

  Future<List<core.Map<String, dynamic>>> fetchHrRecords({
    required String doctype,
    String? company,
    int start = 0,
    String? search,
  }) async {
    final fields = _hrFields[doctype];
    if (fields == null) throw ArgumentError.value(doctype, 'doctype', 'نوع سجل موارد بشرية غير مدعوم.');
    final normalizedCompany = company?.trim() ?? '';
    final query = search?.trim() ?? '';
    final searchFields = switch (doctype) {
      'Employee' => const ['name', 'employee_name', 'department', 'designation'],
      'Attendance' => const ['name', 'employee', 'employee_name'],
      'Leave Application' => const ['name', 'employee', 'employee_name', 'leave_type'],
      'Expense Claim' => const ['name', 'employee', 'employee_name'],
      'Salary Slip' => const ['name', 'employee', 'employee_name', 'payroll_frequency'],
      _ => const <String>[],
    };
    final filters = <List<dynamic>>[];
    if (normalizedCompany.isNotEmpty) filters.add(['company', '=', normalizedCompany]);
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: doctype,
      fields: fields,
      filters: filters,
      orFilters: query.isEmpty ? null : searchFields.map((field) => [field, 'like', '%$query%']).toList(),
      orderBy: doctype == 'Employee' ? 'employee_name asc, name asc' : 'modified desc, name desc',
      start: start,
      pageLength: 50,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل سجلات $doctype. تحقق من صلاحية القراءة.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة سجلات $doctype غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .where((row) => normalizedCompany.isEmpty || row['company'] == normalizedCompany)
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> _fetchHrEmployee(String employee, String company) async {
    final id = employee.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('حدد الموظف والشركة.');
    final response = await _send('GET', '/api/resource/Employee/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر التحقق من الموظف. تحقق من صلاحية قراءة Employee.'));
    }
    final row = data['data'];
    if (row is! core.Map<String, dynamic> || row['name'] != id ||
        row['company'] != normalizedCompany || row['status'] == 'Left' ||
        row['status'] == 'Inactive') {
      throw const FormatException('الموظف غير موجود أو لا يتبع الشركة المحددة أو غير نشط.');
    }
    return core.Map<String, dynamic>.from(row);
  }

  Future<core.Map<String, dynamic>> createAttendanceDraft({
    required String employee,
    required String company,
    required String attendanceDate,
    required String status,
    String? leaveType,
  }) async {
    final date = DateTime.tryParse(attendanceDate.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != attendanceDate.trim()) {
      throw const FormatException('تاريخ الحضور يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (!const {'Present', 'Absent', 'On Leave', 'Half Day', 'Work From Home'}.contains(status)) {
      throw const FormatException('حالة الحضور المحددة غير مدعومة.');
    }
    if (status == 'On Leave' && (leaveType?.trim().isEmpty ?? true)) {
      throw const FormatException('حدد نوع الإجازة عند تسجيل حالة في إجازة.');
    }
    await _fetchHrEmployee(employee, company);
    final duplicateUri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Attendance',
      fields: const ['name', 'docstatus'],
      filters: [
        ['employee', '=', employee.trim()],
        ['attendance_date', '=', attendanceDate.trim()],
      ],
      orderBy: 'modified desc',
      pageLength: 10,
    );
    final duplicateResponse = await _sendUri('GET', duplicateUri);
    final duplicateData = _decode(duplicateResponse.body);
    if (duplicateResponse.statusCode < 200 || duplicateResponse.statusCode >= 300) {
      throw Exception(_message(duplicateData, 'تعذر التحقق من سجلات الحضور السابقة.'));
    }
    final existingAttendance = duplicateData['data'];
    if (existingAttendance is! List) throw const FormatException('استجابة التحقق من تكرار الحضور غير متوقعة.');
    if (existingAttendance.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('يوجد سجل حضور أو مسودة لهذا الموظف في التاريخ المحدد.');
    }
    final payload = <String, dynamic>{
      'doctype': 'Attendance',
      'employee': employee.trim(),
      'company': company.trim(),
      'attendance_date': attendanceDate.trim(),
      'status': status,
      if (leaveType?.trim().isNotEmpty ?? false) 'leave_type': leaveType!.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Attendance', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة الحضور.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Attendance' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مسودة الحضور المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<core.Map<String, dynamic>> createLeaveApplicationDraft({
    required String employee,
    required String company,
    required String leaveType,
    required String fromDate,
    required String toDate,
    String description = '',
  }) async {
    final from = DateTime.tryParse(fromDate.trim()), to = DateTime.tryParse(toDate.trim());
    if (from == null || to == null ||
        from.toIso8601String().substring(0, 10) != fromDate.trim() ||
        to.toIso8601String().substring(0, 10) != toDate.trim() ||
        to.isBefore(from)) {
      throw const FormatException('تحقق من تاريخ بداية الإجازة ونهايتها بصيغة YYYY-MM-DD.');
    }
    if (leaveType.trim().isEmpty) throw const FormatException('حدد نوع الإجازة.');
    await _fetchHrEmployee(employee, company);
    final payload = <String, dynamic>{
      'doctype': 'Leave Application',
      'employee': employee.trim(),
      'company': company.trim(),
      'leave_type': leaveType.trim(),
      'from_date': fromDate.trim(),
      'to_date': toDate.trim(),
      'description': description.trim(),
    };
    final response = await _sendJson('POST', '/api/resource/Leave%20Application', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء طلب الإجازة.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Leave Application' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء طلب الإجازة المطابق.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<List<core.Map<String, dynamic>>> fetchExpenseClaimTypes() async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Expense Claim Type',
      fields: const ['name', 'default_account', 'disabled'],
      filters: const [['disabled', '=', 0]],
      orderBy: 'name asc',
      pageLength: 100,
    );
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر تحميل أنواع المصروفات.'));
    }
    final rows = data['data'];
    if (rows is! List) throw const FormatException('استجابة أنواع المصروفات غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>()
      .where((row) => row['disabled'] != 1 && row['disabled'] != true)
      .map((row) => core.Map<String, dynamic>.from(row)).toList(growable: false);
  }

  Future<core.Map<String, dynamic>> createExpenseClaimDraft({
    required String employee,
    required String company,
    required String postingDate,
    required String expenseType,
    required String amount,
    required String account,
    String description = '',
    String costCenter = '',
  }) async {
    final date = DateTime.tryParse(postingDate.trim());
    final value = double.tryParse(amount.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (value == null || !value.isFinite || value <= 0) {
      throw const FormatException('أدخل مبلغ مصروف أكبر من صفر.');
    }
    if (expenseType.trim().isEmpty) {
      throw const FormatException('نوع المصروف حقل مطلوب.');
    }
    await _fetchHrEmployee(employee, company);
    final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(expenseType.trim()));
    final typeData = _decode(typeResponse.body);
    final type = typeData['data'];
    if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
        type is! core.Map<String, dynamic> || type['name'] != expenseType.trim() ||
        type['disabled'] == 1 || type['disabled'] == true) {
      throw const FormatException('نوع المصروف غير موجود أو معطل في ERPNext.');
    }
    final configuredAccount = type['default_account']?.toString().trim() ?? '';
    final selectedAccount = configuredAccount.isNotEmpty ? configuredAccount : account.trim();
    if (selectedAccount.isEmpty) throw const FormatException('حدد حساب المصروف أو استخدم نوعاً له حساب افتراضي.');
    final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(selectedAccount));
    final accountData = _decode(accountResponse.body);
    final accountDoc = accountData['data'];
    if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
        accountDoc is! core.Map<String, dynamic> || accountDoc['company'] != company.trim() ||
        accountDoc['is_group'] == 1 || accountDoc['is_group'] == true ||
        accountDoc['disabled'] == 1 || accountDoc['disabled'] == true) {
      throw const FormatException('حساب المصروف غير صالح أو لا يتبع الشركة المحددة أو ليس حساب حركة.');
    }
    final normalizedCostCenter = costCenter.trim();
    if (normalizedCostCenter.isNotEmpty) {
      final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(normalizedCostCenter));
      final costData = _decode(costResponse.body);
      final costDoc = costData['data'];
      if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
          costDoc is! core.Map<String, dynamic> || costDoc['company'] != company.trim() ||
          costDoc['is_group'] == 1 || costDoc['is_group'] == true ||
          costDoc['disabled'] == 1 || costDoc['disabled'] == true) {
        throw const FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة المحددة.');
      }
    }
    final payload = <String, dynamic>{
      'doctype': 'Expense Claim',
      'employee': employee.trim(),
      'company': company.trim(),
      'posting_date': postingDate.trim(),
      'expenses': [{
        'doctype': 'Expense Claim Detail',
        'expense_type': expenseType.trim(),
        'expense_date': postingDate.trim(),
        'amount': value,
        'default_account': selectedAccount,
        'description': description.trim(),
        if (normalizedCostCenter.isNotEmpty) 'cost_center': normalizedCostCenter,
      }],
    };
    final response = await _sendJson('POST', '/api/resource/Expense%20Claim', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات.'));
    }
    final created = data['data'];
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim()) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }


  Future<core.Map<String, dynamic>> createExpenseClaimDraftLines({
    required String employee,
    required String company,
    required String postingDate,
    required List<core.Map<String, dynamic>> expenses,
  }) async {
    final date = DateTime.tryParse(postingDate.trim());
    if (date == null || date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('تاريخ المطالبة يجب أن يكون بصيغة YYYY-MM-DD.');
    }
    if (expenses.isEmpty || expenses.length > 50) {
      throw const FormatException('أضف بند مصروف واحداً على الأقل، وبحد أقصى 50 بنداً.');
    }
    await _fetchHrEmployee(employee, company);
    final typeCache = <String, core.Map<String, dynamic>>{};
    final accountCache = <String, core.Map<String, dynamic>>{};
    final costCenterCache = <String, core.Map<String, dynamic>>{};
    final cleanExpenses = <core.Map<String, dynamic>>[];
    for (var index = 0; index < expenses.length; index++) {
      final row = expenses[index];
      final typeName = row['expense_type']?.toString().trim() ?? '';
      final amount = row['amount'] is num
          ? (row['amount'] as num).toDouble()
          : double.tryParse(row['amount']?.toString() ?? '') ?? double.nan;
      if (typeName.isEmpty || !amount.isFinite || amount <= 0) {
        throw FormatException('تحقق من نوع ومبلغ بند المصروف رقم ${index + 1}.');
      }
      var type = typeCache[typeName];
      if (type == null) {
        final typeResponse = await _send('GET', '/api/resource/Expense%20Claim%20Type/' + Uri.encodeComponent(typeName));
        final typeData = _decode(typeResponse.body);
        final rawType = typeData['data'];
        if (typeResponse.statusCode < 200 || typeResponse.statusCode >= 300 ||
            rawType is! core.Map<String, dynamic> || rawType['name'] != typeName ||
            rawType['disabled'] == 1 || rawType['disabled'] == true) {
          throw FormatException('نوع المصروف غير موجود أو معطل: $typeName');
        }
        type = core.Map<String, dynamic>.from(rawType);
        typeCache[typeName] = type;
      }
      final configuredAccount = type['default_account']?.toString().trim() ?? '';
      final account = configuredAccount.isNotEmpty
          ? configuredAccount
          : (row['default_account']?.toString().trim() ?? '');
      if (account.isEmpty) throw FormatException('حدد حساباً لبند المصروف: $typeName');
      var accountDoc = accountCache[account];
      if (accountDoc == null) {
        final accountResponse = await _send('GET', '/api/resource/Account/' + Uri.encodeComponent(account));
        final accountData = _decode(accountResponse.body);
        final rawAccount = accountData['data'];
        if (accountResponse.statusCode < 200 || accountResponse.statusCode >= 300 ||
            rawAccount is! core.Map<String, dynamic> || rawAccount['company'] != company.trim() ||
            rawAccount['is_group'] == 1 || rawAccount['is_group'] == true ||
            rawAccount['disabled'] == 1 || rawAccount['disabled'] == true) {
          throw FormatException('حساب المصروف غير صالح أو لا يتبع الشركة: $account');
        }
        accountDoc = core.Map<String, dynamic>.from(rawAccount);
        accountCache[account] = accountDoc;
      }
      final costCenter = row['cost_center']?.toString().trim() ?? '';
      if (costCenter.isNotEmpty && !costCenterCache.containsKey(costCenter)) {
        final costResponse = await _send('GET', '/api/resource/Cost%20Center/' + Uri.encodeComponent(costCenter));
        final costData = _decode(costResponse.body);
        final rawCostCenter = costData['data'];
        if (costResponse.statusCode < 200 || costResponse.statusCode >= 300 ||
            rawCostCenter is! core.Map<String, dynamic> || rawCostCenter['company'] != company.trim() ||
            rawCostCenter['is_group'] == 1 || rawCostCenter['is_group'] == true ||
            rawCostCenter['disabled'] == 1 || rawCostCenter['disabled'] == true) {
          throw FormatException('مركز التكلفة غير صالح أو لا يتبع الشركة: $costCenter');
        }
        costCenterCache[costCenter] = core.Map<String, dynamic>.from(rawCostCenter);
      }
      cleanExpenses.add({
        'doctype': 'Expense Claim Detail',
        'expense_type': typeName,
        'expense_date': postingDate.trim(),
        'amount': amount,
        'default_account': account,
        'description': row['description']?.toString().trim() ?? '',
        if (costCenter.isNotEmpty) 'cost_center': costCenter,
      });
    }
    final response = await _sendJson('POST', '/api/resource/Expense%20Claim', {
      'doctype': 'Expense Claim',
      'employee': employee.trim(),
      'company': company.trim(),
      'posting_date': postingDate.trim(),
      'expenses': cleanExpenses,
    });
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إنشاء مسودة مطالبة المصروفات متعددة البنود.'));
    }
    final created = data['data'];
    final savedExpenses = created is core.Map<String, dynamic> ? created['expenses'] : null;
    if (created is! core.Map<String, dynamic> || created['doctype'] != 'Expense Claim' ||
        created['name'] is! String || created['docstatus'] != 0 ||
        created['employee'] != employee.trim() || created['company'] != company.trim() ||
        savedExpenses is! List || savedExpenses.length != cleanExpenses.length) {
      throw const FormatException('لم يؤكد ERPNext إنشاء مطالبة المصروفات متعددة البنود المطابقة.');
    }
    return core.Map<String, dynamic>.from(created);
  }

  Future<List<core.Map<String, dynamic>>> fetchWorkflowTransitions({
    required String doctype,
    required String name,
    required String company,
  }) async {
    final type = doctype.trim(), id = name.trim(), normalizedCompany = company.trim();
    if (type.isEmpty || id.isEmpty || normalizedCompany.isEmpty) {
      throw const FormatException('نوع المستند ورقمه والشركة مطلوبة لجلب إجراءات الموافقة.');
    }
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(type) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر قراءة المستند قبل جلب إجراءات الموافقة.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != type ||
        current['name'] != id || current['company'] != normalizedCompany) {
      throw const FormatException('المستند لا ينتمي إلى الشركة المحددة أو أن هويته غير مطابقة.');
    }
    final uri = Uri.parse('$_baseUrl/api/method/frappe.model.workflow.get_transitions')
        .replace(queryParameters: {'doc': jsonEncode(current)});
    final transitionsResponse = await _sendUri('GET', uri);
    final transitionsData = _decode(transitionsResponse.body);
    if (transitionsResponse.statusCode < 200 || transitionsResponse.statusCode >= 300) {
      throw Exception(_message(transitionsData, 'تعذر جلب إجراءات سير العمل من ERPNext.'));
    }
    final rows = transitionsData['message'];
    if (rows is! List) throw const FormatException('استجابة إجراءات سير العمل غير متوقعة.');
    return rows.whereType<core.Map<String, dynamic>>().where((row) =>
      row['action'] is String && (row['action'] as String).trim().isNotEmpty
    ).map((row) => core.Map<String, dynamic>.from(row)).toList();
  }

  Future<core.Map<String, dynamic>> applyWorkflowAction({
    required String doctype,
    required String name,
    required String company,
    required String action,
  }) async {
    final type = doctype.trim(), id = name.trim();
    final normalizedCompany = company.trim(), selectedAction = action.trim();
    if (type.isEmpty || id.isEmpty || normalizedCompany.isEmpty || selectedAction.isEmpty) {
      throw const FormatException('نوع المستند ورقمه والشركة وإجراء الموافقة مطلوبة.');
    }
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(type) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة المستند قبل تنفيذ إجراء الموافقة.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != type ||
        current['name'] != id || current['company'] != normalizedCompany) {
      throw const FormatException('تم رفض الإجراء لأن هوية المستند أو الشركة غير مطابقة.');
    }
    final transitionsUri = Uri.parse('$_baseUrl/api/method/frappe.model.workflow.get_transitions')
        .replace(queryParameters: {'doc': jsonEncode(current)});
    final transitionsResponse = await _sendUri('GET', transitionsUri);
    final transitionsData = _decode(transitionsResponse.body);
    if (transitionsResponse.statusCode < 200 || transitionsResponse.statusCode >= 300) {
      throw Exception(_message(transitionsData, 'تعذر التحقق من صلاحية إجراء سير العمل.'));
    }
    final transitions = transitionsData['message'];
    if (transitions is! List || !transitions.whereType<core.Map>().any((row) =>
        row['action']?.toString() == selectedAction)) {
      throw const FormatException('الإجراء غير متاح لهذا المستند أو للمستخدم الحالي.');
    }
    final appliedResponse = await _sendJson(
      'POST', '/api/method/frappe.model.workflow.apply_workflow',
      {'doc': current, 'action': selectedAction},
    );
    final appliedData = _decode(appliedResponse.body);
    if (appliedResponse.statusCode < 200 || appliedResponse.statusCode >= 300) {
      throw Exception(_message(appliedData, 'رفض ERPNext تنفيذ إجراء سير العمل.'));
    }
    final updated = appliedData['message'];
    if (updated is! core.Map<String, dynamic> || updated['doctype'] != type ||
        updated['name'] != id || updated['company'] != normalizedCompany) {
      throw const FormatException('لم يؤكد ERPNext تنفيذ الإجراء على المستند الصحيح.');
    }
    return core.Map<String, dynamic>.from(updated);
  }

  Future<core.Map<String, dynamic>> submitHrDraft({
    required String doctype,
    required String name,
    required String company,
  }) async {
    if (doctype != 'Attendance' && doctype != 'Leave Application' && doctype != 'Expense Claim') {
      throw ArgumentError.value(doctype, 'doctype', 'ترحيل هذا النوع من سجلات الموارد البشرية غير مدعوم.');
    }
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم المستند والشركة مطلوبان.');
    final response = await _send('GET', '/api/resource/' +
      Uri.encodeComponent(doctype) + '/' + Uri.encodeComponent(id));
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إعادة قراءة المستند قبل الترحيل.'));
    }
    final current = data['data'];
    if (current is! core.Map<String, dynamic> || current['doctype'] != doctype ||
        current['name'] != id || current['company'] != normalizedCompany ||
        current['docstatus'] != 0 || (current['employee']?.toString().isEmpty ?? true)) {
      throw const FormatException('تم رفض الترحيل لأن هوية المستند أو الشركة أو حالته تغيرت.');
    }
    final submittedResponse = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': current});
    final submittedData = _decode(submittedResponse.body);
    if (submittedResponse.statusCode < 200 || submittedResponse.statusCode >= 300) {
      throw Exception(_message(submittedData, 'تعذر ترحيل مستند الموارد البشرية.'));
    }
    final submitted = submittedData['message'];
    if (submitted is! core.Map<String, dynamic> || submitted['doctype'] != doctype ||
        submitted['name'] != id || submitted['company'] != normalizedCompany ||
        submitted['docstatus'] != 1) {
      throw const FormatException('لم يؤكد ERPNext ترحيل المستند المطلوب.');
    }
    return core.Map<String, dynamic>.from(submitted);
  }



  Future<core.Map<String, dynamic>> cancelJournalEntry(String name, {required String company}) async {
    final id = name.trim(), normalizedCompany = company.trim();
    if (id.isEmpty || normalizedCompany.isEmpty) throw const FormatException('رقم القيد والشركة مطلوبان.');
    final current = await fetchJournalEntryDocument(id);
    if (current['company'] != normalizedCompany || current['docstatus'] != 1) {
      throw const FormatException('يمكن إلغاء القيد المرحّل التابع للشركة المحددة فقط.');
    }
    final reversalRemark = 'قيد عكسي للقيد $id';
    final reversalUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'docstatus'],
      filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
      orderBy: 'modified desc', pageLength: 20,
    );
    final reversalResponse = await _sendUri('GET', reversalUri);
    final reversalData = _decode(reversalResponse.body);
    if (reversalResponse.statusCode < 200 || reversalResponse.statusCode >= 300) {
      throw Exception(_message(reversalData, 'تعذر التحقق من وجود قيد عكسي قبل الإلغاء.'));
    }
    final reversalRows = reversalData['data'];
    if (reversalRows is! List) throw const FormatException('استجابة التحقق من القيد العكسي غير متوقعة.');
    if (reversalRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('ألغِ أو احسم القيد العكسي أولاً قبل إلغاء القيد الأصلي.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': current});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إلغاء القيد. تحقق من صلاحية الإلغاء والقيود المرتبطة.'));
    }
    final canceled = data['message'];
    if (canceled is! core.Map<String, dynamic> || canceled['doctype'] != 'Journal Entry' ||
        canceled['name'] != id || canceled['docstatus'] != 2) {
      throw const FormatException('لم يؤكد ERPNext إلغاء القيد.');
    }
    return core.Map<String, dynamic>.from(canceled);
  }

  Future<core.Map<String, dynamic>> createJournalEntryReversalDraft({
    required String name,
    required String company,
    required String postingDate,
  }) async {
    final id = name.trim(), normalizedCompany = company.trim();
    final date = DateTime.tryParse(postingDate.trim());
    if (id.isEmpty || normalizedCompany.isEmpty || date == null ||
        date.toIso8601String().substring(0, 10) != postingDate.trim()) {
      throw const FormatException('رقم القيد والشركة وتاريخ العكس الصحيح مطلوبة.');
    }
    final original = await fetchJournalEntryDocument(id);
    if (original['doctype'] != 'Journal Entry' || original['company'] != normalizedCompany ||
        original['docstatus'] != 1 || original['accounts'] is! List) {
      throw const FormatException('يمكن إنشاء قيد عكسي من قيد مرحّل تابع للشركة المحددة فقط.');
    }
    final reversalRemark = 'قيد عكسي للقيد $id';
    final existingUri = buildResourcePageUri(
      baseUrl: _baseUrl, resource: 'Journal Entry',
      fields: const ['name', 'docstatus', 'user_remark'],
      filters: [['company', '=', normalizedCompany], ['user_remark', '=', reversalRemark]],
      orderBy: 'modified desc', pageLength: 20,
    );
    final existingResponse = await _sendUri('GET', existingUri);
    final existingData = _decode(existingResponse.body);
    if (existingResponse.statusCode < 200 || existingResponse.statusCode >= 300) {
      throw Exception(_message(existingData, 'تعذر التحقق من وجود قيد عكسي سابق.'));
    }
    final existingRows = existingData['data'];
    if (existingRows is! List) throw const FormatException('استجابة التحقق من القيود العكسية غير متوقعة.');
    if (existingRows.whereType<core.Map<String, dynamic>>().any((row) => row['docstatus'] != 2)) {
      throw const FormatException('يوجد بالفعل قيد عكسي غير ملغى لهذا القيد.');
    }
    final reversedLines = <core.Map<String, dynamic>>[];
    for (final raw in (original['accounts'] as List).whereType<core.Map<String, dynamic>>()) {
      reversedLines.add({
        'account': raw['account']?.toString() ?? '',
        'debit': raw['credit_in_account_currency'] ?? raw['credit'] ?? 0,
        'credit': raw['debit_in_account_currency'] ?? raw['debit'] ?? 0,
        'exchange_rate': raw['exchange_rate'] ?? 1,
        'cost_center': raw['cost_center'] ?? '',
        'project': raw['project'] ?? '',
        'party_type': raw['party_type'] ?? '',
        'party': raw['party'] ?? '',
        'reference_type': raw['reference_type'] ?? '',
        'reference_name': raw['reference_name'] ?? '',
        'against_voucher_type': raw['against_voucher_type'] ?? '',
        'against_voucher': raw['against_voucher'] ?? '',
        'is_advance': raw['is_advance'],
      });
    }
    return saveJournalEntryDraft(
      company: normalizedCompany,
      postingDate: postingDate.trim(),
      remark: reversalRemark,
      accounts: reversedLines,
    );
  }

  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
