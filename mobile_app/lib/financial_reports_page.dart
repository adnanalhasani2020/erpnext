import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class FinancialReportsPage extends StatefulWidget {
  const FinancialReportsPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<FinancialReportsPage> createState() => _FinancialReportsPageState();
}

class _FinancialReportsPageState extends State<FinancialReportsPage> {
  bool _receivables = true;
  bool _loading = false;
  String? _company;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchOutstandingInvoices(
        receivable: _receivables,
        company: _company,
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _rows = const [];
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  double _amount(Map<String, dynamic> row) {
    final value = row['outstanding_amount'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _dueDate(Map<String, dynamic> row) {
    final due = DateTime.tryParse(row['due_date']?.toString() ?? '');
    return due ?? DateTime.tryParse(row['posting_date']?.toString() ?? '');
  }

  int _bucket(Map<String, dynamic> row) {
    final due = _dueDate(row);
    if (due == null) return 0;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final dueDate = DateTime(due.year, due.month, due.day);
    final days = todayDate.difference(dueDate).inDays;
    if (days <= 0) return 0;
    if (days <= 30) return 1;
    if (days <= 60) return 2;
    if (days <= 90) return 3;
    return 4;
  }

  String _money(double amount, String currency) =>
      '${amount.toStringAsFixed(2)} ${currency.isEmpty ? '—' : currency}';

  Widget _summaryForCurrency(String currency, List<Map<String, dynamic>> rows) {
    final totals = List<double>.filled(5, 0);
    for (final row in rows) {
      totals[_bucket(row)] += _amount(row);
    }
    final labels = ['غير مستحق', '1–30 يوم', '31–60 يوم', '61–90 يوم', 'أكثر من 90'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('العملة: ${currency.isEmpty ? 'غير محددة' : currency}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...List.generate(5, (index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(labels[index])),
                  Text(_money(totals[index], currency),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            )),
            const Divider(),
            Row(
              children: [
                const Expanded(child: Text('الإجمالي المتبقي',
                    style: TextStyle(fontWeight: FontWeight.bold))),
                Text(_money(totals.fold<double>(0, (a, b) => a + b), currency),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _invoiceTile(Map<String, dynamic> row) {
    final partyField = _receivables ? 'customer_name' : 'supplier_name';
    final partyCodeField = _receivables ? 'customer' : 'supplier';
    final party = row[partyField]?.toString().trim().isNotEmpty == true
        ? row[partyField].toString()
        : row[partyCodeField]?.toString() ?? '—';
    final due = _dueDate(row);
    final currency = row['currency']?.toString() ?? '';
    final overdue = _bucket(row);
    final overdueLabel = ['غير مستحق', 'متأخر 1–30 يوم', 'متأخر 31–60 يوم',
      'متأخر 61–90 يوم', 'متأخر أكثر من 90 يوم'][overdue];
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(overdue >= 3 ? Icons.warning_amber : Icons.receipt_long_outlined),
        ),
        title: Text(row['name']?.toString() ?? '—'),
        subtitle: Text([
          party,
          row['company']?.toString() ?? '',
          'الاستحقاق: ${due == null ? 'غير محدد' : due.toIso8601String().split('T').first}',
          overdueLabel,
        ].where((part) => part.isNotEmpty).join(' • ')),
        trailing: Text(_money(_amount(row), currency),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _rows) {
      final currency = row['currency']?.toString() ?? '';
      grouped.putIfAbsent(currency, () => []).add(row);
    }
    final currencies = grouped.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const CircleAvatar(child: Icon(Icons.assessment_outlined)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('تقارير الذمم', style: Theme.of(context).textTheme.titleLarge),
                  Text('أعمار الفواتير المستحقة للعملاء والموردين',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث التقرير',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('ذمم العملاء'), icon: Icon(Icons.call_received)),
            ButtonSegment(value: false, label: Text('ذمم الموردين'), icon: Icon(Icons.call_made)),
          ],
          selected: {_receivables},
          onSelectionChanged: _loading ? null : (selection) {
            setState(() => _receivables = selection.first);
            _load();
          },
        ),
        const SizedBox(height: 12),
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
          onChanged: _loading ? null : (value) {
            setState(() => _company = value == null || value.isEmpty ? null : value);
            _load();
          },
        ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ),
        if (!_loading && _error == null && _rows.isEmpty)
          const Card(child: ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('لا توجد فواتير مستحقة ضمن نطاق التقرير'),
          )),
        if (_rows.isNotEmpty) ...[
          Text('عدد الفواتير: ${_rows.length}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('تُجمع المبالغ حسب العملة ولا تُخلط العملات المختلفة. الأعمار محسوبة من تاريخ الاستحقاق؛ وإذا لم يتوفر يُستخدم تاريخ الترحيل.'),
          const SizedBox(height: 8),
          ...currencies.map((currency) => _summaryForCurrency(currency, grouped[currency]!)),
          const SizedBox(height: 12),
          Text('تفاصيل الفواتير', style: Theme.of(context).textTheme.titleMedium),
          ..._rows.map(_invoiceTile),
        ],
        const SizedBox(height: 12),
        const Text('التقرير يعرض الفواتير المرحلة ذات الرصيد المتبقي فقط، ويستبعد المرتجعات. الحد الأعلى 10000 فاتورة في الطلب الواحد؛ استخدم فلتر الشركة إذا تجاوزت البيانات هذا الحد.',
            style: TextStyle(fontSize: 12)),
      ],
    );
  }
}
