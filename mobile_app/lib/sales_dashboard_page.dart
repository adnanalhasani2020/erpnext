import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'models/erp_models.dart';

class SalesDashboardPage extends StatefulWidget {
  const SalesDashboardPage({
    super.key,
    required this.api,
    required this.companies,
  });

  final FrappeApi api;
  final List<ErpCompany> companies;

  @override
  State<SalesDashboardPage> createState() => _SalesDashboardPageState();
}

class _SalesDashboardPageState extends State<SalesDashboardPage> {
  String? _company;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  List<Map<String, dynamic>> _invoices = const [];
  bool _loading = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _company = widget.companies.isEmpty ? null : widget.companies.first.name;
    if (_company != null) _load();
  }

  @override
  void dispose() {
    _requestGeneration++;
    super.dispose();
  }

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _load() async {
    final company = _company;
    if (company == null || company.trim().isEmpty || _from.isAfter(_to)) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.api.fetchSalesDashboardInvoices(
        company: company,
        fromDate: _date(_from),
        toDate: _date(_to),
      );
      if (!mounted || generation != _requestGeneration) return;
      setState(() => _invoices = rows);
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _invoices = const [];
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final current = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_from.isAfter(_to)) _to = picked;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = picked;
      }
    });
    await _load();
  }

  Map<String, Map<String, dynamic>> get _currencyTotals {
    final result = <String, Map<String, dynamic>>{};
    for (final invoice in _invoices) {
      final currency = invoice['currency']?.toString() ?? '';
      final total = result.putIfAbsent(currency, () => {
        'total': 0.0,
        'outstanding': 0.0,
        'count': 0,
      });
      total['total'] = (total['total'] as double) + _number(invoice['grand_total']);
      total['outstanding'] = (total['outstanding'] as double) + _number(invoice['outstanding_amount']);
      total['count'] = (total['count'] as int) + 1;
    }
    return result;
  }

  Map<String, List<MapEntry<String, double>>> get _topCustomersByCurrency {
    final grouped = <String, Map<String, double>>{};
    for (final invoice in _invoices) {
      final customer = invoice['customer_name']?.toString().trim().isNotEmpty == true
          ? invoice['customer_name'].toString()
          : invoice['customer']?.toString() ?? 'غير محدد';
      final currency = invoice['currency']?.toString() ?? '';
      final totals = grouped.putIfAbsent(currency, () => <String, double>{});
      totals[customer] = (totals[customer] ?? 0) + _number(invoice['grand_total']);
    }
    return {
      for (final group in grouped.entries)
        group.key: (group.value.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
            .take(5).toList(growable: false),
    };
  }

  Widget _metric(String title, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totals = _currencyTotals;
    final totalInvoices = _invoices.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة مؤشرات المبيعات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.companies.isEmpty)
            const Card(child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('لا توجد شركات متاحة لحساب المستخدم.'),
            ))
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'الشركة'),
              items: widget.companies.map((company) => DropdownMenuItem(
                value: company.name,
                child: Text(company.name, overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: _loading ? null : (value) {
                setState(() => _company = value);
                _load();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickDate(start: true),
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('من ${_date(_from)}'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _loading ? null : () => _pickDate(start: false),
                  icon: const Icon(Icons.event_outlined),
                  label: Text('إلى ${_date(_to)}'),
                )),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
              ),
            if (!_loading && _error == null) ...[
              _metric('عدد فواتير المبيعات', totalInvoices.toString(), Icons.receipt_long_outlined),
              const SizedBox(height: 8),
              Text('ملخص المبيعات حسب العملة', style: Theme.of(context).textTheme.titleMedium),
              if (totals.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد فواتير مرحلة خلال الفترة المحددة.')))
              else
                ...totals.entries.map((entry) {
                  final currency = entry.key.isEmpty ? 'عملة غير محددة' : entry.key;
                  final data = entry.value;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currency, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _line('إجمالي المبيعات', _number(data['total']).toStringAsFixed(2)),
                          _line('المبالغ المستحقة', _number(data['outstanding']).toStringAsFixed(2)),
                          _line('عدد الفواتير', data['count'].toString()),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              Text('أعلى العملاء حسب قيمة الفواتير', style: Theme.of(context).textTheme.titleMedium),
              if (_topCustomersByCurrency.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد بيانات للعملاء.')))
              else
                ..._topCustomersByCurrency.entries.map((group) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 10, bottom: 4),
                      child: Text(group.key.isEmpty ? 'عملة غير محددة' : group.key,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    ...group.value.asMap().entries.map((entry) => Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${entry.key + 1}')),
                        title: Text(entry.value.key),
                        trailing: Text(entry.value.value.toStringAsFixed(2)),
                      ),
                    )),
                  ],
                )),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'المصدر: فواتير المبيعات المرحلة في ERPNext. لا تشمل المرتجعات، ولا يتم جمع عملات مختلفة معاً.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
