import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'sales_invoice_composer.dart';
import 'sales_workflow_page.dart';
import 'purchase_inventory_workflows.dart';
import 'invoice_action_policy.dart';
import 'financial_reports_page.dart';
import 'sales_pricing_page.dart';
import 'sales_commission_page.dart';
import 'models/erp_models.dart';
import 'widgets/count_card.dart';
import 'widgets/load_more_button.dart';
import 'widgets/server_search_field.dart';

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
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'التقارير'),
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
      case 5: return FinancialReportsPage(api: _api, companies: _companies);
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
        enabled: !_inventoryLoading,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: 'ابحث بالاسم أو الرمز',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _itemSearchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    _itemSearchController.clear();
                    _searchItems('');
                  },
                  icon: const Icon(Icons.clear),
                ),
        ),
        onSubmitted: _searchItems,
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        onPressed: _inventoryLoading || _loadingMoreItems
            ? null
            : () => _searchItems(_itemSearchController.text),
        icon: const Icon(Icons.search),
        label: const Text('بحث في جميع الأصناف بالخادم'),
      ),
      const SizedBox(height: 10),
      Text('المعروض ${filtered.length} من ${_items.length} صنف في نتيجة البحث الحالية'),
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
      if (_itemsHasMore || _loadingMoreItems) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.tonal(onPressed: _loadingMoreItems ? null : _loadMoreItems, child: Text(_loadingMoreItems ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من الأصناف'))),
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
          if (item.isStockItem) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
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

  Widget _buildStockPage() {
    final filtered = _stockBalances;
    final loadedWarehouses = filtered.map((row) => row.warehouse).toSet().length;
    return ListView(padding: const EdgeInsets.all(18), children: [
      _pageHeader('أرصدة المخزون', 'الكميات وقيمة المخزون ومعدل التقييم حسب المستودع', Icons.inventory_2_outlined),
      const Text('قيمة المخزون ومعدل التقييم من سجل Bin في ERPNext وبعملة الشركة المالكة للمستودع. لا تجمع القيم بين شركات ذات عملات مختلفة.'),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        initialValue: _selectedWarehouse, isExpanded: true,
        decoration: const InputDecoration(labelText: 'تصفية حسب المستودع'),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('كل المستودعات')),
          ..._warehouses.map((warehouse) => DropdownMenuItem<String>(value: warehouse.id, child: Text(warehouse.name, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: (value) => _searchStockBalances(_stockSearchController.text, updateWarehouse: true, warehouse: value),
      ),
      const SizedBox(height: 12),
      ServerSearchField(
        controller: _stockSearchController,
        label: 'ابحث برمز الصنف',
        onSearch: _searchStockBalances,
        loading: _inventoryLoading,
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: CountCard(label: 'الأرصدة المحمّلة', count: filtered.length, icon: Icons.inventory_outlined)),
        const SizedBox(width: 8),
        Expanded(child: CountCard(label: 'مستودعات ضمن النتائج', count: loadedWarehouses, icon: Icons.warehouse_outlined)),
      ]),
      const Text('الأعداد تخص النتائج المحمّلة فقط. لا تُجمع كميات الأصناف مع اختلاف وحدات القياس.'),
      if (_inventoryLoading) const LinearProgressIndicator(),
      if (_inventoryError != null) _errorCard(_inventoryError!),
      if (filtered.isEmpty && !_inventoryLoading)
        const Card(child: ListTile(title: Text('لا توجد أرصدة مطابقة لرمز الصنف والمستودع المحددين'))),
      ...filtered.map((balance) => Card(child: ListTile(
        title: Text(balance.itemCode),
        subtitle: Text('${balance.warehouse}\nمحجوز: ${balance.reservedQty} • متوقع: ${balance.projectedQty}\nقيمة المخزون: ${balance.stockValue?.toStringAsFixed(2) ?? 'غير متاحة'} • معدل التقييم: ${balance.valuationRate?.toStringAsFixed(2) ?? 'غير متاح'}'),
        isThreeLine: true,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(balance.actualQty.toStringAsFixed(2), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          Text('متاح: ${balance.availableQty.toStringAsFixed(2)}', style: Theme.of(context).textTheme.bodySmall),
          Text(balance.stockUom ?? '—', style: Theme.of(context).textTheme.bodySmall),
        ]),
        onTap: () {
          final matches = _items.where((item) => item.code == balance.itemCode);
          if (matches.isNotEmpty) {
            _showItemDetails(matches.first);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تفاصيل الصنف غير موجودة ضمن البيانات المحمّلة. حدّث قائمة الأصناف أولاً.')),
            );
          }
        },
      ))),
      if (_stockHasMore || _loadingMoreStock) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.tonal(onPressed: _loadingMoreStock ? null : _loadMoreStock, child: Text(_loadingMoreStock ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من الأرصدة'))),
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
      ServerSearchField(
        controller: _warehouseSearchController,
        label: 'بحث في المستودعات أو الشركة',
        onSearch: _searchWarehouses,
        loading: _searchingWarehouses,
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
          onTap: () {
            setState(() => _selectedTab = 2);
            _searchStockBalances(
              _stockSearchController.text,
              updateWarehouse: true,
              warehouse: warehouse.id,
            );
          },
        ));
      }),
      if (_warehousesHasMore || _loadingMoreWarehouses) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: FilledButton.tonal(onPressed: _loadingMoreWarehouses ? null : _loadMoreWarehouses, child: Text(_loadingMoreWarehouses ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من المستودعات'))),
    ]);
  }

  void _openSalesCommissions() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SalesCommissionPage(api: _api),
    );
  }

  void _openSalesPricing() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SalesPricingPage(api: _api),
    );
  }

  void _editCustomerProfile(ErpCustomer customer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomerProfileEditorSheet(
        api: _api,
        customer: customer,
        onSaved: _loadSales,
      ),
    );
  }

  void _showCustomerLedger(ErpCustomer customer) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomerLedgerSheet(api: _api, customer: customer, companies: _companies),
    );
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
                        Map<String, dynamic>? paymentInput;
                        try {
                          paymentInput = await showDialog<Map<String, dynamic>>(
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

  Future<void> _openSalesInvoiceComposer({Map<String, dynamic>? initialDraft}) async {
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

  Future<void> _openSalesWorkflow() async {
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
      ),
    ));
  }

  Future<void> _openPurchaseWorkflow({String? initialInvoiceName}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PurchaseWorkflowPage(
        api: _api,
        companies: _companies,
        suppliers: _suppliers,
        items: _items,
        warehouses: _warehouses,
        initialInvoiceName: initialInvoiceName,
        onChanged: () { _loadPurchases(); _loadInventory(); },
      ),
    ));
  }

  Future<void> _openStockWorkflow({String? initialItemCode}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StockWorkflowPage(
        api: _api,
        companies: _companies,
        suppliers: _suppliers,
        items: _items,
        warehouses: _warehouses,
        initialItemCode: initialItemCode,
        onChanged: _loadInventory,
      ),
    ));
  }

  Widget _buildSalesPage() {
    return ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        Expanded(child: Row(children: [const CircleAvatar(child: Icon(Icons.receipt_long_outlined)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('المعاملات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), Text('فواتير المبيعات وإنشاء الفواتير، مع عرض بيانات المشتريات والعملاء والموردين', style: Theme.of(context).textTheme.bodySmall)]))])),
        IconButton(tooltip: 'تحديث المبيعات', onPressed: _salesLoading ? null : _loadSales, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'تحديث المشتريات', onPressed: _purchaseLoading ? null : _loadPurchases, icon: const Icon(Icons.shopping_cart_outlined)),
      ]),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _salesLoading || _inventoryLoading ? null : _openSalesWorkflow,
            icon: const Icon(Icons.route_outlined),
            label: const Text('دورة المبيعات'),
          ),
          OutlinedButton.icon(
            onPressed: _purchaseLoading || _inventoryLoading ? null : _openPurchaseWorkflow,
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('إدارة المشتريات'),
          ),
          OutlinedButton.icon(
            onPressed: _inventoryLoading ? null : _openStockWorkflow,
            icon: const Icon(Icons.warehouse_outlined),
            label: const Text('عمليات المخزون'),
          ),
          OutlinedButton.icon(
            onPressed: _salesLoading ? null : _openSalesPricing,
            icon: const Icon(Icons.price_change_outlined),
            label: const Text('أسعار البيع'),
          ),
          OutlinedButton.icon(
            onPressed: _salesLoading ? null : _openSalesCommissions,
            icon: const Icon(Icons.percent_outlined),
            label: const Text('العمولات'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          onPressed: _salesLoading || _inventoryLoading ? null : _openSalesInvoiceComposer,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('إنشاء فاتورة مبيعات'),
        ),
      ),
      if (_salesLoading) const LinearProgressIndicator(),
      if (_salesError != null) _errorCard(_salesError!),
      const SizedBox(height: 12),
      ServerSearchField(
        controller: _salesInvoiceSearchController,
        label: 'بحث في فواتير المبيعات',
        onSearch: _searchSalesInvoices,
        loading: _searchingSalesInvoices,
      ),
      Text('فواتير المبيعات (${_salesInvoices.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_salesInvoices.isEmpty && !_salesLoading) const Card(child: ListTile(title: Text('لا توجد فواتير ظاهرة أو تعذر تحميلها'))),
      ..._salesInvoices.map((invoice) => Card(child: ListTile(
        leading: CircleAvatar(child: Icon(invoice.isReturn ? Icons.assignment_return_outlined : Icons.receipt_long_outlined)),
        title: Text(invoice.isReturn ? 'مرتجع • ${invoice.id}' : invoice.id),
        subtitle: Text('${invoice.customerName} • ${invoice.postingDate ?? '—'}${invoice.returnAgainst == null ? '' : '\nمرتبط بالفاتورة: ${invoice.returnAgainst}'}\n${invoice.status ?? 'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}'),
        isThreeLine: true,
        trailing: Text(invoice.grandTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => _showInvoiceDetails('Sales Invoice', invoice.id),
      ))),
      if (_salesInvoicesHasMore || _loadingMoreSalesInvoices) LoadMoreButton(_loadingMoreSalesInvoices, 'تحميل المزيد من فواتير المبيعات', _loadMoreSalesInvoices),
      const SizedBox(height: 18),
      ServerSearchField(
        controller: _customerSearchController,
        label: 'بحث في العملاء',
        onSearch: _searchCustomers,
        loading: _searchingCustomers,
      ),
      Text('العملاء (${_customers.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_customers.isEmpty && !_salesLoading) const Card(child: ListTile(title: Text('لا توجد بيانات عملاء ظاهرة'))),
      ..._customers.map((customer) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(customer.name),
        subtitle: Text([customer.id, if (customer.group != null) customer.group!, if (customer.territory != null) customer.territory!].join(' • ')),
        trailing: IconButton(
          tooltip: 'تعديل ملف العميل',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _editCustomerProfile(customer),
        ),
        onTap: () => _showCustomerLedger(customer),
      ))),
      if (_customersHasMore || _loadingMoreCustomers) LoadMoreButton(_loadingMoreCustomers, 'تحميل المزيد من العملاء', _loadMoreCustomers),
      const Divider(height: 28),
      if (_purchaseLoading) const LinearProgressIndicator(),
      if (_purchaseError != null) _errorCard(_purchaseError!),
      ServerSearchField(
        controller: _purchaseInvoiceSearchController,
        label: 'بحث في فواتير المشتريات',
        onSearch: _searchPurchaseInvoices,
        loading: _searchingPurchaseInvoices,
      ),
      Text('فواتير المشتريات (${_purchaseInvoices.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_purchaseInvoices.isEmpty && !_purchaseLoading) const Card(child: ListTile(title: Text('لا توجد فواتير مشتريات ظاهرة'))),
      ..._purchaseInvoices.map((invoice) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.shopping_cart_outlined)),
        title: Text(invoice.id),
        subtitle: Text('${invoice.supplierName} • ${invoice.postingDate ?? '—'}\n${invoice.status ?? 'حالة غير محددة'} • متبقٍ: ${invoice.outstandingAmount.toStringAsFixed(2)} ${invoice.currency ?? ''}'),
        isThreeLine: true,
        trailing: Text(invoice.grandTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        onTap: () => _openPurchaseWorkflow(initialInvoiceName: invoice.id),
      ))),
      if (_purchaseInvoicesHasMore || _loadingMorePurchaseInvoices) LoadMoreButton(_loadingMorePurchaseInvoices, 'تحميل المزيد من فواتير المشتريات', _loadMorePurchaseInvoices),
      const SizedBox(height: 18),
      ServerSearchField(
        controller: _supplierSearchController,
        label: 'بحث في الموردين',
        onSearch: _searchSuppliers,
        loading: _searchingSuppliers,
      ),
      Text('الموردون (${_suppliers.length})', style: Theme.of(context).textTheme.titleMedium),
      if (_suppliers.isEmpty && !_purchaseLoading) const Card(child: ListTile(title: Text('لا توجد بيانات موردين ظاهرة'))),
      ..._suppliers.map((supplier) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
        title: Text(supplier.name),
        subtitle: Text([supplier.id, if (supplier.group != null) supplier.group!, if (supplier.type != null) supplier.type!].join(' • ')),
      ))),
      if (_suppliersHasMore || _loadingMoreSuppliers) LoadMoreButton(_loadingMoreSuppliers, 'تحميل المزيد من الموردين', _loadMoreSuppliers),
      const SizedBox(height: 10),
      Text('تتم إدارة دورة المبيعات من شاشة المبيعات، ودورة المشتريات والدفعات والمرتجعات من شاشة إدارة المشتريات، مع تحديث أرصدة المخزون بعد العمليات المرحلة.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }

  Widget _buildLogin() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      key: const ValueKey('login'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Form(
            key: _loginFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.inventory_2_outlined, size: 42, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 18),
                Text(
                  'ERPNext للجوال',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'سجّل الدخول للوصول إلى بيانات شركتك ومخزونك ومعاملاتك.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 28),
                TextFormField(
                  controller: _urlController,
                  enabled: !_busy,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'رابط خادم ERPNext',
                    hintText: 'https://erp.example.com',
                    prefixIcon: Icon(Icons.link),
                    helperText: 'استخدم رابط HTTPS الخاص بنظامك.',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'أدخل رابط خادم ERPNext.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _userController,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم أو البريد',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'أدخل اسم المستخدم أو البريد الإلكتروني.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'إخفاء كلمة المرور' : 'إظهار كلمة المرور',
                      onPressed: _busy ? null : () => setState(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'أدخل كلمة المرور.'
                      : null,
                  onFieldSubmitted: (_) { if (!_busy) _login(); },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer))),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_busy ? 'جارٍ الاتصال بالخادم...' : 'تسجيل الدخول'),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'تُرسل بيانات الدخول إلى خادمك مباشرة. لا يحفظ التطبيق كلمة المرور أو ملفات الجلسة على الجهاز؛ تنتهي الجلسة عند تسجيل الخروج أو إغلاق التطبيق.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
            Expanded(child: CountCard(label: 'الأصناف', count: _items.length, icon: Icons.inventory_2_outlined)),
            const SizedBox(width: 10),
            Expanded(child: CountCard(label: 'المستودعات', count: _warehouses.length, icon: Icons.warehouse_outlined)),
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
        Text('يمكنك إنشاء فواتير المبيعات وترحيلها وتسجيل دفعات العملاء وإعداد مسودات المرتجعات من شاشة المعاملات.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CustomerLedgerSheet extends StatefulWidget {
  const _CustomerLedgerSheet({required this.api, required this.customer, required this.companies});

  final FrappeApi api;
  final ErpCustomer customer;
  final List<ErpCompany> companies;

  @override
  State<_CustomerLedgerSheet> createState() => _CustomerLedgerSheetState();
}

class _CustomerLedgerSheetState extends State<_CustomerLedgerSheet> {
  final List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _company;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loadingMore || (more && !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await widget.api.fetchCustomerLedger(
        customer: widget.customer.id,
        company: _company,
        start: more ? _rows.length : 0,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _rows.addAll(page);
        } else {
          _rows
            ..clear()
            ..addAll(page);
        }
        _hasMore = page.length == FrappeApi.pageSize;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  double _amount(Map<String, dynamic> row, String field) =>
      double.tryParse(row[field]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    final debit = _rows.fold<double>(0, (sum, row) => sum + _amount(row, 'debit'));
    final credit = _rows.fold<double>(0, (sum, row) => sum + _amount(row, 'credit'));
    return SizedBox(
      height: MediaQuery.of(context).size.height * .82,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كشف حساب العميل', style: Theme.of(context).textTheme.titleLarge),
                Text('${widget.customer.name} • ${widget.customer.id}'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _company ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الشركة'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('جميع الشركات')),
                    ...widget.companies.map((company) => DropdownMenuItem(
                      value: company.name,
                      child: Text(company.name),
                    )),
                  ],
                  onChanged: (_loading || _loadingMore) ? null : (value) {
                    setState(() => _company = value == null || value.isEmpty ? null : value);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    Text('مدين: ${debit.toStringAsFixed(2)}'),
                    Text('دائن: ${credit.toStringAsFixed(2)}'),
                    Text('صافي الحركات المحمّلة: ${(debit - credit).toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                TextButton.icon(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
              ]),
            ),
          Expanded(
            child: _rows.isEmpty
                ? Center(child: Text(_loading ? 'جارٍ تحميل كشف الحساب...' : 'لا توجد حركات حساب ظاهرة.'))
                : ListView.separated(
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final debitValue = _amount(row, 'debit');
                      final creditValue = _amount(row, 'credit');
                      return ListTile(
                        dense: true,
                        title: Text(row['voucher_no']?.toString() ?? row['name']?.toString() ?? 'قيد محاسبي'),
                        subtitle: Text([
                          row['posting_date']?.toString() ?? '',
                          row['voucher_type']?.toString() ?? '',
                          row['account']?.toString() ?? '',
                          row['company']?.toString() ?? '',
                          row['remarks']?.toString() ?? '',
                        ].where((value) => value.isNotEmpty).join(' • ')),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (debitValue != 0) Text('مدين ${debitValue.toStringAsFixed(2)}'),
                            if (creditValue != 0) Text('دائن ${creditValue.toStringAsFixed(2)}'),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          if (_hasMore || _loadingMore)
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد'),
              ),
            ),
        ],
      ),
    );
  }
}


class _CustomerProfileEditorSheet extends StatefulWidget {
  const _CustomerProfileEditorSheet({
    required this.api,
    required this.customer,
    required this.onSaved,
  });

  final FrappeApi api;
  final ErpCustomer customer;
  final VoidCallback onSaved;

  @override
  State<_CustomerProfileEditorSheet> createState() =>
      _CustomerProfileEditorSheetState();
}

class _CustomerProfileEditorSheetState
    extends State<_CustomerProfileEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _group = TextEditingController();
  final _territory = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _taxId = TextEditingController();
  final _currency = TextEditingController();
  final _priceList = TextEditingController();
  String _type = 'Company';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _group.dispose();
    _territory.dispose();
    _mobile.dispose();
    _email.dispose();
    _website.dispose();
    _taxId.dispose();
    _currency.dispose();
    _priceList.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final document = await widget.api.fetchCustomerDocument(widget.customer.id);
      if (!mounted) return;
      _name.text = document['customer_name']?.toString() ?? '';
      _group.text = document['customer_group']?.toString() ?? '';
      _territory.text = document['territory']?.toString() ?? '';
      _mobile.text = document['mobile_no']?.toString() ?? '';
      _email.text = document['email_id']?.toString() ?? '';
      _website.text = document['website']?.toString() ?? '';
      _taxId.text = document['tax_id']?.toString() ?? '';
      _currency.text = document['default_currency']?.toString() ?? '';
      _priceList.text = document['default_price_list']?.toString() ?? '';
      _type = document['customer_type']?.toString() == 'Individual'
          ? 'Individual'
          : 'Company';
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateCustomerProfile(
        customerId: widget.customer.id,
        values: {
          'customer_name': _name.text,
          'customer_type': _type,
          'customer_group': _group.text,
          'territory': _territory.text,
          'mobile_no': _mobile.text,
          'email_id': _email.text,
          'website': _website.text,
          'tax_id': _taxId.text,
          'default_currency': _currency.text,
          'default_price_list': _priceList.text,
        },
      );
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث ملف العميل في ERPNext.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
      {bool required = false, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => value == null || value.trim().isEmpty
                ? 'هذا الحقل مطلوب'
                : null
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .88,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                children: [
                  Text('تعديل ملف العميل',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(widget.customer.id,
                      style: Theme.of(context).textTheme.bodySmall),
                  if (_error != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            )),
                      ),
                    ),
                  _field(_name, 'اسم العميل', required: true),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: 'نوع العميل'),
                    items: const [
                      DropdownMenuItem(value: 'Company', child: Text('شركة')),
                      DropdownMenuItem(value: 'Individual', child: Text('فرد')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _type = value);
                          },
                  ),
                  const SizedBox(height: 10),
                  _field(_group, 'مجموعة العملاء', required: true),
                  _field(_territory, 'المنطقة', required: true),
                  _field(_mobile, 'رقم الهاتف',
                      keyboardType: TextInputType.phone),
                  _field(_email, 'البريد الإلكتروني',
                      keyboardType: TextInputType.emailAddress),
                  _field(_website, 'الموقع الإلكتروني'),
                  _field(_taxId, 'الرقم الضريبي'),
                  _field(_currency, 'العملة الافتراضية'),
                  _field(_priceList, 'قائمة الأسعار الافتراضية'),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التعديلات'),
                  ),
                ],
              ),
            ),
    );
  }
}
