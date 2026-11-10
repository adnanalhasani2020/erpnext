import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';
import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class JournalEntriesPage extends StatefulWidget {
  const JournalEntriesPage({super.key, required this.api, required this.companies});
  final FrappeApi api;
  final List<ErpCompany> companies;
  @override
  State<JournalEntriesPage> createState() => _JournalEntriesPageState();
}

class _JournalEntriesPageState extends State<JournalEntriesPage> {
  String? _company;
  final _date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
  final _remark = TextEditingController();
  final _search = TextEditingController();
  final _accountSearch = TextEditingController();
  List<core.Map<String, dynamic>> _accountOptions = [];
  bool _accountsLoading = false;
  String? _accountError;
  int _accountRequestId = 0;
  final List<_JournalLine> _lines = [_JournalLine(), _JournalLine()];
  List<core.Map<String, dynamic>> _drafts = [];
  String? _editing;
  String? _error;
  bool _loading = false, _saving = false, _submitting = false;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _loadAccounts();
    _load();
  }

  @override
  void dispose() {
    _accountRequestId++;
    _date.dispose(); _remark.dispose(); _search.dispose(); _accountSearch.dispose();
    for (final line in _lines) { line.dispose(); }
    super.dispose();
  }

  String _postingDateString(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickPostingDate() async {
    final initial = DateTime.tryParse(_date.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = _postingDateString(picked);
      _error = null;
    });
  }

  Future<void> _loadAccounts() async {
    final company = _company;
    final requestId = ++_accountRequestId;
    if (company == null || company.trim().isEmpty) {
      if (mounted) setState(() => _accountOptions = []);
      return;
    }
    setState(() {
      _accountsLoading = true;
      _accountError = null;
      _accountOptions = [];
    });
    try {
      final rows = await widget.api.fetchAccountingAccounts(
        company: company,
        search: _accountSearch.text.trim(),
      );
      if (!mounted || requestId != _accountRequestId || company != _company) return;
      setState(() {
        _accountOptions = rows.whereType<Map<String, dynamic>>().where((row) =>
          row['is_group'] != 1 && row['is_group'] != true &&
          row['disabled'] != 1 && row['disabled'] != true
        ).toList(growable: false);
      });
    } catch (error) {
      if (mounted && requestId == _accountRequestId) {
        setState(() => _accountError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && requestId == _accountRequestId) {
        setState(() => _accountsLoading = false);
      }
    }
  }

  double _amount(String value) => double.tryParse(value.trim()) ?? 0;
  double get _debit => _lines.fold(0, (v, e) => v + _amount(e.debit.text) * (_amount(e.exchangeRate.text) > 0 ? _amount(e.exchangeRate.text) : 1));
  double get _credit => _lines.fold(0, (v, e) => v + _amount(e.credit.text) * (_amount(e.exchangeRate.text) > 0 ? _amount(e.exchangeRate.text) : 1));

  Future<void> _load() async {
    final company = _company;
    if (company == null || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.api.fetchJournalEntryDrafts(company: company, search: _search.text);
      if (!mounted) return;
      setState(() => _drafts = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => _loading = false); }
  }

  void _resetForm() {
    for (final line in _lines) { line.dispose(); }
    _lines..clear()..addAll([_JournalLine(), _JournalLine()]);
    _editing = null; _remark.clear();
    _date.text = DateTime.now().toIso8601String().substring(0, 10);
    setState(() {});
  }

  Future<void> _edit(core.Map<String, dynamic> row) async {
    setState(() { _loading = true; _error = null; });
    try {
      final doc = await widget.api.fetchJournalEntryDocument(row['name'].toString());
      if (!mounted) return;
      if (doc['docstatus'] != 0 || doc['company'] != _company) throw const FormatException('المستند لم يعد مسودة لهذه الشركة.');
      for (final line in _lines) { line.dispose(); }
      _lines.clear();
      final raw = doc['accounts'];
      if (raw is List) {
        for (final item in raw.whereType<core.Map>()) {
          _lines.add(_JournalLine(
            account: item['account']?.toString() ?? '',
            debit: (item['debit_in_account_currency'] ?? item['debit'] ?? '').toString(),
            credit: (item['credit_in_account_currency'] ?? item['credit'] ?? '').toString(),
            exchangeRate: (item['exchange_rate'] ?? '1').toString(),
            costCenter: item['cost_center']?.toString() ?? '',
            project: item['project']?.toString() ?? '',
          ));
        }
      }
      while (_lines.length < 2) { _lines.add(_JournalLine()); }
      setState(() {
        _editing = doc['name'].toString();
        _date.text = doc['posting_date']?.toString() ?? _date.text;
        _remark.text = doc['user_remark']?.toString() ?? '';
      });
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _save() async {
    if (_saving || _company == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      final result = await widget.api.saveJournalEntryDraft(
        name: _editing, company: _company!, postingDate: _date.text.trim(),
        remark: _remark.text, accounts: _lines.map((e) => {
          'account': e.account.text, 'debit': _amount(e.debit.text), 'credit': _amount(e.credit.text),
          'cost_center': e.costCenter.text, 'project': e.project.text, 'exchange_rate': _amount(e.exchangeRate.text),
        }).toList(),
      );
      if (!mounted) return;
      _resetForm();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ المسودة: ${result['name']}')));
      await _load();
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _submit(core.Map<String, dynamic> row) async {
    if (_submitting) return;
    final name = row['name']?.toString() ?? '';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('ترحيل القيد اليومي'),
      content: Text('سيتم ترحيل القيد $name نهائياً عبر ERPNext، وقد ينشئ قيوداً محاسبية مؤثرة. راجع التاريخ والحسابات والتوازن قبل المتابعة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ترحيل')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { _submitting = true; _error = null; });
    try {
      await widget.api.submitJournalEntry(name, company: _company!);
      if (!mounted) return;
      if (_editing == name) _resetForm();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكد ERPNext ترحيل القيد.')));
      await _load();
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _submitting = false); }
  }


  Future<void> _cancel(core.Map<String, dynamic> row) async {
    final name = row['name']?.toString() ?? '';
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('تأكيد إلغاء القيد'),
      content: Text('سيُرسل طلب إلغاء القيد المرحّل $name إلى ERPNext. قد يرفض النظام الإلغاء إذا وُجدت قيود أو مستندات مرتبطة.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إلغاء القيد')),
      ],
    ));
    if (confirmed != true || !mounted || _submitting) return;
    setState(() { _submitting = true; _error = null; });
    try {
      await widget.api.cancelJournalEntry(name, company: _company ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('أكد ERPNext إلغاء القيد $name.')));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reverse(core.Map<String, dynamic> row) async {
    final name = row['name']?.toString() ?? '';
    final date = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('إنشاء قيد عكسي'),
      content: TextField(controller: date, decoration: const InputDecoration(labelText: 'تاريخ القيد العكسي YYYY-MM-DD')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إنشاء مسودة عكس')),
      ],
    ));
    if (confirmed != true || !mounted || _submitting) { date.dispose(); return; }
    setState(() { _submitting = true; _error = null; });
    try {
      final reversal = await widget.api.createJournalEntryReversalDraft(
        name: name, company: _company ?? '', postingDate: date.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إنشاء مسودة القيد العكسي: ${reversal['name']}')));
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      date.dispose();
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('القيود اليومية')),
    body: ListView(padding: const EdgeInsets.all(14), children: [
      DropdownButtonFormField<String>(
        initialValue: _company, isExpanded: true,
        decoration: const InputDecoration(labelText: 'الشركة'),
        items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
        onChanged: _loading || _saving || _submitting ? null : (v) { setState(() { _company = v; _drafts = []; }); _accountSearch.clear(); _resetForm(); _loadAccounts(); _load(); },
      ),
      const SizedBox(height: 12),
      Text(_editing == null ? 'إنشاء قيد جديد' : 'تعديل المسودة $_editing', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      TextField(
        controller: _accountSearch,
        enabled: !_accountsLoading && !_saving && !_submitting,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _loadAccounts(),
        decoration: InputDecoration(
          labelText: 'ابحث عن حساب الحركة',
          hintText: 'اسم الحساب أو رمزه أو نوعه',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            tooltip: 'بحث في دليل الحسابات',
            onPressed: _accountsLoading || _saving || _submitting ? null : _loadAccounts,
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      if (_accountsLoading) const LinearProgressIndicator(),
      if (_accountError != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('تعذر تحميل الحسابات'),
            subtitle: Text(_accountError!),
            trailing: IconButton(
              tooltip: 'إعادة المحاولة',
              onPressed: _accountsLoading ? null : _loadAccounts,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
      if (!_accountsLoading && _accountError == null && _accountOptions.isEmpty)
        const Text('لا توجد حسابات حركة مطابقة. ابحث بالاسم أو الرمز، وتأكد من صلاحية قراءة Account.'),
      const SizedBox(height: 8),
      TextField(
        controller: _date,
        readOnly: true,
        enabled: !_saving && !_submitting,
        onTap: _saving || _submitting ? null : _pickPostingDate,
        decoration: const InputDecoration(
          labelText: 'تاريخ القيد',
          hintText: 'YYYY-MM-DD',
          suffixIcon: Icon(Icons.calendar_today_outlined),
        ),
      ),
      const SizedBox(height: 8),
      TextField(controller: _remark, enabled: !_saving && !_submitting, decoration: const InputDecoration(labelText: 'البيان / شرح القيد')),
      const SizedBox(height: 12),
      ...List.generate(_lines.length, (i) {
        final line = _lines[i];
        final selectedAccount = line.account.text.trim();
        final selectedAccountFound = _accountOptions.any((row) => row['name']?.toString() == selectedAccount);
        return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
          Row(children: [
            Expanded(child: Text('السطر ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (_lines.length > 2) IconButton(onPressed: _saving || _submitting ? null : () { setState(() { _lines.removeAt(i).dispose(); }); }, icon: const Icon(Icons.delete_outline)),
          ]),
          DropdownButtonFormField<String>(
            key: ValueKey('journal-account-$i-$selectedAccount'),
            initialValue: selectedAccount.isEmpty ? null : selectedAccount,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'حساب الحركة'),
            items: [
              ..._accountOptions.map((account) {
                final id = account['name']?.toString() ?? '';
                final name = account['account_name']?.toString() ?? id;
                final currency = account['account_currency']?.toString() ?? '';
                return DropdownMenuItem(
                  value: id,
                  child: Text('$name • $id${currency.isEmpty ? '' : ' • $currency'}', overflow: TextOverflow.ellipsis),
                );
              }),
              if (selectedAccount.isNotEmpty && !selectedAccountFound)
                DropdownMenuItem(
                  value: selectedAccount,
                  child: Text('$selectedAccount • غير موجود في نتائج البحث الحالية', overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _saving || _submitting || _accountsLoading ? null : (value) {
              if (value == null) return;
              setState(() {
                line.account.text = value;
                // Never carry an exchange rate from a previously selected account.
                // Foreign-currency lines must be reviewed and assigned their own rate.
                line.exchangeRate.text = '1';
              });
            },
            validator: (value) => value == null || value.trim().isEmpty ? 'اختر حساب حركة من دليل الشركة.' : null,
          ),
          const SizedBox(height: 8),
          TextField(controller: line.exchangeRate, enabled: !_saving && !_submitting, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'سعر تحويل عملة الحساب إلى عملة الشركة (1 للحسابات المحلية)')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: line.debit, enabled: !_saving && !_submitting, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'مدين بعملة الحساب'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: line.credit, enabled: !_saving && !_submitting, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'دائن بعملة الحساب'))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: line.costCenter, enabled: !_saving && !_submitting, decoration: const InputDecoration(labelText: 'مركز التكلفة (اختياري)')),
          const SizedBox(height: 8),
          TextField(controller: line.project, enabled: !_saving && !_submitting, decoration: const InputDecoration(labelText: 'المشروع (اختياري)')),
        ])));
      }),
      OutlinedButton.icon(onPressed: _saving || _submitting ? null : () => setState(() => _lines.add(_JournalLine())), icon: const Icon(Icons.add), label: const Text('إضافة سطر')),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('يحوّل التطبيق مبالغ كل حساب إلى عملة الشركة بسعر التحويل المحدد، ويشترط توازن إجمالي المدين والدائن بعملة الشركة.')),
      Card(child: ListTile(
        title: Text('المدين: ${_debit.toStringAsFixed(2)}'),
        subtitle: Text('الدائن: ${_credit.toStringAsFixed(2)}'),
        trailing: Icon((_debit > 0 && (_debit - _credit).abs() <= 0.005) ? Icons.check_circle : Icons.balance,
          color: (_debit > 0 && (_debit - _credit).abs() <= 0.005) ? Colors.green : null),
      )),
      FilledButton.icon(onPressed: _saving || _loading || _submitting ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ المسودة')),
      if (_editing != null) TextButton(onPressed: _saving || _submitting ? null : _resetForm, child: const Text('إلغاء التعديل')),
      const Divider(height: 30),
      Text('سجل القيود اليومية', style: Theme.of(context).textTheme.titleLarge),
      TextField(controller: _search, enabled: !_loading && !_saving && !_submitting, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(),
        decoration: InputDecoration(labelText: 'بحث برقم القيد أو البيان', suffixIcon: IconButton(onPressed: _loading || _saving || _submitting ? null : _load, icon: const Icon(Icons.search)))),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
      if (_drafts.isEmpty && !_loading) const ListTile(title: Text('لا توجد مسودات ظاهرة لهذه الشركة.')),
      ..._drafts.map((row) => Card(child: ListTile(
        title: Text('${row['name']?.toString() ?? ''} • ${row['docstatus'] == 1 ? 'مرحّل' : 'مسودة'}'),
        subtitle: Text('${row['posting_date'] ?? ''} • مدين ${row['total_debit'] ?? '—'} • دائن ${row['total_credit'] ?? '—'}'),
        onTap: _loading || _saving || _submitting || row['docstatus'] != 0 ? null : () => _edit(row),
        trailing: row['docstatus'] == 0
          ? IconButton(tooltip: 'ترحيل', onPressed: _submitting ? null : () => _submit(row), icon: const Icon(Icons.publish))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(tooltip: 'إنشاء قيد عكسي', onPressed: _submitting ? null : () => _reverse(row), icon: const Icon(Icons.swap_horiz)),
              IconButton(tooltip: 'إلغاء القيد', onPressed: _submitting ? null : () => _cancel(row), icon: const Icon(Icons.cancel_outlined)),
            ]),
      ))),
      const SizedBox(height: 20),
    ]),
  );
}

class _JournalLine {
  _JournalLine({
    String account = '',
    String debit = '',
    String credit = '',
    String exchangeRate = '1',
    String costCenter = '',
    String project = '',
  })  : account = TextEditingController(text: account),
        debit = TextEditingController(text: debit),
        credit = TextEditingController(text: credit),
        exchangeRate = TextEditingController(text: exchangeRate),
        costCenter = TextEditingController(text: costCenter),
        project = TextEditingController(text: project);
  final TextEditingController account, debit, credit, exchangeRate, costCenter, project;
  void dispose() {
    account.dispose();
    debit.dispose();
    credit.dispose();
    exchangeRate.dispose();
    costCenter.dispose();
    project.dispose();
  }
}
