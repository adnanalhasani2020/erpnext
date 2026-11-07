import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'models/erp_models.dart';

export 'models/erp_models.dart';

void main() => runApp(const ErpNextMobileApp());

class ErpNextMobileApp extends StatelessWidget {
  const ErpNextMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ERPNext Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF24936E)),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: MobileHomePage(),
      ),
    );
  }
}

class FrappeApi {
  final HttpClient _client = HttpClient();
  final Map<String, String> _cookies = {};
  String _baseUrl = '';

  void configure(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasAuthority ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                (uri.host == 'localhost' || uri.host == '10.0.2.2')))) {
      throw const FormatException('أدخل رابطاً صحيحاً يبدأ بـ https://');
    }
    _baseUrl = normalized;
  }

  Future<String> login(String username, String password) async {
    final request = await _client.postUrl(Uri.parse('$_baseUrl/api/method/login'));
    request.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    request.write(Uri(queryParameters: {'usr': username.trim(), 'pwd': password}).query);
    final response = await request.close();
    _captureCookies(response);
    final data = _decode(await utf8.decoder.bind(response).join());
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


  Future<List<ErpItem>> fetchItems() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Item').replace(queryParameters: {
      'fields': jsonEncode(['item_code', 'item_name', 'item_group', 'stock_uom', 'is_stock_item']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      'limit_page_length': '100',
      'order_by': 'modified desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_message(data, 'تعذر جلب الأصناف. تحقق من صلاحية قراءة Item.'));
    }
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة الأصناف من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpItem.fromJson).toList(growable: false);
  }

  Future<List<ErpWarehouse>> fetchWarehouses() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Warehouse').replace(queryParameters: {
      'fields': jsonEncode(['name', 'warehouse_name', 'company', 'is_group']),
      'filters': jsonEncode([['disabled', '=', 0], ['is_group', '=', 0]]),
      'limit_page_length': '100',
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


  Future<List<ErpStockBalance>> fetchStockBalances() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Bin').replace(queryParameters: {
      'fields': jsonEncode(['item_code', 'warehouse', 'actual_qty', 'reserved_qty', 'projected_qty', 'stock_uom']),
      'filters': jsonEncode([['actual_qty', '!=', 0]]),
      'limit_page_length': '100',
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

  Future<List<ErpCustomer>> fetchCustomers() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Customer').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer_name', 'customer_type', 'customer_group', 'territory']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      'limit_page_length': '100', 'order_by': 'customer_name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب العملاء. تحقق من صلاحية قراءة Customer.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة العملاء من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpCustomer.fromJson).toList(growable: false);
  }

  Future<List<ErpSalesInvoice>> fetchSalesInvoices() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Sales%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'customer', 'customer_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status']),
      'limit_page_length': '100', 'order_by': 'posting_date desc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب فواتير المبيعات. تحقق من صلاحية قراءة Sales Invoice.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة فواتير المبيعات من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSalesInvoice.fromJson).toList(growable: false);
  }
  Future<List<ErpSupplier>> fetchSuppliers() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Supplier').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier_name', 'supplier_group', 'supplier_type']),
      'filters': jsonEncode([['disabled', '=', 0]]),
      'limit_page_length': '100', 'order_by': 'supplier_name asc',
    });
    final response = await _sendUri('GET', uri);
    final data = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception(_message(data, 'تعذر جلب الموردين. تحقق من صلاحية قراءة Supplier.'));
    final rows = data['data'];
    if (rows is! List) throw Exception('استجابة الموردين من ERPNext غير متوقعة.');
    return rows.whereType<Map<String, dynamic>>().map(ErpSupplier.fromJson).toList(growable: false);
  }

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices() async {
    final uri = Uri.parse('$_baseUrl/api/resource/Purchase%20Invoice').replace(queryParameters: {
      'fields': jsonEncode(['name', 'supplier', 'supplier_name', 'posting_date', 'due_date', 'currency', 'grand_total', 'outstanding_amount', 'status']),
      'limit_page_length': '100', 'order_by': 'posting_date desc',
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
    final response = await request.close();
    _captureCookies(response);
    return _ApiResponse(response.statusCode, await utf8.decoder.bind(response).join());
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

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({super.key});

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  final _api = FrappeApi();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _itemSearchController = TextEditingController();
  final _warehouseSearchController = TextEditingController();
  String _itemSearch = '';
  String _warehouseSearch = '';
  String? _selectedWarehouse;
  int _selectedTab = 0;
  bool _busy = false;
  String? _error;
  String? _user;
  List<ErpCompany> _companies = const [];
  String? _companyError;
  bool _companiesLoading = false;
  List<ErpItem> _items = const [];
  List<ErpWarehouse> _warehouses = const [];
  List<ErpStockBalance> _stockBalances = const [];
  String? _inventoryError;
  bool _inventoryLoading = false;
  List<ErpCustomer> _customers = const [];
  List<ErpSalesInvoice> _salesInvoices = const [];
  String? _salesError;
  bool _salesLoading = false;
  List<ErpSupplier> _suppliers = const [];
  List<ErpPurchaseInvoice> _purchaseInvoices = const [];
  String? _purchaseError;
  bool _purchaseLoading = false;

  @override
  void dispose() {
    _api.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _itemSearchController.dispose();
    _warehouseSearchController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      _api.configure(_urlController.text);
      final user = await _api.login(_userController.text, _passwordController.text);
      if (!mounted) return;
      setState(() {
        _user = user;
        _passwordController.clear();
        _companiesLoading = true;
        _companyError = null;
      });
      await _loadCompanies();
      if (!mounted) return;
      await _loadInventory();
      if (!mounted) return;
      await _loadSales();
      if (!mounted) return;
      await _loadPurchases();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;

    setState(() { _companiesLoading = true; _companyError = null; });
    try {
      final companies = await _api.fetchCompanies();
      if (!mounted) return;
      setState(() => _companies = companies);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _companies = const [];
        _companyError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _companiesLoading = false);
    }
  }


  Future<void> _loadInventory() async {
    if (!mounted || _inventoryLoading) return;
    setState(() { _inventoryLoading = true; _inventoryError = null; });
    final errors = <String>[];

    try {
      final items = await _api.fetchItems();
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      errors.add('الأصناف: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    try {
      final warehouses = await _api.fetchWarehouses();
      if (!mounted) return;
      setState(() => _warehouses = warehouses);
    } catch (error) {
      errors.add('المستودعات: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    try {
      final balances = await _api.fetchStockBalances();
      if (!mounted) return;
      setState(() => _stockBalances = balances);
    } catch (error) {
      errors.add('الأرصدة: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    if (!mounted) return;
    setState(() {
      _inventoryError = errors.isEmpty ? null : errors.join('\n');
      _inventoryLoading = false;
    });
  }

  Future<void> _loadSales() async {
    if (!mounted || _salesLoading) return;
    setState(() { _salesLoading = true; _salesError = null; });
    final errors = <String>[];
    try {
      final customers = await _api.fetchCustomers();
      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (error) {
      errors.add('العملاء: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    try {
      final invoices = await _api.fetchSalesInvoices();
      if (!mounted) return;
      setState(() => _salesInvoices = invoices);
    } catch (error) {
      errors.add('الفواتير: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!mounted) return;
    setState(() { _salesError = errors.isEmpty ? null : errors.join('\n'); _salesLoading = false; });
  }

  Future<void> _loadPurchases() async {
    if (!mounted || _purchaseLoading) return;
    setState(() { _purchaseLoading = true; _purchaseError = null; });
    final errors = <String>[];
    try {
      final suppliers = await _api.fetchSuppliers();
      if (!mounted) return;
      setState(() => _suppliers = suppliers);
    } catch (error) {
      errors.add('الموردون: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    try {
      final invoices = await _api.fetchPurchaseInvoices();
      if (!mounted) return;
      setState(() => _purchaseInvoices = invoices);
    } catch (error) {
      errors.add('فواتير المشتريات: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!mounted) return;
    setState(() { _purchaseError = errors.isEmpty ? null : errors.join('\n'); _purchaseLoading = false; });
  }

  Future<void> _logout() async {
    setState(() => _busy = true);
    await _api.logout();
    if (!mounted) return;
    setState(() {
      _user = null;
      _selectedTab = 0;
      _selectedWarehouse = null;
      _itemSearch = '';
      _warehouseSearch = '';
      _itemSearchController.clear();
      _warehouseSearchController.clear();
      _busy = false;
      _companies = const [];
      _companyError = null;
      _items = const [];
      _warehouses = const [];
      _stockBalances = const [];
      _inventoryError = null;
      _customers = const [];
      _salesInvoices = const [];
      _salesError = null;
      _suppliers = const [];
      _purchaseInvoices = const [];
      _purchaseError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _user == null ? _buildLogin() : _buildSelectedPage(),
        ),
      ),
      bottomNavigationBar: _user == null ? null : NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'الأصناف'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'الأرصدة'),
          NavigationDestination(icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse), label: 'المستودعات'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'المعاملات'),
        ],
      ),
    );
  }


  Widget _buildSelectedPage() {
    switch (_selectedTab) {
      case 1: return _buildItemsPage();
      case 2: return _buildStockPage();
      case 3: return _buildWarehousesPage();
      case 4: return _buildSalesPage();
      default: return _buildDashboard();
    }
  }

  Widget _pageHeader(String title, String subtitle, IconData icon) => Row(children: [
    CircleAvatar(child: Icon(icon)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ])),
    IconButton(tooltip: 'تحديث البيانات', onPressed: _inventoryLoading ? null : _loadInventory, icon: const Icon(Icons.refresh)),
  ]);

  Widget _errorCard(String message) => Card(
    child: Padding(padding: const EdgeInsets.all(14), child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.error))),
  );

  Widget _buildItemsPage() {
    final query = _itemSearch.trim().toLowerCase();
    final filtered = _items.where((item) =>
      item.code.toLowerCase().contains(query) || item.name.toLowerCase().contains(query) ||
      (item.group ?? '').toLowerCase().contains(query)
    ).toList(growable: false);
    return ListView(padding: const EdgeInsets.all(18), children: [
      _pageHeader('الأصناف', 'بحث في الأصناف المحمّلة من ERPNext', Icons.sell_outlined),
      const SizedBox(height: 16),
      TextField(
        controller: _itemSearchController,
        decoration: InputDecoration(
          labelText: 'ابحث بالاسم أو الرمز أو المجموعة',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _itemSearch.isEmpty ? null : IconButton(
            tooltip: 'مسح البحث',
            onPressed: () { _itemSearchController.clear(); setState(() => _itemSearch = ''); },
            icon: const Icon(Icons.clear),
          ),
        ),
        onChanged: (value) => setState(() => _itemSearch = value),
      ),
      const SizedBox(height: 10),
      Text('المعروض ${filtered.length} من ${_items.length} صنف محمّل'),
      if (_inventoryLoading) const LinearProgressIndicator(),
      if (_inventoryError != null) _errorCard(_inventoryError!),
      if (filtered.isEmpty && !_inventoryLoading)
        const Card(child: ListTile(leading: Icon(Icons.search_off), title: Text('لا توجد أصناف مطابقة'))),
      ...filtered.map((item) => Card(child: ListTile(
        leading: CircleAvatar(child: Icon(item.isStockItem ? Icons.inventory_2_outlined : Icons.miscellaneous_services_outlined)),
        title: Text(item.name),
        subtitle: Text([item.code, if (item.group != null) item.group!, if (item.stockUom != null) item.stockUom!].join(' • ')),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => _showItemDetails(item),
      ))),
    ]);
  }

  void _showItemDetails(ErpItem item) {
    final balances = _stockBalances.where((row) => row.itemCode == item.code).toList(growable: false);
    showModalBottomSheet<void>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(item.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('رمز الصنف: ${item.code}'),
          Text('المجموعة: ${item.group ?? '—'}'),
          Text('وحدة القياس: ${item.stockUom ?? '—'}'),
          Text(item.isStockItem ? 'صنف مخزني' : 'صنف غير مخزني'),
          const Divider(height: 24),
          Text('الأرصدة حسب المستودع', style: Theme.of(context).textTheme.titleMedium),
          if (balances.isEmpty) const Text('لا توجد أرصدة ظاهرة لهذا الصنف.'),
          ...balances.map((balance) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(balance.warehouse),
            subtitle: Text('محجوز: ${balance.reservedQty} • متوقع: ${balance.projectedQty}'),
            trailing: Text('${balance.actualQty} ${balance.stockUom ?? ''}'),
          )),
        ]),
      )),
    );
  }

  Widget _buildStockPage() {
    final selected = _selectedWarehouse;
    final filtered = _stockBalances.where((row) => selected == null || row.warehouse == selected).toList(growable: false);
    final totalActual = filtered.fold<double>(0, (sum, row) => sum + row.actualQty);
    final totalReserved = filtered.fold<double>(0, (sum, row) => sum + row.reservedQty);
    return ListView(padding: const EdgeInsets.all(18), children: [
      _pageHeader('أرصدة المخزون', 'الكمية الفعلية والمحجوزة والمتاحة تقديرياً', Icons.inventory_2_outlined),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: _selectedWarehouse, isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب المستودع'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل المستودعات')),
          ..._warehouses.map((warehouse) => DropdownMenuItem<String>(value: warehouse.id, child: Text(warehouse.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (value) => setState(() => _selectedWarehouse = value),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _CountCard(label: 'عدد الأرصدة', count: filtered.length, icon: Icons.inventory_outlined)),
        const SizedBox(width: 8),
        Expanded(child: _CountCard(label: 'المستودعات', count: selected == null ? _warehouses.length : 1, icon: Icons.warehouse_outlined)),
      ]),
      Text('مجموع الكميات الفعلية: ${totalActual.toStringAsFixed(2)} • المحجوز: ${totalReserved.toStringAsFixed(2)}'),
      if (_inventoryLoading) const LinearProgressIndicator(),
      if (_inventoryError != null) _errorCard(_inventoryError!),
      if (filtered.isEmpty && !_inventoryLoading)
        const Card(child: ListTile(title: Text('لا توجد أرصدة مطابقة لهذا المستودع'))),
      ...filtered.map((balance) => Card(child: ListTile(
        title: Text(balance.itemCode),
        subtitle: Text('${balance.warehouse}\nمحجوز: ${balance.reservedQty} • متوقع: ${balance.projectedQty}'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(balance.actualQty.toStringAsFixed(2), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text('متاح: ${balance.availableQty.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
          Text(balance.stockUom ?? '—', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ))),
    ]);
  }

  Widget _buildWarehousesPage() {
    final query = _warehouseSearch.trim().toLowerCase();
    final filtered = _warehouses.where((warehouse) =>
      warehouse.name.toLowerCase().contains(query) || warehouse.id.toLowerCase().contains(query) ||
      (warehouse.company ?? '').toLowerCase().contains(query)
    ).toList(growable: false);
    return ListView(padding: const EdgeInsets.all(18), children: [
      _pageHeader('المستودعات', 'المستودعات الفعلية المتاحة للمستخدم', Icons.warehouse_outlined),
      const SizedBox(height: 16),
      TextField(
        controller: _warehouseSearchController,
        decoration: InputDecoration(
          labelText: 'ابحث عن مستودع أو شركة',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _warehouseSearch.isEmpty ? null : IconButton(
            onPressed: () { _warehouseSearchController.clear(); setState(() => _warehouseSearch = ''); },
            icon: const Icon(Icons.clear),
          ),
        ),
        onChanged: (value) => setState(() => _warehouseSearch = value),
      ),
      const SizedBox(height: 10),
      Text('${filtered.length} مستودع من ${_warehouses.length} مستودع محمّل'),
      if (_inventoryLoading) const LinearProgressIndicator(),
      if (_inventoryError != null) _errorCard(_inventoryError!),
      if (filtered.isEmpty && !_inventoryLoading)
        const Card(child: ListTile(title: Text('لا توجد مستودعات مطابقة'))),
      ...filtered.map((warehouse) {
        final count = _stockBalances.where((row) => row.warehouse == warehouse.id).length;
        return Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.warehouse_outlined)),
          title: Text(warehouse.name),
          subtitle: Text('${warehouse.company ?? 'شركة غير محددة'} • $count أرصدة'),
          onTap: () => setState(() { _selectedWarehouse = warehouse.id; _selectedTab = 2; }),
        ));
      }),
    ]);
  }

  void _showInvoiceDetails(String documentType, String invoiceId) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FutureBuilder<Map<String, dynamic>>(
            future: _api.fetchInvoiceDocument(documentType, invoiceId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(height: 220, child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return SizedBox(height: 180, child: Center(child: Text('تعذر تحميل تفاصيل الفاتورة: ${snapshot.error}')));
              }
              final document = snapshot.data ?? const <String, dynamic>{};
              final rawItems = document['items'];
              final lines = <ErpInvoiceLine>[];
              if (rawItems is List) {
                for (final row in rawItems) {
                  if (row is Map<String, dynamic>) {
                    try { lines.add(ErpInvoiceLine.fromJson(row)); } catch (_) {}
                  }
                }
              }
              final currency = document['currency'] is String ? document['currency'] as String : '';
              String amount(String field) {
                final value = document[field];
                if (value is num) return '${value.toStringAsFixed(2)} $currency';
                return '${value?.toString() ?? '—'} $currency';
              }
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
                child: ListView(shrinkWrap: true, children: [
                  Text(invoiceId, style: Theme.of(context).textTheme.titleLarge),
                  Text('$documentType • ${document['status']?.toString() ?? 'حالة غير محددة'}'),
                  const Divider(height: 24),
                  ListTile(title: const Text('الإجمالي'), trailing: Text(amount('grand_total'))),
                  ListTile(title: const Text('المبلغ المتبقي'), trailing: Text(amount('outstanding_amount'))),
                  ListTile(title: const Text('تاريخ الفاتورة'), trailing: Text(document['posting_date']?.toString() ?? '—')),
                  ListTile(title: const Text('تاريخ الاستحقاق'), trailing: Text(document['due_date']?.toString() ?? '—')),
                  const Divider(height: 24),
                  Text('بنود الفاتورة (${lines.length})', style: Theme.of(context).textTheme.titleMedium),
                  if (lines.isEmpty) const ListTile(title: Text('لا توجد بنود ظاهرة أو لا تتوفر صلاحية قراءتها.')),
                  ...lines.map((line) => Card(child: ListTile(
                    title: Text(line.itemName),
                    subtitle: Text('${line.itemCode} • الكمية: ${line.qty.toStringAsFixed(2)} ${line.uom ?? ''}${line.warehouse == null ? '' : ' • ${line.warehouse}'}'),
                    trailing: Text('${line.amount.toStringAsFixed(2)} $currency'),
                  ))),
                  const SizedBox(height: 8),
                  const Text('تفاصيل للعرض فقط. لا يتم تعديل الفاتورة أو ترحيلها من هذه الشاشة.', textAlign: TextAlign.center),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSalesPage() {
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Expanded(child: Row(children: [const CircleAvatar(child: Icon(Icons.receipt_long_outlined)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('المعاملات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), Text('المبيعات والمشتريات والعملاء والموردون للعرض فقط', style: Theme.of(context).textTheme.bodySmall)]))])),
        IconButton(tooltip: 'تحديث المبيعات', onPressed: _salesLoading ? null : _loadSales, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'تحديث المشتريات', onPressed: _purchaseLoading ? null : _loadPurchases, icon: const Icon(Icons.shopping_cart_outlined)),
      ]),
      if (_salesLoading) const LinearProgressIndicator(),
      if (_salesError != null) _errorCard(_salesError!),
      const SizedBox(height: 12),
      Text('فواتير المبيعات (${_salesInvoices.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_salesInvoices.isEmpty && !_salesLoading) const Card(child: ListTile(title: Text('لا توجد فواتير ظاهرة أو تعذر تحميلها'))),
      ..._salesInvoices.map((invoice) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
        title: Text(invoice.id),
        subtitle: Text('${invoice.customerName} • ${invoice.postingDate ?? '—'}\n${invoice.status ?? 'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}'),
        isThreeLine: true,
        trailing: Text(invoice.grandTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => _showInvoiceDetails('Sales Invoice', invoice.id),
      ))),
      const SizedBox(height: 18),
      Text('العملاء (${_customers.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_customers.isEmpty && !_salesLoading) const Card(child: ListTile(title: Text('لا توجد بيانات عملاء ظاهرة'))),
      ..._customers.map((customer) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(customer.name),
        subtitle: Text([customer.id, if (customer.group != null) customer.group!, if (customer.territory != null) customer.territory!].join(' • ')),
      ))),
      const Divider(height: 28),
      if (_purchaseLoading) const LinearProgressIndicator(),
      if (_purchaseError != null) _errorCard(_purchaseError!),
      Text('فواتير المشتريات (${_purchaseInvoices.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_purchaseInvoices.isEmpty && !_purchaseLoading) const Card(child: ListTile(title: Text('لا توجد فواتير مشتريات ظاهرة'))),
      ..._purchaseInvoices.map((invoice) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.shopping_cart_outlined)),
        title: Text(invoice.id),
        subtitle: Text('${invoice.supplierName} • ${invoice.postingDate ?? '—'}\n${invoice.status ?? 'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}'),
        isThreeLine: true,
        trailing: Text(invoice.grandTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => _showInvoiceDetails('Purchase Invoice', invoice.id),
      ))),
      const SizedBox(height: 18),
      Text('الموردون (${_suppliers.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_suppliers.isEmpty && !_purchaseLoading) const Card(child: ListTile(title: Text('لا توجد بيانات موردين ظاهرة'))),
      ..._suppliers.map((supplier) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
        title: Text(supplier.name),
        subtitle: Text([supplier.id, if (supplier.group != null) supplier.group!, if (supplier.type != null) supplier.type!].join(' • ')),
      ))),
      const SizedBox(height: 10),
      Text('هذه الشاشة للقراءة فقط؛ لا تنشئ أو تعدّل أو ترحّل الفواتير.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildLogin() {
    return Center(
      key: const ValueKey('login'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 68),
              const SizedBox(height: 18),
              Text('ERPNext للجوال',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('اتصل بنظام ERPNext الخاص بك',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط الخادم',
                  hintText: 'https://erp.example.com',
                  prefixIcon: Icon(Icons.link),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _userController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم أو البريد',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                onSubmitted: (_) { if (!_busy) _login(); },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: Text(_busy ? 'جارٍ الاتصال...' : 'تسجيل الدخول'),
              ),
              const SizedBox(height: 18),
              Text(
                'نسخة تأسيسية: يلزم تشغيل خادم ERPNext وإدخال رابطه قبل تسجيل الدخول.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      key: const ValueKey('dashboard'),
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          const CircleAvatar(child: Icon(Icons.business)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('لوحة التحكم', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(_user ?? ''),
            ],
          )),
          IconButton(tooltip: 'تسجيل الخروج', onPressed: _busy ? null : _logout, icon: const Icon(Icons.logout)),
        ]),
        const SizedBox(height: 24),
        Card(
          color: scheme.primaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.cloud_done_outlined, size: 30),
              SizedBox(height: 10),
              Text('تم الاتصال بخادم ERPNext', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              SizedBox(height: 5),
              Text('تسجيل الدخول والتحقق من الجلسة يعملان عبر واجهة Frappe API.'),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('شركات النظام', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'تحديث الشركات', onPressed: _companiesLoading ? null : _loadCompanies, icon: const Icon(Icons.refresh)),
        ]),
        if (_companiesLoading)
          const LinearProgressIndicator()
        else if (_companyError != null)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_companyError!, style: TextStyle(color: scheme.error))))
        else if (_companies.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('لا توجد شركات ظاهرة لهذا المستخدم'), subtitle: Text('قد لا توجد شركات أو قد تكون صلاحية القراءة محدودة.')))
        else ...[
          Text('تم جلب ${_companies.length} شركة من الخادم.'),
          ..._companies.map((company) => Card(child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.business_outlined)),
            title: Text(company.name),
            subtitle: company.abbr == null ? null : Text('الاختصار: ${company.abbr}'),
          ))),
        ],

        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: Text('بيانات المخزون', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          IconButton(tooltip: 'تحديث بيانات المخزون', onPressed: _inventoryLoading ? null : _loadInventory, icon: const Icon(Icons.refresh)),
        ]),
        if (_inventoryLoading)
          const LinearProgressIndicator(),
        if (_inventoryError != null)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(_inventoryError!, style: TextStyle(color: scheme.error)))),
        ...[
          Row(children: [
            Expanded(child: _CountCard(label: 'الأصناف', count: _items.length, icon: Icons.inventory_2_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _CountCard(label: 'المستودعات', count: _warehouses.length, icon: Icons.warehouse_outlined)),
          ]),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('أحدث الأصناف', style: Theme.of(context).textTheme.titleSmall),
            ..._items.take(8).map((item) => ListTile(
              dense: true,
              leading: const Icon(Icons.sell_outlined),
              title: Text(item.name),
              subtitle: Text([item.code, if (item.group != null) item.group!, if (item.stockUom != null) item.stockUom!].join(' • ')),
            )),
          ],

          if (_stockBalances.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('أرصدة الأصناف حسب المستودع', style: Theme.of(context).textTheme.titleSmall),
            ..._stockBalances.take(30).map((balance) => ListTile(
              dense: true,
              leading: const Icon(Icons.inventory_outlined),
              title: Text(balance.itemCode),
              subtitle: Text(balance.warehouse),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(balance.actualQty.toStringAsFixed(2), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                Text(balance.stockUom ?? '—', style: Theme.of(context).textTheme.bodySmall),
              ]),
            )),
            if (_stockBalances.length > 30) Text('يُعرض أول 30 رصيداً من أصل ${_stockBalances.length}.'),
          ] else ...[
            const SizedBox(height: 8),
            const Text('لا توجد أرصدة فعلية غير صفرية ظاهرة للمستخدم.'),
          ],

          if (_warehouses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('المستودعات', style: Theme.of(context).textTheme.titleSmall),
            ..._warehouses.take(8).map((warehouse) => ListTile(
              dense: true,
              leading: const Icon(Icons.warehouse_outlined),
              title: Text(warehouse.name),
              subtitle: warehouse.company == null ? null : Text(warehouse.company!),
            )),
          ],
        ],
        const SizedBox(height: 18),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.receipt_long_outlined)),
          title: const Text('المعاملات'),
          subtitle: const Text('عرض فواتير المبيعات والمشتريات والعملاء والموردين'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => setState(() => _selectedTab = 4),
        )),
        const SizedBox(height: 10),
        Text('العمليات الحالية للقراءة فقط. إنشاء الفواتير وترحيلها والمدفوعات غير مفعّلة بعد.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}


class _CountCard extends StatelessWidget {
  const _CountCard({required this.label, required this.count, required this.icon});
  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(icon, size: 26),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text('$count', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ])),
      ]),
    ),
  );
}

