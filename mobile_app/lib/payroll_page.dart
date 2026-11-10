import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class PayrollPage extends StatefulWidget {
  const PayrollPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  String? _company;
  String? _costCenter;
  String? _payableAccount;
  String? _bankAccount;
  String _frequency = 'Monthly';
  final _postingDate = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  final _startDate = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month, 1).toIso8601String().substring(0, 10));
  final _endDate = TextEditingController(text: DateTime(DateTime.now().year, DateTime.now().month + 1, 0).toIso8601String().substring(0, 10));
  final _exchangeRate = TextEditingController(text: '1');
  late final TextEditingController _currencyController;
  List<core.Map<String, dynamic>> _costCenters = [];
  List<core.Map<String, dynamic>> _payableAccounts = [];
  List<core.Map<String, dynamic>> _bankAccounts = [];
  List<core.Map<String, dynamic>> _entries = [];
  bool _loadingSetup = false;
  bool _loadingEntries = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _currencyController = TextEditingController(text: _currency);
    _loadSetup();
    _loadEntries();
  }

  @override
  void dispose() {
    _postingDate.dispose();
    _startDate.dispose();
    _endDate.dispose();
    _exchangeRate.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  String get _currency {
    for (final item in widget.companies) {
      if (item.name == _company) return item.defaultCurrency ?? '';
    }
    return '';
  }

  Future<void> _loadSetup() async {
    final company = _company;
    if (company == null || company.isEmpty) return;
    setState(() {
      _loadingSetup = true;
      _error = null;
      _costCenters = [];
      _payableAccounts = [];
      _bankAccounts = [];
      _costCenter = null;
      _payableAccount = null;
      _bankAccount = null;
    });
    try {
      final results = await Future.wait([
        widget.api.fetchPayrollCostCenters(company: company),
        widget.api.fetchAccountingAccounts(company: company),
        widget.api.fetchBankAccounts(company: company),
      ]);
      if (!mounted || company != _company) return;
      final accounts = results[1].where((row) =>
        row['account_type'] == 'Payable' &&
        row['is_group'] != 1 && row['is_group'] != true
      ).toList();
      setState(() {
        _costCenters = results[0];
        _payableAccounts = accounts;
        _bankAccounts = results[2];
        _costCenter = _costCenters.isEmpty ? null : _costCenters.first['name']?.toString();
        _payableAccount = _payableAccounts.isEmpty ? null : _payableAccounts.first['name']?.toString();
        _bankAccount = _bankAccounts.isEmpty ? null : _bankAccounts.first['name']?.toString();
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingSetup = false);
    }
  }

  Future<void> _loadEntries() async {
    final company = _company;
    if (company == null || company.isEmpty) return;
    setState(() {
      _loadingEntries = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchPayrollEntries(company: company);
      if (!mounted || company != _company) return;
      setState(() => _entries = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingEntries = false);
    }
  }

  Future<void> _pickDate(TextEditingController controller, String label) async {
    final current = DateTime.tryParse(controller.text) ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: label,
    );
    if (value != null) {
      controller.text = value.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _createDraft() async {
    final company = _company;
    if (company == null || _costCenter == null || _payableAccount == null || _currencyController.text.trim().isEmpty) {
      setState(() => _error = 'يلزم إعداد مركز تكلفة وحساب رواتب دائن وعملة افتراضية للشركة في ERPNext.');
      return;
    }
    final rate = double.tryParse(_exchangeRate.text.trim());
    if (rate == null || !rate.isFinite || rate <= 0) {
      setState(() => _error = 'أدخل سعر صرف صحيحاً أكبر من صفر.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await widget.api.createPayrollEntryDraft(
        company: company,
        postingDate: _postingDate.text,
        startDate: _startDate.text,
        endDate: _endDate.text,
        payrollFrequency: _frequency,
        costCenter: _costCenter!,
        currency: _currencyController.text.trim(),
        exchangeRate: rate,
        payrollPayableAccount: _payableAccount!,
        paymentAccount: _bankAccount == null
            ? null
            : _bankAccounts.firstWhere((row) => row['name'] == _bankAccount)['account']?.toString(),
        bankAccount: _bankAccount,
      );
      final id = created['name']?.toString() ?? '';
      final filled = await widget.api.fillPayrollEmployees(name: id, company: company);
      final employees = filled['employees'] is List ? (filled['employees'] as List).length : 0;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُنشئت مسودة $id. عدد الموظفين المطابقين لإعدادات الرواتب: $employees. راجعها قبل الترحيل.')),
      );
      await _loadEntries();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showEntry(core.Map<String, dynamic> row) async {
    final company = _company;
    final name = row['name']?.toString() ?? '';
    if (company == null || name.isEmpty || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final document = await widget.api.fetchPayrollEntryDocument(name: name, company: company);
      final slips = await widget.api.fetchPayrollSalarySlips(payrollEntry: name, company: company);
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => _PayrollEntrySheet(
          document: document,
          slips: slips,
          onAction: (value) => Navigator.pop(sheetContext, value),
        ),
      );
      if (action == null || !mounted) return;
      setState(() => _saving = true);
      if (action == 'submit_entry') {
        final confirmed = await _confirm(
          'ترحيل دورة الرواتب',
          'سيقوم ERPNext بترحيل دورة الرواتب وإنشاء كشوف الرواتب للموظفين المدرجين. لا تتابع إلا بعد مراجعة الفترة والموظفين والحسابات.',
        );
        if (confirmed) {
          final submitted = await widget.api.submitPayrollEntry(name: name, company: company);
          final generatedSlips = await widget.api.fetchPayrollSalarySlips(
            payrollEntry: name, company: company,
          );
          final queued = submitted['status']?.toString() == 'Queued' || generatedSlips.isEmpty;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(queued
              ? 'رحّل ERPNext الدورة ووضع إنشاء كشوف الرواتب في قائمة المعالجة. حدّث الشاشة بعد اكتمال المهمة الخلفية.'
                : 'رحّل ERPNext الدورة وأنشأ ${generatedSlips.length} كشفاً كمسودات للمراجعة.')),
            );
          }
        }
      } else if (action == 'submit_slips') {
        final confirmed = await _confirm(
          'اعتماد كشوف الرواتب',
          'سيعتمد ERPNext كشوف الرواتب للمسودات المرتبطة بهذه الدورة وينشئ قيد استحقاق الرواتب وفق إعدادات الحسابات.',
        );
        if (confirmed) {
          final result = await widget.api.submitPayrollSalarySlips(name: name, company: company);
          final pending = int.tryParse(result['mobile_pending_salary_slips']?.toString() ?? '0') ?? 0;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(pending > 0
              ? 'قبل ERPNext الطلب، وما زال $pending كشفاً قيد المعالجة أو ينتظر الاعتماد.'
                : 'أكد ERPNext اعتماد كشوف الرواتب المعروضة.')),
            );
          }
        }
      } else if (action == 'bank_entry') {
        final confirmed = await _confirm(
          'إنشاء قيد صرف الرواتب',
          'سيستخدم ERPNext حساب الدفع والبنك المحددين في دورة الرواتب لإنشاء قيد الصرف. راجع حسابات الدفع قبل المتابعة.',
        );
        if (confirmed) {
          await widget.api.createPayrollBankEntry(name: name, company: company);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('أعاد ERPNext استجابة إنشاء قيد صرف الرواتب. راجع القيد في النظام قبل اعتبار الرواتب مدفوعة.')),
            );
          }
        }
      }
      await _loadEntries();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد')),
          ],
        ),
      ) == true;

  Widget _dateField(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      onTap: () => _pickDate(controller, label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دورة الرواتب'),
        actions: [
          IconButton(
            tooltip: 'تحديث الدورات',
            onPressed: _loadingEntries || _saving ? null : _loadEntries,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد شركات متاحة.')))
          else
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _saving ? null : (value) {
                setState(() {
                  _company = value;
                  _currencyController.text = _currency;
                });
                _loadSetup();
                _loadEntries();
              },
            ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('إنشاء دورة رواتب جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(labelText: 'تكرار الرواتب'),
                    items: const [
                      DropdownMenuItem(value: 'Monthly', child: Text('شهري')),
                      DropdownMenuItem(value: 'Fortnightly', child: Text('كل أسبوعين')),
                      DropdownMenuItem(value: 'Bimonthly', child: Text('مرتان شهرياً')),
                      DropdownMenuItem(value: 'Weekly', child: Text('أسبوعي')),
                      DropdownMenuItem(value: 'Daily', child: Text('يومي')),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _frequency = value ?? 'Monthly'),
                  ),
                  const SizedBox(height: 10),
                  _dateField(_postingDate, 'تاريخ الترحيل'),
                  _dateField(_startDate, 'بداية فترة الرواتب'),
                  _dateField(_endDate, 'نهاية فترة الرواتب'),
                  DropdownButtonFormField<String>(
                    initialValue: _costCenter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'مركز التكلفة'),
                    items: _costCenters.map((row) => DropdownMenuItem(
                      value: row['name']?.toString(),
                      child: Text(row['cost_center_name']?.toString() ?? row['name']?.toString() ?? ''),
                    )).toList(),
                    onChanged: _saving ? null : (value) => setState(() => _costCenter = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _payableAccount,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'حساب الرواتب المستحقة (Payable)'),
                    items: _payableAccounts.map((row) => DropdownMenuItem(
                      value: row['name']?.toString(),
                      child: Text(row['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: _saving ? null : (value) => setState(() => _payableAccount = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _bankAccount,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'حساب البنك للصرف (اختياري)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('بدون إعداد حساب صرف الآن')),
                      ..._bankAccounts.map((row) => DropdownMenuItem<String?>(
                        value: row['name']?.toString(),
                        child: Text(row['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
                      )),
                    ],
                    onChanged: _saving ? null : (value) => setState(() => _bankAccount = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _currencyController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'عملة الرواتب',
                      helperText: 'عملة الشركة الافتراضية: ${_currency.isEmpty ? 'غير محددة' : _currency}. يجب أن تطابق تعيينات هياكل الرواتب.',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _exchangeRate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر الصرف'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _saving || _loadingSetup || _costCenters.isEmpty || _payableAccounts.isEmpty
                        ? null : _createDraft,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(_saving ? 'جارٍ التنفيذ...' : 'إنشاء المسودة وجلب الموظفين'),
                  ),
                  if (_loadingSetup) const LinearProgressIndicator(),
                  const Text(
                    'تُحسب الرواتب داخل HRMS حسب هيكل الراتب والتعيينات والحضور والإجازات والضرائب. لا يحسب التطبيق الرواتب محلياً.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            ),
          const SizedBox(height: 12),
          Text('الدورات الموجودة', style: Theme.of(context).textTheme.titleMedium),
          if (_loadingEntries) const LinearProgressIndicator(),
          if (!_loadingEntries && _entries.isEmpty)
            const ListTile(title: Text('لا توجد دورات رواتب ظاهرة لهذه الشركة.')),
          ..._entries.map((row) => Card(
            child: ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: Text(row['name']?.toString() ?? ''),
              subtitle: Text(
                '${row['start_date'] ?? ''} → ${row['end_date'] ?? ''} • '
                '${row['number_of_employees'] ?? 0} موظف • ${row['status'] ?? ''}',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: _saving ? null : () => _showEntry(row),
            ),
          )),
        ],
      ),
    );
  }
}

class _PayrollEntrySheet extends StatelessWidget {
  const _PayrollEntrySheet({
    required this.document,
    required this.slips,
    required this.onAction,
  });

  final core.Map<String, dynamic> document;
  final List<core.Map<String, dynamic>> slips;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final submitted = document['docstatus'] == 1;
    final draft = document['docstatus'] == 0;
    final slipDrafts = slips.where((row) => row['docstatus'] == 0).length;
    final slipSubmitted = slips.where((row) => row['docstatus'] == 1).length;
    final employees = document['employees'] is List
        ? (document['employees'] as List).whereType<core.Map<String, dynamic>>().toList()
        : <core.Map<String, dynamic>>[];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text('دورة ${document['name'] ?? ''}', style: Theme.of(context).textTheme.titleLarge),
          Text('الحالة: ${document['status'] ?? ''} • الموظفون: ${document['number_of_employees'] ?? 0}'),
          Text('الفترة: ${document['start_date'] ?? ''} → ${document['end_date'] ?? ''}'),
          const Divider(),
          Text('الموظفون المحددون: ${employees.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          ...employees.take(100).map((row) => ListTile(
            dense: true,
            leading: const Icon(Icons.person_outline),
            title: Text('${row['employee_name'] ?? row['employee'] ?? ''}'),
            subtitle: Text('${row['employee'] ?? ''} • هيكل الراتب: ${row['salary_structure'] ?? 'سيُحدّد بواسطة HRMS'}'),
          )),
          if (employees.length > 100)
            Text('يُعرض أول 100 موظف من ${employees.length} لتخفيف تحميل الشاشة.'),
          const Divider(),
          Text('كشوف الرواتب: ${slips.length} • مسودات: $slipDrafts • معتمدة: $slipSubmitted'),
          ...slips.take(100).map((row) => ListTile(
            dense: true,
            title: Text('${row['employee_name'] ?? row['employee'] ?? ''}'),
            subtitle: Text('${row['name'] ?? ''} • ${row['status'] ?? ''}'),
            trailing: Text('${row['net_pay'] ?? 0} ${row['currency'] ?? ''}'),
          )),
          if (slips.length > 100)
            Text('يُعرض أول 100 كشف من ${slips.length} لتخفيف تحميل الشاشة.'),
          const SizedBox(height: 12),
          if (draft) ...[
            FilledButton(
              onPressed: (document['employees'] is List && (document['employees'] as List).isNotEmpty)
                  ? () => onAction('submit_entry') : null,
              child: const Text('ترحيل الدورة وإنشاء كشوف الرواتب'),
            ),
            const Text('يجب تحميل الموظفين أولاً؛ بعد الترحيل ينشئ HRMS كشوف الرواتب كمسودات للمراجعة.', style: TextStyle(fontSize: 12)),
          ],
          if (submitted && slipDrafts > 0)
            FilledButton(
              onPressed: () => onAction('submit_slips'),
              child: const Text('اعتماد كشوف الرواتب وقيد الاستحقاق'),
            ),
          if (submitted && slipDrafts == 0 && slipSubmitted > 0 &&
              (document['payment_account']?.toString().isNotEmpty ?? false) &&
              (document['bank_account']?.toString().isNotEmpty ?? false))
            FilledButton.tonal(
              onPressed: () => onAction('bank_entry'),
              child: const Text('إنشاء قيد صرف الرواتب'),
            ),
          if (document['error_message']?.toString().trim().isNotEmpty == true)
            Text(document['error_message'].toString(), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}
