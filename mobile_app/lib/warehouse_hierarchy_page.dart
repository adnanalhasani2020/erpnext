import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';

import 'api/frappe_api.dart';
import 'workspace_native_destination_page.dart';
import 'master_data_page.dart';
import 'models/erp_models.dart';

class WarehouseHierarchyPage extends StatefulWidget {
  const WarehouseHierarchyPage({super.key, required this.api});
  final FrappeApi api;

  @override
  State<WarehouseHierarchyPage> createState() => _WarehouseHierarchyPageState();
}

class _WarehouseHierarchyPageState extends State<WarehouseHierarchyPage> {
  List<core.Map<String, dynamic>> _rows = [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _offset = 0;
  String? _error;
  String _query = '';
  String? _company;
  final Set<String> _selected = <String>{};
  final Set<String> _collapsedGroups = <String>{};
  List<ErpCompany> _companies = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false, String? search}) async {
    if (_loading || _loadingMore || (more && !_hasMore)) return;
    setState(() {
      if (more) { _loadingMore = true; } else { _loading = true; _error = null; _offset = 0; _hasMore = false; _selected.clear(); _collapsedGroups.clear(); }
    });
    try {
      if (_companies.isEmpty) {
        final loadedCompanies = await widget.api.fetchCompanies();
        if (!mounted) return;
        setState(() => _companies = loadedCompanies);
      }
      final page = await widget.api.fetchMasterDataRows(doctype: 'Warehouse', search: search ?? _query, start: more ? _offset : 0);
      if (!mounted) return;
      setState(() {
        if (more) {
          final known = _rows.map((row) => row['name']?.toString()).toSet();
          _rows.addAll(page.whereType<core.Map<String, dynamic>>().where((row) => !known.contains(row['name']?.toString())));
        } else { _rows = page; }
        _offset = more ? _offset + page.length : page.length;
        _hasMore = page.length == FrappeApi.pageSize;
      });
    } catch (error) { if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', '')); }
    finally { if (mounted) setState(() { _loading = false; _loadingMore = false; }); }
  }

  Future<void> _manageWarehouses() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MasterDataPage(api: widget.api, companies: _companies, initialType: 'Warehouse')));
    if (mounted) await _load();
  }

  Future<void> _bulkSetDisabled(bool disabled) async {
    final selectedRows = _rows.where((row) => _selected.contains(row['name']?.toString())).toList();
    if (selectedRows.isEmpty || _loading || _loadingMore) return;
    final action = disabled ? 'تعطيل' : 'تفعيل';
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: Text('$action ${selectedRows.length} مستودع'),
      content: const Text('سيتم إرسال تحديث مستقل لكل مستودع محدد إلى ERPNext. لن يتم حذف أي سجل. هل تريد المتابعة؟'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('تأكيد $action'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() { _loading = true; _error = null; });
    var succeeded = 0;
    final failures = <String>[];
    for (final row in selectedRows) {
      final id = row['name']?.toString() ?? '';
      if (id.isEmpty) continue;
      try { await widget.api.saveMasterDataDocument(doctype: 'Warehouse', name: id, values: {
          'warehouse_name': row['warehouse_name'] ?? id,
          'company': row['company'] ?? '',
          'parent_warehouse': row['parent_warehouse'] ?? '',
          'is_group': row['is_group'] == 1 || row['is_group'] == true,
          'disabled': disabled,
        }); succeeded++; }
      catch (error) { failures.add('$id: ${error.toString().replaceFirst('Exception: ', '')}'); }
    }
    if (!mounted) return;
    setState(() { _selected.clear(); _loading = false; });
    await _load();
    if (!mounted) return;
    final message = failures.isEmpty ? 'تم $action $succeeded مستودع بنجاح.' : 'نجح $succeeded وفشل ${failures.length}. أول خطأ: ${failures.first}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
  Future<void> _bulkMoveToParent() async {
    final selectedRows = _rows.where((row) =>
      _selected.contains(row['name']?.toString())
    ).toList();
    if (selectedRows.isEmpty || _loading || _loadingMore) return;
    final companies = selectedRows.map((row) => row['company']?.toString() ?? '').toSet();
    if (companies.length != 1 || companies.first.isEmpty) {
      setState(() => _error = 'حدد مستودعات تتبع شركة واحدة فقط قبل نقلها جماعياً.');
      return;
    }
    final company = companies.first;
    final selectedIds = selectedRows.map((row) => row['name']?.toString() ?? '').toSet();
    final byId = <String, core.Map<String, dynamic>>{
      for (final row in _rows) row['name']?.toString() ?? '': row,
    };
    bool hasSelectedAncestor(core.Map<String, dynamic> row) {
      var parent = row['parent_warehouse']?.toString() ?? '';
      final visited = <String>{};
      while (parent.isNotEmpty && visited.add(parent)) {
        if (selectedIds.contains(parent)) return true;
        parent = byId[parent]?['parent_warehouse']?.toString() ?? '';
      }
      return false;
    }
    final moveRows = selectedRows.where((row) => !hasSelectedAncestor(row)).toList();
    bool isInsideSelectedBranch(String candidate) {
      var current = byId[candidate];
      final visited = <String>{};
      while (current != null) {
        final parent = current['parent_warehouse']?.toString() ?? '';
        if (parent.isEmpty || !visited.add(parent)) return false;
        if (selectedIds.contains(parent)) return true;
        current = byId[parent];
      }
      return false;
    }
    final possibleParents = _rows.where((row) =>
      row['company'] == company &&
      (row['is_group'] == 1 || row['is_group'] == true) &&
      !selectedIds.contains(row['name']?.toString()) &&
      !isInsideSelectedBranch(row['name']?.toString() ?? '')
    ).toList();
    String? selectedParent;
    final parent = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refresh) => AlertDialog(
          title: Text('نقل ${moveRows.length} مجموعة / مستودع'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('الشركة: $company'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: selectedParent,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'المستودع الأب الجديد'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('الجذر (بدون مستودع أب)')),
                  ...possibleParents.map((row) => DropdownMenuItem<String?>(
                    value: row['name']?.toString(),
                    child: Text(row['warehouse_name']?.toString() ?? row['name']?.toString() ?? ''),
                  )),
                ],
                onChanged: (value) => refresh(() => selectedParent = value),
              ),
              const SizedBox(height: 8),
              const Text('لن يسمح التطبيق بالنقل إلى مستودع من نفس الفرع المحدد لتجنب إنشاء حلقة في الشجرة. سيتحقق ERPNext أيضاً من صحة الهيكل والشركة.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selectedParent ?? ''), child: const Text('متابعة')),
          ],
        ),
      ),
    );
    if (parent == null || !mounted) return;
    final newParent = parent;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تغيير الهيكل'),
        content: Text('سيتم نقل ${moveRows.length} مجموعة / مستودع إلى ${newParent.isEmpty ? 'الجذر' : newParent}. ستبقى المستودعات الفرعية التابعة داخل مجموعاتها. لن تتغير أرصدة المخزون أو الحركات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('تأكيد النقل')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _loading = true; _error = null; });
    var succeeded = 0;
    final failures = <String>[];
    for (final row in moveRows) {
      final id = row['name']?.toString() ?? '';
      if (id.isEmpty) continue;
      try {
        await widget.api.saveMasterDataDocument(
          doctype: 'Warehouse',
          name: id,
          values: {
            'warehouse_name': row['warehouse_name'] ?? id,
            'company': company,
            'parent_warehouse': newParent,
            'is_group': row['is_group'] == 1 || row['is_group'] == true,
            'disabled': row['disabled'] == 1 || row['disabled'] == true,
          },
        );
        succeeded++;
      } catch (error) {
        failures.add('$id: ${error.toString().replaceFirst('Exception: ', '')}');
      }
    }
    if (!mounted) return;
    setState(() { _selected.clear(); _loading = false; });
    await _load();
    if (!mounted) return;
    final message = failures.isEmpty
        ? 'تم نقل $succeeded مستودع بنجاح.'
        : 'نُقل $succeeded وفشل ${failures.length}. أول خطأ: ${failures.first}';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<core.Map<String, dynamic>> get _visibleRows {
    final rows = _rows.where((row) =>
      _company == null || _company!.isEmpty || row['company'] == _company
    ).toList(growable: false);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;
    final companies = _companies.map((company) => company.name).where((value) => value.isNotEmpty).toList()..sort();
    final byParent = <String, List<core.Map<String, dynamic>>>{};
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
        actions: [
          IconButton(tooltip: 'فتح قائمة الجوال', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WorkspaceNativeDestinationPage(api: widget.api, title: 'Warehouse', linkType: 'DocTypeList', target: 'Warehouse'))), icon: const Icon(Icons.arrow_forward)),IconButton(onPressed: _loading || _loadingMore ? null : _manageWarehouses, tooltip: 'إدارة المستودعات', icon: const Icon(Icons.edit_note)), IconButton(onPressed: _loading || _loadingMore ? null : () => _load(), tooltip: 'تحديث', icon: const Icon(Icons.refresh))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            DropdownButtonFormField<String>(
              initialValue: _company,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'تصفية حسب الشركة'),
              items: [
                const DropdownMenuItem<String>(value: null, child: Text('كل الشركات')),
                ...companies.map((company) => DropdownMenuItem(value: company, child: Text(company))),
              ],
              onChanged: (value) => setState(() { _company = value; _selected.clear(); _collapsedGroups.clear(); }),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(labelText: 'بحث في اسم المستودع أو رقمه', prefixIcon: Icon(Icons.search)),
              onSubmitted: (value) { setState(() => _query = value); _load(search: value); },
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 6),
            if (_rows.isNotEmpty) Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _loading || _loadingMore ? null : () => setState(() {
                  final visibleIds = _visibleRows.map((row) => row['name']?.toString() ?? '').where((id) => id.isNotEmpty);
                  if (visibleIds.every(_selected.contains)) { _selected.removeAll(visibleIds); } else { _selected.addAll(visibleIds); }
                }),
                icon: const Icon(Icons.select_all),
                label: const Text('تحديد / إلغاء تحديد المستودعات المعروضة'),
              ),
            ),
            if (_selected.isNotEmpty) Wrap(spacing: 8, children: [
              Chip(label: Text('محدد: ${_selected.length}')),
              TextButton.icon(onPressed: _loading ? null : () => _bulkSetDisabled(false), icon: const Icon(Icons.check_circle_outline), label: const Text('تفعيل')),
              TextButton.icon(onPressed: _loading ? null : _bulkMoveToParent, icon: const Icon(Icons.drive_file_move_outline), label: const Text('نقل إلى مجموعة')),
              TextButton.icon(onPressed: _loading ? null : () => _bulkSetDisabled(true), icon: const Icon(Icons.block_outlined), label: const Text('تعطيل')),
              TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('إلغاء التحديد')),
            ]),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('${rows.length} مستودع ضمن النتائج • ${_rows.where((r) => r['is_group'] == 1 || r['is_group'] == true).length} مجموعات في البيانات المحمّلة'),
            ),
          ]),
        ),
        if (_loading || _loadingMore) const LinearProgressIndicator(),
        if (_error != null) Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
        Expanded(
          child: rows.isEmpty && !_loading
            ? const Center(child: Text('لا توجد مستودعات مطابقة أو لا تتوفر صلاحية القراءة.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                children: [
          ...roots.map((row) => _node(row, byParent, visited, 0)),
          // ERP data can contain orphaned or cyclic parent references. Keep
          // those records visible rather than silently dropping them.
          ...rows
              .where((row) => !visited.contains(row['name']?.toString() ?? ''))
              .map((row) => _node(row, byParent, visited, 0)),
        ],
              ),
        ),
        if (_hasMore || _loadingMore) Padding(padding: const EdgeInsets.all(12), child: OutlinedButton.icon(onPressed: _loadingMore ? null : () => _load(more: true), icon: const Icon(Icons.expand_more), label: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل مستودعات إضافية'))),
        const Padding(
          padding: EdgeInsets.all(10),
          child: Text('تدعم هذه الشاشة التحديد الجماعي وتفعيل وتعطيل المستودعات ونقلها بين المجموعات. إنشاء مستودع جديد وتغيير الشركة يتم من إدارة البيانات الأساسية، ويظل ERPNext مرجع التحقق النهائي.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }

  void _markDescendantsVisited(
      String parentId,
      core.Map<String, List<core.Map<String, dynamic>>> byParent,
      Set<String> visited,
    ) {
    for (final child in byParent[parentId] ?? const <core.Map<String, dynamic>>[]) {
      final childId = child['name']?.toString() ?? '';
      if (childId.isEmpty || !visited.add(childId)) continue;
      _markDescendantsVisited(childId, byParent, visited);
    }
  }

  void _toggleGroup(String name) {
    setState(() {
      if (!_collapsedGroups.add(name)) _collapsedGroups.remove(name);
    });
  }

  Widget _node(core.Map<String, dynamic> row,
      core.Map<String, List<core.Map<String, dynamic>>> byParent,
      Set<String> visited, int depth) {
    final id = row['name']?.toString() ?? '';
    if (id.isEmpty || !visited.add(id)) return const SizedBox.shrink();
    final children = byParent[id] ?? const <core.Map<String, dynamic>>[];
    final isGroup = row['is_group'] == 1 || row['is_group'] == true;
    final isCollapsed = _collapsedGroups.contains(id);
    if (isCollapsed) _markDescendantsVisited(id, byParent, visited);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: depth * 16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            leading: Row(mainAxisSize: MainAxisSize.min, children: [Checkbox(value: _selected.contains(id), onChanged: (checked) => setState(() { if (checked == true) { _selected.add(id); } else { _selected.remove(id); } })), Icon(isGroup ? Icons.folder_outlined : Icons.warehouse_outlined)]),
            title: Text((row['warehouse_name'] ?? id).toString()),
            subtitle: Text('$id • ${row['company'] ?? 'شركة غير محددة'}${row['disabled'] == 1 || row['disabled'] == true ? ' • معطل' : ''}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(isGroup ? '${children.length} فرعي' : 'مخزن'),
              if (isGroup)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: isCollapsed ? 'توسيع المجموعة' : 'طي المجموعة',
                  onPressed: () => _toggleGroup(id),
                  icon: Icon(isCollapsed ? Icons.chevron_right : Icons.expand_more),
                ),
            ]),
          ),
        ),
        if (!isCollapsed) ...children.map((child) => _node(child, byParent, visited, depth + 1)),
      ]),
    );
  }
}
