// ignore_for_file: prefer_interpolation_to_compose_strings

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
  bool _showInventoryValuation = false;
  bool _showStandardReport = false;
  bool _standardLoading = false;
  String _standardReportName = 'Profit and Loss Statement';
  String? _standardError;
  List<dynamic> _standardColumns = const [];
  List<dynamic> _standardRows = const [];
  DateTime _reportFrom = DateTime(DateTime.now().year, 1, 1);
  DateTime _reportTo = DateTime.now();
  String _reportAccount = '';
  bool _loading = false;
  bool _stockLoading = false;
  bool _stockLoaded = false;
  String? _company;
  String? _error;
  String? _stockError;
  List<Map<String, dynamic>> _rows = const [];
  List<ErpStockBalance> _stockBalances = const [];
  List<ErpWarehouse> _warehouses = const [];
  int _requestGeneration = 0;
  int _stockRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _stockRequestGeneration++;
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

  Future<void> _loadInventoryValuation() async {
    final generation = ++_stockRequestGeneration;
    setState(() {
      _stockLoading = true;
      _stockError = null;
    });
    try {
      final warehouses = <ErpWarehouse>[];
      var warehouseOffset = 0;
      while (true) {
        final page = await widget.api.fetchWarehouses(start: warehouseOffset);
        warehouses.addAll(page);
        if (warehouses.length > 10000) {
          throw const FormatException('تجاوز عدد المستودعات الحد الآمن لتقرير قيمة المخزون.');
        }
        if (page.length < FrappeApi.pageSize) break;
        warehouseOffset += page.length;
      }

      final balances = <ErpStockBalance>[];
      var balanceOffset = 0;
      while (true) {
        final page = await widget.api.fetchStockBalances(start: balanceOffset);
        balances.addAll(page);
        if (balances.length > 10000) {
          throw const FormatException('تجاوز عدد أرصدة المخزون الحد الآمن للتقرير؛ استخدم شاشة المخزون لتصفية النتائج.');
        }
        if (page.length < FrappeApi.pageSize) break;
        balanceOffset += page.length;
      }
      if (!mounted || generation != _stockRequestGeneration) return;
      setState(() {
        _warehouses = warehouses;
        _stockBalances = balances;
        _stockLoaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _stockRequestGeneration) return;
      setState(() {
        _stockBalances = const [];
        _stockError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted && generation == _stockRequestGeneration) {
        setState(() => _stockLoading = false);
      }
    }
  }

  String _reportDate(DateTime value) {
    return value.year.toString().padLeft(4, '0') + '-' +
        value.month.toString().padLeft(2, '0') + '-' +
        value.day.toString().padLeft(2, '0');
  }

  Future<void> _loadStandardReport() async {
    if (_company == null || _company!.trim().isEmpty) {
      setState(() => _standardError = 'حدد الشركة قبل تشغيل التقرير.');
      return;
    }
    if (_reportFrom.isAfter(_reportTo)) {
      setState(() => _standardError = 'تاريخ البداية يجب ألا يتجاوز تاريخ النهاية.');
      return;
    }
    setState(() {
      _standardLoading = true;
      _standardError = null;
      _standardRows = const [];
      _standardColumns = const [];
    });
    try {
      final filters = <String, dynamic>{'company': _company};
      if (_standardReportName == 'Profit and Loss Statement' ||
          _standardReportName == 'Balance Sheet' ||
          _standardReportName == 'Cash Flow') {
        filters.addAll({
          'filter_based_on': 'Date Range',
          'period_start_date': _reportDate(_reportFrom),
          'period_end_date': _reportDate(_reportTo),
          'periodicity': 'Monthly',
          'include_default_book_entries': 1,
        });
      } else if (_standardReportName == 'Bank Reconciliation Statement') {
        if (_reportAccount.trim().isEmpty) {
          throw const FormatException('أدخل حساب البنك أو الصندوق لتشغيل كشف التسوية.');
        }
        filters.addAll({
          'account': _reportAccount.trim(),
          'report_date': _reportDate(_reportTo),
          'include_pos_transactions': 0,
        });
      } else if (_standardReportName == 'Sales Analytics') {
        filters.addAll({
          'tree_type': 'Customer',
          'doc_type': 'Sales Invoice',
          'value_quantity': 'Value',
          'range': 'Monthly',
          'curves': 'all',
          'entity': <String>[],
          'from_date': _reportDate(_reportFrom),
          'to_date': _reportDate(_reportTo),
        });
      } else {
        filters.addAll({
          'from_date': _reportDate(_reportFrom),
          'to_date': _reportDate(_reportTo),
        });
      }
      final result = await widget.api.runStandardReport(
        reportName: _standardReportName,
        filters: filters,
      );
      if (!mounted) return;
      setState(() {
        _standardColumns = result['columns'] as List;
        _standardRows = result['result'] as List;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _standardError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _standardLoading = false);
    }
  }

  Future<void> _pickReportDate({required bool from}) async {
    final current = from ? _reportFrom : _reportTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _reportFrom = picked;
      } else {
        _reportTo = picked;
      }
    });
  }

  Widget _buildStandardReport() {
    final columns = _standardColumns.whereType<Map>().toList(growable: false);
    final visibleColumns = columns.take(8).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('القوائم والتقارير المالية', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('تُنفذ التقارير القياسية داخل ERPNext وفق صلاحيات المستخدم وإعدادات الشركة.'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _standardReportName,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'نوع التقرير'),
          items: const [
            DropdownMenuItem(value: 'Profit and Loss Statement', child: Text('الأرباح والخسائر')),
            DropdownMenuItem(value: 'Balance Sheet', child: Text('الميزانية العمومية')),
            DropdownMenuItem(value: 'Cash Flow', child: Text('التدفقات النقدية')),
            DropdownMenuItem(value: 'General Ledger', child: Text('دفتر الأستاذ العام')),
            DropdownMenuItem(value: 'Trial Balance', child: Text('ميزان المراجعة')),
            DropdownMenuItem(value: 'Sales Register', child: Text('سجل المبيعات')),
            DropdownMenuItem(value: 'Sales Analytics', child: Text('تحليل المبيعات')),
            DropdownMenuItem(value: 'Purchase Register', child: Text('سجل المشتريات')),
            DropdownMenuItem(value: 'Bank Reconciliation Statement', child: Text('كشف التسوية البنكية')),
            DropdownMenuItem(value: 'Payment Ledger', child: Text('دفتر المدفوعات')),
            DropdownMenuItem(value: 'Stock Balance', child: Text('رصيد وتقييم المخزون')),
            DropdownMenuItem(value: 'Stock Ledger', child: Text('دفتر حركة المخزون')),
          ],
          onChanged: _standardLoading ? null : (value) {
            if (value == null) return;
            setState(() => _standardReportName = value);
          },
        ),
        const SizedBox(height: 10),
        if (_standardReportName == 'Bank Reconciliation Statement')
          OutlinedButton.icon(
            onPressed: _standardLoading ? null : () => _pickReportDate(from: false),
            icon: const Icon(Icons.event),
            label: Text('تاريخ كشف البنك: ' + _reportDate(_reportTo)),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _standardLoading ? null : () => _pickReportDate(from: true),
                  icon: const Icon(Icons.calendar_today),
                  label: Text('من: ' + _reportDate(_reportFrom)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _standardLoading ? null : () => _pickReportDate(from: false),
                  icon: const Icon(Icons.event),
                  label: Text('إلى: ' + _reportDate(_reportTo)),
                ),
              ),
            ],
          ),
        if (_standardReportName == 'Bank Reconciliation Statement')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: TextFormField(
              initialValue: _reportAccount,
              decoration: const InputDecoration(
                labelText: 'حساب البنك/الصندوق في ERPNext',
                hintText: 'مثال: 1010 - Bank - AC',
              ),
              onChanged: (value) => _reportAccount = value,
            ),
          ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _standardLoading ? null : _loadStandardReport,
          icon: const Icon(Icons.play_arrow),
          label: const Text('تشغيل التقرير'),
        ),
        if (_standardLoading) const LinearProgressIndicator(),
        if (_standardError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _standardError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (!_standardLoading && _standardError == null && _standardRows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('عدد الصفوف: ' + _standardRows.length.toString(),
              style: Theme.of(context).textTheme.titleMedium),
          ..._standardRows.take(300).map((rawRow) {
            final values = <String>[];
            for (var index = 0; index < visibleColumns.length; index++) {
              final column = visibleColumns[index];
              final field = column['fieldname']?.toString() ?? '';
              final label = column['label']?.toString() ?? field;
              dynamic value;
              if (rawRow is Map) {
                value = rawRow[field];
                if (value == null && label.isNotEmpty) value = rawRow[label];
              } else if (rawRow is List && index < rawRow.length) {
                value = rawRow[index];
              }
              if (value != null && value.toString().trim().isNotEmpty) {
                values.add(label + ': ' + value.toString());
              }
            }
            if (values.isEmpty && rawRow is Map) {
              rawRow.forEach((key, value) {
                if (value != null && value.toString().trim().isNotEmpty) {
                  values.add(key.toString() + ': ' + value.toString());
                }
              });
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: values.take(8).map((value) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(value),
                  )).toList(),
                ),
              ),
            );
          }),
          if (_standardRows.length > 300)
            Text('يُعرض أول 300 صف من أصل ' + _standardRows.length.toString() + '. استخدم فلاتر التقرير لتضييق النتائج.'),
        ],
        if (!_standardLoading && _standardError == null && _standardRows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('حدد الشركة والفترة ثم شغّل التقرير لعرض النتائج.'),
          ),
      ],
    );
  }

  Widget _buildInventoryValuation() {
    final warehouseById = {for (final warehouse in _warehouses) warehouse.id: warehouse};
    final companyByName = {for (final company in widget.companies) company.name: company};
    final filtered = _stockBalances.where((balance) {
      if (_company == null || _company!.isEmpty) return true;
      return warehouseById[balance.warehouse]?.company == _company;
    }).toList(growable: false);
    final grouped = <String, List<ErpStockBalance>>{};
    for (final balance in filtered) {
      final warehouse = warehouseById[balance.warehouse];
      final companyName = warehouse?.company;
      final key = companyName ?? 'شركة غير محددة • ${balance.warehouse}';
      grouped.putIfAbsent(key, () => []).add(balance);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('قيمة المخزون الحالية', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('لقطة حالية من Bin في ERPNext. تُعرض القيم لكل شركة بعملتها الافتراضية، ولا تُجمع العملات المختلفة.'),
        const SizedBox(height: 10),
        if (_stockLoading) const LinearProgressIndicator(),
        if (_stockError != null)
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_stockError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          )),
        if (!_stockLoading && _stockError == null && filtered.isEmpty)
          const Card(child: ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('لا توجد أرصدة مخزون ضمن نطاق التقرير'),
          )),
        ...grouped.entries.map((entry) {
          final company = companyByName[entry.key];
          final currency = company?.defaultCurrency ?? '';
          final knownValues = entry.value.where((row) => row.stockValue != null).fold<double>(
            0, (sum, row) => sum + row.stockValue!,
          );
          final missingValues = entry.value.where((row) => row.stockValue == null).length;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
                  Text('عدد أرصدة الأصناف: ${entry.value.length}'),
                  Text('القيمة المعروفة: ${knownValues.toStringAsFixed(2)} ${currency.isEmpty ? 'عملة غير محددة' : currency}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (missingValues > 0)
                    Text('تنبيه: قيمة التقييم غير متاحة لـ $missingValues رصيد؛ الإجمالي جزئي.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  const Divider(),
                  ...entry.value.take(60).map((row) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(row.itemCode),
                    subtitle: Text('${row.warehouse} • الكمية: ${row.actualQty.toStringAsFixed(2)} ${row.stockUom ?? ''} • معدل التقييم: ${row.valuationRate?.toStringAsFixed(2) ?? '—'}'),
                    trailing: Text(row.stockValue?.toStringAsFixed(2) ?? '—'),
                  )),
                  if (entry.value.length > 60)
                    Text('يُعرض أول 60 رصيداً من أصل ${entry.value.length}. راجع شاشة المخزون للتصفية التفصيلية.'),
                ],
              ),
            ),
          );
        }),
        if (_stockLoaded && filtered.isNotEmpty)
          Text('الأرصدة المعروضة: ${filtered.length} • عدد الشركات/المجموعات: ${grouped.length}'),
      ],
    );
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
                  Text(_showStandardReport ? 'القوائم المالية' : (_showInventoryValuation ? 'تقارير المخزون' : 'تقارير الذمم'),
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(_showStandardReport
                      ? 'الأرباح والخسائر والميزانية والتدفقات ودفتر الأستاذ'
                      : (_showInventoryValuation
                          ? 'قيمة المخزون الحالية حسب الشركة والمستودع'
                          : 'أعمار الفواتير المستحقة للعملاء والموردين'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              tooltip: 'تحديث التقرير',
              onPressed: _showStandardReport
                  ? (_standardLoading ? null : _loadStandardReport)
                  : (_showInventoryValuation
                      ? (_stockLoading ? null : _loadInventoryValuation)
                      : (_loading ? null : _load)),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showInventoryValuation = !_showInventoryValuation;
                  _showStandardReport = false;
                });
                if (_showInventoryValuation) {
                  if (!_stockLoaded && !_stockLoading) _loadInventoryValuation();
                } else {
                  _load();
                }
              },
              icon: Icon(_showInventoryValuation ? Icons.account_balance_outlined : Icons.inventory_2_outlined),
              label: Text(_showInventoryValuation ? 'العودة إلى تقارير الذمم' : 'فتح تقرير قيمة المخزون'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _showStandardReport = !_showStandardReport;
                  _showInventoryValuation = false;
                });
                if (!_showStandardReport) {
                  _load();
                }
              },
              icon: Icon(_showStandardReport ? Icons.arrow_back : Icons.analytics_outlined),
              label: Text(_showStandardReport ? 'العودة إلى تقارير الذمم' : 'فتح القوائم المالية'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (!_showInventoryValuation) ...[
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
        ],
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
          onChanged: (_loading || _stockLoading) ? null : (value) {
            setState(() => _company = value == null || value.isEmpty ? null : value);
            if (!_showInventoryValuation && !_showStandardReport) _load();
          },
        ),
        const SizedBox(height: 12),
        if (_showStandardReport)
          _buildStandardReport()
        else if (_showInventoryValuation)
          _buildInventoryValuation()
        else ...[
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
      ],
    );
  }

}
