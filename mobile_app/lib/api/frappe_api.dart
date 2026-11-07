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
    final endpoint = '$normalizedBase/api/resource/${Uri.encodeComponent(resource)}';
    return Uri.parse(endpoint).replace(queryParameters: parameters);
  }

  final Map<String, String> _cookies = {};
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
    final generation = _sessionGeneration;
    if (username.trim().isEmpty || password.isEmpty) {
      throw const FormatException('أدخل اسم المستخدم وكلمة المرور.');
    }
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/login'));
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

  Future<List<ErpCompany>> fetchCompanies() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Company').replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'abbr']),
        'limit_page_length': '20',
        'order_by': 'name asc',
      },
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
    return rows.whereType<Map<String, dynamic>>().map(ErpCompany.fromJson).toList(growable: false);
  }


  Future<List<ErpItem>> fetchItems({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Item',
      fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item'],
      filters: [['disabled', '=', 0]],
      orFilters: search == null || search.trim().isEmpty
          ? null
          : [
              ['item_code', 'like', '%${search.trim()}%'],
              ['item_name', 'like', '%${search.trim()}%'],
            ],
      orderBy: 'modified desc',
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

  Future<List<ErpWarehouse>> fetchWarehouses({int start = 0}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Warehouse').replace(queryParameters: {
      'fields': jsonEncode(['name', 'warehouse_name', 'company', 'is_group']),
      'filters': jsonEncode([['disabled', '=', 0], ['is_group', '=', 0]]),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(),
      'order_by': 'warehouse_name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب المستودعات. تحقق من صلاحية قراءة Warehouse.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة المستودعات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpWarehouse.fromJson).toList(growable: false);
  }


  Future<List<ErpStockBalance>> fetchStockBalances({int start = 0}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Bin').replace(queryParameters: {
      'fields': jsonEncode(['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty', 'stock_uom']),
      'filters': jsonEncode([['actual_qty', '!=', 0]]),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(),
      'order_by': 'item_code asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب أرصدة المخزون. تحقق من صلاحية قراءة Bin.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة أرصدة المخزون من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpStockBalance.fromJson).toList(growable: false);
  }

  Future<List<ErpCustomer>> fetchCustomers({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Customer').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer_name', 'customer_type', 'customer_group', 'territory']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'customer_name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب العملاء. تحقق من صلاحية قراءة Customer.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة العملاء من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpCustomer.fromJson).toList(growable: false);
  }

  Future<List<ErpSalesInvoice>> fetchSalesInvoices({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Sales%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer', 'customer_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status']),
      'limit_page_length': pageSize.toString(),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","customer","customer_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة فواتير المبيعات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSalesInvoice.fromJson).toList(growable: false);
  }
  Future<List<ErpSupplier>> fetchSuppliers({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Supplier').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier_name', 'supplier_group', 'supplier_type']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_page_length': pageSize.toString(),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'supplier_name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب الموردين. تحقق من صلاحية قراءة Supplier.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة الموردين من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSupplier.fromJson).toList(growable: false);
  }

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier', 'supplier_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status']),
      'limit_page_length': pageSize.toString(),
      if (search != null && search.trim().isNotEmpty) 'or_filters': jsonEncode(["name","supplier","supplier_name"].map((field) => [field, 'like', '%${search.trim()}%']).toList()),
      'limit_start': (start < 0 ? 0 : start).toString(), 'order_by': 'posting_date desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المشتريات. تحقق من صلاحية قراءة Purchase Invoice.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة فواتير المشتريات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpPurchaseInvoice.fromJson).toList(growable: false);
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

  void _captureCookies(HttpClientResponse response) {
    for (final header in response.headers[HttpHeaders.setCookieHeader] ?? []) {
      final pair = header.split(';').first.split('=');
      if (pair.length >= 2) {
        _cookies[pair.first.trim()] = pair.sublist(1).join('=').trim();
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

  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
