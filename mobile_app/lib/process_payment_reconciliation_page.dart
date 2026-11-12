import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'workspace_web_page.dart';
import 'models/erp_models.dart';

class ProcessPaymentReconciliationPage extends StatefulWidget {
  const ProcessPaymentReconciliationPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<ProcessPaymentReconciliationPage> createState() =>
      _ProcessPaymentReconciliationPageState();
}

class _ProcessPaymentReconciliationPageState
    extends State<ProcessPaymentReconciliationPage> {
  final _search = TextEditingController();
  final _party = TextEditingController();
  final _receivableAccount = TextEditingController();
  final _advanceAccount = TextEditingController();
  final _bankCashAccount = TextEditingController();
  final _costCenter = TextEditingController();
  final _invoiceFrom = TextEditingController();
  final _invoiceTo = TextEditingController();
  final _paymentFrom = TextEditingController();
  final _paymentTo = TextEditingController();

  String? _company;
  String? _editingJobName;
  String _partyType = 'Customer';
  String? _statusFilter;
  String? _partyTypeFilter;
  List<core.Map<String, dynamic>> _jobs = [];
  int _offset = 0;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _saving = false;
  bool _loadingPartyAccounts = false;
  final Set<String> _busyJobs = <String>{};
  final Map<String, core.Map<String, dynamic>> _details = {};
  final Map<String, String> _detailErrors = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _party.dispose();
    _receivableAccount.dispose();
    _advanceAccount.dispose();
    _bankCashAccount.dispose();
    _costCenter.dispose();
    _invoiceFrom.dispose();
    _invoiceTo.dispose();
    _paymentFrom.dispose();
    _paymentTo.dispose();
    super.dispose();
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  String _dateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim()) ?? DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value == null || !mounted) return;
    setState(() => controller.text = _dateString(value));
  }

  Widget _dateField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: IconButton(
            tooltip: 'اختيار التاريخ',
            onPressed: _saving ? null : () => _pickDate(controller),
            icon: const Icon(Icons.calendar_today_outlined),
          ),
        ),
      );

  Future<void> _load({bool more = false}) async {
    if (_loading || _loadingMore || (more && !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _offset = 0;
        _hasMore = false;
        _jobs = [];
        _error = null;
      }
    });
    try {
      final rows = await widget.api.fetchProcessPaymentReconciliationJobs(
        start: more ? _offset : 0,
        search: _search.text,
        company: _company,
        status: _statusFilter,
        partyType: _partyTypeFilter,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _jobs.addAll(rows);
        } else {
          _jobs = rows;
        }
        _offset += rows.length;
        _hasMore = rows.length == 50;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  String? _validateDates() {
    DateTime? parse(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null || parsed.toIso8601String().substring(0, 10) != raw) return null;
      return parsed;
    }
    final pairs = [
      (_invoiceFrom, _invoiceTo, 'الفواتير'),
      (_paymentFrom, _paymentTo, 'المدفوعات'),
    ];
    for (final pair in pairs) {
      for (final controller in [pair.$1, pair.$2]) {
        if (controller.text.trim().isNotEmpty && parse(controller) == null) {
          return 'تاريخ ${pair.$3} غير صحيح.';
        }
      }
      final from = parse(pair.$1), to = parse(pair.$2);
      if (from != null && to != null && from.isAfter(to)) {
        return 'بداية فترة ${pair.$3} يجب ألا تتجاوز نهايتها.';
      }
    }
    return null;
  }

  Future<void> _loadPartyAccounts() async {
    final company = _company;
    final party = _party.text.trim();
    if (_loadingPartyAccounts || _saving || company == null || party.isEmpty) return;
    setState(() {
      _loadingPartyAccounts = true;
      _error = null;
    });
    try {
      final defaults = await widget.api.fetchProcessPaymentReconciliationPartyAccounts(
        company: company,
        partyType: _partyType,
        party: party,
      );
      if (!mounted || company != _company || party != _party.text.trim()) return;
      setState(() {
        _receivableAccount.text = defaults['receivable_payable_account']?.toString() ?? '';
        _advanceAccount.text = defaults['default_advance_account']?.toString() ?? '';
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingPartyAccounts = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_saving) return;
    final company = _company;
    if (company == null || company.isEmpty) {
      setState(() => _error = 'حدد الشركة أولاً.');
      return;
    }
    final dateError = _validateDates();
    if (dateError != null) {
      setState(() => _error = dateError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.saveProcessPaymentReconciliationDraft(
        name: _editingJobName,
        company: company,
        partyType: _partyType,
        party: _party.text,
        receivablePayableAccount: _receivableAccount.text,
        defaultAdvanceAccount: _advanceAccount.text,
        bankCashAccount: _bankCashAccount.text,
        costCenter: _costCenter.text,
        fromInvoiceDate: _invoiceFrom.text,
        toInvoiceDate: _invoiceTo.text,
        fromPaymentDate: _paymentFrom.text,
        toPaymentDate: _paymentTo.text,
      );
      if (!mounted) return;
      _editingJobName = null;
      _party.clear();
      _receivableAccount.clear();
      _advanceAccount.clear();
      _bankCashAccount.clear();
      _costCenter.clear();
      _invoiceFrom.clear();
      _invoiceTo.clear();
      _paymentFrom.clear();
      _paymentTo.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حُفظت مسودة المهمة ${saved['name']}')),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadDraftForEdit(String name) async {
    if (_busyJobs.contains(name)) return;
    setState(() {
      _busyJobs.add(name);
      _error = null;
    });
    try {
      final document = await widget.api.fetchProcessPaymentReconciliationJob(name);
      if (!mounted) return;
      if (document['docstatus'] != 0) {
        throw const FormatException('لم تعد هذه المهمة مسودة قابلة للتعديل.');
      }
      setState(() {
        _editingJobName = name;
        _company = document['company']?.toString();
        _partyType = document['party_type']?.toString() ?? 'Customer';
        _party.text = document['party']?.toString() ?? '';
        _receivableAccount.text = document['receivable_payable_account']?.toString() ?? '';
        _advanceAccount.text = document['default_advance_account']?.toString() ?? '';
        _bankCashAccount.text = document['bank_cash_account']?.toString() ?? '';
        _costCenter.text = document['cost_center']?.toString() ?? '';
        _invoiceFrom.text = document['from_invoice_date']?.toString() ?? '';
        _invoiceTo.text = document['to_invoice_date']?.toString() ?? '';
        _paymentFrom.text = document['from_payment_date']?.toString() ?? '';
        _paymentTo.text = document['to_payment_date']?.toString() ?? '';
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyJobs.remove(name));
    }
  }

  Future<void> _runAction(
    String name,
    Future<core.Map<String, dynamic>> Function(String) action,
    String successMessage,
  ) async {
    if (!_busyJobs.add(name)) return;
    setState(() => _error = null);
    try {
      final updated = await action(name);
      if (!mounted) return;
      setState(() {
        final index = _jobs.indexWhere((row) => row['name'] == name);
        if (index >= 0) _jobs[index] = {..._jobs[index], ...updated};
        _details.remove(name);
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busyJobs.remove(name));
    }
  }

  Future<void> _loadDetails(String name) async {
    if (_busyJobs.contains(name)) return;
    setState(() {
      _busyJobs.add(name);
      _detailErrors.remove(name);
    });
    try {
      final values = await Future.wait([
        widget.api.fetchProcessPaymentReconciliationJob(name),
        widget.api.fetchProcessPaymentReconciliationProgress(name),
        widget.api.fetchProcessPaymentReconciliationLog(name),
      ]);
      if (!mounted) return;
      setState(() {
        _details[name] = {
          'document': values[0],
          'progress': values[1],
          'log': values[2],
        };
      });
    } catch (error) {
      if (mounted) {
        setState(() => _detailErrors[name] =
            error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busyJobs.remove(name));
    }
  }

  Widget _jobCard(core.Map<String, dynamic> job) {
    final name = job['name']?.toString() ?? '';
    final status = job['status']?.toString() ?? 'غير محددة';
    final docStatus = int.tryParse(job['docstatus']?.toString() ?? '0') ?? 0;
    final busy = _busyJobs.contains(name);
    final detail = _details[name];
    final progress = detail?['progress'] is core.Map
        ? detail!['progress'] as core.Map
        : const <String, dynamic>{};
    final log = detail?['log'] is core.Map
        ? detail!['log'] as core.Map
        : null;
    final allocations = log?['allocations'] is List
        ? (log!['allocations'] as List).whereType<core.Map>().toList()
        : <core.Map>[];
    final total = int.tryParse(progress['total']?.toString() ?? '0') ?? 0;
    final processed = int.tryParse(progress['processed']?.toString() ?? '0') ?? 0;
    final ratio = total <= 0 ? (status == 'Completed' ? 1.0 : 0.0) : (processed / total).clamp(0.0, 1.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(name, textDirection: TextDirection.ltr),
              subtitle: Text(
                '${job['party_type'] ?? ''} • ${job['party'] ?? ''}\n'
                '${job['company'] ?? ''} • ${job['receivable_payable_account'] ?? ''}\n'
                'الحالة: $status • حالة المستند: ${docStatus == 0 ? 'مسودة' : docStatus == 1 ? 'مرحّل' : 'ملغي'}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'تحديث التقدم والسجل',
                onPressed: busy ? null : () => _loadDetails(name),
                icon: const Icon(Icons.analytics_outlined),
              ),
            ),
            if (job['error_log']?.toString().trim().isNotEmpty == true)
              ExpansionTile(
                title: const Text('سجل أخطاء الخادم'),
                children: [Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(job['error_log'].toString()),
                )],
              ),
            if (busy) const LinearProgressIndicator(),
            if (detail != null) ...[
              Text('التقدم: $processed من $total'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: ratio),
              if (log != null) ...[
                const SizedBox(height: 8),
                Text('سجل التنفيذ: ${log['name']} • ${log['status'] ?? ''}'),
                Text('التخصيصات: ${log['total_allocations'] ?? 0} • المنفذ: ${log['reconciled_entries'] ?? 0}'),
                if (allocations.isNotEmpty)
                  ExpansionTile(
                    title: Text('تفاصيل التخصيصات (${allocations.length})'),
                    children: allocations.map((row) => ListTile(
                      dense: true,
                      title: Text('${row['reference_type'] ?? ''} • ${row['reference_name'] ?? ''}'),
                      subtitle: Text('إلى ${row['invoice_type'] ?? ''} • ${row['invoice_number'] ?? ''} • ${row['reconciled'] == 1 || row['reconciled'] == true ? 'تمت التسوية' : 'بانتظار التنفيذ'}'),
                      trailing: Text(_number(row['allocated_amount']).toStringAsFixed(2)),
                    )).toList(),
                  ),
              ] else
                const Text('لم ينشئ الخادم سجل التنفيذ بعد.'),
            ],
            if (_detailErrors.containsKey(name))
              Text(_detailErrors[name]!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (docStatus == 0) ...[
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _loadDraftForEdit(name),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('تعديل المسودة'),
                  ),
                  FilledButton.tonal(
                    onPressed: busy ? null : () => _confirmSubmit(name),
                    child: const Text('ترحيل المهمة'),
                  ),
                ],
                if (docStatus == 1 && (status == 'Queued' || status == 'Paused'))
                  FilledButton(
                    onPressed: busy ? null : () => _runAction(
                      name, widget.api.startProcessPaymentReconciliation, 'استلم ERPNext طلب بدء المهمة؛ تحقق من حالتها بعد قليل.',
                    ),
                    child: Text(status == 'Paused' ? 'استئناف' : 'بدء التنفيذ'),
                  ),
                if (docStatus == 1 && status == 'Running')
                  OutlinedButton(
                    onPressed: busy ? null : () => _runAction(
                      name, widget.api.pauseProcessPaymentReconciliation, 'تم إيقاف المهمة مؤقتاً.',
                    ),
                    child: const Text('إيقاف مؤقت'),
                  ),
                if (docStatus == 1 && status != 'Running' && status != 'Completed' && status != 'Cancelled')
                  TextButton(
                    onPressed: busy ? null : () => _confirmCancel(name),
                    child: const Text('إلغاء المهمة'),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : () => _loadDetails(name),
                  child: const Text('عرض التقدم والسجل'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSubmit(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ترحيل مهمة التسوية الجماعية'),
        content: Text(
          'سيتم ترحيل المهمة $name إلى قائمة ERPNext. بعد بدء التنفيذ، قد ينشئ الخادم تسويات فعلية لعدد كبير من الفواتير والمدفوعات في الخلفية. راجع الشركة والطرف وحساب الذمم والفترات قبل المتابعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('مراجعة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد الترحيل'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runAction(
        name,
        widget.api.submitProcessPaymentReconciliation,
        'تم ترحيل المهمة ووضعها في قائمة الانتظار.',
      );
    }
  }

  Future<void> _confirmCancel(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء مهمة التسوية'),
        content: Text('سيطلب من ERPNext إلغاء المهمة $name. لن تُلغى أي مستندات دفع تم ترحيلها سابقاً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('رجوع')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد الإلغاء')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _runAction(name, widget.api.cancelProcessPaymentReconciliation, 'أكد ERPNext إلغاء المهمة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التسوية الآلية للمدفوعات'),
        actions: [
          IconButton(tooltip: 'فتح قائمة ERPNext الأصلية', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceWebPage(api: widget.api, title: 'Process Payment Reconciliation', linkType: 'DocTypeList', target: 'Process Payment Reconciliation'))), icon: const Icon(Icons.open_in_browser)),
          IconButton(
            tooltip: 'تحديث المهام',
            onPressed: _loading || _loadingMore ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد شركات متاحة.')))
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تصفية حسب الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _loading || _loadingMore ? null : (value) {
                setState(() => _company = value);
                _load();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _statusFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تصفية حالة المهمة'),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('كل الحالات')),
                DropdownMenuItem<String?>(value: 'Queued', child: Text('في قائمة الانتظار')),
                DropdownMenuItem<String?>(value: 'Running', child: Text('قيد التنفيذ')),
                DropdownMenuItem<String?>(value: 'Paused', child: Text('متوقفة مؤقتاً')),
                DropdownMenuItem<String?>(value: 'Completed', child: Text('مكتملة')),
                DropdownMenuItem<String?>(value: 'Partially Reconciled', child: Text('مسواة جزئياً')),
                DropdownMenuItem<String?>(value: 'Failed', child: Text('فشلت')),
                DropdownMenuItem<String?>(value: 'Cancelled', child: Text('ملغاة')),
              ],
              onChanged: _loading || _loadingMore ? null : (value) {
                setState(() => _statusFilter = value);
                _load();
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: _partyTypeFilter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تصفية نوع الطرف'),
              items: const [
                DropdownMenuItem<String?>(value: null, child: Text('كل أنواع الأطراف')),
                DropdownMenuItem<String?>(value: 'Customer', child: Text('العملاء')),
                DropdownMenuItem<String?>(value: 'Supplier', child: Text('الموردون')),
                DropdownMenuItem<String?>(value: 'Employee', child: Text('الموظفون')),
              ],
              onChanged: _loading || _loadingMore ? null : (value) {
                setState(() => _partyTypeFilter = value);
                _load();
              },
            ),
            const SizedBox(height: 10),
            ExpansionTile(
              key: ValueKey('process-reconciliation-form-${_editingJobName ?? 'new'}'),
              initiallyExpanded: _editingJobName != null,
              title: Text(_editingJobName == null ? 'إنشاء مهمة تسوية جماعية' : 'تعديل مسودة $_editingJobName'),
              subtitle: const Text('يعالج ERPNext الفواتير والمدفوعات في الخلفية ويحتفظ بسجل التقدم.'),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _partyType,
                  decoration: const InputDecoration(labelText: 'نوع الطرف'),
                  items: const [
                    DropdownMenuItem(value: 'Customer', child: Text('عميل')),
                    DropdownMenuItem(value: 'Supplier', child: Text('مورد')),
                    DropdownMenuItem(value: 'Employee', child: Text('موظف')),
                  ],
                  onChanged: _saving || _loadingPartyAccounts ? null : (value) {
                    if (value != null) {
                      setState(() {
                        _partyType = value;
                        _party.clear();
                        _receivableAccount.clear();
                        _advanceAccount.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _party,
                  enabled: !_saving && !_loadingPartyAccounts,
                  decoration: InputDecoration(
                    labelText: 'رمز الطرف',
                    suffixIcon: IconButton(
                      tooltip: 'جلب حسابات الطرف من ERPNext',
                      onPressed: _saving || _loadingPartyAccounts ? null : _loadPartyAccounts,
                      icon: _loadingPartyAccounts
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.manage_search),
                    ),
                  ),
                  onSubmitted: (_) => _loadPartyAccounts(),
                  onChanged: (_) {
                    if (_receivableAccount.text.isNotEmpty || _advanceAccount.text.isNotEmpty) {
                      setState(() {
                        _receivableAccount.clear();
                        _advanceAccount.clear();
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(controller: _receivableAccount, decoration: const InputDecoration(labelText: 'حساب الذمم')),
                const SizedBox(height: 8),
                TextField(controller: _advanceAccount, decoration: const InputDecoration(labelText: 'حساب الدفعات المقدمة (اختياري)')),
                const SizedBox(height: 8),
                TextField(controller: _bankCashAccount, decoration: const InputDecoration(labelText: 'حساب البنك/الصندوق (اختياري)')),
                const SizedBox(height: 8),
                TextField(controller: _costCenter, decoration: const InputDecoration(labelText: 'مركز التكلفة (اختياري)')),
                const SizedBox(height: 8),
                _dateField(_invoiceFrom, 'الفواتير من تاريخ'),
                const SizedBox(height: 8),
                _dateField(_invoiceTo, 'الفواتير إلى تاريخ'),
                const SizedBox(height: 8),
                _dateField(_paymentFrom, 'المدفوعات من تاريخ'),
                const SizedBox(height: 8),
                _dateField(_paymentTo, 'المدفوعات إلى تاريخ'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving || _loadingPartyAccounts ? null : _saveDraft,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: Text(_editingJobName == null ? 'حفظ مسودة المهمة' : 'حفظ تعديلات المسودة'),
                ),
                if (_editingJobName != null)
                  TextButton(
                    onPressed: _saving ? null : () {
                      setState(() {
                        _editingJobName = null;
                        _party.clear();
                        _receivableAccount.clear();
                        _advanceAccount.clear();
                        _bankCashAccount.clear();
                        _costCenter.clear();
                        _invoiceFrom.clear();
                        _invoiceTo.clear();
                        _paymentFrom.clear();
                        _paymentTo.clear();
                      });
                    },
                    child: const Text('إلغاء التعديل'),
                  ),
              ],
            ),
            const Divider(height: 28),
          ],
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'بحث برقم المهمة أو الطرف',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'بحث',
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (!_loading && _jobs.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد مهام تسوية مطابقة للفلاتر.'))),
          ..._jobs.map(_jobCard),
          if (_hasMore || _loadingMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.tonal(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(_loadingMore ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من المهام'),
              ),
            ),
        ],
      ),
    );
  }
}
