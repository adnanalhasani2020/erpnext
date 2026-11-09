import 'package:flutter/material.dart';

import 'api/frappe_api.dart';

class WarehouseHierarchyPage extends StatefulWidget {
  const WarehouseHierarchyPage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<WarehouseHierarchyPage> createState() => _WarehouseHierarchyPageState();
}

class _WarehouseHierarchyPageState extends State<WarehouseHierarchyPage> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  String? _company;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading && _rows.isNotEmpty) return;
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await widget.api.fetchMasterDataOptions('Warehouse');
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final rows = _rows.where((row) =>
      _company == null || _company!.isEmpty || row['company'] == _company
    ).toList(growable: false);
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows.where((row) =>
      (row['warehouse_name'] ?? '').toString().toLowerCase().contains(query) ||
      (row['name'] ?? '').toString().toLowerCase().contains(query) ||
      (row['parent_warehouse'] ?? '').toString().toLowerCase().contains(query)
    ).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final companies = _rows.map((row) => row['company']?.toString() ?? '')
      .where((value) => value.isNotEmpty).toSet().toList()..sort();
    final byParent = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final parent = row['parent_warehouse']?.toString() ?? '';
      byParent.putIfAbsent(parent, () => []).add(row);
    }
    for (final group in byParent.values) {
      group.sort((a, b) => (a['warehouse_name'] ?? a['name'] ?? '')
        .toString().compareTo((b['warehouse_name'] ?? b['name'] ?? '').toString()));
    }
    final ids = rows.map((row) => row['name']?.toString() ?? '').toSet();
    final roots = rows.where((row) {
      final parent = row['parent_warehouse']?.toString() ?? '';
      return parent.isEmpty || !ids.contains(parent);
    }).toList(growable: false);
    final visited = <String>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('شجرة المستودعات'),
        actions: [IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            DropdownButtonFormField<String>(
              value: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تصفية حسب الشركة'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('كل الشركات')),
                ...companies.map((company) => DropdownMenuItem(value: company, child: Text(company))),
              ],
              onChanged: (value) => setState(() => _company = value),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'بحث في اسم المستودع أو رقمه', prefixIcon: Icon(Icons.search)),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('${rows.length} مستودع ضمن النتائج • ${_rows.where((r) => r['is_group'] == 1 || r['is_group'] == true).length} مجموعات في البيانات المحمّلة'),
            ),
          ]),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        Expanded(
          child: rows.isEmpty && !_loading
            ? const Center(child: Text('لا توجد مستودعات مطابقة أو لا تتوفر صلاحية القراءة.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                children: roots.map((row) => _node(row, byParent, visited, 0)).toList(),
              ),
        ),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text('عرض هرمي للقراءة فقط. إنشاء المستودعات وتعديل الأب والشركة يتم من إدارة البيانات الأساسية، وتظل قواعد ERPNext هي المرجع.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  Widget _node(Map<String, dynamic> row,
      Map<String, List<Map<String, dynamic>>> byParent,
      Set<String> visited, int depth) {
    final id = row['name']?.toString() ?? '';
    if (id.isEmpty || !visited.add(id)) return const SizedBox.shrink();
    final children = byParent[id] ?? const <Map<String, dynamic>>[];
    final isGroup = row['is_group'] == 1 || row['is_group'] == true;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            leading: Icon(isGroup ? Icons.folder_outlined : Icons.warehouse_outlined),
            title: Text((row['warehouse_name'] ?? id).toString()),
            subtitle: Text('$id • ${row['company'] ?? 'شركة غير محددة'}${row['disabled'] == 1 || row['disabled'] == true ? ' • معطل' : ''}'),
            trailing: Text(isGroup ? '${children.length} فرعي' : 'مخزن'),
          ),
        ),
        ...children.map((child) => _node(child, byParent, visited, depth + 1)),
      ]),
    );
  }
}
