import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class PaymentReconciliationPage extends StatefulWidget {
  const PaymentReconciliationPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<PaymentReconciliationPage> createState() => _PaymentReconciliationPageState();
}

class _PaymentReconciliationPageState extends State<PaymentReconciliationPage> {
  final _partyController = TextEditingController();
  final _invoiceFromController = TextEditingController();
  final _invoiceToController = TextEditingController();
  final _paymentFromController = TextEditingController();
  final _paymentToController = TextEditingController();
  final _bankCashAccountController = TextEditingController();
  final _advanceAccountController = TextEditingController();
  final _costCenterController = TextEditingController();
  final _projectController = TextEditingController();
  final _invoiceNameController = TextEditingController();
  final _paymentNameController = TextEditingController();
  final _minimumInvoiceController = TextEditingController();
  final _maximumInvoiceController = TextEditingController();
  final _minimumPaymentController = TextEditingController();
  final _maximumPaymentController = TextEditingController();

  String? _company;
  String _partyType = 'Customer';
  String? _account;
  int _invoiceLimit = 50;
  int _paymentLimit = 50;
  List<core.Map<String, dynamic>> _accounts = const [];
  List<core.Map<String, dynamic>> _dimensionDefinitions = const [];
  final Map<String, TextEditingController> _dimensionControllers = {};
  int _dimensionGeneration = 0;
  bool _loadingDimensions = false;
  core.Map<String, dynamic>? _document;
  final Set<String> _selectedInvoiceNumbers = <String>{};
  final Set<String> _selectedPaymentReferences = <String>{};
  bool _loadingAccounts = false;
  bool _loadingEntries = false;
  bool _allocating = false;
  bool _reconciling = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    if (_company != null) {
      _loadAccounts();
      _loadDimensions();
    }
  }

  @override
  void dispose() {
    _requestGeneration++;
    _partyController.dispose();
    _invoiceFromController.dispose();
    _invoiceToController.dispose();
    _paymentFromController.dispose();
    _paymentToController.dispose();
    _bankCashAccountController.dispose();
    _advanceAccountController.dispose();
    _costCenterController.dispose();
    _projectController.dispose();
    _invoiceNameController.dispose();
    _paymentNameController.dispose();
    _minimumInvoiceController.dispose();
    _maximumInvoiceController.dispose();
    _minimumPaymentController.dispose();
    _maximumPaymentController.dispose();
    _dimensionGeneration++;
    for (final controller in _dimensionControllers.values) {
      controller.dispose();
    }
    _dimensionControllers.clear();
    super.dispose();
  }

  bool get _busy => _loadingAccounts || _loadingDimensions || _loadingEntries || _allocating || _reconciling;

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      controller.text = _dateString(picked);
      _document = null;
      _error = null;
    });
  }

  Widget _dateField(TextEditingController controller, String label) => TextField(
    controller: controller,
    readOnly: true,
    enabled: !_busy,
    onTap: _busy ? null : () => _pickDate(controller),
    decoration: InputDecoration(
      labelText: label,
      hintText: 'YYYY-MM-DD',
      suffixIcon: controller.text.isEmpty
          ? const Icon(Icons.calendar_today_outlined)
          : IconButton(
              tooltip: 'مسح التاريخ',
              onPressed: _busy ? null : () => setState(() {
                controller.clear();
                _document = null;
              }),
              icon: const Icon(Icons.clear),
            ),
    ),
  );

  String? _validateDateFilters() {
    DateTime? parse(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;
      final value = DateTime.tryParse(raw);
      if (value == null || value.toIso8601String().substring(0, 10) != raw) {
        return null;
      }
      return value;
    }
    final controllers = [
      _invoiceFromController, _invoiceToController,
      _paymentFromController, _paymentToController,
    ];
    for (final controller in controllers) {
      final raw = controller.text.trim();
      if (raw.isNotEmpty && parse(controller) == null) {
        return 'اختر تاريخاً صحيحاً بصيغة YYYY-MM-DD.';
      }
    }
    final invoiceFrom = parse(_invoiceFromController);
    final invoiceTo = parse(_invoiceToController);
    if (invoiceFrom != null && invoiceTo != null && invoiceFrom.isAfter(invoiceTo)) {
      return 'بداية فترة الفواتير يجب ألا تتجاوز نهايتها.';
    }
    final paymentFrom = parse(_paymentFromController);
    final paymentTo = parse(_paymentToController);
    if (paymentFrom != null && paymentTo != null && paymentFrom.isAfter(paymentTo)) {
      return 'بداية فترة المدفوعات يجب ألا تتجاوز نهايتها.';
    }
    return null;
  }

  Future<void> _loadDimensions() async {
    final company = _company;
    if (company == null || company.isEmpty) return;
    final generation = ++_dimensionGeneration;
    setState(() => _loadingDimensions = true);
    try {
      final definitions = await widget.api.fetchPaymentReconciliationDimensions(company);
      if (!mounted || generation != _dimensionGeneration || company != _company) return;
      final next = <String, TextEditingController>{};
      for (final definition in definitions) {
        final fieldname = definition['fieldname']?.toString() ?? '';
        if (fieldname.isEmpty) continue;
        next[fieldname] = _dimensionControllers[fieldname] ?? TextEditingController();
      }
      for (final entry in _dimensionControllers.entries) {
        if (!next.containsKey(entry.key)) entry.value.dispose();
      }
      setState(() {
        _dimensionControllers
          ..clear()
          ..addAll(next);
        _dimensionDefinitions = definitions;
        _document = null;
      });
    } catch (error) {
      if (mounted && generation == _dimensionGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == _dimensionGeneration) {
        setState(() => _loadingDimensions = false);
      }
    }
  }

  Future<void> _loadAccounts() async {
    final company = _company;
    if (company == null) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loadingAccounts = true;
      _error = null;
      _account = null;
      _accounts = const [];
      _document = null;
    });
    try {
      final rows = await widget.api.fetchReconciliationAccounts(
        company: company,
        partyType: _partyType,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _accounts = rows;
        _account = rows.isEmpty ? null : rows.first['name']?.toString();
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingAccounts = false);
      }
    }
  }

  double? _optionalAmount(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value < 0) {
      throw FormatException('أدخل مبلغاً صحيحاً موجباً أو اترك الحقل فارغاً.');
    }
    return value;
  }

  Widget _advancedFilter(TextEditingController controller, String label,
      {bool numeric = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      enabled: !_busy,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (_) {
        if (_document != null) setState(() => _document = null);
      },
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح',
                onPressed: _busy ? null : () {
                  controller.clear();
                  setState(() => _document = null);
                },
                icon: const Icon(Icons.clear),
              ),
      ),
    ),
  );

  Future<void> _loadEntries() async {
    final company = _company;
    final party = _partyController.text.trim();
    final account = _account;
    if (company == null || party.isEmpty || account == null || account.isEmpty) {
      setState(() => _error = 'حدد الشركة والحساب وأدخل رمز العميل أو المورد.');
      return;
    }
    final dateError = _validateDateFilters();
    if (dateError != null) {
      setState(() => _error = dateError);
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loadingEntries = true;
      _error = null;
      _document = null;
    });
    try {
      final document = await widget.api.fetchUnreconciledPaymentEntries(
        company: company,
        partyType: _partyType,
        party: party,
        receivablePayableAccount: account,
        fromInvoiceDate: _invoiceFromController.text.trim(),
        toInvoiceDate: _invoiceToController.text.trim(),
        fromPaymentDate: _paymentFromController.text.trim(),
        toPaymentDate: _paymentToController.text.trim(),
        invoiceLimit: _invoiceLimit,
        paymentLimit: _paymentLimit,
        bankCashAccount: _bankCashAccountController.text,
        defaultAdvanceAccount: _advanceAccountController.text,
        costCenter: _costCenterController.text,
        project: _projectController.text,
        invoiceName: _invoiceNameController.text,
        paymentName: _paymentNameController.text,
        accountingDimensions: {
          for (final entry in _dimensionControllers.entries)
            if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
        },
        minimumInvoiceAmount: _optionalAmount(_minimumInvoiceController),
        maximumInvoiceAmount: _optionalAmount(_maximumInvoiceController),
        minimumPaymentAmount: _optionalAmount(_minimumPaymentController),
        maximumPaymentAmount: _optionalAmount(_maximumPaymentController),
      );
      if (!mounted || generation != _requestGeneration) return;
      final invoiceRows = document['invoices'] as List;
      final paymentRows = document['payments'] as List;
      setState(() {
        _document = document;
        _selectedInvoiceNumbers
          ..clear()
          ..addAll(invoiceRows.whereType<core.Map<String, dynamic>>()
              .map((row) => row['invoice_number']?.toString() ?? '')
              .where((name) => name.isNotEmpty));
        _selectedPaymentReferences
          ..clear()
          ..addAll(paymentRows.whereType<core.Map<String, dynamic>>()
              .map((row) => row['reference_name']?.toString() ?? '')
              .where((name) => name.isNotEmpty));
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingEntries = false);
      }
    }
  }

  Future<void> _previewAllocation() async {
    final document = _document;
    if (document == null || _busy) return;
    setState(() {
      _allocating = true;
      _error = null;
    });
    try {
      if (_selectedInvoiceNumbers.isEmpty || _selectedPaymentReferences.isEmpty) {
        throw const FormatException('حدد فاتورة واحدة ودفعة واحدة على الأقل قبل معاينة التخصيص.');
      }
      final result = await widget.api.allocatePaymentReconciliation(
        document,
        selectedInvoiceNumbers: _selectedInvoiceNumbers.toList(growable: false),
        selectedPaymentReferences: _selectedPaymentReferences.toList(growable: false),
      );
      if (!mounted) return;
      setState(() => _document = result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _allocating = false);
    }
  }

  Future<void> _editAllocation(int index) async {
    final document = _document;
    final raw = document?['allocation'];
    if (document == null || raw is! List || index < 0 || index >= raw.length || _busy) return;
    final current = raw[index];
    if (current is! core.Map) return;
    final controller = TextEditingController(
      text: current['allocated_amount']?.toString() ?? '',
    );
    final differenceAccountController = TextEditingController(
      text: current['difference_account']?.toString() ?? '',
    );
    final gainLossDateController = TextEditingController(
      text: current['gain_loss_posting_date']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    final values = await showDialog<core.Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل التخصيص'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'المبلغ المخصص',
                  helperText: 'سيعيد ERPNext التحقق من الرصيد المتاح عند التسوية.',
                ),
                validator: (value) {
                  final parsed = double.tryParse(value?.trim() ?? '');
                  if (parsed == null || !parsed.isFinite || parsed <= 0) {
                    return 'أدخل مبلغاً أكبر من صفر.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: differenceAccountController,
                decoration: const InputDecoration(
                  labelText: 'حساب فرق العملة (عند وجود فرق)',
                  helperText: 'حساب حركة تابع للشركة، وفق صلاحيات ERPNext.',
                ),
              ),
              TextFormField(
                controller: gainLossDateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'تاريخ قيد فرق العملة (عند وجود فرق)',
                  suffixIcon: Icon(Icons.calendar_today_outlined),
                ),
                onTap: () async {
                  final initial = DateTime.tryParse(gainLossDateController.text) ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) gainLossDateController.text = _dateString(picked);
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogContext, <String, dynamic>{
                'amount': double.parse(controller.text.trim()),
                'difference_account': differenceAccountController.text.trim(),
                'gain_loss_posting_date': gainLossDateController.text.trim(),
              });
            },
            child: const Text('حفظ التخصيص'),
          ),
        ],
      ),
    );
    controller.dispose();
    differenceAccountController.dispose();
    gainLossDateController.dispose();
    if (values == null || !mounted || _document != document) return;
    final amount = values['amount'] as double;
    setState(() {
      _allocating = true;
      _error = null;
    });
    try {
      final allocation = core.Map<String, dynamic>.from(current);
      final difference = await widget.api.calculatePaymentReconciliationDifference(
        document: document,
        allocation: allocation,
        allocatedAmount: amount,
      );
      if (difference.abs() > 0.0000001 &&
          ((values['difference_account'] as String).isEmpty ||
           (values['gain_loss_posting_date'] as String).isEmpty)) {
        throw const FormatException(
          'يوجد فرق عملة. حدد حساب الفرق وتاريخ قيد فرق العملة قبل حفظ التخصيص.',
        );
      }
      if (!mounted || _document != document) return;
      final updatedDocument = core.Map<String, dynamic>.from(document);
      final updatedAllocations = raw.map((row) =>
        core.Map<String, dynamic>.from(row as core.Map)
      ).toList(growable: true);
      updatedAllocations[index]['allocated_amount'] = amount;
      updatedAllocations[index]['difference_amount'] = difference;
      if ((values['difference_account'] as String).isNotEmpty) {
        updatedAllocations[index]['difference_account'] = values['difference_account'];
      }
      if ((values['gain_loss_posting_date'] as String).isNotEmpty) {
        updatedAllocations[index]['gain_loss_posting_date'] = values['gain_loss_posting_date'];
      }
      updatedDocument['allocation'] = updatedAllocations;
      setState(() {
        _document = updatedDocument;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _allocating = false);
    }
  }

  Future<void> _confirmReconciliation() async {
    final document = _document;
    final allocations = document?['allocation'];
    if (document == null || allocations is! List || allocations.isEmpty || _busy) return;
    final total = allocations.fold<double>(
      0,
      (sum, row) => sum + (row is core.Map ? _number(row['allocated_amount']) : 0),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسوية المدفوعات'),
        content: Text(
          'سيتم ربط ${allocations.length} تخصيصات بمبلغ إجمالي ${total.toStringAsFixed(2)} '
          'على ${document['party_type']} ${document['party']} في ERPNext. '
          'لن يتم إنشاء حركة بنكية جديدة. راجع التخصيصات قبل المتابعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('مراجعة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد التسوية'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _reconciling = true;
      _error = null;
    });
    try {
      await widget.api.reconcilePaymentAllocations(document);
      if (!mounted) return;
      setState(() => _document = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أكد ERPNext تنفيذ التسوية. أعد جلب السجلات لمراجعة المتبقي.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Map<String, double> _selectedTotals(
    List<core.Map<String, dynamic>> rows,
    Set<String> selected,
    String nameField,
    String amountField,
  ) {
    final totals = <String, double>{};
    for (final row in rows) {
      final name = row[nameField]?.toString() ?? '';
      if (name.isEmpty || !selected.contains(name)) continue;
      final currency = row['currency']?.toString().trim();
      final key = currency == null || currency.isEmpty ? 'عملة غير محددة' : currency;
      totals[key] = (totals[key] ?? 0) + _number(row[amountField]);
    }
    return totals;
  }

  Widget _currencyTotalsCard({
    required String title,
    required Map<String, double> totals,
  }) {
    if (totals.isEmpty) {
      return Card(
        child: ListTile(
          dense: true,
          title: Text(title),
          subtitle: const Text('لا توجد سجلات محددة.'),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...totals.entries.map((entry) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(entry.key),
                Text(entry.value.toStringAsFixed(2)),
              ],
            )),
          ],
        ),
      ),
    );
  }

  void _removeAllocation(int index) {
    final document = _document;
    final raw = document?['allocation'];
    if (document == null || raw is! List || index < 0 || index >= raw.length || _busy) return;
    setState(() {
      final updated = core.Map<String, dynamic>.from(document);
      final rows = raw
          .whereType<core.Map>()
          .map((row) => core.Map<String, dynamic>.from(row))
          .toList(growable: true);
      if (index >= rows.length) return;
      rows.removeAt(index);
      updated['allocation'] = rows;
      _document = updated;
      _error = null;
    });
  }

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 18, bottom: 8),
    child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  );

  Widget _selectableEntryCard({
    required String title,
    required String subtitle,
    required String amount,
    required bool selected,
    required ValueChanged<bool?> onChanged,
    IconData icon = Icons.receipt_long_outlined,
  }) => Card(
    child: CheckboxListTile(
      value: selected,
      onChanged: _busy ? null : onChanged,
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text('$subtitle • $amount'),
      controlAffinity: ListTileControlAffinity.leading,
      isThreeLine: false,
      dense: true,
    ),
  );

  void _changeInvoiceSelection(String name, bool? selected) {
    if (selected == null) return;
    setState(() {
      if (selected) {
        _selectedInvoiceNumbers.add(name);
      } else {
        _selectedInvoiceNumbers.remove(name);
      }
      if (_document != null) {
        _document = core.Map<String, dynamic>.from(_document!)
          ..['allocation'] = <core.Map<String, dynamic>>[];
      }
    });
  }

  void _changePaymentSelection(String name, bool? selected) {
    if (selected == null) return;
    setState(() {
      if (selected) {
        _selectedPaymentReferences.add(name);
      } else {
        _selectedPaymentReferences.remove(name);
      }
      if (_document != null) {
        _document = core.Map<String, dynamic>.from(_document!)
          ..['allocation'] = <core.Map<String, dynamic>>[];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final invoices = document?['invoices'] is List
        ? (document!['invoices'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    final payments = document?['payments'] is List
        ? (document!['payments'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    final allocations = document?['allocation'] is List
        ? (document!['allocation'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    final selectedInvoiceTotals = _selectedTotals(
      invoices, _selectedInvoiceNumbers, 'invoice_number', 'outstanding_amount',
    );
    final selectedPaymentTotals = _selectedTotals(
      payments, _selectedPaymentReferences, 'reference_name', 'amount',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('تسوية المدفوعات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد شركات متاحة.')))
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _busy ? null : (value) {
                setState(() => _company = value);
                _loadAccounts();
                _loadDimensions();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _partyType,
              decoration: const InputDecoration(labelText: 'نوع الطرف'),
              items: const [
                DropdownMenuItem(value: 'Customer', child: Text('عميل')),
                DropdownMenuItem(value: 'Supplier', child: Text('مورد')),
                DropdownMenuItem(value: 'Employee', child: Text('موظف')),
              ],
              onChanged: _busy ? null : (value) {
                if (value == null) return;
                setState(() {
                  _partyType = value;
                  _document = null;
                });
                _loadAccounts();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _partyController,
              enabled: !_busy,
              onChanged: (_) {
                if (_document != null) setState(() => _document = null);
              },
              decoration: InputDecoration(
                labelText: _partyType == 'Customer'
                    ? 'رمز العميل'
                    : _partyType == 'Supplier' ? 'رمز المورد' : 'رمز الموظف',
                hintText: _partyType == 'Customer'
                    ? 'مثال: CUST-0001'
                    : _partyType == 'Supplier' ? 'مثال: SUPP-0001' : 'مثال: HR-EMP-0001',
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingAccounts || _loadingDimensions) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              initialValue: _account,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'حساب الذمم'),
              items: _accounts.map((row) => DropdownMenuItem(
                value: row['name']?.toString(),
                child: Text(
                  '${row['name']} • ${row['account_currency'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              )).toList(),
              onChanged: _busy || _accounts.isEmpty ? null : (value) {
                setState(() {
                  _account = value;
                  _document = null;
                });
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _invoiceLimit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'حد الفواتير'),
                    items: const [50, 100, 250, 500].map((value) =>
                      DropdownMenuItem(value: value, child: Text('$value'))
                    ).toList(),
                    onChanged: _busy ? null : (value) {
                      if (value == null) return;
                      setState(() { _invoiceLimit = value; _document = null; });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _paymentLimit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'حد المدفوعات'),
                    items: const [50, 100, 250, 500].map((value) =>
                      DropdownMenuItem(value: value, child: Text('$value'))
                    ).toList(),
                    onChanged: _busy ? null : (value) {
                      if (value == null) return;
                      setState(() { _paymentLimit = value; _document = null; });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('فلاتر التاريخ'),
              children: [
                _dateField(_invoiceFromController, 'من تاريخ الفاتورة'),
                _dateField(_invoiceToController, 'إلى تاريخ الفاتورة'),
                _dateField(_paymentFromController, 'من تاريخ الدفعة'),
                _dateField(_paymentToController, 'إلى تاريخ الدفعة'),
              ],
            ),
            if (_dimensionDefinitions.isNotEmpty)
              ExpansionTile(
                title: Text('الأبعاد المحاسبية (${_dimensionDefinitions.length})'),
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.only(bottom: 8),
                    child: Text('هذه الأبعاد تُكتشف من إعدادات ERPNext وتُطبق على الفواتير والمدفوعات والقيود وفق صلاحيات المستخدم.'),
                  ),
                  ..._dimensionDefinitions.map((definition) {
                    final fieldname = definition['fieldname']?.toString() ?? '';
                    final controller = _dimensionControllers[fieldname];
                    if (controller == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: controller,
                        enabled: !_busy,
                        decoration: InputDecoration(
                          labelText: definition['label']?.toString() ?? fieldname,
                          helperText: 'نوع البيانات: ${definition['options'] ?? ''}',
                          suffixIcon: controller.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'مسح البعد',
                                  onPressed: _busy ? null : () {
                                    controller.clear();
                                    setState(() => _document = null);
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                        onChanged: (_) {
                          if (_document != null) setState(() => _document = null);
                        },
                      ),
                    );
                  }),
                ],
              ),
            ExpansionTile(
              title: const Text('الفلاتر المتقدمة المطابقة لـ ERPNext'),
              subtitle: const Text('تضييق النتائج حسب الحسابات والمبالغ والمستندات'),
              children: [
                _advancedFilter(_bankCashAccountController, 'حساب البنك أو النقد'),
                _advancedFilter(_advanceAccountController, 'حساب الدفعات المقدمة'),
                _advancedFilter(_costCenterController, 'مركز التكلفة'),
                _advancedFilter(_projectController, 'المشروع'),
                _advancedFilter(_invoiceNameController, 'رقم فاتورة محددة'),
                _advancedFilter(_paymentNameController, 'رقم دفعة محددة'),
                Row(children: [
                  Expanded(child: _advancedFilter(_minimumInvoiceController, 'أقل مبلغ فاتورة', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _advancedFilter(_maximumInvoiceController, 'أعلى مبلغ فاتورة', numeric: true)),
                ]),
                Row(children: [
                  Expanded(child: _advancedFilter(_minimumPaymentController, 'أقل مبلغ دفعة', numeric: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _advancedFilter(_maximumPaymentController, 'أعلى مبلغ دفعة', numeric: true)),
                ]),
                const Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
                  child: Text(
                    'تُرسل هذه المعايير إلى مستند Payment Reconciliation الأصلي؛ ويتحقق ERPNext من صلاحية الحسابات ومراكز التكلفة والمشاريع وفق الشركة وصلاحيات المستخدم.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _accounts.isEmpty ? null : _loadEntries,
              icon: const Icon(Icons.search),
              label: Text(_loadingEntries ? 'جارٍ جلب السجلات...' : 'جلب الفواتير والمدفوعات غير المسواة'),
            ),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (_loadingEntries || _allocating || _reconciling)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(),
              ),
            if (document != null) ...[
              _sectionTitle('الفواتير غير المسواة (${invoices.length}) • المحدد: ${_selectedInvoiceNumbers.length}'),
              if (invoices.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد فواتير مستحقة ضمن الفلاتر.')))
              else
                ...invoices.map((row) {
                  final name = row['invoice_number']?.toString() ?? '';
                  return _selectableEntryCard(
                    title: '${row['invoice_type'] ?? ''} • $name',
                    subtitle: '${row['invoice_date'] ?? ''} • ${row['currency'] ?? ''}',
                    amount: _number(row['outstanding_amount']).toStringAsFixed(2),
                    selected: _selectedInvoiceNumbers.contains(name),
                    onChanged: (value) => _changeInvoiceSelection(name, value),
                  );
                }),
              _currencyTotalsCard(
                title: 'إجمالي الفواتير المحددة حسب العملة',
                totals: selectedInvoiceTotals,
              ),
              _sectionTitle('المدفوعات غير المخصصة (${payments.length}) • المحدد: ${_selectedPaymentReferences.length}'),
              if (payments.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد مدفوعات غير مخصصة ضمن الفلاتر.')))
              else
                ...payments.map((row) {
                  final name = row['reference_name']?.toString() ?? '';
                  return _selectableEntryCard(
                    title: '${row['reference_type'] ?? ''} • $name',
                    subtitle: '${row['posting_date'] ?? ''} • ${row['currency'] ?? ''}',
                    amount: _number(row['amount']).toStringAsFixed(2),
                    selected: _selectedPaymentReferences.contains(name),
                    onChanged: (value) => _changePaymentSelection(name, value),
                    icon: Icons.payments_outlined,
                  );
                }),
              _currencyTotalsCard(
                title: 'إجمالي المدفوعات المحددة حسب العملة',
                totals: selectedPaymentTotals,
              ),
              if (allocations.isEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy || invoices.isEmpty || payments.isEmpty ||
                      _selectedInvoiceNumbers.isEmpty || _selectedPaymentReferences.isEmpty
                      ? null : _previewAllocation,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('معاينة التوزيع التلقائي حسب الأقدمية'),
                ),
              ] else ...[
                _sectionTitle('معاينة التخصيصات (${allocations.length})'),
                ...allocations.asMap().entries.map((entry) {
                  final row = entry.value;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.compare_arrows_outlined),
                      title: Text('${row['reference_type'] ?? ''} • ${row['reference_name'] ?? ''}'),
                      subtitle: Text(
                        'إلى ${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''}'
                        '${_number(row['difference_amount']).abs() > 0.0000001 ? '\nفرق العملة: ${_number(row['difference_amount']).toStringAsFixed(2)} • ${row['difference_account'] ?? 'حساب الفرق غير محدد'}' : ''}',
                      ),
                      isThreeLine: _number(row['difference_amount']).abs() > 0.0000001,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_number(row['allocated_amount']).toStringAsFixed(2)),
                          IconButton(
                            tooltip: 'تعديل مبلغ التخصيص',
                            onPressed: _busy ? null : () => _editAllocation(entry.key),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'حذف هذا التخصيص من المعاينة',
                            onPressed: _busy ? null : () => _removeAllocation(entry.key),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('يمكن تعديل مبلغ كل تخصيص قبل التأكيد. يتحقق ERPNext من الأرصدة والحدود النهائية عند تنفيذ التسوية.', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _confirmReconciliation,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('تأكيد التخصيص وترحيل التسوية'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _loadEntries,
                  child: const Text('إلغاء المعاينة وإعادة جلب السجلات'),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}
