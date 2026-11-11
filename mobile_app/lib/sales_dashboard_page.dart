import 'dart:core';
import 'dart:core' as core;
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
  List<core.Map<String, dynamic>> _currencyTotals = const [];
  Map<String, List<core.Map<String, dynamic>>> _topCustomersByCurrency = const {};
  int _totalInvoices = 0;
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
      final summary = await widget.api.fetchSalesDashboardSummary(
        company: company,
        fromDate: _date(_from),
        toDate: _date(_to),
      );
      if (!mounted || generation != _requestGeneration) return;
      final rawTotals = summary['currency_totals'];
      final rawTop = summary['top_customers_by_currency'];
      final top = <String, List<core.Map<String, dynamic>>>{};
      if (rawTop is core.Map) {
        for (final entry in rawTop.entries) {
          if (entry.value is List) {
            top[entry.key.toString()] = (entry.value as List)
                .whereType<core.Map<String, dynamic>>()
                .map((row) => core.Map<String, dynamic>.from(row))
                .toList(growable: false);
          }
        }
      }
      setState(() {
        _currencyTotals = rawTotals is List
            ? rawTotals.whereType<core.Map<String, dynamic>>()
                .map((row) => core.Map<String, dynamic>.from(row))
                .toList(growable: false)
            : const [];
        _topCustomersByCurrency = top;
        _totalInvoices = int.tryParse(summary['total_invoices']?.toString() ?? '') ?? 0;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _currencyTotals = const [];
        _topCustomersByCurrency = const {};
        _totalInvoices = 0;
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
              _metric('عدد فواتير المبيعات', _totalInvoices.toString(), Icons.receipt_long_outlined),
              const SizedBox(height: 8),
              Text('ملخص المبيعات حسب العملة', style: Theme.of(context).textTheme.titleMedium),
              if (totals.isEmpty)
                const Card(child: ListTile(title: Text('لا توجد فواتير مرحلة خلال الفترة المحددة.')))
              else
                ...totals.map((data) {
                  final rawCurrency = data['currency']?.toString() ?? '';
                  final currency = rawCurrency.isEmpty ? 'عملة غير محددة' : rawCurrency;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currency, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          _line('إجمالي فواتير البيع', _number(data['total']).toStringAsFixed(2)),
                          _line('المرتجعات / الإشعارات الدائنة', _number(data['return_total']).toStringAsFixed(2)),
                          _line('صافي المبيعات بعد المرتجعات', _number(data['net_total']).toStringAsFixed(2)),
                          _line('المبالغ المستحقة على فواتير البيع', _number(data['outstanding']).toStringAsFixed(2)),
                          _line('فواتير البيع', data['invoice_count']?.toString() ?? '0'),
                          _line('فواتير المرتجعات', data['return_invoice_count']?.toString() ?? '0'),
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
                        title: Text(entry.value['customer_name']?.toString() ?? entry.value['customer']?.toString() ?? 'غير محدد'),
                        trailing: Text(_number(entry.value['total']).toStringAsFixed(2)),
                      ),
                    )),
                  ],
                )),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'المصدر: تجميعات خادمية من فواتير البيع والمرتجعات المرحلة في ERPNext. صافي المبيعات = إجمالي البيع ناقص قيمة المرتجعات. تبقى كل عملة مستقلة، وترتيب أعلى العملاء مبني على فواتير البيع قبل المرتجعات.',
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
