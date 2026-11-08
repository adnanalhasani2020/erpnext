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
      fields: ['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item'],
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

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices({int start = 0, String? search}) async {
    final uri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier', 'supplier_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status']),
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
    if (document is! Map<String, dynamic> || document['name'] is! String) {
      throw Exception('استجابة حفظ الفاتورة غير متوقعة؛ تحقق من قائمة الفواتير قبل إعادة المحاولة.');
    }
    return document;
  }

  Future<Map<String, dynamic>> submitSalesInvoice(Map<String, dynamic> document) async {
    if (document['doctype'] != 'Sales Invoice' || document['name'] is! String || document['name'].toString().isEmpty) {
      throw const FormatException('لا يمكن ترحيل هذا المستند؛ يجب أن يكون فاتورة مبيعات صحيحة.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': document});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تم حفظ المسودة، لكن تعذر ترحيل الفاتورة (${response.statusCode}).'));
    }
    final submitted = data['message'];
    if (submitted is Map<String, dynamic>) return submitted;
    return document;
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

  Future<Map<String, dynamic>> receiveSalesInvoicePayment({
    required String invoiceName,
    required double amount,
    String? bankAccount,
  }) async {
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
      return result is Map<String, dynamic> ? result : created;
    } catch (error) {
      throw Exception('تم إنشاء سند القبض كمسودة ${created['name']}، لكن لم يتم تأكيد ترحيله. راجع سند القبض في ERPNext قبل محاولة تسجيل دفعة أخرى. التفاصيل: ${error.toString().replaceFirst('Exception: ', '')}');
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
        created['name'] is! String ||
        created['return_against'] != normalizedName) {
      throw Exception('استجابة حفظ المرتجع غير مكتملة؛ تحقق من فواتير المبيعات قبل إعادة المحاولة.');
    }
    return created;
  }

  Future<Map<String, dynamic>> cancelSalesInvoice(Map<String, dynamic> document) async {
    if (document['doctype'] != 'Sales Invoice' || document['name'] is! String || document['name'].toString().isEmpty || document['docstatus'] != 1) {
      throw const FormatException('لا يمكن إلغاء هذا المستند؛ يجب أن يكون فاتورة مبيعات مرحّلة.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.cancel', {'doc': document});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر إلغاء فاتورة المبيعات (${response.statusCode}).'));
    }
    final cancelled = data['message'];
    if (cancelled is Map<String, dynamic>) return cancelled;
    return document;
  }


  Future<Map<String, dynamic>> createPurchaseInvoice(Map<String, dynamic> invoice) async {
    _validatePurchase(invoice);
    final response = await _sendJson('POST', '/api/resource/Purchase%20Invoice', invoice);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ فاتورة المشتريات.'));
    final doc = data['data'];
    if (doc is! Map<String, dynamic> || doc['name'] is! String) throw Exception('استجابة حفظ فاتورة المشتريات غير مؤكدة.');
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
          row['rate'] is! num || !(row['rate'] as num).isFinite || (row['rate'] as num) < 0) {
        throw const FormatException('تحقق من رمز الصنف والكمية والسعر في كل بند.');
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

  Future<Map<String, dynamic>> createPurchaseReturn(String invoiceName) async {
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
    final inserted = await _sendJson('POST', '/api/resource/Purchase%20Invoice', Map<String, dynamic>.from(raw));
    final data = _decode(inserted.body);
    if (inserted.statusCode < 200 || inserted.statusCode >= 300) throw Exception(_message(data, 'تعذر حفظ مسودة المرتجع.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> || created['name'] is! String || created['return_against'] != invoiceName) {
      throw Exception('لم يتم تأكيد حفظ مسودة المرتجع.');
    }
    return created;
  }

  Future<Map<String, dynamic>> payPurchaseInvoice({
    required String invoiceName, required double amount, String? bankAccount,
  }) async {
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
      throw Exception('تم حفظ سند الصرف ' + created['name'].toString() + ' كمسودة ولم يؤكد ترحيله. راجع هذا السند قبل تسجيل دفعة أخرى. ' + error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<Map<String, dynamic>> _submitMobileDocument(Map<String, dynamic> doc, String doctype) async {
    if (doc['doctype'] != doctype || doc['name'] is! String || doc['docstatus'] == 1) {
      throw FormatException('لا يمكن ترحيل المستند من النوع أو الحالة الحالية.');
    }
    final response = await _sendJson('POST', '/api/method/frappe.client.submit', {'doc': doc});
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر ترحيل المستند.'));
    return data['message'] is Map<String, dynamic> ? data['message'] as Map<String, dynamic> : doc;
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
      if (row['item_code'] is! String || row['qty'] is! num || !(row['qty'] as num).isFinite || (row['qty'] as num) <= 0) {
        throw const FormatException('كل بند يحتاج صنفاً وكمية موجبة.');
      }
    }
    final payload = <String, dynamic>{
      'doctype': 'Stock Entry', 'company': company, 'purpose': purpose, 'stock_entry_type': purpose,
      if (fromWarehouse != null) 'from_warehouse': fromWarehouse,
      if (toWarehouse != null) 'to_warehouse': toWarehouse,
      if (remarks != null && remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
      'items': items.map((row) => <String, dynamic>{
        ...row,
        if (purpose == 'Material Receipt' || purpose == 'Material Transfer') 't_warehouse': toWarehouse,
        if (purpose == 'Material Issue' || purpose == 'Material Transfer') 's_warehouse': fromWarehouse,
      }).toList(),
    };
    final response = await _sendJson('POST', '/api/resource/Stock%20Entry', payload);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء حركة المخزون.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> || created['name'] is! String) throw Exception('لم يتم تأكيد إنشاء حركة المخزون.');
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
          row['warehouse'] is! String || (row['warehouse'] as String).trim().isEmpty) {
        throw const FormatException('بيانات استلام البضائع غير مكتملة: الصنف والكمية والسعر والمستودع مطلوبة.');
      }
    }
    final response = await _sendJson('POST', '/api/resource/Purchase%20Receipt', document);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر إنشاء سند استلام المشتريات.'));
    final created = data['data'];
    if (created is! Map<String, dynamic> || created['name'] is! String) throw Exception('لم يتم تأكيد إنشاء سند استلام المشتريات.');
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
    if (created is! Map<String, dynamic> || created['name'] is! String) throw Exception('لم يتم تأكيد إنشاء مسودة التسوية.');
    return created;
  }

  Future<Map<String, dynamic>> submitStockReconciliation(Map<String, dynamic> doc) =>
      _submitMobileDocument(doc, 'Stock Reconciliation');

  Future<List<Map<String, dynamic>>> fetchStockMovements({int start = 0, String? itemCode, String? warehouse}) async {
    final filters = <List<dynamic>>[];
    if (itemCode != null && itemCode.trim().isNotEmpty) filters.add(['item_code', '=', itemCode.trim()]);
    if (warehouse != null && warehouse.trim().isNotEmpty) filters.add(['warehouse', '=', warehouse.trim()]);
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
