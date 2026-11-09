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
  final List<_JournalLine> _lines = [_JournalLine(), _JournalLine()];
  List<Map<String, dynamic>> _drafts = [];
  String? _editing;
  String? _error;
  bool _loading = false, _saving = false, _submitting = false;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    _load();
  }

  @override
  void dispose() {
    _date.dispose(); _remark.dispose(); _search.dispose();
    for (final line in _lines) { line.dispose(); }
    super.dispose();
  }

  double _amount(String value) => double.tryParse(value.trim()) ?? 0;
  double get _debit => _lines.fold(0, (v, e) => v + _amount(e.debit.text));
  double get _credit => _lines.fold(0, (v, e) => v + _amount(e.credit.text));

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

  Future<void> _edit(Map<String, dynamic> row) async {
    setState(() { _loading = true; _error = null; });
    try {
      final doc = await widget.api.fetchJournalEntryDocument(row['name'].toString());
      if (!mounted) return;
      if (doc['docstatus'] != 0 || doc['company'] != _company) throw const FormatException('المستند لم يعد مسودة لهذه الشركة.');
      for (final line in _lines) { line.dispose(); }
      _lines.clear();
      final raw = doc['accounts'];
      if (raw is List) {
        for (final item in raw.whereType<Map>()) {
          _lines.add(_JournalLine(
            account: item['account']?.toString() ?? '',
            debit: (item['debit_in_account_currency'] ?? item['debit'] ?? '').toString(),
            credit: (item['credit_in_account_currency'] ?? item['credit'] ?? '').toString(),
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
        }).toList(),
      );
      if (!mounted) return;
      _resetForm();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حفظ المسودة: ${result['name']}')));
      await _load();
    } catch (e) { if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  Future<void> _submit(Map<String, dynamic> row) async {
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('القيود اليومية')),
    body: ListView(padding: const EdgeInsets.all(14), children: [
      DropdownButtonFormField<String>(
        initialValue: _company, isExpanded: true,
        decoration: const InputDecoration(labelText: 'الشركة'),
        items: widget.companies.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
        onChanged: _loading || _saving ? null : (v) { setState(() { _company = v; _drafts = []; }); _resetForm(); _load(); },
      ),
      const SizedBox(height: 12),
      Text(_editing == null ? 'إنشاء مسودة قيد' : 'تعديل المسودة $_editing', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      TextField(controller: _date, decoration: const InputDecoration(labelText: 'تاريخ القيد (YYYY-MM-DD)')),
      const SizedBox(height: 8),
      TextField(controller: _remark, decoration: const InputDecoration(labelText: 'البيان / شرح القيد')),
      const SizedBox(height: 12),
      ...List.generate(_lines.length, (i) {
        final line = _lines[i];
        return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
          Row(children: [
            Expanded(child: Text('السطر ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold))),
            if (_lines.length > 2) IconButton(onPressed: _saving ? null : () { setState(() { _lines.removeAt(i).dispose(); }); }, icon: const Icon(Icons.delete_outline)),
          ]),
          TextField(controller: line.account, decoration: const InputDecoration(labelText: 'رمز حساب الحركة في ERPNext')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: line.debit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'مدين'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: line.credit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'دائن'))),
          ]),
        ])));
      }),
      OutlinedButton.icon(onPressed: _saving ? null : () => setState(() => _lines.add(_JournalLine())), icon: const Icon(Icons.add), label: const Text('إضافة سطر')),
      Card(child: ListTile(
        title: Text('المدين: ${_debit.toStringAsFixed(2)}'),
        subtitle: Text('الدائن: ${_credit.toStringAsFixed(2)}'),
        trailing: Icon((_debit > 0 && (_debit - _credit).abs() <= 0.005) ? Icons.check_circle : Icons.balance,
          color: (_debit > 0 && (_debit - _credit).abs() <= 0.005) ? Colors.green : null),
      )),
      FilledButton.icon(onPressed: _saving || _loading ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ المسودة')),
      if (_editing != null) TextButton(onPressed: _saving ? null : _resetForm, child: const Text('إلغاء التعديل')),
      const Divider(height: 30),
      Text('مسودات القيود', style: Theme.of(context).textTheme.titleLarge),
      TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(),
        decoration: InputDecoration(labelText: 'بحث برقم القيد أو البيان', suffixIcon: IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.search)))),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Card(color: Theme.of(context).colorScheme.errorContainer, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!))),
      if (_drafts.isEmpty && !_loading) const ListTile(title: Text('لا توجد مسودات ظاهرة لهذه الشركة.')),
      ..._drafts.map((row) => Card(child: ListTile(
        title: Text(row['name']?.toString() ?? ''),
        subtitle: Text('${row['posting_date'] ?? ''} • مدين ${row['total_debit'] ?? '—'} • دائن ${row['total_credit'] ?? '—'}'),
        onTap: _loading || _saving ? null : () => _edit(row),
        trailing: IconButton(tooltip: 'ترحيل', onPressed: _submitting ? null : () => _submit(row), icon: const Icon(Icons.publish)),
      ))),
      const SizedBox(height: 20),
    ]),
  );
}

class _JournalLine {
  _JournalLine({String account = '', String debit = '', String credit = ''})
      : account = TextEditingController(text: account),
        debit = TextEditingController(text: debit),
        credit = TextEditingController(text: credit);
  final TextEditingController account, debit, credit;
  void dispose() { account.dispose(); debit.dispose(); credit.dispose(); }
}
