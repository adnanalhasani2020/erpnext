import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'sales_invoice_composer.dart';
import 'sales_workflow_page.dart';
import 'purchase_workflow_page.dart';
import 'stock_workflow_page.dart';
import 'invoice_action_policy.dart';
import 'workspace_report_page.dart';
import 'workspace_native_destination_page.dart';
import 'sales_pricing_page.dart';
import 'payment_reconciliation_page.dart';
import 'process_payment_reconciliation_page.dart';
import 'process_payment_reconciliation_log_page.dart';
import 'bank_reconciliation_page.dart';
import 'item_catalog_page.dart';
import 'chart_of_accounts_page.dart';
import 'journal_entries_page.dart';
import 'hr_workflows_page.dart';
import 'payroll_page.dart';
import 'warehouse_hierarchy_page.dart';
import 'warehouse_list_page.dart';
import 'item_list_page.dart';
import 'stock_balances_page.dart';
import 'sales_overview_page.dart';
import 'sales_invoices_page.dart';
import 'customer_directory_page.dart';
import 'supplier_directory_page.dart';
import 'doctype_workspace_page.dart';
import 'models/erp_models.dart';
import 'login_page.dart';
import 'dashboard_page.dart';
import 'guest_reports_page.dart';
import 'customer_ledger_sheet.dart';
import 'supplier_ledger_sheet.dart';
import 'customer_profile_editor_sheet.dart';

export 'api/frappe_api.dart';

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
  final _loginFormKey = GlobalKey<FormState>();
  bool _showPassword = false;
  bool _isGuest = false;
  final _itemSearchController = TextEditingController();
  final _stockSearchController = TextEditingController();
  final _warehouseSearchController = TextEditingController();
  final _customerSearchController = TextEditingController();
  final _salesInvoiceSearchController = TextEditingController();
  final _supplierSearchController = TextEditingController();
  final _purchaseInvoiceSearchController = TextEditingController();
  String _customerSearch = '';
  String _salesInvoiceSearch = '';
  String _supplierSearch = '';
  String _purchaseInvoiceSearch = '';
  bool _searchingWarehouses = false;
  bool _searchingCustomers = false;
  bool _searchingSalesInvoices = false;
  bool _searchingSuppliers = false;
  bool _searchingPurchaseInvoices = false;
  String _itemSearch = '';
  String _stockSearch = '';
  String _warehouseSearch = '';
  String? _selectedWarehouse;
  int _selectedTab = 0;
  bool _busy = false;
  int _loginAttempt = 0;
  String? _error;
  String? _user;
  List<ErpCompany> _companies = const [];
  String? _companyError;
  bool _companiesLoading = false;
  List<ErpItem> _items = const [];
  List<ErpWarehouse> _warehouses = const [];
  List<ErpStockBalance> _stockBalances = const [];
  int _itemsOffset = 0, _warehousesOffset = 0, _stockOffset = 0;
  bool _itemsHasMore = false, _warehousesHasMore = false, _stockHasMore = false;
  bool _loadingMoreItems = false, _loadingMoreWarehouses = false, _loadingMoreStock = false;
  String? _inventoryError;
  bool _inventoryLoading = false;
  List<ErpCustomer> _customers = const [];
  List<ErpSalesInvoice> _salesInvoices = const [];
  int _customersOffset = 0, _salesInvoicesOffset = 0;
  bool _customersHasMore = false, _salesInvoicesHasMore = false;
  bool _loadingMoreCustomers = false, _loadingMoreSalesInvoices = false;
  String? _salesError;
  bool _salesLoading = false;
  List<ErpSupplier> _suppliers = const [];
  List<ErpPurchaseInvoice> _purchaseInvoices = const [];
  int _suppliersOffset = 0, _purchaseInvoicesOffset = 0;
  bool _suppliersHasMore = false, _purchaseInvoicesHasMore = false;
  bool _loadingMoreSuppliers = false, _loadingMorePurchaseInvoices = false;
  String? _purchaseError;
  bool _purchaseLoading = false;

  @override
  void dispose() {
    _api.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _itemSearchController.dispose();
    _stockSearchController.dispose();
    _warehouseSearchController.dispose();
    _customerSearchController.dispose();
    _salesInvoiceSearchController.dispose();
    _supplierSearchController.dispose();
    _purchaseInvoiceSearchController.dispose();
    super.dispose();
  }

  bool _isCurrentSession(int generation) =>
      mounted && _user != null && _api.sessionGeneration == generation;

  Future<void> _login() async {
    final attempt = ++_loginAttempt;
    FocusScope.of(context).unfocus();
    if (!(_loginFormKey.currentState?.validate() ?? false)) return;
    setState(() { _busy = true; _error = null; });
    try {
      _api.configure(_urlController.text.trim());
      final user = await _api.login(_userController.text, _passwordController.text);
      if (!mounted || attempt != _loginAttempt) return;
      setState(() {
        _user = user;
        _isGuest = false;
        _passwordController.clear();
        _companiesLoading = true;
        _companyError = null;
      });
      await _loadCompanies();
      if (!mounted || attempt != _loginAttempt) return;
      await _loadInventory();
      if (!mounted || attempt != _loginAttempt) return;
      await _loadSales();
      if (!mounted || attempt != _loginAttempt) return;
      await _loadPurchases();
    } catch (error) {
      if (!mounted || attempt != _loginAttempt) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && attempt == _loginAttempt) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    final attempt = ++_loginAttempt;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    try {
      // Guest access is fully local: no server URL, authentication, or HTTP calls.
      _api.enableGuestMode();
      if (!mounted || attempt != _loginAttempt) return;
      setState(() {
        _user = 'ضيف';
        _isGuest = true;
        // Clearly synthetic sample records make the main screens useful offline.
        _companies = const [
          ErpCompany(name: 'شركة العرض التجريبي', abbr: 'DEMO', defaultCurrency: 'YER'),
        ];
        _items = const [
          ErpItem(code: 'DEMO-001', name: 'هاتف ذكي - عينة', group: 'إلكترونيات', stockUom: 'قطعة', isStockItem: true),
          ErpItem(code: 'DEMO-002', name: 'سماعة لاسلكية - عينة', group: 'إلكترونيات', stockUom: 'قطعة', isStockItem: true),
          ErpItem(code: 'DEMO-003', name: 'شاحن سريع - عينة', group: 'إكسسوارات', stockUom: 'قطعة', isStockItem: true),
          ErpItem(code: 'DEMO-004', name: 'كابل USB - عينة', group: 'إكسسوارات', stockUom: 'قطعة', isStockItem: true),
        ];
        _warehouses = const [
          ErpWarehouse(id: 'DEMO-WH-01', name: 'المستودع الرئيسي - تجريبي', company: 'شركة العرض التجريبي'),
          ErpWarehouse(id: 'DEMO-WH-02', name: 'معرض البيع - تجريبي', company: 'شركة العرض التجريبي'),
        ];
        _stockBalances = const [
          ErpStockBalance(itemCode: 'DEMO-001', warehouse: 'DEMO-WH-01', actualQty: 12, reservedQty: 2, projectedQty: 10, stockUom: 'قطعة', valuationRate: 85000, stockValue: 1020000),
          ErpStockBalance(itemCode: 'DEMO-002', warehouse: 'DEMO-WH-01', actualQty: 25, reservedQty: 3, projectedQty: 22, stockUom: 'قطعة', valuationRate: 12000, stockValue: 300000),
          ErpStockBalance(itemCode: 'DEMO-003', warehouse: 'DEMO-WH-02', actualQty: 3, reservedQty: 1, projectedQty: 2, stockUom: 'قطعة', valuationRate: 6500, stockValue: 19500),
          ErpStockBalance(itemCode: 'DEMO-004', warehouse: 'DEMO-WH-02', actualQty: 40, reservedQty: 0, projectedQty: 40, stockUom: 'قطعة', valuationRate: 1800, stockValue: 72000),
        ];
        _customers = const [
          ErpCustomer(id: 'DEMO-CUST-01', name: 'عميل تجريبي أول', type: 'Individual', group: 'تجريبي', territory: 'صنعاء'),
          ErpCustomer(id: 'DEMO-CUST-02', name: 'مؤسسة العرض التجريبي', type: 'Company', group: 'تجريبي', territory: 'تعز'),
        ];
        _salesInvoices = const [
          ErpSalesInvoice(id: 'DEMO-SINV-001', customer: 'DEMO-CUST-01', customerName: 'عميل تجريبي أول', postingDate: '2026-11-08', currency: 'YER', grandTotal: 97000, outstandingAmount: 25000, status: 'غير مدفوعة جزئياً'),
          ErpSalesInvoice(id: 'DEMO-SINV-002', customer: 'DEMO-CUST-02', customerName: 'مؤسسة العرض التجريبي', postingDate: '2026-11-07', currency: 'YER', grandTotal: 24000, outstandingAmount: 0, status: 'مدفوعة'),
        ];
        _suppliers = const [
          ErpSupplier(id: 'DEMO-SUP-01', name: 'مورد تجريبي للإلكترونيات', group: 'تجريبي', type: 'Company'),
          ErpSupplier(id: 'DEMO-SUP-02', name: 'مورد تجريبي للإكسسوارات', group: 'تجريبي', type: 'Company'),
        ];
        _purchaseInvoices = const [
          ErpPurchaseInvoice(id: 'DEMO-PINV-001', supplier: 'DEMO-SUP-01', supplierName: 'مورد تجريبي للإلكترونيات', postingDate: '2026-11-06', currency: 'YER', grandTotal: 650000, outstandingAmount: 150000, status: 'غير مدفوعة جزئياً'),
        ];
        _companiesLoading = false;
        _companyError = null;
        _inventoryLoading = false;
        _inventoryError = null;
        _salesLoading = false;
        _salesError = null;
        _purchaseLoading = false;
        _purchaseError = null;
      });
    } catch (error) {
      if (!mounted || attempt != _loginAttempt) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && attempt == _loginAttempt) setState(() => _busy = false);
    }
  }

  Future<void> _loadCompanies() async {
    if (!mounted) return;
    final sessionGeneration = _api.sessionGeneration;

    setState(() { _companiesLoading = true; _companyError = null; });
    try {
      final companies = await _api.fetchCompanies();
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() => _companies = companies);
    } catch (error) {
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _companies = const [];
        _companyError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _companiesLoading = false);
    }
  }


  Future<void> _loadInventory() async {
    if (!mounted || _inventoryLoading) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() { _inventoryLoading = true; _inventoryError = null; });
    final errors = <String>[];

    try {
      final items = await _api.fetchItems();
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _items = items; _itemsOffset = items.length; _itemsHasMore = items.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('الأصناف: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    if (!_isCurrentSession(sessionGeneration)) return;
    try {
      final warehouses = await _api.fetchWarehouses(search: _warehouseSearch.isEmpty ? null : _warehouseSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _warehouses = warehouses; _warehousesOffset = warehouses.length; _warehousesHasMore = warehouses.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('المستودعات: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    if (!_isCurrentSession(sessionGeneration)) return;
    try {
      final balances = await _api.fetchStockBalances(
        search: _stockSearch.isEmpty ? null : _stockSearch,
        warehouse: _selectedWarehouse,
      );
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _stockBalances = balances; _stockOffset = balances.length; _stockHasMore = balances.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('الأرصدة: ${error.toString().replaceFirst('Exception: ', '')}');
    }

    if (!_isCurrentSession(sessionGeneration)) return;
    setState(() {
      _inventoryError = errors.isEmpty ? null : errors.join('\n');
      _inventoryLoading = false;
    });
  }

  Future<void> _searchItems(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _itemSearch = query);
      return;
    }
    if (_inventoryLoading || _loadingMoreItems) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _itemSearch = query;
      _items = const [];
      _itemsOffset = 0;
      _itemsHasMore = false;
      _inventoryLoading = true;
      _inventoryError = null;
    });
    try {
      final page = await _api.fetchItems(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _items = page;
        _itemsOffset = page.length;
        _itemsHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() {
          _inventoryError =
              'تعذر البحث في الأصناف: ${error.toString().replaceFirst('Exception: ', '')}';
        });
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _inventoryLoading = false);
    }
  }

  Future<void> _loadMoreItems() async {
    if (_loadingMoreItems || !_itemsHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreItems = true);
    try {
      final page = await _api.fetchItems(start: _itemsOffset, search: _itemSearch.isEmpty ? null : _itemSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _items = [..._items, ...page];
        _itemsOffset += page.length;
        _itemsHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _inventoryError = 'تعذر تحميل بقية الأصناف: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreItems = false);
    }
  }

  Future<void> _searchWarehouses(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _warehouseSearch = query);
      return;
    }
    if (_inventoryLoading || _loadingMoreWarehouses || _searchingWarehouses) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _warehouseSearch = query;
      _warehouses = const [];
      _warehousesOffset = 0;
      _warehousesHasMore = false;
      _searchingWarehouses = true;
      _inventoryError = null;
    });
    try {
      final page = await _api.fetchWarehouses(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _warehouses = page;
        _warehousesOffset = page.length;
        _warehousesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _inventoryError =
            'تعذر البحث في المستودعات: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _searchingWarehouses = false);
      }
    }
  }

  Future<void> _loadMoreWarehouses() async {
    if (_loadingMoreWarehouses || !_warehousesHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreWarehouses = true);
    try {
      final page = await _api.fetchWarehouses(start: _warehousesOffset, search: _warehouseSearch.isEmpty ? null : _warehouseSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _warehouses = [..._warehouses, ...page];
        _warehousesOffset += page.length;
        _warehousesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _inventoryError = 'تعذر تحميل بقية المستودعات: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreWarehouses = false);
    }
  }

  Future<void> _searchStockBalances(String value, {bool updateWarehouse = false, String? warehouse}) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() {
        _stockSearch = query;
        if (updateWarehouse) _selectedWarehouse = warehouse;
      });
      return;
    }
    if (_loadingMoreStock || _inventoryLoading) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _stockSearch = query;
      if (updateWarehouse) _selectedWarehouse = warehouse;
      _stockBalances = const [];
      _stockOffset = 0;
      _stockHasMore = false;
      _inventoryLoading = true;
      _inventoryError = null;
    });
    try {
      final page = await _api.fetchStockBalances(
        search: query.isEmpty ? null : query,
        warehouse: _selectedWarehouse,
      );
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _stockBalances = page;
        _stockOffset = page.length;
        _stockHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _inventoryError =
            'تعذر تحميل أرصدة المخزون: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _inventoryLoading = false);
      }
    }
  }

  Future<void> _loadMoreStock() async {
    if (_loadingMoreStock || !_stockHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreStock = true);
    try {
      final page = await _api.fetchStockBalances(start: _stockOffset, search: _stockSearch, warehouse: _selectedWarehouse);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _stockBalances = [..._stockBalances, ...page];
        _stockOffset += page.length;
        _stockHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _inventoryError = 'تعذر تحميل بقية الأرصدة: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreStock = false);
    }
  }

  Future<void> _loadSales() async {
    if (!mounted || _salesLoading) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() { _salesLoading = true; _salesError = null; });
    final errors = <String>[];
    try {
      final customers = await _api.fetchCustomers(search: _customerSearch.isEmpty ? null : _customerSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _customers = customers; _customersOffset = customers.length; _customersHasMore = customers.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('العملاء: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!_isCurrentSession(sessionGeneration)) return;
    try {
      final invoices = await _api.fetchSalesInvoices(search: _salesInvoiceSearch.isEmpty ? null : _salesInvoiceSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _salesInvoices = invoices; _salesInvoicesOffset = invoices.length; _salesInvoicesHasMore = invoices.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('الفواتير: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!_isCurrentSession(sessionGeneration)) return;
    setState(() { _salesError = errors.isEmpty ? null : errors.join('\n'); _salesLoading = false; });
  }

  Future<void> _loadPurchases() async {
    if (!mounted || _purchaseLoading) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() { _purchaseLoading = true; _purchaseError = null; });
    final errors = <String>[];
    try {
      final suppliers = await _api.fetchSuppliers(search: _supplierSearch.isEmpty ? null : _supplierSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _suppliers = suppliers; _suppliersOffset = suppliers.length; _suppliersHasMore = suppliers.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('الموردون: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!_isCurrentSession(sessionGeneration)) return;
    try {
      final invoices = await _api.fetchPurchaseInvoices(search: _purchaseInvoiceSearch.isEmpty ? null : _purchaseInvoiceSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() { _purchaseInvoices = invoices; _purchaseInvoicesOffset = invoices.length; _purchaseInvoicesHasMore = invoices.length == FrappeApi.pageSize; });
    } catch (error) {
      errors.add('فواتير المشتريات: ${error.toString().replaceFirst('Exception: ', '')}');
    }
    if (!_isCurrentSession(sessionGeneration)) return;
    setState(() { _purchaseError = errors.isEmpty ? null : errors.join('\n'); _purchaseLoading = false; });
  }


  Future<void> _searchCustomers(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _customerSearch = query);
      return;
    }
    if (_salesLoading || _loadingMoreCustomers || _searchingCustomers) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingCustomers = true;
      _customerSearch = query;
      _customers = const [];
      _customersOffset = 0;
      _customersHasMore = false;
      _salesError = null;
    });
    try {
      final page = await _api.fetchCustomers(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _customers = page;
        _customersOffset = page.length;
        _customersHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (exception) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _salesError =
            'تعذر البحث في العملاء: ${exception.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _searchingCustomers = false);
    }
  }


  Future<void> _searchSalesInvoices(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _salesInvoiceSearch = query);
      return;
    }
    if (_salesLoading || _loadingMoreSalesInvoices || _searchingSalesInvoices) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingSalesInvoices = true;
      _salesInvoiceSearch = query;
      _salesInvoices = const [];
      _salesInvoicesOffset = 0;
      _salesInvoicesHasMore = false;
      _salesError = null;
    });
    try {
      final page = await _api.fetchSalesInvoices(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _salesInvoices = page;
        _salesInvoicesOffset = page.length;
        _salesInvoicesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (exception) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _salesError =
            'تعذر البحث في فواتير المبيعات: ${exception.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _searchingSalesInvoices = false);
    }
  }


  Future<void> _searchSuppliers(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _supplierSearch = query);
      return;
    }
    if (_purchaseLoading || _loadingMoreSuppliers || _searchingSuppliers) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingSuppliers = true;
      _supplierSearch = query;
      _suppliers = const [];
      _suppliersOffset = 0;
      _suppliersHasMore = false;
      _purchaseError = null;
    });
    try {
      final page = await _api.fetchSuppliers(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _suppliers = page;
        _suppliersOffset = page.length;
        _suppliersHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (exception) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _purchaseError =
            'تعذر البحث في الموردين: ${exception.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _searchingSuppliers = false);
    }
  }


  Future<void> _searchPurchaseInvoices(String value) async {
    final query = value.trim();
    if (_isGuest) {
      setState(() => _purchaseInvoiceSearch = query);
      return;
    }
    if (_purchaseLoading || _loadingMorePurchaseInvoices || _searchingPurchaseInvoices) return;
    final sessionGeneration = _api.sessionGeneration;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchingPurchaseInvoices = true;
      _purchaseInvoiceSearch = query;
      _purchaseInvoices = const [];
      _purchaseInvoicesOffset = 0;
      _purchaseInvoicesHasMore = false;
      _purchaseError = null;
    });
    try {
      final page = await _api.fetchPurchaseInvoices(search: query.isEmpty ? null : query);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _purchaseInvoices = page;
        _purchaseInvoicesOffset = page.length;
        _purchaseInvoicesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (exception) {
      if (_isCurrentSession(sessionGeneration)) {
        setState(() => _purchaseError =
            'تعذر البحث في فواتير المشتريات: ${exception.toString().replaceFirst('Exception: ', '')}');
      }
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _searchingPurchaseInvoices = false);
    }
  }


  Future<void> _loadMoreCustomers() async {
    if (_loadingMoreCustomers || !_customersHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreCustomers = true);
    try {
      final page = await _api.fetchCustomers(start: _customersOffset, search: _customerSearch.isEmpty ? null : _customerSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _customers = [..._customers, ...page];
        _customersOffset += page.length;
        _customersHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _salesError = 'تعذر تحميل بقية العملاء: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreCustomers = false);
    }
  }

  Future<void> _loadMoreSalesInvoices() async {
    if (_loadingMoreSalesInvoices || !_salesInvoicesHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreSalesInvoices = true);
    try {
      final page = await _api.fetchSalesInvoices(start: _salesInvoicesOffset, search: _salesInvoiceSearch.isEmpty ? null : _salesInvoiceSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _salesInvoices = [..._salesInvoices, ...page];
        _salesInvoicesOffset += page.length;
        _salesInvoicesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _salesError = 'تعذر تحميل بقية فواتير المبيعات: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreSalesInvoices = false);
    }
  }

  Future<void> _loadMoreSuppliers() async {
    if (_loadingMoreSuppliers || !_suppliersHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMoreSuppliers = true);
    try {
      final page = await _api.fetchSuppliers(start: _suppliersOffset, search: _supplierSearch.isEmpty ? null : _supplierSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _suppliers = [..._suppliers, ...page];
        _suppliersOffset += page.length;
        _suppliersHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _purchaseError = 'تعذر تحميل بقية الموردين: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMoreSuppliers = false);
    }
  }

  Future<void> _loadMorePurchaseInvoices() async {
    if (_loadingMorePurchaseInvoices || !_purchaseInvoicesHasMore) return;
    final sessionGeneration = _api.sessionGeneration;
    setState(() => _loadingMorePurchaseInvoices = true);
    try {
      final page = await _api.fetchPurchaseInvoices(start: _purchaseInvoicesOffset, search: _purchaseInvoiceSearch.isEmpty ? null : _purchaseInvoiceSearch);
      if (!_isCurrentSession(sessionGeneration)) return;
      setState(() {
        _purchaseInvoices = [..._purchaseInvoices, ...page];
        _purchaseInvoicesOffset += page.length;
        _purchaseInvoicesHasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) {
      if (_isCurrentSession(sessionGeneration)) setState(() => _purchaseError = 'تعذر تحميل بقية فواتير المشتريات: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (_isCurrentSession(sessionGeneration)) setState(() => _loadingMorePurchaseInvoices = false);
    }
  }

  Future<void> _logout() async {
    _loginAttempt++;
    final logoutRequest = _api.logout();
    if (!mounted) {
      await logoutRequest;
      return;
    }
    setState(() {
      _user = null;
      _isGuest = false;
      _selectedTab = 0;
      _selectedWarehouse = null;
      _itemSearch = '';
      _warehouseSearch = '';
      _itemSearchController.clear();
      _warehouseSearchController.clear();
      _searchingWarehouses = false;
      _customerSearch = '';
      _salesInvoiceSearch = '';
      _supplierSearch = '';
      _purchaseInvoiceSearch = '';
      _customerSearchController.clear();
      _salesInvoiceSearchController.clear();
      _supplierSearchController.clear();
      _purchaseInvoiceSearchController.clear();
      _passwordController.clear();
      _showPassword = false;
      _error = null;
      _busy = true;
      _companies = const [];
      _companyError = null;
      _companiesLoading = false;
      _items = const [];
      _warehouses = const [];
      _stockBalances = const [];
      _itemsOffset = 0;
      _warehousesOffset = 0;
      _stockOffset = 0;
      _itemsHasMore = false;
      _warehousesHasMore = false;
      _stockHasMore = false;
      _loadingMoreItems = false;
      _loadingMoreWarehouses = false;
      _loadingMoreStock = false;
      _inventoryError = null;
      _inventoryLoading = false;
      _customers = const [];
      _salesInvoices = const [];
      _customersOffset = 0;
      _salesInvoicesOffset = 0;
      _customersHasMore = false;
      _salesInvoicesHasMore = false;
      _loadingMoreCustomers = false;
      _loadingMoreSalesInvoices = false;
      _searchingCustomers = false;
      _searchingSalesInvoices = false;
      _salesLoading = false;
      _salesError = null;
      _suppliers = const [];
      _purchaseInvoices = const [];
      _suppliersOffset = 0;
      _purchaseInvoicesOffset = 0;
      _suppliersHasMore = false;
      _purchaseInvoicesHasMore = false;
      _loadingMoreSuppliers = false;
      _loadingMorePurchaseInvoices = false;
      _searchingSuppliers = false;
      _searchingPurchaseInvoices = false;
      _purchaseLoading = false;
      _purchaseError = null;
    });
    await logoutRequest;
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _user == null ? LoginPage(
            formKey: _loginFormKey,
            urlController: _urlController,
            userController: _userController,
            passwordController: _passwordController,
            busy: _busy,
            showPassword: _showPassword,
            error: _error,
            onLogin: _login,
            onContinueAsGuest: _continueAsGuest,
            onTogglePassword: () => setState(() => _showPassword = !_showPassword),
          ) : _buildSelectedPage(),
        ),
      ),
      bottomNavigationBar: _user == null ? null : NavigationBar(
        selectedIndex: _selectedTab.clamp(0, _isGuest ? 5 : 4).toInt(),
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'الرئيسية'),
          const NavigationDestination(icon: Icon(Icons.sell_outlined), selectedIcon: Icon(Icons.sell), label: 'الأصناف'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'الأرصدة'),
          const NavigationDestination(icon: Icon(Icons.warehouse_outlined), selectedIcon: Icon(Icons.warehouse), label: 'المستودعات'),
          const NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps), label: 'مساحات العمل'),
          if (_isGuest)
            const NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'تقارير تجريبية'),
        ],
      ),
    );
  }



  Widget _buildSelectedPage() {
    switch (_selectedTab) {
      case 1: return _buildItemsPage();
      case 2: return _buildStockPage();
      case 3: return _buildWarehousesPage();
      case 4: return _isGuest ? _buildSalesPage() : ErpDocTypeDirectoryPage(api: _api, onOpenDefinition: _openDocTypeDefinition);
      case 5: return _isGuest ? const GuestReportsPage() : ErpDocTypeDirectoryPage(api: _api, onOpenDefinition: _openDocTypeDefinition);
      default: return DashboardPage(
        user: _user,
        isGuest: _isGuest,
        busy: _busy,
        onLogout: _logout,
        companies: _companies,
        companiesLoading: _companiesLoading,
        companyError: _companyError,
        onRefreshCompanies: _loadCompanies,
        inventoryLoading: _inventoryLoading,
        inventoryError: _inventoryError,
        onRefreshInventory: _loadInventory,
        items: _items,
        warehouses: _warehouses,
        stockBalances: _stockBalances,
        onOpenDocTypeDirectory: _openDocTypeDirectory,
      );
    }
  }

  Widget _guestDemoBanner() => const GuestDemoBanner();

  bool _requireServerAccess(String feature) {
    if (!_isGuest) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('ميزة "$feature" تحتاج إلى تسجيل الدخول إلى خادم ERPNext. وضع الضيف للعرض المحلي فقط.'),
        behavior: SnackBarBehavior.floating,
      ));
    return false;
  }

  Widget _buildItemsPage() => ItemListPage(
    items: _items,
    search: _itemSearch,
    searchController: _itemSearchController,
    guest: _isGuest,
    loading: _inventoryLoading,
    loadingMore: _loadingMoreItems,
    error: _inventoryError,
    hasMore: _itemsHasMore,
    onSearch: _searchItems,
    onLoadMore: _loadMoreItems,
    onShowDetails: _showItemDetails,
    onRefresh: _loadInventory,
  );

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
          if (item.isStockItem) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isGuest ? null : () {
                Navigator.of(context).pop();
                _openStockWorkflow(initialItemCode: item.code);
              },
              icon: const Icon(Icons.history),
              label: const Text('عرض حركات هذا الصنف'),
            ),
          ],
        ]),
      )),
    );
  }

  Widget _buildStockPage() => StockBalancesPage(
    stockBalances: _stockBalances,
    warehouses: _warehouses,
    search: _stockSearch,
    searchController: _stockSearchController,
    selectedWarehouse: _selectedWarehouse,
    guest: _isGuest,
    loading: _inventoryLoading,
    loadingMore: _loadingMoreStock,
    error: _inventoryError,
    hasMore: _stockHasMore,
    onSearch: _searchStockBalances,
    onOpenStockWorkflow: _openStockWorkflow,
    onSelectWarehouse: (value) => _searchStockBalances(
      _stockSearchController.text,
      updateWarehouse: true,
      warehouse: value,
    ),
    onLoadMore: _loadMoreStock,
    onRefresh: _loadInventory,
    onShowItemDetails: (balance) {
      final matches = _items.where((item) => item.code == balance.itemCode);
      if (matches.isNotEmpty) {
        _showItemDetails(matches.first);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تفاصيل الصنف غير موجودة ضمن البيانات المحمّلة. حدّث قائمة الأصناف أولاً.')),
        );
      }
    },
  );

  Widget _buildWarehousesPage() => WarehouseListPage(
    warehouses: _warehouses,
    search: _warehouseSearch,
    searchController: _warehouseSearchController,
    searching: _searchingWarehouses,
    guest: _isGuest,
    loading: _inventoryLoading,
    error: _inventoryError,
    stockBalances: _stockBalances,
    hasMore: _warehousesHasMore,
    loadingMore: _loadingMoreWarehouses,
    onSearch: _searchWarehouses,
    onOpenHierarchy: _openWarehouseHierarchy,
    onSelectWarehouse: (warehouse) {
      setState(() => _selectedTab = 2);
      _searchStockBalances(
        _stockSearchController.text,
        updateWarehouse: true,
        warehouse: warehouse.id,
      );
    },
    onLoadMore: _loadMoreWarehouses,
    onRefresh: _loadInventory,
  );

  void _openBankReconciliation({String? doctype}) {
    if (!_requireServerAccess('التسوية البنكية')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BankReconciliationPage(api: _api, companies: _companies, initialDoctype: doctype),
    ));
  }

  void _openPaymentReconciliation() {
    if (!_requireServerAccess('تسوية المدفوعات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PaymentReconciliationPage(api: _api, companies: _companies),
    ));
  }

  void _openProcessPaymentReconciliation() {
    if (!_requireServerAccess('التسوية الآلية الجماعية للمدفوعات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProcessPaymentReconciliationPage(api: _api, companies: _companies),
    ));
  }

  void _openProcessPaymentReconciliationLogs() {
    if (!_requireServerAccess('سجلات التسوية الآلية للمدفوعات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProcessPaymentReconciliationLogPage(api: _api),
    ));
  }

  void _openChartOfAccounts() {
    if (!_requireServerAccess('دليل الحسابات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ChartOfAccountsPage(api: _api, companies: _companies),
    ));
  }

  void _openJournalEntries() {
    if (!_requireServerAccess('القيود اليومية')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => JournalEntriesPage(api: _api, companies: _companies),
    ));
  }

  void _openPayroll() {
    if (!_requireServerAccess('دورة الرواتب')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PayrollPage(api: _api, companies: _companies),
    ));
  }

  void _openDocTypeDirectory() {
    if (!_requireServerAccess('شاشات ERPNext المستقلة')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ErpDocTypeDirectoryPage(api: _api, onOpenDefinition: _openDocTypeDefinition),
    ));
  }

  void _openOriginalDocTypeList(String doctype) {
    if (!_requireServerAccess(doctype)) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WorkspaceNativeDestinationPage(
        api: _api,
        title: doctype,
        linkType: 'DocTypeList',
        target: doctype,
      ),
    ));
  }

  void _openSalesInvoices() {
    if (!_requireServerAccess('فواتير المبيعات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StatefulBuilder(
        builder: (pageContext, setPageState) => SalesInvoicesPage(
          loading: _salesLoading,
          error: _salesError,
          invoices: _salesInvoices,
          search: _salesInvoiceSearch,
          searchController: _salesInvoiceSearchController,
          searching: _searchingSalesInvoices,
          hasMore: _salesInvoicesHasMore,
          loadingMore: _loadingMoreSalesInvoices,
          onRefresh: () async {
            await _loadSales();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onSearch: (value) async {
            await _searchSalesInvoices(value);
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onLoadMore: () async {
            await _loadMoreSalesInvoices();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onOpenInvoice: (name) async {
            await _showInvoiceDetails('Sales Invoice', name);
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onOpenDesk: () => _openOriginalDocTypeList('Sales Invoice'),
          onCreateInvoice: () async {
            await _openSalesInvoiceComposer();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
        ),
      ),
    ));
  }

  void _openCustomerDirectory() {
    if (!_requireServerAccess('العملاء')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StatefulBuilder(
        builder: (pageContext, setPageState) => CustomerDirectoryPage(
          loading: _salesLoading,
          error: _salesError,
          customers: _customers,
          search: _customerSearch,
          searchController: _customerSearchController,
          searching: _searchingCustomers,
          hasMore: _customersHasMore,
          loadingMore: _loadingMoreCustomers,
          onRefresh: () async {
            await _loadSales();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onSearch: (value) async {
            await _searchCustomers(value);
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onLoadMore: () async {
            await _loadMoreCustomers();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onEdit: (customer) async {
            await _editCustomerProfile(customer);
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onOpenLedger: _showCustomerLedger,
          onOpenDesk: () => _openOriginalDocTypeList('Customer'),
        ),
      ),
    ));
  }

  void _openSupplierDirectory() {
    if (!_requireServerAccess('الموردون')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StatefulBuilder(
        builder: (pageContext, setPageState) => SupplierDirectoryPage(
          loading: _purchaseLoading,
          error: _purchaseError,
          suppliers: _suppliers,
          search: _supplierSearch,
          searchController: _supplierSearchController,
          searching: _searchingSuppliers,
          hasMore: _suppliersHasMore,
          loadingMore: _loadingMoreSuppliers,
          onRefresh: () async {
            await _loadPurchases();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onSearch: (value) async {
            await _searchSuppliers(value);
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onLoadMore: () async {
            await _loadMoreSuppliers();
            if (ModalRoute.of(pageContext)?.isCurrent ?? false) setPageState(() {});
          },
          onOpenLedger: _showSupplierLedger,
          onOpenDesk: () => _openOriginalDocTypeList('Supplier'),
        ),
      ),
    ));
  }

  void _openWorkspaceReport(String reportName, {Map<String, dynamic> initialFilters = const {}}) {
    if (!_requireServerAccess('تشغيل التقرير')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WorkspaceReportPage(
        api: _api,
        companies: _companies,
        reportName: reportName,
        initialFilters: initialFilters,
      ),
    ));
  }

  void _openDocTypeDefinition(ErpDocTypeDefinition item) {
    if (const {'Page', 'URL', 'Dashboard', 'Workspace'}.contains(item.linkType)) {
      if (!_requireServerAccess(item.label)) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorkspaceNativeDestinationPage(
          api: _api,
          title: item.label,
          linkType: item.linkType,
          target: item.doctype,
          routeOptions: item.routeOptions,
        ),
      ));
      return;
    }
    if (item.linkType == 'Report') {
      _openWorkspaceReport(item.doctype, initialFilters: item.routeOptions);
      return;
    }
    if (item.routeOptions.isNotEmpty) {
      if (!_requireServerAccess(item.label)) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ErpDocTypeWorkspacePage(api: _api, definition: item),
      ));
      return;
    }
    switch (item.doctype) {
      case 'Item':
        _openMasterData();
        return;
      case 'Sales Invoice':
        _openSalesInvoices();
        return;
      case 'Customer':
        _openCustomerDirectory();
        return;
      case 'Supplier':
        _openSupplierDirectory();
        return;
      case 'Account':
        _openChartOfAccounts();
        return;
      case 'Journal Entry':
        _openJournalEntries();
        return;
      case 'Payment Reconciliation':
        _openPaymentReconciliation();
        return;
      case 'Process Payment Reconciliation':
        _openProcessPaymentReconciliation();
        return;
      case 'Process Payment Reconciliation Log':
        _openProcessPaymentReconciliationLogs();
        return;
      case 'Bank Transaction':
      case 'Bank Statement Import':
        _openBankReconciliation(doctype: item.doctype);
        return;
      case 'Warehouse':
        _openWarehouseHierarchy();
        return;
      case 'Item Price':
      case 'Pricing Rule':
        _openSalesPricing(doctype: item.doctype);
        return;
      case 'Quotation':
      case 'Sales Order':
      case 'Delivery Note':
        _openSalesWorkflow(doctype: item.doctype);
        return;
      case 'Purchase Order':
      case 'Purchase Invoice':
        _openPurchaseWorkflow(section: item.doctype);
        return;
      case 'Stock Entry':
      case 'Purchase Receipt':
      case 'Stock Reconciliation':
      case 'Pick List':
      case 'Batch':
      case 'Serial No':
      case 'Item Reorder':
        _openStockWorkflow(section: item.doctype);
        return;
      case 'Employee':
      case 'Attendance':
      case 'Leave Application':
      case 'Expense Claim':
      case 'Salary Slip':
        _openHrWorkflows(doctype: item.doctype);
        return;
      case 'Payroll Entry':
        _openPayroll();
        return;
      default:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ErpDocTypeWorkspacePage(api: _api, definition: item),
        ));
    }
  }

  void _openHrWorkflows({String? doctype}) {
    if (!_requireServerAccess('الموارد البشرية')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => HrWorkflowsPage(api: _api, companies: _companies, initialDoctype: doctype, standalone: doctype != null),
    ));
  }

  void _openWarehouseHierarchy() {
    if (!_requireServerAccess('شجرة المستودعات')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => WarehouseHierarchyPage(api: _api),
    ));
  }

  void _openMasterData() {
    if (!_requireServerAccess('إدارة البيانات الأساسية')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ItemCatalogPage(api: _api, companies: _companies),
    ));
  }

  void _openSalesPricing({String? doctype}) {
    if (!_requireServerAccess('أسعار البيع')) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SalesPricingPage(api: _api, initialDoctype: doctype),
    ));
  }

  Future<void> _editCustomerProfile(ErpCustomer customer) async {
    if (!_requireServerAccess('تعديل ملف العميل')) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CustomerProfileEditorSheet(
        api: _api,
        customer: customer,
        onSaved: _loadSales,
      ),
    );
  }

  Future<void> _showCustomerLedger(ErpCustomer customer) async {
    if (!_requireServerAccess('كشف حساب العميل')) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CustomerLedgerSheet(api: _api, customer: customer, companies: _companies),
    );
  }

  Future<void> _showSupplierLedger(ErpSupplier supplier) async {
    if (!_requireServerAccess('كشف حساب المورد')) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SupplierLedgerSheet(api: _api, supplier: supplier, companies: _companies),
    );
  }

  Future<void> _showInvoiceDetails(String documentType, String invoiceId) async {
    if (!_requireServerAccess('تفاصيل الفاتورة')) return;
    await showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: FutureBuilder<core.Map<String, dynamic>>(
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
                  if (row is core.Map<String, dynamic>) {
                    try { lines.add(ErpInvoiceLine.fromJson(row)); } catch (_) {}
                  }
                }
              }
              final currency = document['currency'] is String ? document['currency'] as String : '';
              final docStatus = document['docstatus'] is num ? (document['docstatus'] as num).toInt() : -1;
              final updatesStock = document['update_stock'] == 1 || document['update_stock'] == true;
              final outstandingAmount = double.tryParse(document['outstanding_amount']?.toString() ?? '') ?? 0;
              String amount(String field) {
                final value = document[field];
                if (value is num) return '${value.toStringAsFixed(2)} $currency';
                return '${value?.toString() ?? '—'} $currency';
              }
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
                child: ListView(shrinkWrap: true, children: [
                  Text(invoiceId, style: Theme.of(context).textTheme.titleLarge),
                  Text(document['is_return'] == 1 || document['is_return'] == true
                      ? 'مرتجع مبيعات • ${document['status']?.toString() ?? 'حالة غير محددة'}'
                      : '$documentType • ${document['status']?.toString() ?? 'حالة غير محددة'}'),
                  if (document['is_return'] == 1 || document['is_return'] == true)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link),
                      title: const Text('الفاتورة الأصلية'),
                      subtitle: Text(document['return_against']?.toString() ?? 'مرجع الفاتورة الأصلية غير ظاهر'),
                    ),
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
                  if (documentType == 'Purchase Invoice') OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openPurchaseWorkflow(initialInvoiceName: invoiceId);
                    },
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('فتح إدارة المشتريات لهذا المستند'),
                  ),
                  const SizedBox(height: 8),
                  if (InvoiceActionPolicy.canEditSalesDraft(
                     documentType: documentType,
                     docStatus: docStatus,
                     isReturn: document['is_return'] == 1 || document['is_return'] == true,
                   )) OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _openSalesInvoiceComposer(initialDraft: document);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل مسودة الفاتورة'),
                  ),
                  if (InvoiceActionPolicy.canSubmitSalesDraft(documentType: documentType, docStatus: docStatus)) FilledButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('ترحيل مسودة الفاتورة'),
                          content: const Text('سيتم ترحيل هذه المسودة في ERPNext، وقد ينتج عنها تحديث المخزون إذا كان ذلك مفعلاً. هل تريد المتابعة؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رجوع')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('ترحيل')),
                          ],
                        ),
                      );
                      if (confirmed != true || !mounted || !sheetContext.mounted) return;
                      try {
                        await _api.submitSalesInvoice(document);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        _loadSales();
                        if (updatesStock) _loadInventory();
                        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('تم ترحيل الفاتورة بنجاح.')));
                      } catch (error) {
                        if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('تعذر ترحيل الفاتورة: ${error.toString().replaceFirst('Exception: ', '')}')));
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('ترحيل المسودة'),
                  ),
                  if (InvoiceActionPolicy.canReceiveCustomerPayment(
                     documentType: documentType,
                     docStatus: docStatus,
                     outstandingAmount: outstandingAmount,
                     isReturn: document['is_return'] == 1 || document['is_return'] == true,
                   )) FilledButton.icon(
                    onPressed: () async {
                      try {
                        final accounts = await _api.fetchPaymentAccounts(document['company']?.toString() ?? '');
                        if (!mounted || !sheetContext.mounted) return;
                        if (accounts.isEmpty) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('لا توجد حسابات صندوق أو بنك مفعّلة لهذه الشركة.')),
                          );
                          return;
                        }

                        final amountController = TextEditingController(text: outstandingAmount.toStringAsFixed(2));
                        var selectedAccount = accounts.first.name;
                        core.Map<String, dynamic>? paymentInput;
                        try {
                          paymentInput = await showDialog<core.Map<String, dynamic>>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('تسجيل دفعة من العميل'),
                              content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Text('المبلغ المتبقي: ${outstandingAmount.toStringAsFixed(2)} $currency'),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: amountController,
                                  autofocus: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'مبلغ الدفعة', border: OutlineInputBorder()),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedAccount,
                                  isExpanded: true,
                                  decoration: const InputDecoration(labelText: 'حساب التحصيل', border: OutlineInputBorder()),
                                  items: accounts.map((account) => DropdownMenuItem(
                                    value: account.name,
                                    child: Text(
                                      '${account.accountName} • ${account.accountType}${account.currency == null ? '' : ' • ${account.currency}'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )).toList(),
                                  onChanged: (value) {
                                    if (value != null) selectedAccount = value;
                                  },
                                ),
                              ]),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
                                FilledButton(
                                  onPressed: () {
                                    final value = double.tryParse(amountController.text.trim());
                                    if (value == null || !value.isFinite || value <= 0 || value > outstandingAmount) return;
                                    Navigator.pop(dialogContext, {'amount': value, 'account': selectedAccount});
                                  },
                                  child: const Text('تأكيد المبلغ والحساب'),
                                ),
                              ],
                            ),
                          );
                        } finally {
                          amountController.dispose();
                        }
                        if (paymentInput == null || !mounted || !sheetContext.mounted) return;
                        await _api.receiveSalesInvoicePayment(
                          invoiceName: invoiceId,
                          amount: paymentInput['amount'] as double,
                          bankAccount: paymentInput['account'] as String,
                        );
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        _loadSales();
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text('تم تسجيل وترحيل سند القبض إلى الحساب المحدد: ${paymentInput['account']}')),
                        );
                      } catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('تسجيل دفعة من العميل'),
                  ),
                  if (InvoiceActionPolicy.canCancelSalesInvoice(documentType: documentType, docStatus: docStatus)) OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('إلغاء فاتورة المبيعات'),
                          content: const Text('سيطلب التطبيق من ERPNext إلغاء الفاتورة. سيعالج ERPNext عكس أثر المخزون والقيود وفق إعداداته وصلاحياتك. هل أنت متأكد؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('تراجع')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد الإلغاء')),
                          ],
                        ),
                      );
                      if (confirmed != true || !mounted || !sheetContext.mounted) return;
                      try {
                        await _api.cancelSalesInvoice(document);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        _loadSales();
                        if (updatesStock) _loadInventory();
                        ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('تم إلغاء الفاتورة بنجاح.')));
                      } catch (error) {
                        if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('تعذر إلغاء الفاتورة: ${error.toString().replaceFirst('Exception: ', '')}')));
                      }
                    },
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('إلغاء الفاتورة'),
                  ),
                  if (InvoiceActionPolicy.canCreateSalesReturn(documentType: documentType, docStatus: docStatus, isReturn: document['is_return'] == 1 || document['is_return'] == true)) OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('إنشاء مرتجع / إشعار دائن'),
                          content: const Text('سيُنشئ ERPNext مسودة مرتجع مرتبطة بالفاتورة الأصلية، مع احتساب الكميات التي سبق إرجاعها. راجع المسودة قبل ترحيلها؛ ترحيلها قد يعكس المخزون والقيود المحاسبية. هل تريد المتابعة؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('إنشاء المسودة')),
                          ],
                        ),
                      );
                      if (confirmed != true || !mounted || !sheetContext.mounted) return;
                      try {
                        final returnDraft = await _api.createSalesReturn(invoiceId);
                        if (!mounted || !sheetContext.mounted) return;
                        Navigator.of(sheetContext).pop();
                        await _loadSales();
                        if (!mounted) return;
                        _showInvoiceDetails('Sales Invoice', returnDraft['name'].toString());
                      } catch (error) {
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('تعذر إنشاء المرتجع: ${error.toString().replaceFirst('Exception: ', '')}')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('إنشاء مرتجع / إشعار دائن'),
                  ),
                  const Text('يمكن تعديل المسودات قبل الترحيل. المرتجعات تُنشأ كمسودات من مستند ERPNext الأصلي وتحتاج مراجعة قبل الترحيل.', textAlign: TextAlign.center),
                ]),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openSalesInvoiceComposer({core.Map<String, dynamic>? initialDraft}) async {
    if (!_requireServerAccess('إنشاء فاتورة مبيعات')) return;
    if (_customers.isEmpty || _items.isEmpty || _companies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن إنشاء فاتورة قبل تحميل العملاء والأصناف والشركات. تحقق من صلاحيات القراءة ثم حدّث البيانات.')),
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SalesInvoiceComposer(
        api: _api,
        customers: _customers,
        items: _items,
        warehouses: _warehouses,
        companies: _companies,
        initialDraft: initialDraft,
        onCompleted: (submitted) {
          _loadSales();
          if (submitted) _loadInventory();
        },
      ),
    ));
  }

  Future<void> _openSalesWorkflow({String? doctype}) async {
    if (!_requireServerAccess('دورة المبيعات')) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SalesWorkflowPage(
        api: _api,
        companies: _companies,
        customers: _customers,
        items: _items,
        warehouses: _warehouses,
        onChanged: () { _loadSales(); _loadInventory(); },
        onSalesInvoiceDraftCreated: (draft) {
          _openSalesInvoiceComposer(initialDraft: draft);
        },
        initialDoctype: doctype,
        standalone: doctype != null,
      ),
    ));
  }

  Future<void> _openPurchaseWorkflow({String? initialInvoiceName, String? section}) async {
    if (!_requireServerAccess('إدارة المشتريات')) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PurchaseWorkflowPage(
        api: _api,
        companies: _companies,
        suppliers: _suppliers,
        items: _items,
        warehouses: _warehouses,
        initialInvoiceName: initialInvoiceName,
        initialSection: section ?? (initialInvoiceName != null ? 'Purchase Invoice' : null),
        onChanged: () { _loadPurchases(); _loadInventory(); },
      ),
    ));
  }

  Future<void> _openStockWorkflow({String? initialItemCode, String? section}) async {
    if (!_requireServerAccess('عمليات المخزون')) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StockWorkflowPage(
        api: _api,
        companies: _companies,
        suppliers: _suppliers,
        items: _items,
        warehouses: _warehouses,
        initialItemCode: initialItemCode,
        initialSection: section ?? (initialItemCode != null ? 'Stock Entry' : null),
        onChanged: _loadInventory,
      ),
    ));
  }

  Widget _buildSalesPage() => SalesOverviewPage(
    guest: _isGuest,
    guestBanner: _isGuest ? _guestDemoBanner() : null,
    salesLoading: _salesLoading,
    purchaseLoading: _purchaseLoading,
    inventoryLoading: _inventoryLoading,
    salesError: _salesError,
    purchaseError: _purchaseError,
    salesInvoices: _salesInvoices,
    customers: _customers,
    purchaseInvoices: _purchaseInvoices,
    suppliers: _suppliers,
    salesInvoiceSearch: _salesInvoiceSearch,
    customerSearch: _customerSearch,
    purchaseInvoiceSearch: _purchaseInvoiceSearch,
    supplierSearch: _supplierSearch,
    salesInvoiceSearchController: _salesInvoiceSearchController,
    customerSearchController: _customerSearchController,
    purchaseInvoiceSearchController: _purchaseInvoiceSearchController,
    supplierSearchController: _supplierSearchController,
    searchingSalesInvoices: _searchingSalesInvoices,
    searchingCustomers: _searchingCustomers,
    searchingPurchaseInvoices: _searchingPurchaseInvoices,
    searchingSuppliers: _searchingSuppliers,
    salesInvoicesHasMore: _salesInvoicesHasMore,
    customersHasMore: _customersHasMore,
    purchaseInvoicesHasMore: _purchaseInvoicesHasMore,
    suppliersHasMore: _suppliersHasMore,
    loadingMoreSalesInvoices: _loadingMoreSalesInvoices,
    loadingMoreCustomers: _loadingMoreCustomers,
    loadingMorePurchaseInvoices: _loadingMorePurchaseInvoices,
    loadingMoreSuppliers: _loadingMoreSuppliers,
    companiesAvailable: _companies.isNotEmpty,
    onLoadSales: _loadSales,
    onLoadPurchases: _loadPurchases,
    onOpenSalesInvoices: _openSalesInvoices,
    onOpenCustomers: _openCustomerDirectory,
    onOpenSuppliers: _openSupplierDirectory,
    onOpenSalesWorkflow: _openSalesWorkflow,
    onOpenPurchaseWorkflow: _openPurchaseWorkflow,
    onOpenStockWorkflow: _openStockWorkflow,
    onOpenBankReconciliation: _openBankReconciliation,
    onOpenPayroll: _openPayroll,
    onOpenHrWorkflows: _openHrWorkflows,
    onOpenPaymentReconciliation: _openPaymentReconciliation,
    onOpenSalesPricing: _openSalesPricing,
    onOpenChartOfAccounts: _openChartOfAccounts,
    onOpenJournalEntries: _openJournalEntries,
    onOpenMasterData: _openMasterData,
    onOpenSalesInvoiceComposer: _openSalesInvoiceComposer,
    onSearchSalesInvoices: _searchSalesInvoices,
    onSearchCustomers: _searchCustomers,
    onSearchPurchaseInvoices: _searchPurchaseInvoices,
    onSearchSuppliers: _searchSuppliers,
    onLoadMoreSalesInvoices: _loadMoreSalesInvoices,
    onLoadMoreCustomers: _loadMoreCustomers,
    onLoadMorePurchaseInvoices: _loadMorePurchaseInvoices,
    onLoadMoreSuppliers: _loadMoreSuppliers,
    onShowInvoiceDetails: _showInvoiceDetails,
    onEditCustomer: _editCustomerProfile,
    onShowCustomerLedger: _showCustomerLedger,
    onShowSupplierLedger: _showSupplierLedger,
  );


}
