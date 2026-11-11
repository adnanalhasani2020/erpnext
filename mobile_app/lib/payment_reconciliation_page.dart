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
  core.Map<String, dynamic>? _document;
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
    if (_company != null) _loadAccounts();
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
    super.dispose();
  }

  bool get _busy => _loadingAccounts || _loadingEntries || _allocating || _reconciling;

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
        minimumInvoiceAmount: _optionalAmount(_minimumInvoiceController),
        maximumInvoiceAmount: _optionalAmount(_maximumInvoiceController),
        minimumPaymentAmount: _optionalAmount(_minimumPaymentController),
        maximumPaymentAmount: _optionalAmount(_maximumPaymentController),
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _document = document);
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
      final result = await widget.api.allocatePaymentReconciliation(document);
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
    final formKey = GlobalKey<FormState>();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تعديل مبلغ التخصيص'),
        content: Form(
          key: formKey,
          child: TextFormField(
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
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogContext, double.parse(controller.text.trim()));
            },
            child: const Text('حفظ المبلغ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null || !mounted || _document != document) return;
    final updatedDocument = core.Map<String, dynamic>.from(document);
    final updatedAllocations = raw.map((row) =>
      core.Map<String, dynamic>.from(row as core.Map)
    ).toList(growable: true);
    updatedAllocations[index]['allocated_amount'] = amount;
    updatedDocument['allocation'] = updatedAllocations;
    setState(() {
      _document = updatedDocument;
      _error = null;
    });
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

  Widget _sectionTitle(String value) => Padding(
    padding: const EdgeInsetsDirectional.only(top: 18, bottom: 8),
    child: Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
  );

  Widget _entryCard({
    required String title,
    required String subtitle,
    required String amount,
    IconData icon = Icons.receipt_long_outlined,
  }) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Text(amount, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

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
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _partyType,
              decoration: const InputDecoration(labelText: 'نوع الطرف'),
              items: const [
                DropdownMenuItem(value: 'Customer', child: Text('عميل')),
                DropdownMenuItem(value: 'Supplier', child: Text('مورد')),
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
                labelText: _partyType == 'Customer' ? 'رمز العميل' : 'رمز المورد',
                hintText: _partyType == 'Customer' ? 'مثال: CUST-0001' : 'مثال: SUPP-0001',
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingAccounts) const LinearProgressIndicator(),
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
              _sectionTitle('الفواتير غير المسواة (${invoices.length})'),
              if (invoices.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد فواتير مستحقة ضمن الفلاتر.')))
              else
                ...invoices.map((row) => _entryCard(
                  title: '${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''}',
                  subtitle: '${row['invoice_date'] ?? ''} • ${row['currency'] ?? ''}',
                  amount: _number(row['outstanding_amount']).toStringAsFixed(2),
                )),
              _sectionTitle('المدفوعات غير المخصصة (${payments.length})'),
              if (payments.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد مدفوعات غير مخصصة ضمن الفلاتر.')))
              else
                ...payments.map((row) => _entryCard(
                  title: '${row['reference_type'] ?? ''} • ${row['reference_name'] ?? ''}',
                  subtitle: '${row['posting_date'] ?? ''} • ${row['currency'] ?? ''}',
                  amount: _number(row['amount']).toStringAsFixed(2),
                  icon: Icons.payments_outlined,
                )),
              if (allocations.isEmpty) ...[
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _busy || invoices.isEmpty || payments.isEmpty ? null : _previewAllocation,
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
                      subtitle: Text('إلى ${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_number(row['allocated_amount']).toStringAsFixed(2)),
                          IconButton(
                            tooltip: 'تعديل مبلغ التخصيص',
                            onPressed: _busy ? null : () => _editAllocation(entry.key),
                            icon: const Icon(Icons.edit_outlined),
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
