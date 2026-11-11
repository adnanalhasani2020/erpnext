// ignore_for_file: unused_element, unused_element_parameter, prefer_interpolation_to_compose_strings, prefer_const_constructors
part of 'frappe_api.dart';

abstract class _FrappeApiCore {
  // Public and cross-domain operations are declared here so domain mixins can
  // call each other without coupling their implementation files.
  void _validateSerialBatchRows(List<dynamic> items);

  List<core.Map<String, dynamic>> _cleanSerialBatchRows(List<dynamic> items);

  Future<List<ErpCompany>> fetchCompanies();

  Future<List<ErpItem>> fetchItems({int start = 0, String? search});

  Future<void> _ensureIncomingBatchNumbers(List<dynamic> items);

  Future<List<core.Map<String, dynamic>>> fetchAvailableBatches({
      required String itemCode,
      required String warehouse,
      bool ignoreReservedStock = false,
      bool includeExpired = false,
    });

  Future<List<String>> fetchAvailableSerialNumbers({
      required String itemCode,
      required String warehouse,
      required int quantity,
      List<String> batchNumbers = const [],
    });

  Future<List<ErpWarehouse>> fetchWarehouses({int start = 0, String? search});

  Future<List<ErpStockBalance>> fetchStockBalances({int start = 0, String? search, String? warehouse});

  Future<List<ErpStockReorderAlert>> fetchStockReorderAlerts();

  Future<List<ErpCustomer>> fetchCustomers({int start = 0, String? search});

  Future<core.Map<String, dynamic>> fetchCustomerDocument(String customerId);

  Future<core.Map<String, dynamic>> updateCustomerProfile({
      required String customerId,
      required core.Map<String, dynamic> values,
    });

  Future<List<core.Map<String, dynamic>>> fetchSellingPriceLists();

  Future<List<core.Map<String, dynamic>>> fetchItemCatalogRows({
      int start = 0, String? search, String? itemGroup, String? brand, String? status,
    });

  Future<core.Map<String, dynamic>> fetchItemCatalogDocument(String itemCode);

  Future<List<core.Map<String, dynamic>>> fetchItemCatalogPrices(String itemCode);

  Future<core.Map<String, dynamic>?> fetchItemByBarcode(String barcode);

  Future<List<String>> fetchItemBrands();

  Future<List<core.Map<String, dynamic>>> fetchItemPrices({
      required String priceList,
      String? search,
      int start = 0,
    });

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
    });

  Future<List<core.Map<String, dynamic>>> fetchSellingPromotionalSchemes({
      int start = 0,
      String? company,
      bool activeOnly = false,
    });

  Future<core.Map<String, dynamic>> fetchSellingPromotionalSchemeDocument(String schemeId);

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
    });

  double _asDouble(dynamic value);

  Future<void> setSellingPromotionalSchemeDisabled(String schemeId, {required bool disabled});

  Future<void> disableSellingPromotionalScheme(String schemeId);

  Future<void> enableSellingPromotionalScheme(String schemeId);

  Future<List<core.Map<String, dynamic>>> fetchSellingPricingRules({
      int start = 0,
    });

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
    });

  Future<void> disableSellingPricingRule(String ruleId);

  Future<_ApiResponse> _updateExistingItemPrice(
      String id,
      String itemCode,
      String priceList,
      core.Map<String, dynamic> payload,
    );

  Future<List<ErpSalesInvoice>> fetchSalesInvoices({int start = 0, String? search});

  Future<List<core.Map<String, dynamic>>> fetchSalesPersons({
      int start = 0,
      String? search,
    });

  Future<core.Map<String, dynamic>> updateSalesPersonCommission({
      required String salesPersonId,
      required double commissionRate,
    });

  Future<List<ErpSupplier>> fetchSuppliers({int start = 0, String? search});

  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrders({int start = 0, String? search});

  Future<core.Map<String, dynamic>> fetchPurchaseOrderDocument(String name);

  Future<List<core.Map<String, dynamic>>> fetchPurchaseOrderRecords({int start = 0, String? search});

  Future<core.Map<String, dynamic>> _fetchPurchaseOrderAnyStatus(String name);

  Future<core.Map<String, dynamic>> fetchPurchaseOrderRecordDocument(String name);

  Future<core.Map<String, dynamic>> createPurchaseOrder(core.Map<String, dynamic> document);

  void _validatePurchaseOrder(core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> updateDraftPurchaseOrder({required String name, required core.Map<String, dynamic> changes});

  Future<core.Map<String, dynamic>> submitPurchaseOrder(core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> cancelPurchaseOrder(String name);

  Future<List<core.Map<String, dynamic>>> fetchSupplierLedger({
      required String supplier, int start = 0, String? company,
      String? fromDate, String? toDate, String? account, String? voucherType,
    });

  Future<List<core.Map<String, dynamic>>> fetchCustomerLedger({
      required String customer, int start = 0, String? company,
      String? fromDate, String? toDate, String? account, String? voucherType,
    });

  String? _validateLedgerDate(String? raw, String label);

  Future<List<core.Map<String, dynamic>>> _fetchPartyLedger({
      required String partyType, required String party, int start = 0,
      String? company, String? fromDate, String? toDate,
      String? account, String? voucherType,
    });

  Future<core.Map<String, dynamic>> fetchPartyLedgerOpeningBalance({
      required String partyType, required String party, required String beforeDate,
      String? company, String? account, String? voucherType,
    });

  Future<List<core.Map<String, dynamic>>> fetchReconciliationAccounts({
      required String company,
      required String partyType,
    });

  Future<List<core.Map<String, dynamic>>> fetchBankAccounts({
      required String company,
    });

  Future<core.Map<String, dynamic>> createBankStatementImportPreview({
      required String bankAccount,
      required String company,
      required String fileName,
      required List<int> fileBytes,
    });

  Future<core.Map<String, dynamic>> fetchBankReconciliationBalances({
      required String bankAccount,
      required String company,
      required String date,
    });

  Future<List<core.Map<String, dynamic>>> fetchBankTransactions({
      required String bankAccount,
      required String company,
      String? fromDate,
      String? toDate,
      int start = 0,
    });

  Future<List<core.Map<String, dynamic>>> fetchLinkedBankVouchers({
      required String transactionName,
      required String bankAccount,
      required String company,
      String? fromDate,
      String? toDate,
    });

  Future<core.Map<String, dynamic>> reconcileBankTransaction({
      required String transactionName,
      required String bankAccount,
      required String company,
      required List<core.Map<String, dynamic>> vouchers,
      String? fromDate,
      String? toDate,
    });

  Future<core.Map<String, dynamic>> _runPaymentReconciliationMethod({
      required core.Map<String, dynamic> document,
      required String method,
      core.Map<String, dynamic>? args,
    });

  Future<List<core.Map<String, dynamic>>> fetchPaymentReconciliationDimensions(String company);

  Future<List<String>> searchPaymentReconciliationDimensionValues({
      required String company,
      required String fieldname,
      required String search,
    });

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
      String? bankCashAccount,
      String? defaultAdvanceAccount,
      String? costCenter,
      String? project,
      String? invoiceName,
      String? paymentName,
      core.Map<String, String>? accountingDimensions,
      double? minimumInvoiceAmount,
      double? maximumInvoiceAmount,
      double? minimumPaymentAmount,
      double? maximumPaymentAmount,
    });

  Future<core.Map<String, dynamic>> allocatePaymentReconciliation(
      core.Map<String, dynamic> document, {
      List<String>? selectedInvoiceNumbers,
      List<String>? selectedPaymentReferences,
    });

  Future<double> calculatePaymentReconciliationDifference({
      required core.Map<String, dynamic> document,
      required core.Map<String, dynamic> allocation,
      required double allocatedAmount,
    });

  Future<core.Map<String, dynamic>> reconcilePaymentAllocations(
      core.Map<String, dynamic> document,
    );

  Future<List<core.Map<String, dynamic>>> fetchSupplierPayments({int start = 0, String? search});

  Future<List<core.Map<String, dynamic>>> fetchDraftSupplierPayments({
      int start = 0,
      String? search,
    });

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDraftDocument(String name);

  Future<core.Map<String, dynamic>> submitSupplierPaymentDraft(
      core.Map<String, dynamic> draft,
    );

  Future<core.Map<String, dynamic>> fetchSupplierPaymentDocument(String name);

  Future<List<ErpPurchaseInvoice>> fetchPurchaseInvoices({int start = 0, String? search});

  Future<List<core.Map<String, dynamic>>> fetchSalesDashboardInvoices({
      required String company,
      required String fromDate,
      required String toDate,
    });

  Future<core.Map<String, dynamic>> fetchSalesDashboardSummary({
      required String company,
      required String fromDate,
      required String toDate,
    });

  Future<List<core.Map<String, dynamic>>> fetchOutstandingInvoices({
      required bool receivable,
      String? company,
    });

  Future<core.Map<String, dynamic>> runStandardReport({
      required String reportName,
      required core.Map<String, dynamic> filters,
    });

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
    });

  Future<core.Map<String, dynamic>> updateEmployeeProfile({
      required String employee,
      required String company,
      required String employeeName,
      String department = '',
      String designation = '',
      String cellNumber = '',
      String email = '',
      String status = 'Active',
    });

  Future<core.Map<String, dynamic>> updateAttendanceDraft({
      required String name,
      required String company,
      required String attendanceDate,
      required String status,
      String leaveType = '',
    });

  Future<List<core.Map<String, dynamic>>> fetchLeaveTypes();

  Future<core.Map<String, dynamic>> createLeaveType({
      required String name,
      bool isLeaveWithoutPay = false,
      bool allowNegative = false,
      double? maxDaysAllowed,
    });

  Future<core.Map<String, dynamic>> updateLeaveType({
      required String name,
      required bool isLeaveWithoutPay,
      required bool allowNegative,
      double? maxDaysAllowed,
    });

  String _salesWorkflowResource(String doctype);

  Future<List<core.Map<String, dynamic>>> fetchSalesWorkflowDocuments(
      String doctype, {int start = 0, String? search}
    );

  Future<core.Map<String, dynamic>> fetchSalesWorkflowDocument(String doctype, String name);

  void _validateSalesWorkflowDraft(String doctype, core.Map<String, dynamic> doc);

  Future<core.Map<String, dynamic>> createSalesWorkflowDraft(String doctype, core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> updateSalesWorkflowDraft(String doctype, String name, core.Map<String, dynamic> changes);

  Future<core.Map<String, dynamic>> updateDeliveryNoteTracking({
      required String name,
      required List<core.Map<String, dynamic>> trackingRows,
    });

  Future<core.Map<String, dynamic>> submitSalesWorkflowDocument(String doctype, String name);

  Future<core.Map<String, dynamic>> cancelSalesWorkflowDocument(String doctype, String name);

  Future<core.Map<String, dynamic>> makeSalesWorkflowDocument({
      required String sourceDoctype, required String sourceName, required String targetDoctype,
    });

  void _validateSalesTeamAllocation(dynamic raw);

  Future<core.Map<String, dynamic>> createSalesInvoice(core.Map<String, dynamic> invoice);

  Future<core.Map<String, dynamic>> submitSalesInvoice(core.Map<String, dynamic> document);

  Future<List<ErpPaymentAccount>> fetchPaymentAccounts(String company);

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDocument(String name);

  Future<core.Map<String, dynamic>> receiveSalesInvoicePayment({
      required String invoiceName,
      required double amount,
      String? bankAccount,
    });

  Future<core.Map<String, dynamic>> updateDraftSalesInvoice({
      required String invoiceName,
      required core.Map<String, dynamic> changes,
    });

  Future<core.Map<String, dynamic>> createSalesReturn(String invoiceName);

  Future<core.Map<String, dynamic>> cancelSalesInvoice(core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> createPurchaseInvoice(core.Map<String, dynamic> invoice);

  void _validatePurchase(core.Map<String, dynamic> doc);

  Future<core.Map<String, dynamic>> updateDraftPurchaseInvoice({
      required String invoiceName, required core.Map<String, dynamic> changes,
    });

  Future<core.Map<String, dynamic>> submitPurchaseInvoice(core.Map<String, dynamic> doc);

  Future<core.Map<String, double>> fetchPurchaseReturnableQuantities(String invoiceName);

  Future<core.Map<String, dynamic>> createPurchaseReturn(String invoiceName, {core.Map<String, double?>? quantitiesBySourceItem});

  Future<core.Map<String, dynamic>> payPurchaseInvoice({
      required String invoiceName, required double amount, String? bankAccount,
    });

  Future<core.Map<String, dynamic>> _fetchPaymentEntryDraft(String name, {required String paymentType, required String partyType});

  Future<core.Map<String, dynamic>> cancelPurchaseInvoice(String name);

  Future<void> _validateWarehouseForCompany(String warehouseName, String company);

  Future<void> _validateDocumentWarehouses(core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> createStockEntry({
      required String company, required String purpose, required List<core.Map<String, dynamic>> items,
      String? fromWarehouse, String? toWarehouse, String? remarks,
    });

  Future<core.Map<String, dynamic>> createPurchaseReceipt(core.Map<String, dynamic> document);

  Future<core.Map<String, dynamic>> submitPurchaseReceipt(core.Map<String, dynamic> doc);

  Future<core.Map<String, dynamic>> submitStockEntry(core.Map<String, dynamic> doc);

  Future<core.Map<String, dynamic>> createStockReconciliation({
      required String company, required String warehouse, required List<core.Map<String, dynamic>> items, String? remarks,
    });

  Future<core.Map<String, dynamic>> submitStockReconciliation(core.Map<String, dynamic> doc);

  Future<List<core.Map<String, dynamic>>> fetchDraftStockDocuments(String doctype, {int start = 0});

  Future<List<core.Map<String, dynamic>>> fetchBatchTraceRecords({int start = 0, String? search, String? itemCode});

  Future<List<core.Map<String, dynamic>>> fetchSerialTraceRecords({int start = 0, String? search, String? itemCode});

  Future<core.Map<String, dynamic>> createPickListFromSalesOrder(String salesOrderName);

  Future<core.Map<String, dynamic>> saveStockPickList(String name, List<core.Map<String, dynamic>> locations);

  Future<core.Map<String, dynamic>> submitPickList(core.Map<String, dynamic> doc);

  Future<List<core.Map<String, dynamic>>> createDeliveryNotesFromPickList(String pickListName);

  Future<List<core.Map<String, dynamic>>> fetchBatchLedgerEntries(String batchNo, {int start = 0});

  Future<List<core.Map<String, dynamic>>> fetchSerialLedgerEntries(String serialNo, {int start = 0});

  Future<core.Map<String, dynamic>> fetchStockDocument(String doctype, String name);

  Future<List<core.Map<String, dynamic>>> fetchStockMovements({
      int start = 0,
      String? itemCode,
      String? warehouse,
      String? company,
      DateTime? fromDate,
      DateTime? toDate,
      String? batchNo,
    });

  Future<List<core.Map<String, dynamic>>> fetchAccountingAccounts({
      required String company,
      int start = 0,
      String? search,
      bool includeDisabled = false,
    });

  Future<List<core.Map<String, dynamic>>> fetchMasterDataOptions(String doctype);

  Future<List<core.Map<String, dynamic>>> fetchMasterDataRows({
      required String doctype,
      int start = 0,
      String? search,
    });

  Future<core.Map<String, dynamic>> fetchMasterDataDocument({
      required String doctype,
      required String name,
    });

  Future<core.Map<String, dynamic>> saveMasterDataDocument({
      required String doctype,
      String? name,
      required core.Map<String, dynamic> values,
    });

  Future<List<core.Map<String, dynamic>>> fetchJournalEntryDrafts({
      required String company,
      int start = 0,
      String? search,
      int? docStatus,
      String? fromDate,
      String? toDate,
      String? voucherType,
    });

  Future<core.Map<String, dynamic>> fetchJournalEntryDocument(String name);

  Future<core.Map<String, dynamic>> saveJournalEntryDraft({String? name, required String company, required String postingDate, required String remark, required List<core.Map<String, dynamic>> accounts});

  Future<core.Map<String, dynamic>> submitJournalEntry(String name, {required String company});

  Future<List<core.Map<String, dynamic>>> fetchPayrollCostCenters({
      required String company,
    });

  Future<List<core.Map<String, dynamic>>> fetchPayrollEntries({
      required String company,
      int start = 0,
    });

  Future<core.Map<String, dynamic>> fetchPayrollEntryDocument({
      required String name,
      required String company,
    });

  Future<List<core.Map<String, dynamic>>> fetchPayrollSalarySlips({
      required String payrollEntry,
      required String company,
    });

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
    });

  Future<core.Map<String, dynamic>> _runPayrollEntryMethod({
      required String name,
      required String company,
      required String method,
      bool requireSubmitted = false,
    });

  Future<core.Map<String, dynamic>> fillPayrollEmployees({
      required String name,
      required String company,
    });

  Future<core.Map<String, dynamic>> submitPayrollSalarySlips({
      required String name,
      required String company,
    });

  Future<core.Map<String, dynamic>> createPayrollBankEntry({
      required String name,
      required String company,
    });

  Future<core.Map<String, dynamic>> submitPayrollEntry({
      required String name,
      required String company,
    });

  Future<core.Map<String, dynamic>> fetchSalarySlipDetails({
      required String name,
      required String company,
    });

  Future<List<core.Map<String, dynamic>>> fetchHrRecords({
      required String doctype,
      String? company,
      int start = 0,
      String? search,
    });

  Future<core.Map<String, dynamic>> _fetchHrEmployee(String employee, String company);

  Future<core.Map<String, dynamic>> createAttendanceDraft({
      required String employee,
      required String company,
      required String attendanceDate,
      required String status,
      String? leaveType,
    });

  Future<core.Map<String, dynamic>> createLeaveApplicationDraft({
      required String employee,
      required String company,
      required String leaveType,
      required String fromDate,
      required String toDate,
      String description = '',
    });

  Future<List<core.Map<String, dynamic>>> fetchExpenseClaimTypes();

  Future<core.Map<String, dynamic>> createExpenseClaimDraft({
      required String employee,
      required String company,
      required String postingDate,
      required String expenseType,
      required String amount,
      required String account,
      String description = '',
      String costCenter = '',
    });

  Future<core.Map<String, dynamic>> createExpenseClaimDraftLines({
      required String employee,
      required String company,
      required String postingDate,
      required List<core.Map<String, dynamic>> expenses,
    });

  Future<core.Map<String, dynamic>> payExpenseClaim({
      required String claimName,
      required double amount,
      String? bankAccount,
    });

  Future<core.Map<String, dynamic>> submitHrDraft({
      required String doctype,
      required String name,
      required String company,
    });

  Future<core.Map<String, dynamic>> cancelJournalEntry(String name, {required String company});

  Future<core.Map<String, dynamic>> createJournalEntryReversalDraft({
      required String name,
      required String company,
      required String postingDate,
    });

  Future<core.Map<String, dynamic>> startBankStatementImport(String importName);

  Future<core.Map<String, dynamic>> fetchBankStatementImportStatus(String importName);

  Future<List<core.Map<String, dynamic>>> fetchBankStatementImports({
      required String bankAccount,
      required String company,
      int start = 0,
    });

  Future<List<core.Map<String, dynamic>>> fetchBankStatementImportLogs(String importName);

  Future<core.Map<String, dynamic>> saveBankStatementClosingBalance({
      required String bankAccount, required String company,
      required String statementDate, required double closingBalance,
      String? importName,
    });

  Future<core.Map<String, dynamic>?> fetchLatestBankStatementClosingBalance({
      required String bankAccount, required String company,
    });

  Future<List<core.Map<String, dynamic>>> fetchProcessPaymentReconciliationJobs({
      int start = 0, String? search, String? company, String? status, String? partyType,
    });

  Future<core.Map<String, dynamic>> fetchProcessPaymentReconciliationJob(String name);

  Future<core.Map<String, dynamic>> saveProcessPaymentReconciliationDraft({
      String? name,
      required String company,
      required String partyType,
      required String party,
      required String receivablePayableAccount,
      String? defaultAdvanceAccount,
      String? fromInvoiceDate,
      String? toInvoiceDate,
      String? fromPaymentDate,
      String? toPaymentDate,
      String? costCenter,
      String? bankCashAccount,
    });

  Future<core.Map<String, dynamic>> submitProcessPaymentReconciliation(String name);

  Future<core.Map<String, dynamic>> cancelProcessPaymentReconciliation(String name);

  Future<core.Map<String, dynamic>> startProcessPaymentReconciliation(String name);

  Future<core.Map<String, dynamic>> pauseProcessPaymentReconciliation(String name);

  Future<core.Map<String, dynamic>> fetchProcessPaymentReconciliationProgress(String name);

  Future<core.Map<String, dynamic>?> fetchProcessPaymentReconciliationLog(String name);

  Future<List<core.Map<String, dynamic>>> fetchProcessPaymentReconciliationLogs({
      int start = 0, String? search, String? status,
    });

  Future<core.Map<String, dynamic>> fetchProcessPaymentReconciliationLogDocument(String name);

  Future<core.Map<String, dynamic>> fetchPartyLedgerTotals({
      required String partyType, required String party,
      String? company, String? fromDate, String? toDate,
      String? account, String? voucherType,
    });

  _FrappeApiCore({HttpClient? httpClient})
      : _client = (httpClient ?? _DirectHttpOverrides().createHttpClient(null))
          ..connectionTimeout = const Duration(seconds: 20);

  final HttpClient _client;

  final core.Map<String, String> _cookies = {};

  final Set<String> _inFlightSalesActions = <String>{};

  final Set<String> _inFlightPaymentActions = <String>{};

  final Set<String> _inFlightPurchaseActions = <String>{};

  final Set<String> _inFlightDocumentActions = <String>{};

  String _baseUrl = '';

  int _sessionGeneration = 0;

  bool _guestMode = false;

  String get baseUrl => _baseUrl;

  Map<String, String> get imageRequestHeaders => _cookies.isEmpty
        ? const <String, String>{}
        : <String, String>{'Cookie': _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ')};

  Map<String, String> imageRequestHeadersFor(String imageUrl) {
      final base = Uri.tryParse(_baseUrl);
      final target = Uri.tryParse(imageUrl);
      if (base == null || target == null || target.scheme != base.scheme ||
          target.host != base.host || target.port != base.port) {
        return const <String, String>{};
      }
      return imageRequestHeaders;
    }

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

  void dispose() => _client.close(force: true);
}
