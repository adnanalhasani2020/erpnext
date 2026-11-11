import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';

class ProcessPaymentReconciliationLogPage extends StatefulWidget {
  const ProcessPaymentReconciliationLogPage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<ProcessPaymentReconciliationLogPage> createState() =>
      _ProcessPaymentReconciliationLogPageState();
}

class _ProcessPaymentReconciliationLogPageState
    extends State<ProcessPaymentReconciliationLogPage> {
  final _search = TextEditingController();
  String? _status;
  List<core.Map<String, dynamic>> _logs = [];
  final Map<String, core.Map<String, dynamic>> _details = {};
  final Set<String> _loadingDetails = <String>{};
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading || _loadingMore || (more && !_hasMore)) return;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _offset = 0;
        _hasMore = false;
        _logs = [];
        _details.clear();
        _error = null;
      }
    });
    try {
      final rows = await widget.api.fetchProcessPaymentReconciliationLogs(
        start: more ? _offset : 0,
        search: _search.text,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _logs.addAll(rows);
        } else {
          _logs = rows;
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

  Future<void> _loadDetail(String name) async {
    if (!_loadingDetails.add(name)) return;
    setState(() => _error = null);
    try {
      final document = await widget.api.fetchProcessPaymentReconciliationLogDocument(name);
      if (!mounted) return;
      setState(() => _details[name] = document);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingDetails.remove(name));
    }
  }

  double _number(dynamic value) =>
      value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

  bool _checked(dynamic value) => value == true || value == 1 || value?.toString() == '1';

  Widget _logCard(core.Map<String, dynamic> row) {
    final name = row['name']?.toString() ?? '';
    final status = row['status']?.toString() ?? 'غير محدد';
    final detail = _details[name];
    final allocations = detail?['allocations'] is List
        ? (detail!['allocations'] as List).whereType<core.Map>().toList()
        : <core.Map>[];
    final loading = _loadingDetails.contains(name);
    final total = int.tryParse(row['total_allocations']?.toString() ?? '0') ?? 0;
    final processed = int.tryParse(row['reconciled_entries']?.toString() ?? '0') ?? 0;
    final ratio = total == 0
        ? (_checked(row['reconciled']) ? 1.0 : 0.0)
        : (processed / total).clamp(0.0, 1.0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(name, textDirection: TextDirection.ltr),
              subtitle: Text(
                'المهمة: ${row['process_pr'] ?? ''}\n'
                'الحالة: $status • التخصيصات: $total • المنفذ: $processed',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'تحميل تفاصيل السجل',
                onPressed: loading || name.isEmpty ? null : () => _loadDetail(name),
                icon: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.open_in_new),
              ),
            ),
            LinearProgressIndicator(value: ratio),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('تمت التسوية: ${_checked(detail['reconciled']) ? 'نعم' : 'لا'}')),
                  Text('مخصص: ${_checked(detail['allocated']) ? 'نعم' : 'لا'}'),
                ],
              ),
              if (detail['error_log']?.toString().trim().isNotEmpty == true)
                ExpansionTile(
                  title: const Text('أخطاء التنفيذ'),
                  children: [Padding(
                    padding: const EdgeInsets.all(8),
                    child: SelectableText(detail['error_log'].toString()),
                  )],
                ),
              if (allocations.isNotEmpty)
                ExpansionTile(
                  title: Text('تفاصيل التخصيصات (${allocations.length})'),
                  children: allocations.map((allocation) {
                    final reconciled = _checked(allocation['reconciled']);
                    final difference = _number(allocation['difference_amount']);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        reconciled ? Icons.check_circle_outline : Icons.pending_outlined,
                        color: reconciled ? Colors.green : null,
                      ),
                      title: Text('${allocation['reference_type'] ?? ''} • ${allocation['reference_name'] ?? ''}'),
                      subtitle: Text('إلى ${allocation['invoice_type'] ?? ''} • ${allocation['invoice_number'] ?? ''}'),
                      trailing: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${_number(allocation['allocated_amount']).toStringAsFixed(2)} ${allocation['currency'] ?? ''}'),
                          if (difference.abs() > 0)
                            Text('فرق: ${difference.toStringAsFixed(2)}'),
                        ],
                      ),
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجلات التسوية الآلية'),
        actions: [
          IconButton(
            tooltip: 'تحديث السجلات',
            onPressed: _loading || _loadingMore ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'بحث برقم السجل أو المهمة',
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
          DropdownButtonFormField<String?>(
            initialValue: _status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'حالة سجل التنفيذ'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('كل الحالات')),
              DropdownMenuItem<String?>(value: 'Running', child: Text('قيد التنفيذ')),
              DropdownMenuItem<String?>(value: 'Paused', child: Text('متوقف مؤقتاً')),
              DropdownMenuItem<String?>(value: 'Reconciled', child: Text('تمت التسوية')),
              DropdownMenuItem<String?>(value: 'Partially Reconciled', child: Text('مسوى جزئياً')),
              DropdownMenuItem<String?>(value: 'Failed', child: Text('فشل')),
              DropdownMenuItem<String?>(value: 'Cancelled', child: Text('ملغي')),
            ],
            onChanged: _loading || _loadingMore ? null : (value) {
              setState(() => _status = value);
              _load();
            },
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
          if (!_loading && _logs.isEmpty)
            const Card(child: ListTile(title: Text('لا توجد سجلات تسوية مطابقة للفلاتر.'))),
          ..._logs.map(_logCard),
          if (_hasMore || _loadingMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: FilledButton.tonal(
                onPressed: _loadingMore ? null : () => _load(more: true),
                child: Text(_loadingMore ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من السجلات'),
              ),
            ),
        ],
      ),
    );
  }
}
