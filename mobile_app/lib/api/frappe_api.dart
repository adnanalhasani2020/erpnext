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
    final endpoint = '$normalizedBase/api/resource/${Uri.encodeComponent(resource)}';
    return Uri.parse(endpoint).replace(queryParameters: parameters);
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

  Future<List<ErpCompany>> fetchCompanies() async {
    const companyPageSize = pageSize;
    const maxCompanyCount = 10000;
    final companies = <ErpCompany>[];
    var start = 0;

    while (true) {
      final uri = buildResourcePageUri(
        baseUrl: _baseUrl,
        resource: 'Company',
        fields: const ['name', 'abbr'],
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


  Future<List<ErpItem>> fetchItems({int start = 0, String? search}) async {
    final uri = buildResourcePageUri(
      baseUrl: _baseUrl,
      resource: 'Item',
      fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item', 'has_serial_no', 'has_batch_no'],
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
      fields: ['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty', 'stock_uom'],
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
    if (raw is! Map<String, dynamic> || raw['doctype'] != targetDoctype || raw['items'] is! List || (raw['items'] as List).isEmpty) {
      throw Exception('لم يُرجع ERPNext مستند $targetDoctype صالحاً من أداة التحويل.');
    }
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

  Future<Map<String, dynamic>> createSalesInvoice(Map<String, dynamic> invoice) async {
    final customer = invoice['customer'];
    final company = invoice['company'];
    final rawItems = invoice['items'];
    if (invoice['doctype'] != 'Sales Invoice' || customer is! String || customer.trim().isEmpty || company is! String || company.trim().isEmpty || rawItems is! List || rawItems.isEmpty) {
      throw const FormatException('حدد الشركة والعميل وأضف صنفاً واحداً على الأقل.');
    }
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
    if (rawDocument is! Map<String, dynamic>) {
      throw Exception('استجابة تجهيز سند القبض غير متوقعة.');
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
    if (created is! Map<String, dynamic> || created['name'] is! String) {
      throw Exception('استجابة حفظ سند القبض غير متوقعة؛ تحقق من سجل Payment Entry قبل إعادة المحاولة.');
    }
    try {
      final submitted = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': created});
      final submittedData = _decode(submitted.body);
      if (submitted.statusCode < 200 || submitted.statusCode >= 300) {
        throw Exception(_message(submittedData, 'تعذر ترحيل سند القبض.'));
      }
      final result = submittedData['message'];
      if (result is! Map<String, dynamic> ||
          result['doctype'] != 'Payment Entry' ||
          result['name'] != created['name'] ||
          result['docstatus'] != 1 ||
          result['payment_type'] != 'Receive') {
        throw Exception('لم يؤكد ERPNext ترحيل سند القبض.');
      }
      return result;
    } catch (error) {
      // A timeout or lost response must not cause a second receipt to be created.
      // Re-read the same Payment Entry before reporting an uncertain outcome.
      try {
        final confirmed = await _fetchPaymentEntryDocument(created['name'].toString());
        if (confirmed['docstatus'] == 1 && confirmed['payment_type'] == 'Receive') {
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
    _validatePurchase(invoice);
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
    _validatePurchase(changes);
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
    if (created is! Map<String, dynamic> || created['name'] is! String) throw Exception('لم يتم تأكيد حفظ سند الصرف.');
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

  Future<Map<String, dynamic>> _fetchPaymentEntryDraft(String name) async {
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
        document['name'] != name.trim() || document['docstatus'] != 0) {
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
      'Payment Entry' => await _fetchPaymentEntryDraft(name),
      'Purchase Invoice' => await fetchInvoiceDocument('Purchase Invoice', name),
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
    final payload = <String, dynamic>{
      'doctype': 'Stock Entry', 'company': company, 'purpose': purpose, 'stock_entry_type': purpose,
      if (fromWarehouse != null) 'from_warehouse': fromWarehouse,
      if (toWarehouse != null) 'to_warehouse': toWarehouse,
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
      'items': items.map((row) {
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
    final seen = <String>{};
    for (final row in items) {
      final code = row['item_code'];
      final qty = row['qty'];
      if (code is! String || code.trim().isEmpty || !seen.add(code) || qty is! num || !qty.isFinite || qty < 0) {
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
    final payload = <String, dynamic>{
      'doctype': 'Stock Reconciliation', 'company': company, 'purpose': 'Stock Reconciliation',
      'items': items.map((row) => <String, dynamic>{...row, 'warehouse': warehouse}).toList(),
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
    const allowed = {'Purchase Invoice', 'Purchase Receipt', 'Stock Entry', 'Stock Reconciliation'};
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

  Future<List<Map<String, dynamic>>> fetchStockMovements({int start = 0, String? itemCode, String? warehouse, String? company}) async {
    final filters = <List<dynamic>>[];
    if (itemCode != null && itemCode.trim().isNotEmpty) filters.add(['item_code', '=', itemCode.trim()]);
    if (warehouse != null && warehouse.trim().isNotEmpty) filters.add(['warehouse', '=', warehouse.trim()]);
    if (company != null && company.trim().isNotEmpty) filters.add(['company', '=', company.trim()]);
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

  void dispose() => _client.close(force: true);
}

class _ApiResponse {
  const _ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}
